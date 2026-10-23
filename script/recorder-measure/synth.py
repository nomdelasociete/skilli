"""Text to speech for the measurement corpus: macOS `say` voices and Piper
voices, as 48 kHz mono float arrays. Cached by (voice, rate, text).

Voice specs: "say:Samantha", "say:Thomas (French (France))",
"piper:en_GB-vctk-medium:12" (model:speaker).
"""
import hashlib
import os
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

HERE = Path(__file__).resolve().parent
# Everything downloaded or made: work/ (git ignores it), see setup.sh.
WORK = HERE / "work"
MODELS = WORK / "models" / "piper"
CACHE = WORK / "cache" / "tts"
CACHE.mkdir(parents=True, exist_ok=True)
RATE = 48000

_voices = {}


def _piper(model):
    if model not in _voices:
        from piper import PiperVoice
        # espeak-ng refuses data paths longer than its buffer: a short
        # relative link (`ed`, made by setup.sh) in work/, used from there.
        os.chdir(WORK)
        _voices[model] = PiperVoice.load(str(MODELS / f"{model}.onnx"), espeak_data_dir="ed")
    return _voices[model]


def synth(voice: str, text: str, rate: int = 0) -> np.ndarray:
    key = hashlib.sha1(f"{voice}|{rate}|{text}".encode()).hexdigest()
    path = CACHE / f"{key}.flac"
    if path.exists():
        audio, _ = sf.read(path, dtype="float32")
        return audio
    kind, _, name = voice.partition(":")
    if kind == "say":
        tmp = CACHE / f"{key}.tmp.wav"
        cmd = ["say", "-v", name, "--file-format=WAVE", "--data-format=LEF32@48000", "-o", str(tmp)]
        if rate:
            cmd += ["-r", str(rate)]
        subprocess.run(cmd + ["--", text], check=True)
        audio, sr = sf.read(tmp, dtype="float32")
        tmp.unlink()
        assert sr == RATE, sr
    elif kind == "piper":
        from piper.config import SynthesisConfig
        model, _, speaker = name.partition(":")
        v = _piper(model)
        # length_scale > 1 is slower speech; Piper's default reads fast.
        cfg = SynthesisConfig(speaker_id=int(speaker) if speaker else None,
                              length_scale=(1.0 + (170 - rate) / 170.0) if rate else 1.05)
        chunks = [np.frombuffer(c.audio_int16_bytes, dtype=np.int16) for c in v.synthesize(text, syn_config=cfg)]
        pcm = np.concatenate(chunks).astype(np.float32) / 32768.0
        sr = v.config.sample_rate
        g = np.gcd(sr, RATE)
        audio = resample_poly(pcm, RATE // g, sr // g).astype(np.float32)
    else:
        raise ValueError(voice)
    # Trim leading and trailing silence, normalise to -20 dBFS RMS.
    loud = np.flatnonzero(np.abs(audio) > 0.003)
    if loud.size:
        audio = audio[max(0, loud[0] - 960): loud[-1] + 960]
    rms = float(np.sqrt(np.mean(audio ** 2))) or 1.0
    audio = (audio * (0.1 / rms)).clip(-1, 1).astype(np.float32)
    sf.write(path, audio, RATE, format="FLAC")
    # What the cache gives back (16-bit), the first time too: a call built
    # again is the same, sample for sample.
    audio, _ = sf.read(path, dtype="float32")
    return audio


if __name__ == "__main__":
    out = sys.argv[3]
    sf.write(out, synth(sys.argv[1], sys.argv[2]), RATE)
