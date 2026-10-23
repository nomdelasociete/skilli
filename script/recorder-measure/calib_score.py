import json, re, sys
from pathlib import Path
import normtext as n
src = open("calib.py", encoding="utf-8").read()
EN = eval(re.search(r'EN = (\(.*?\))\n', src, re.S).group(1)); FR = eval(re.search(r'FR = (\(.*?\))\n', src, re.S).group(1))
root = Path(sys.argv[1]); runs = Path(sys.argv[2])
rows = []
for m in json.load(open(root / "manifest.json", encoding="utf-8")):
    ref = n.tokens(EN if m["lang"] == "en" else FR, m["lang"])
    w = (runs / f"{m['id']}.wav.txt").read_text(encoding="utf-8")
    s = json.load(open(runs / f"{m['id']}.st.json", encoding="utf-8"))["text"]
    sw = n.score(ref, [False] * len(ref), w, m["lang"])["wer"]
    ss = n.score(ref, [False] * len(ref), s, m["lang"])["wer"]
    rows.append((m["lang"], m["voice"], sw, ss, m["id"]))
for r in sorted(rows, key=lambda r: (r[0], min(r[2], r[3]))):
    print(f"{r[0]} {min(r[2], r[3]):5.1f}  whisper {r[2]:5.1f}  st {r[3]:5.1f}  {r[1]}  {r[4]}")
json.dump(rows, open(runs / "calib_scores.json", "w", encoding="utf-8"), ensure_ascii=False)
