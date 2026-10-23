"""Speaker separation scores: diarization error rate (missed speech, false
alarm, speaker confusion, over the reference speech; overlap counted, no
collar), the share of words given to the right speaker, and the speaker
count found.

  der.py calls_dir runs_dir tool... [--tracks them,mix]
"""
import argparse
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
from scipy.optimize import linear_sum_assignment

FPS = 100


def frames(segments, labels, total):
    m = np.zeros((len(labels), total), dtype=bool)
    for spk, s, e in segments:
        a, b = int(s * FPS), min(total, int(e * FPS))
        if b > a:
            m[labels[spk], a:b] = True
    return m


def der(ref_segs, hyp_segs, seconds):
    total = int(seconds * FPS) + 1
    rl = {s: i for i, s in enumerate(sorted({x[0] for x in ref_segs}))}
    hl = {s: i for i, s in enumerate(sorted({x[0] for x in hyp_segs}))}
    R = frames(ref_segs, rl, total)
    H = frames(hyp_segs, hl, total) if hl else np.zeros((0, total), dtype=bool)
    ref_n, hyp_n = R.sum(0), H.sum(0)
    speech = ref_n.sum()
    miss = np.maximum(0, ref_n - hyp_n).sum()
    fa = np.maximum(0, hyp_n - ref_n).sum()
    # Best one-to-one map of found speakers to real ones (most shared time).
    mapping = {}
    if len(hl):
        overlap = (R.astype(np.int32) @ H.T.astype(np.int32))
        rows, cols = linear_sum_assignment(-overlap)
        mapping = {c: r for r, c in zip(rows, cols)}
    correct = 0
    for h, r in mapping.items():
        correct += (R[r] & H[h]).sum()
    conf = np.minimum(ref_n, hyp_n).sum() - correct
    inv_r = {i: s for s, i in rl.items()}
    inv_h = {i: s for s, i in hl.items()}
    return dict(der=100 * (miss + fa + conf) / speech, miss=100 * miss / speech, fa=100 * fa / speech, conf=100 * conf / speech,
                speech=speech / FPS, ref_speakers=len(rl), hyp_speakers=len(hl),
                mapping={inv_h[h]: inv_r[r] for h, r in mapping.items()})


def reference(truth, track):
    segs = []
    for t in truth["turns"]:
        if track == "them" and t["me"]:
            continue
        for s, e in t.get("speech") or [[t["start"], t["end"]]]:
            segs.append((t["speaker"], s, e))
    return segs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("calls")
    ap.add_argument("runs")
    ap.add_argument("tools", nargs="+")
    ap.add_argument("--tracks", default="them,mix")
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    out = {}
    for tool in a.tools:
        for track in a.tracks.split(","):
            agg = defaultdict(float)
            rows = []
            for d in sorted(Path(a.calls).iterdir()):
                p = Path(a.runs) / tool / d.name / f"{track}.json"
                if not (d / "truth.json").exists() or not p.exists():
                    continue
                truth = json.load(open(d / "truth.json"))
                run = json.load(open(p))
                hyp = [(s["speaker"], s["start"], s["end"]) for s in run["segments"]]
                r = der(reference(truth, track), hyp, truth["seconds"])
                for k in ("miss", "fa", "conf"):
                    agg[k] += r[k] * r["speech"] / 100
                agg["speech"] += r["speech"]
                agg["count_right"] += r["ref_speakers"] == r["hyp_speakers"]
                agg["files"] += 1
                agg["audio"] += run["audioSeconds"]
                agg["wall"] += run["wallSeconds"]
                agg["mb"] = max(agg["mb"], run.get("maxRSSMB", 0))
                rows.append((d.name, round(r["der"], 1), r["ref_speakers"], r["hyp_speakers"]))
            if not agg["files"]:
                continue
            s = agg["speech"]
            res = dict(der=100 * (agg["miss"] + agg["fa"] + agg["conf"]) / s, miss=100 * agg["miss"] / s, fa=100 * agg["fa"] / s,
                       conf=100 * agg["conf"] / s, count_right=int(agg["count_right"]), files=int(agg["files"]),
                       rt=agg["audio"] / agg["wall"], mb=agg["mb"], rows=rows)
            out[f"{tool}/{track}"] = res
            print(f"{tool:16s} {track:5s} DER {res['der']:5.1f} (miss {res['miss']:4.1f} fa {res['fa']:4.1f} conf {res['conf']:4.1f})  "
                  f"count right {res['count_right']}/{res['files']}  x{res['rt']:.0f} RT  {res['mb']:.0f} MB")
            print("    ", " ".join(f"{n}:{d}({r}/{h})" for n, d, r, h in rows))
    if a.json:
        json.dump(out, open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
