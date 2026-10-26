#!/bin/bash
# SpeakerKit's models, which tell voices apart in the meeting recorder's
# transcripts (docs/meeting-recorder.md, "Who spoke"): pyannote
# community-1 on Core ML, Argmax's conversion (CC BY 4.0), 11 MB. Fetched
# once from huggingface.co/argmaxinc/speakerkit-coreml at a fixed revision,
# each file checked by its SHA-256, kept in build/ (git ignores it), then
# copied into the app: Contents/Resources/SpeakerKit, read by skil.li
# Transcriber. Nothing is downloaded when the app runs.
#
# Run by the Skilli target's build (project.yml). Offline with nothing kept
# yet: a Debug build goes on without them (the voices are not told apart),
# a Release build stops.
set -euo pipefail
REV=556fc52a13327837688f02289457cded017802e9
ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CACHE="$ROOT/build/speakerkit/$REV"
BASE="https://huggingface.co/argmaxinc/speakerkit-coreml/resolve/$REV"

missing() {
  if [ "${CONFIGURATION:-Debug}" = "Release" ]; then
    echo "error: SpeakerKit's models: $1" >&2
    exit 1
  fi
  echo "warning: SpeakerKit's models: $1 (this build does not tell voices apart)"
  exit 0
}

while read -r sha path; do
  [ -n "$sha" ] || continue
  file="$CACHE/$path"
  if [ -f "$file" ] && [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" = "$sha" ]; then continue; fi
  mkdir -p "$(dirname "$file")"
  curl -sfL --retry 2 -o "$file.part" "$BASE/$path" || missing "could not fetch $path"
  [ "$(shasum -a 256 "$file.part" | cut -d' ' -f1)" = "$sha" ] || { rm -f "$file.part"; missing "$path is not the file expected"; }
  mv "$file.part" "$file"
done <<'FILES'
75ff1725ef4e58dacf9176466ec274a8a13a6132c296d6b571fb78ddad5455c4 speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/weights/weight.bin
423c358915acab0d440c99f5162c17456936c2c02f7394b05ab226b9a34c122a speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/model.mil
2fd6aaf6beb17b3758f5d0c5b2cf5feeacb0cc0c9267dbcd7536b247b1a5860e speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/metadata.json
6c356ed983b2a3332ce51299ca0f9747a35cb6c2a67b0ac24c69dbef3f989634 speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/coremldata.bin
40637aa0cb2a073bc303c7ca9ee79da35fa81d2cad1ead180e93b134005b95de speaker_segmenter/pyannote-v3/W8A16/SpeakerSegmenter.mlmodelc/analytics/coremldata.bin
a02861969f47cf3a67e3b0d276e54b3c8bc3a6e43d40d77d1cccbd57da0e5795 speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/weights/weight.bin
5eee9f6aa380aef88fee604d75c5deaa23adc83c9480cb8f6dedc72803973e77 speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/model.mil
29ea3421161c8344f6ea95db9b472217638a869f686f2494d10e5d11f11f4cda speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/metadata.json
1597d6c037ac52436b5c2e1abc47e6c68483c19eeac75267dfb8795a78ec07c5 speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/coremldata.bin
ba8405dfc9b9348ade705e052888b4bdc7fb8d079ef3ff71108a5f692d0209f2 speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedder.mlmodelc/analytics/coremldata.bin
5f2c284bd22f1f7ab76901c1c6e57f82d4ebbf057fa0b924aad057f124f77a89 speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/weights/weight.bin
42e552ebd7efb12ea813eceb474018dd0f46168e84ad3a1c54945bfc47be7a82 speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/model.mil
789f81c17dc04d469611d253684e534565fb4a008e54c722b925f1608bf87fce speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/metadata.json
b4ebd0b9ce5a84768672663aff426eb19f9648d4b9f74286f0e19fc753ad76ba speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/coremldata.bin
ce9bef9fb3125a5401300b5c5998c5d8f211094692cae780645d3e2757410f2c speaker_embedder/pyannote-v3/W8A16/SpeakerEmbedderPreprocessor.mlmodelc/analytics/coremldata.bin
a1dbbb651a0a67fcfe5334672f459df090fa960917a6ee3a5423245a7ab92ced speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/weights/weight.bin
209e641bf4d9c3868c9dc43ab8705094997917eb2df5f5d8c8fda09fed54b1d4 speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/model.mil
acc86b4a4f542d8e7eaf84fc290fe72bd8629b0ffcc16e5b1a9e13d777abd9d8 speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/metadata.json
6f6820ccf221d4cc7c107101d0ae4d716eb224e4fdffaf8f7ca36af70ae64c40 speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/coremldata.bin
3e13c8f4df77ea27cbbcdd6d083c63f5e7b3f32566cc5bf223fab92d40b81b8b speaker_clusterer/pyannote-v4/W32A32/PldaProjector.mlmodelc/analytics/coremldata.bin
FILES

cat > "$CACHE/NOTICE.txt" <<'NOTICE'
Speaker separation models: pyannote/speaker-diarization-community-1
(pyannoteAI, CC BY 4.0), converted to Core ML by Argmax, Inc.
(huggingface.co/argmaxinc/speakerkit-coreml, CC BY 4.0), used by Argmax's
SpeakerKit (MIT). https://creativecommons.org/licenses/by/4.0/
NOTICE

[ -n "${TARGET_BUILD_DIR:-}" ] || exit 0
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/SpeakerKit"
mkdir -p "$DEST"
rsync -a --delete "$CACHE/" "$DEST/"
