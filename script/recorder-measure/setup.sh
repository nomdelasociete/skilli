#!/bin/bash
# Everything the measurement needs, in work/ (git ignores it): a Python
# venv, Piper's voices, whisper.cpp built here (never installed), its
# models, sherpa-onnx's models, the two Swift probes. Needs uv, ffmpeg, git
# and Xcode. Nothing goes outside this folder but uv's own Python.
set -euo pipefail
cd "$(dirname "$0")"
W=work
mkdir -p $W/models/piper $W/models/whisper $W/models/sherpa $W/bin
[ -x $W/venv/bin/python ] || uv venv --python 3.12 $W/venv
VIRTUAL_ENV=$W/venv uv pip install -q piper-tts numpy soundfile jiwer num2words scipy sherpa-onnx cmake
# espeak-ng refuses long data paths: synth.py reads it through this link.
ln -sfn venv/lib/python3.12/site-packages/piper/espeak-ng-data $W/ed

HF=https://huggingface.co
for v in en/en_GB/vctk/medium/en_GB-vctk-medium en/en_US/libritts_r/medium/en_US-libritts_r-medium \
         fr/fr_FR/siwis/medium/fr_FR-siwis-medium fr/fr_FR/upmc/medium/fr_FR-upmc-medium fr/fr_FR/tom/medium/fr_FR-tom-medium; do
  b=$(basename $v)
  [ -f $W/models/piper/$b.onnx ] || curl -sfL -o $W/models/piper/$b.onnx "$HF/rhasspy/piper-voices/resolve/main/$v.onnx"
  [ -f $W/models/piper/$b.onnx.json ] || curl -sfL -o $W/models/piper/$b.onnx.json "$HF/rhasspy/piper-voices/resolve/main/$v.onnx.json"
done

# whisper.cpp, pinned, built static with Metal (measurement only: not in the app).
if [ ! -x $W/whisper.cpp/build/bin/whisper-cli ]; then
  [ -d $W/whisper.cpp ] || git clone -q --depth 1 --branch v1.9.5 https://github.com/ggml-org/whisper.cpp $W/whisper.cpp
  PATH=$PWD/$W/venv/bin:$PATH cmake -S $W/whisper.cpp -B $W/whisper.cpp/build -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DWHISPER_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release >/dev/null
  PATH=$PWD/$W/venv/bin:$PATH cmake --build $W/whisper.cpp/build -j 8 --config Release --target whisper-cli >/dev/null
fi
cp $W/whisper.cpp/build/bin/whisper-cli $W/bin/
fetch() { [ -f "$2" ] || curl -sfL -o "$2" "$1"; echo "$3  $2" | shasum -a 256 -c --quiet; }
fetch $HF/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin $W/models/whisper/ggml-large-v3-turbo.bin \
  1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69
fetch $HF/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin $W/models/whisper/ggml-large-v3-turbo-q5_0.bin \
  394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2
fetch $HF/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin $W/models/whisper/ggml-silero-v5.1.2.bin \
  29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf

GH=https://github.com/k2-fsa/sherpa-onnx/releases/download
[ -d $W/models/sherpa/sherpa-onnx-pyannote-segmentation-3-0 ] || \
  curl -sfL $GH/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2 | tar xj -C $W/models/sherpa
[ -f $W/models/sherpa/wespeaker_en_voxceleb_resnet34_LM.onnx ] || \
  curl -sfL -o $W/models/sherpa/wespeaker_en_voxceleb_resnet34_LM.onnx $GH/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx

# The probes: macOS's two engines (a command-line tool) and the two Swift
# speaker-separation packages.
xcrun swiftc -O -parse-as-library -swift-version 6 speechprobe/main.swift -o $W/bin/speechprobe
swift build -c release --package-path diarprobe --scratch-path $W/diarprobe-build >/dev/null
cp -R $W/diarprobe-build/release/diarprobe $W/diarprobe-build/release/FluidAudio_FluidAudio.bundle $W/bin/
echo "work/ ready"
