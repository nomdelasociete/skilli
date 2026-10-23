"""No headphones: the microphone also hears the other side from the Mac's
speakers. How much of the other side ends up in the user's transcript,
and what dropping the microphone's words that the Mac's sound already has
(the same word, at the same moment) does to it.

  echo_dedup.py calls_dir runs_dir engine... [--levels 12,20]
"""
import argparse
import json
from collections import defaultdict
from pathlib import Path

import jiwer

import normtext as n
from score_engines import ref_words


def timed_words(path: Path, lang):
    """(word, time) of a transcript: Apple's words carry their times;
    whisper's segments do (its token times are off with VAD), so words
    are spread over their segment."""
    d = json.load(open(path, encoding="utf-8"))
    out = []
    if "transcription" in d:
        for seg in d["transcription"]:
            toks = n.tokens(seg["text"], lang)
            a, b = seg["offsets"]["from"] / 1000, seg["offsets"]["to"] / 1000
            for i, t in enumerate(toks):
                out.append((t, a + (i + 0.5) / max(1, len(toks)) * (b - a)))
    else:
        for w in d["words"]:
            for t in n.tokens(w["w"], lang):
                out.append((t, (w["start"] + w["end"]) / 2))
    return out


def drop_echo(mic, them, before=0.5, after=2.0, run=2):
    """The microphone's words that the Mac's sound has too, the same word
    from `before` s earlier to `after` s later, in runs of `run` or more
    (a lone "yes" or "okay" said by the user is kept)."""
    hit = []
    for w, t in mic:
        hit.append(any(tw == w and tt - before <= t <= tt + after for tw, tt in them))
    keep = []
    for i, (w, t) in enumerate(mic):
        lo = i
        while lo > 0 and hit[lo - 1]:
            lo -= 1
        hi = i
        while hi + 1 < len(mic) and hit[hi + 1]:
            hi += 1
        in_run = hit[i] and (hi - lo + 1) >= run
        if not in_run:
            keep.append((w, t))
    return keep


def matched(ref_words_list, hyp_tokens):
    out = jiwer.process_words(" ".join(ref_words_list), " ".join(hyp_tokens or ["<nothing>"]))
    ok = [False] * len(ref_words_list)
    for c in out.alignments[0]:
        if c.type == "equal":
            for k in range(c.ref_start_idx, c.ref_end_idx):
                ok[k] = True
    wer = 100 * (out.substitutions + out.deletions + out.insertions) / max(1, len(ref_words_list))
    return ok, wer, out.insertions


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("calls")
    ap.add_argument("runs")
    ap.add_argument("engines", nargs="+")
    ap.add_argument("--levels", default="12,20")
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    results = {}
    for engine in a.engines:
        for level in a.levels.split(","):
            g = defaultdict(float)
            for d in sorted(Path(a.calls).iterdir()):
                p = Path(a.runs) / engine / d.name
                if not (p / f"echo-{level}.json").exists() or not (p / "them.json").exists() or not (p / "me.json").exists():
                    continue
                truth = json.load(open(d / "truth.json", encoding="utf-8"))
                lang = truth["language"]
                me_ref, _ = ref_words(truth, "me")
                all_ref, all_meta = ref_words(truth, "mix")
                is_them = [not any(t["me"] for t in truth["turns"] if t["speaker"] == m["speaker"]) for m in all_meta]
                clean = [w for w, _ in timed_words(p / "me.json", lang)]
                mic = timed_words(p / f"echo-{level}.json", lang)
                them = timed_words(p / "them.json", lang)
                kept = drop_echo(mic, them)
                for name, hyp in (("clean", clean), ("raw", [w for w, _ in mic]), ("dedup", [w for w, _ in kept])):
                    _, wer, ins = matched(me_ref, hyp)
                    ok, _, _ = matched(all_ref, hyp)
                    g[f"{name}_err"] += wer * len(me_ref) / 100
                    g[f"{name}_ins"] += ins
                    g[f"{name}_them_heard"] += sum(1 for k, o in enumerate(ok) if o and is_them[k])
                    g[f"{name}_me_heard"] += sum(1 for k, o in enumerate(ok) if o and not is_them[k])
                g["me_ref"] += len(me_ref)
                g["them_ref"] += sum(is_them)
                g["mic_words"] += len(mic)
                g["dropped"] += len(mic) - len(kept)
                g["calls"] += 1
            if not g["calls"]:
                continue
            r = {k: v for k, v in g.items()}
            results[f"{engine}/{level}"] = r
            print(f"{engine:5s} echo -{level} dB  user's words: WER clean {100 * g['clean_err'] / g['me_ref']:5.1f}  "
                  f"no headphones {100 * g['raw_err'] / g['me_ref']:5.1f}  after dropping {100 * g['dedup_err'] / g['me_ref']:5.1f}  |  "
                  f"other side's words in the user's transcript: {100 * g['raw_them_heard'] / g['them_ref']:4.1f}% → {100 * g['dedup_them_heard'] / g['them_ref']:4.1f}%  |  "
                  f"user's words kept: {g['raw_me_heard']:.0f} → {g['dedup_me_heard']:.0f} (clean {g['clean_me_heard']:.0f})  [{int(g['calls'])} calls]")
    if a.json:
        json.dump(results, open(a.json, "w", encoding="utf-8"), indent=1)


if __name__ == "__main__":
    main()
