"""Scores the engine runs: errors per hundred words (WER), names right,
time and memory, pooled over calls, with the errors broken down by what
the reference words were (crosstalk, a strong accent, a bad line).

  score_engines.py calls_dir out_dir variant... [--tracks me,them] [--calls en01,...] [--json out.json]
"""
import argparse
import json
import re
from collections import defaultdict
from pathlib import Path

import jiwer

import normtext as n

HEAVY = {"say:Thomas (French (France))@en", "say:Daniel@fr"}
# The calls on a bad line (Opus at 12 kb/s, mix.py).
BAD = {"en02", "fr04"}


def hyp_text(path: Path, attendees=None) -> str | None:
    """A transcript's text. With `attendees` (whisper only): its two
    failures measured taken out, a segment repeated right after itself
    and an attendee's name written as a speaker label ("Camille Kerjean :")."""
    if not path.exists():
        return None
    d = json.load(open(path))
    if "transcription" in d:  # whisper.cpp -ojf
        segs = [seg["text"] for seg in d["transcription"]]
        if attendees is not None:
            segs = [t for i, t in enumerate(segs) if i == 0 or t.strip() != segs[i - 1].strip()]
            label = re.compile(r"(^|[.!?…]\s+|\s)(" + "|".join(re.escape(a) for a in attendees) + r")\s?:\s", re.I)
            segs = [label.sub(r"\1", t) for t in segs]
        return " ".join(segs)
    return d.get("text", "")


