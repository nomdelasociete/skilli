"""Text normalisation and scoring for the speech-engine measurement:
errors per hundred words (WER) and names right."""
import re
import unicodedata

import jiwer
from num2words import num2words

FILLERS = {"um", "uh", "uhm", "erm", "er", "hmm", "mm", "mhm", "mmh", "euh", "heu", "hum", "mmm", "ah", "oh"}
SAME = {"ok": "okay", "alright": "all right", "e-mail": "email", "mail": "mail"}
NAME_STOP = {"le", "la", "de", "du", "van", "von", "der", "ni", "mac", "des"}


def _number(match, lang):
    s = match.group(0).replace(" ", "").replace(" ", "").replace(" ", "")
    s = s.replace(",", "") if lang == "en" else s.replace(".", "")
    try:
        if "," in s or "." in s:
            whole, frac = re.split(r"[.,]", s, maxsplit=1)
            word = " virgule " if lang == "fr" else " point "
            return num2words(int(whole), lang=lang) + word + " ".join(num2words(int(d), lang=lang) for d in frac)
        return " " + num2words(int(s), lang=lang) + " "
    except Exception:
        return s


def tokens(text: str, lang: str) -> list[str]:
    """Words of `text`, compared as a person would read them: case,
    punctuation, hyphens, fillers and how a number is written left out."""
    t = unicodedata.normalize("NFC", text).lower()
    t = t.replace("’", "'").replace("‘", "'").replace("`", "'")
    t = re.sub(r"([$€£])\s?(\d[\d,.\u202f\u00a0 ]*)", r"\2 \1", t)
    t = t.replace("%", " pour cent " if lang == "fr" else " percent ")
    t = t.replace("€", " euros ").replace("$", " dollars ").replace("£", " pounds ").replace("&", " et " if lang == "fr" else " and ")
    t = re.sub(r"(\d)\s?h\s?(\d\d)", r"\1 heures \2", t) if lang == "fr" else t
    t = re.sub(r"\d[\d   ]*(?:[.,]\d+)?", lambda m: _number(m, lang), t)
    t = t.replace("-", " ")
    # French elision: "l'équipe" → "l' équipe", the same in both texts.
    t = re.sub(r"(\w)'(\w)", r"\1' \2", t) if lang == "fr" else re.sub(r"(\w)'s\b", r"\1 's", t)
    t = re.sub(r"[^\w' ]+", " ", t)
    out = []
    for w in t.split():
        w = w if re.match(r"^\w'$", w) or w == "'s" else w.strip("'")
        if not w or w in FILLERS:
            continue
        out.extend(SAME.get(w, w).split())
    return out


def fold(w: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", w) if unicodedata.category(c) != "Mn")


def name_tokens(names: list[str], lang: str) -> set[str]:
    out = set()
    for n in names:
        for tok in tokens(n, lang):
            if tok not in NAME_STOP and len(tok) > 1:
                out.add(tok)
    return out


def reference(turn_texts: list[str], names: list[str], lang: str):
    """The reference's words, and for each whether it is part of a name
    (a word of an attendee's or a mentioned name, written with a capital)."""
    keys = name_tokens(names, lang)
    words, is_name = [], []
    for text in turn_texts:
        for orig in text.split():
            toks = tokens(orig, lang)
            cap = orig.lstrip("«\"'(").strip()[:1].isupper()
            for tok in toks:
                words.append(tok)
                is_name.append(cap and tok in keys)
    return words, is_name


def score(ref_words, ref_is_name, hyp_text: str, lang: str):
    hyp = tokens(hyp_text, lang)
    if not ref_words:
        return dict(ref=0, hyp=len(hyp), sub=0, dele=0, ins=len(hyp), wer=None, names=0, names_right=0, names_right_folded=0)
    if not hyp:
        hyp = ["<nothing>"]
    out = jiwer.process_words(" ".join(ref_words), " ".join(hyp))
    names = right = right_folded = 0
    for chunk in out.alignments[0]:
        for k in range(chunk.ref_start_idx, chunk.ref_end_idx):
            if not ref_is_name[k]:
                continue
            names += 1
            if chunk.type == "equal":
                right += 1
                right_folded += 1
            elif chunk.type == "substitute":
                h = chunk.hyp_start_idx + (k - chunk.ref_start_idx)
                if h < chunk.hyp_end_idx and fold(hyp[h]) == fold(ref_words[k]):
                    right_folded += 1
    return dict(ref=len(ref_words), hyp=len(hyp), sub=out.substitutions, dele=out.deletions, ins=out.insertions,
                wer=100.0 * (out.substitutions + out.deletions + out.insertions) / len(ref_words),
                names=names, names_right=right, names_right_folded=right_folded)
