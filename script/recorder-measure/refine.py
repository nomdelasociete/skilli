"""Adds to each truth.json where each turn's voice actually sounds
(`speech`: [[start, end], ...]), from the dry synthesized audio (cached),
for the speaker-separation reference."""
import json, sys
from pathlib import Path
import numpy as np
from synth import synth
from mix import to16k, SR
for d in sorted(Path(sys.argv[1]).iterdir()):
    p = d / "truth.json"
    if not p.exists():
        continue
    t = json.load(open(p))
    for turn in t["turns"]:
        rate = 0 if turn["voice"].startswith("piper") else 172
        a = to16k(synth(turn["voice"], turn["text"], rate))
        hop = SR // 50
        rms = np.sqrt(np.convolve(a ** 2, np.ones(hop) / hop, mode="same"))[::hop]
        on = rms > rms.max() * 0.03
        spans, start = [], None
        for i, v in enumerate(on):
            if v and start is None:
                start = i
            if not v and start is not None:
                spans.append([start / 50, i / 50]); start = None
        if start is not None:
            spans.append([start / 50, len(on) / 50])
        merged = []
        for s in spans:
            if merged and s[0] - merged[-1][1] < 0.3:
                merged[-1][1] = s[1]
            else:
                merged.append(s)
        turn["speech"] = [[round(turn["start"] + s, 3), round(turn["start"] + e, 3)] for s, e in merged if e - s >= 0.1]
    json.dump(t, open(p, "w"), indent=1, ensure_ascii=False)
    print(d.name, sum(len(x["speech"]) for x in t["turns"]), "speech spans")