def cost(log: Path, audio_s: float):
    t = log.read_text() if log.exists() else ""
    wall = re.search(r"^wall ([\d.]+)", t, re.M)
    total = re.search(r"total time =\s+([\d.]+) ms", t)
    load = re.search(r"load time =\s+([\d.]+) ms", t)
    service = re.search(r"service_peak_mb (\d+)", t)
    footprint = re.search(r"(\d+)\s+peak memory footprint", t)
    probe = re.search(r"in ([\d.]+)s \(x", t)
    seconds = float(total.group(1)) / 1000 - (float(load.group(1)) / 1000 if load else 0) if total else (
        float(probe.group(1)) if probe else float(wall.group(1)) if wall else None)
    mb = int(service.group(1)) if service else (int(footprint.group(1)) // 1048576 if footprint else None)
    return seconds, mb


def ref_words(truth, track):
    """Reference words of a track, each with what it is: its turn, whether
    it falls in crosstalk (another turn on the same track at that time),
    whether it is a name."""
    lang = truth["language"]
    keep = [t for t in truth["turns"] if (track == "mix") or (t["me"] == (track in ("me", "echo-12", "echo-20")))]
    keep.sort(key=lambda t: t["start"])
    keys = n.name_tokens(truth["names"], lang)
    att = n.name_tokens(truth["attendees"], lang)
    words, meta = [], []
    for ti, t in enumerate(keep):
        raw = t["text"].split()
        toks = []
        for orig in raw:
            cap = orig.lstrip("«\"'(").strip()[:1].isupper()
            for tok in n.tokens(orig, lang):
                toks.append((tok, cap and tok in keys, cap and tok in att))
        for i, (tok, is_name, is_att) in enumerate(toks):
            at = t["start"] + (i + 0.5) / len(toks) * (t["end"] - t["start"])
            cross = any(o is not t and o["start"] <= at <= o["end"] for o in keep)
            words.append(tok)
            meta.append(dict(name=is_name, attendee=is_att, cross=cross, heavy=f"{t['voice']}@{lang}" in HEAVY,
                             bad=t["call"] in BAD and not t["me"],
                             speaker=t["speaker"], call=t["call"]))
    return words, meta


def align(words, meta, hyp, lang):
    """Errors per reference word (substitution or deletion; an insertion
    counts against the reference word before it)."""
    toks = n.tokens(hyp or "", lang) or ["<nothing>"]
    out = jiwer.process_words(" ".join(words), " ".join(toks))
    err = [0] * len(words)
    names_ok = [False] * len(words)
    folded_ok = [False] * len(words)
    for c in out.alignments[0]:
        if c.type == "equal":
            for k in range(c.ref_start_idx, c.ref_end_idx):
                names_ok[k] = folded_ok[k] = True
        elif c.type in ("substitute", "delete"):
            for k in range(c.ref_start_idx, c.ref_end_idx):
                err[k] += 1
                if c.type == "substitute":
                    h = c.hyp_start_idx + (k - c.ref_start_idx)
                    folded_ok[k] = n.fold(toks[h]) == n.fold(words[k])
        elif c.type == "insert":
            k = max(0, min(len(words) - 1, c.ref_start_idx - 1))
            err[k] += c.hyp_end_idx - c.hyp_start_idx
    return err, names_ok, folded_ok, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("calls")
    ap.add_argument("out")
    ap.add_argument("variants", nargs="+")
    ap.add_argument("--tracks", default="me,them")
    ap.add_argument("--calls", dest="only", default="")
    ap.add_argument("--json", default="")
    ap.add_argument("--tidy", action="store_true", help="whisper: repeated segments and speaker labels taken out")
    a = ap.parse_args()
    calls = Path(a.calls)
    dirs = [d for d in sorted(calls.iterdir()) if (d / "truth.json").exists()]
    if a.only:
        dirs = [d for d in dirs if d.name in a.only.split(",")]
    results = {}
    for variant in a.variants:
        agg = defaultdict(lambda: defaultdict(float))
        for d in dirs:
            truth = json.load(open(d / "truth.json"))
            lang = truth["language"]
            for track in a.tracks.split(","):
                hyp = hyp_text(Path(a.out) / variant / d.name / f"{track}.json", truth["attendees"] if a.tidy else None)
                if hyp is None:
                    continue
                words, meta = ref_words(truth, track)
                err, ok, fok, out = align(words, meta, hyp, lang)
                secs, mb = cost(Path(a.out) / variant / d.name / f"{track}.log", truth["seconds"])
                for key in (f"{lang}/{track}", f"all/{track}", f"{lang}/all", "all/all"):
                    g = agg[key]
                    g["ref"] += len(words)
                    g["err"] += sum(err)
                    g["audio"] += truth["seconds"]
                    g["secs"] += secs or 0
                    g["mb"] = max(g["mb"], mb or 0)
                    g["files"] += 1
                    for k, m in enumerate(meta):
                        for flag in ("name", "attendee", "cross", "heavy", "bad"):
                            if m[flag]:
                                g[f"{flag}_n"] += 1
                                g[f"{flag}_err"] += err[k]
                                if flag in ("name", "attendee"):
                                    g[f"{flag}_ok"] += ok[k]
                                    g[f"{flag}_fok"] += fok[k]
                        if not m["cross"] and not m["heavy"] and not m["bad"]:
                            g["clean_n"] += 1
                            g["clean_err"] += err[k]
                    if key == f"{lang}/{track}":
                        g[f"call:{d.name}"] = 100 * sum(err) / max(1, len(words))
        results[variant] = {k: dict(v) for k, v in agg.items()}
        for key in sorted(agg):
            g = agg[key]
            pct = lambda e, nn: f"{100 * g[e] / g[nn]:5.1f}" if g[nn] else "  -  "
            print(f"{variant:5s} {key:10s} WER {pct('err', 'ref')}  clean {pct('clean_err', 'clean_n')}  "
                  f"crosstalk {pct('cross_err', 'cross_n')}  accent {pct('heavy_err', 'heavy_n')}  "
                  f"names {pct('name_ok', 'name_n')}% (accents aside {pct('name_fok', 'name_n')})  attendees {pct('attendee_ok', 'attendee_n')}%  "
                  f"x{g['audio'] / g['secs']:.0f} RT  {int(g['mb'])} MB  [{int(g['ref'])} words, {int(g['name_n'])} names, {int(g['files'])} files]")
    if a.json:
        json.dump(results, open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
