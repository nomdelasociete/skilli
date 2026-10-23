"""Builds the measurement calls from the scripts: each turn read by its
speaker's voice, the remote side through each speaker's own room and an
Opus voice codec, the user's side through a room and a laptop-mic noise
floor, crosstalk where the script marks it. Writes per call:

  me.wav    the microphone track (the user only)
  them.wav  the Mac's sound (everyone else, one track)
  mix.wav   both on one track (an imported recording)
  echo-12.wav, echo-20.wav  the microphone without headphones: the user plus
            the other side heard again from the speakers, 12 or 20 dB under
  truth.json  every turn: speaker, track, start, end, text; names; vocabulary

All 16 kHz mono 16-bit (what the engines read), deterministic (seeded).
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import butter, fftconvolve, resample_poly, sosfilt

from synth import RATE, synth

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE / "corpus"
OUT = HERE / "work" / "calls"
SR = 16000

VCTK = "piper:en_GB-vctk-medium:"
LIBRI = "piper:en_US-libritts_r-medium:"
# One voice per person, the same in every call (accent from the voice:
# VCTK speakers keep their recorded accent).
PEOPLE = {
    "Priyanka Venkataraman": "say:Tara", "Bartholomew Okonkwo": VCTK + "51", "Ingrid Haugland": "say:Karen",
    "Torsten Lindqvist": VCTK + "94", "Ngozi Eze-Barnes": "say:Tessa", "Rohan Pillai": "say:Rishi",
    "Saskia Brouwer": LIBRI + "300", "Imogen Tregarthen": VCTK + "97", "Kwabena Mensah": LIBRI + "150",
    "Marisol Echeverría": "say:Moira", "Lachlan Whitcombe": VCTK + "71", "Anouk Verhoeven": LIBRI + "500",
    "Thandiwe Mahlangu": VCTK + "32", "Dashiell Prewitt": VCTK + "39", "Zbigniew Kowalczyk": VCTK + "6",
    "Keziah Ashdown": "say:Samantha", "Aarav Chaturvedi": "say:Aman", "Rafferty Quinlan": VCTK + "42",
    "Yusuf Demirci": VCTK + "87", "Hamish Dunleavy": VCTK + "102", "Oluwaseun Adebayo": LIBRI + "650",
    # The French committee.
    "Camille Kerjean": "piper:fr_FR-siwis-medium", "Maëlys Le Guennec": "piper:fr_FR-upmc-medium:0",
    "Jean-François Martaing": "piper:fr_FR-tom-medium", "Tancrède Abgrall": "say:Thomas (French (France))",
    "Oumou Diakité": "say:Amélie (French (Canada))",
    # An English speaker's French: the strongest accent of the set.
    "Ysaline Vandevelde": "say:Daniel",
}
# The English calls' user (Camille Rocher) is another person in each call;
# in en03 and en07 a French voice reads the English (a strong accent).
ME_EN = {"en01": "say:Daniel", "en02": VCTK + "0", "en03": "say:Thomas (French (France))", "en04": LIBRI + "50",
         "en05": VCTK + "107", "en06": LIBRI + "850", "en07": "say:Thomas (French (France))", "en08": VCTK + "60"}
# A bad line (lower codec rate) in two calls.
BITRATE = {"en02": 12, "fr04": 12}
# Words to expect, for the engines that take them: everyone named in the
# corpus (the user's contacts), plus people never named (contacts too).
EXTRA_CONTACTS = [
    "Aurélien Bossard", "Clémence Fauvel", "Baptiste Lemarchand", "Inès Rouquette", "Gaspard Villiers", "Noémie Bercot",
    "Hugo Tessier", "Léa Marchetti", "Romain Deschamps", "Salomé Briand", "Elliot Carver", "Harriet Penrose",
    "Felix Ashworth", "Mila Novak", "Tobias Reinholt", "Greta Sorensen", "Owen Pritchard", "Freya Lindgren",
    "Matteo Rinaldi", "Sofia Albescu", "Jasper Kingsley", "Nadia Haddad", "Victor Ponsard", "Agathe Ferrand",
    "Basile Rivière", "Capucine Laval", "Dorian Mercadier", "Eulalie Brossard", "Firmin Daguerre", "Garance Thibault",
    "Horace Lemoine", "Isaure Delorme", "Joachim Peyrol", "Kenza Belkacem", "Lorcan Fitzpatrick", "Maelle Corbin",
    "Nathaniel Brook", "Ophélie Gaudin", "Pascal Rigaud", "Quentin Vasseur", "Rosalind Thorne", "Sacha Morel",
    "Tilda Okafor", "Ulysse Charron", "Valentina Russo",
]


def rir(rng, rt60):
    """A small room's impulse response: the direct sound, then a decaying
    tail (exponential noise, low-passed)."""
    n = int(SR * rt60 * 1.2)
    t = np.arange(n) / SR
    tail = rng.standard_normal(n) * np.exp(-6.9 * t / rt60)
    tail = sosfilt(butter(2, 4000, fs=SR, output="sos"), tail)
    h = np.zeros(n)
    h[0] = 1.0
    h += 0.25 * tail / (np.sqrt(np.sum(tail ** 2)) or 1)
    return h / np.sqrt(np.sum(h ** 2))


def noise(rng, n, color):
    """Pink-ish (color 1) or brown-ish (2) background noise, unit RMS."""
    spectrum = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    spectrum /= f ** (color / 2)
    x = np.fft.irfft(spectrum, n)
    return x / (np.sqrt(np.mean(x ** 2)) or 1)


def opus(x, kbps):
    """Through Opus (VoIP mode) and back, as a call carries a voice."""
    with tempfile.TemporaryDirectory() as d:
        src, enc, dec = Path(d, "a.wav"), Path(d, "a.ogg"), Path(d, "b.wav")
        sf.write(src, resample_poly(x, 3, 1).astype(np.float32), 48000, subtype="FLOAT")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-c:a", "libopus", "-b:a", f"{kbps}k",
                        "-application", "voip", enc], check=True)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", enc, "-ar", "48000", "-ac", "1", "-c:a", "pcm_f32le", dec], check=True)
        y, _ = sf.read(dec, dtype="float32")
    y = resample_poly(y, 1, 3)
    out = np.zeros_like(x)
    out[: min(len(x), len(y))] = y[: len(x)]
    return out


def to16k(a):
    return resample_poly(a, 1, 3).astype(np.float32)


def build(call_ids, name):
    rng = np.random.default_rng(sum(map(ord, name)))
    scripts = [json.load(open(SCRIPTS / f"{c}.json", encoding="utf-8")) for c in call_ids]
    lang = scripts[0]["language"]
    turns, t = [], 0.5
    for si, script in enumerate(scripts):
        ids = {a["id"]: a["name"] for a in script["attendees"]}
        if si:
            t += 3.0  # the next agenda item
        prev_start = prev_end = None
        prev_speaker = None
        for turn in script["turns"]:
            who = ids[turn["speaker"]]
            voice = ME_EN[script["id"]] if (lang == "en" and turn["speaker"] == "me") else PEOPLE[who]
            rate = 0 if voice.startswith("piper") else 172
            audio = to16k(synth(voice, turn["text"], rate))
            dur = len(audio) / SR
            if turn.get("overlap") and prev_end is not None and who != prev_speaker:
                words = len(turn["text"].split())
                if words <= 4:
                    # A quick "yes" or "right" while the other still talks.
                    start = prev_start + (prev_end - prev_start) * rng.uniform(0.3, 0.8)
                else:
                    start = prev_end - min(rng.uniform(0.4, 1.4), 0.6 * (prev_end - prev_start))
            else:
                start = (prev_end if prev_end is not None else t) + rng.uniform(0.25, 0.9)
            turns.append(dict(call=script["id"], speaker=who, me=turn["speaker"] == "me", voice=voice,
                              start=round(start, 3), end=round(start + dur, 3), text=turn["text"], audio=audio))
            if start + dur > (prev_end or 0):
                prev_start, prev_end, prev_speaker = start, start + dur, who
        t = prev_end
    total = int((max(x["end"] for x in turns) + 1.5) * SR)

    # Each remote speaker: their own room, noise and codec, then the mix.
    them = np.zeros(total, dtype=np.float64)
    me = np.zeros(total, dtype=np.float64)
    for person in sorted({x["speaker"] for x in turns if not x["me"]}):
        track = np.zeros(total)
        for x in turns:
            if x["speaker"] == person and not x["me"]:
                i = int(x["start"] * SR)
                track[i: i + len(x["audio"])] += x["audio"]
        track = fftconvolve(track, rir(rng, rng.uniform(0.2, 0.5)))[:total]
        track *= 10 ** (rng.uniform(-4, 2) / 20)
        level = np.sqrt(np.mean(track[track != 0] ** 2)) if np.any(track) else 0.1
        track += noise(rng, total, rng.choice([1, 2])) * level * 10 ** (-rng.uniform(25, 35) / 20)
        kbps = BITRATE.get(scripts[0]["id"], int(rng.choice([24, 32])))
        them += opus(track.astype(np.float32), kbps)
    for x in turns:
        if x["me"]:
            i = int(x["start"] * SR)
            me[i: i + len(x["audio"])] += x["audio"]
    me = fftconvolve(me, rir(rng, rng.uniform(0.3, 0.5)))[:total]
    me_level = np.sqrt(np.mean(me[np.abs(me) > 1e-4] ** 2))
    me_clean = me.copy()
    me = me + noise(rng, total, 1) * me_level * 10 ** (-rng.uniform(22, 30) / 20)

    out = OUT / name
    out.mkdir(parents=True, exist_ok=True)
    peak = max(np.abs(me).max(), np.abs(them).max(), 1e-9)
    g = min(1.0, 0.7 / peak)
    sf.write(out / "me.wav", (me * g).astype(np.float32), SR, subtype="PCM_16")
    sf.write(out / "them.wav", (them * g).astype(np.float32), SR, subtype="PCM_16")
    sf.write(out / "mix.wav", ((me + them) * g * 0.7).astype(np.float32), SR, subtype="PCM_16")
    # No headphones: the other side from the Mac's speakers (small-speaker
    # band, the room, a few tens of ms later) into the microphone.
    speaker = sosfilt(butter(2, [180, 7000], btype="band", fs=SR, output="sos"), them)
    heard = fftconvolve(speaker, rir(rng, 0.4))[:total]
    heard = np.concatenate([np.zeros(int(0.045 * SR)), heard])[:total]
    them_level = np.sqrt(np.mean(heard[np.abs(heard) > 1e-4] ** 2))
    for db in (12, 20):
        echo = me + heard * (me_level / them_level) * 10 ** (-db / 20)
        sf.write(out / f"echo-{db}.wav", (echo * g).astype(np.float32), SR, subtype="PCM_16")

    names = []
    for s in scripts:
        names += [a["name"] for a in s["attendees"]] + s["mentioned"]
    names = list(dict.fromkeys(names))
    attendees = list(dict.fromkeys(a["name"] for s in scripts for a in s["attendees"]))
    truth = dict(name=name, calls=call_ids, language=lang, seconds=total / SR, attendees=attendees, names=names,
                 turns=[{k: v for k, v in x.items() if k != "audio"} for x in turns])
    json.dump(truth, open(out / "truth.json", "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print(name, lang, round(total / SR / 60, 1), "min", len(turns), "turns", flush=True)


def vocabulary():
    """The contacts: everyone named anywhere in the corpus, plus others."""
    names = []
    for p in sorted(SCRIPTS.glob("*.json")):
        s = json.load(open(p, encoding="utf-8"))
        names += [a["name"] for a in s["attendees"]] + s["mentioned"]
    return list(dict.fromkeys(names + EXTRA_CONTACTS))


if __name__ == "__main__":
    which = sys.argv[1:] or [p.stem for p in sorted(SCRIPTS.glob("*.json"))] + ["fr-hour"]
    for w in which:
        build([f"fr0{i}" for i in range(1, 9)] if w == "fr-hour" else [w], w)
    json.dump(vocabulary(), open(OUT / "contacts.json", "w", encoding="utf-8"), indent=1, ensure_ascii=False)
