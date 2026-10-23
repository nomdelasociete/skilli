"""Calibration: each candidate voice reads the same paragraph; voices the
best engine cannot follow are left out of the corpus."""
import json, sys
from pathlib import Path
import numpy as np, soundfile as sf
from synth import synth, RATE

EN = ("Thanks for joining everyone. Before we start, I want to go through the plan for next week, because a few things "
      "changed since Monday. The supplier moved the delivery to Thursday afternoon, so we will need someone in the office "
      "to check the boxes when they arrive. If that works for you, I will send the updated schedule tonight.")
FR = ("Merci à tous d'être là. Avant de commencer, je voudrais revoir le planning de la semaine prochaine, parce que "
      "plusieurs choses ont changé depuis lundi. Le fournisseur a décalé la livraison à jeudi après-midi, donc il faudra "
      "quelqu'un au bureau pour vérifier les cartons à leur arrivée. Si ça vous va, j'envoie le nouveau planning ce soir.")
say_en = ["Samantha", "Daniel", "Karen", "Moira", "Rishi", "Tessa", "Tara", "Aman", "Fred", "Kathy", "Ralph",
          "Eddy (English (US))", "Flo (English (UK))", "Reed (English (US))", "Rocko (English (UK))", "Sandy (English (US))",
          "Shelley (English (UK))", "Grandma (English (UK))", "Grandpa (English (US))"]
say_en_fr_accent = ["Thomas (French (France))", "Jacques", "Amélie (French (Canada))", "Flo (French (France))"]
say_fr = ["Thomas (French (France))", "Jacques", "Amélie (French (Canada))", "Eddy (French (France))", "Flo (French (France))",
          "Grandma (French (France))", "Grandpa (French (France))", "Rocko (French (France))", "Sandy (French (France))",
          "Shelley (French (France))", "Reed (French (Canada))"]
say_fr_en_accent = ["Samantha", "Daniel", "Karen"]
voices = []
voices += [("en", f"say:{v}") for v in say_en + say_en_fr_accent]
voices += [("en", f"piper:en_GB-vctk-medium:{i}") for i in range(0, 109, 6)]
voices += [("en", f"piper:en_US-libritts_r-medium:{i}") for i in range(0, 904, 50)]
voices += [("fr", f"say:{v}") for v in say_fr + say_fr_en_accent]
voices += [("fr", "piper:fr_FR-siwis-medium"), ("fr", "piper:fr_FR-upmc-medium:0"), ("fr", "piper:fr_FR-upmc-medium:1"), ("fr", "piper:fr_FR-tom-medium")]
# Measured and left out: fr_FR-mls-medium (its 125 voices babble for
# seconds on short sentences, so engines "miss" words never spoken).
out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
manifest = []
for i, (lang, v) in enumerate(voices):
    audio = synth(v, EN if lang == "en" else FR)
    # 16 kHz mono for the engines, half a second of silence each side.
    pad = np.zeros(RATE // 2, dtype=np.float32)
    name = f"cal{i:03d}"
    sf.write(out / f"{name}.wav", np.concatenate([pad, audio, pad]), RATE, subtype="PCM_16")
    manifest.append(dict(id=name, lang=lang, voice=v, seconds=len(audio) / RATE))
    print(name, lang, v, round(len(audio) / RATE, 1), flush=True)
json.dump(manifest, open(out / "manifest.json", "w"), indent=1, ensure_ascii=False)
