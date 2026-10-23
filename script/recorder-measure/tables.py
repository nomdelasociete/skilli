"""The Measured section's speech tables, as Markdown, from
score_engines.py's --json output (so no number is typed by hand).

  tables.py short.json hour.json
"""
import json
import sys

NAMES = {
    "st": "`SpeechTranscriber`", "stw": "`SpeechTranscriber` + names", "dt0": "`DictationTranscriber`",
    "dtw": "`DictationTranscriber` + names", "w0": "whisper turbo", "wp": "whisper turbo + names",
    "wv": "whisper turbo + VAD", "wpv": "whisper turbo + VAD + names", "q5p": "whisper turbo q5_0 + VAD + names",
}


def pct(g, a, b):
    return f"{100 * g[a] / g[b]:.1f}" if g.get(b) else "–"


def main():
    short = json.load(open(sys.argv[1], encoding="utf-8"))
    hour = json.load(open(sys.argv[2], encoding="utf-8")) if len(sys.argv) > 2 else {}
    order = [v for v in NAMES if v in short]
    print("| Engine | EN me | EN them | FR me | FR them | All | Clean | Crosstalk | Strong accent | Bad line | Names right | × real time | Peak memory |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for v in order:
        s = short[v]
        a = s["all/all"]
        row = [NAMES[v]] + [pct(s[k], "err", "ref") for k in ("en/me", "en/them", "fr/me", "fr/them")] + [
            f"**{pct(a, 'err', 'ref')}**", pct(a, "clean_err", "clean_n"), pct(a, "cross_err", "cross_n"),
            pct(a, "heavy_err", "heavy_n"), pct(a, "bad_err", "bad_n"), f"{pct(a, 'name_ok', 'name_n')} %", f"{a['audio'] / a['secs']:.0f}", f"{a['mb'] / 1024:.1f} GB"]
        print("| " + " | ".join(row) + " |")
    if hour:
        print()
        print("| Engine (the hour) | Me | Them | All | Names right | × real time | Peak memory |")
        print("|---|---|---|---|---|---|---|")
        for v in [v for v in NAMES if v in hour]:
            s = hour[v]
            row = [NAMES[v], pct(s["fr/me"], "err", "ref"), pct(s["fr/them"], "err", "ref"), f"**{pct(s['fr/all'], 'err', 'ref')}**",
                   f"{pct(s['fr/all'], 'name_ok', 'name_n')} %", f"{s['fr/all']['audio'] / s['fr/all']['secs']:.0f}", f"{s['fr/all']['mb'] / 1024:.1f} GB"]
            print("| " + " | ".join(row) + " |")


if __name__ == "__main__":
    main()
