"""Measurement probe: sherpa-onnx offline diarization (pyannote
segmentation 3.0 + WeSpeaker ResNet34-LM embeddings, agglomerative
clustering). Same JSON as diarprobe.

  sherpa_diar.py models_dir in.wav out.json [speakers]
"""
import json
import resource
import sys
import time

import sherpa_onnx
import soundfile as sf

models, path, out = sys.argv[1], sys.argv[2], sys.argv[3]
speakers = int(sys.argv[4]) if len(sys.argv) > 4 else -1
t0 = time.time()
config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
    segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
        pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
            model=f"{models}/sherpa-onnx-pyannote-segmentation-3-0/model.onnx"), num_threads=4),
    embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=f"{models}/wespeaker_en_voxceleb_resnet34_LM.onnx", num_threads=4),
    clustering=sherpa_onnx.FastClusteringConfig(num_clusters=speakers, threshold=0.5),
    min_duration_on=0.3, min_duration_off=0.5)
assert config.validate()
sd = sherpa_onnx.OfflineSpeakerDiarization(config)
audio, sr = sf.read(path, dtype="float32")
assert sr == sd.sample_rate
load = time.time() - t0
t1 = time.time()
result = sd.process(audio).sort_by_start_time()
wall = time.time() - t1
segments = [dict(speaker=str(r.speaker), start=r.start, end=r.end) for r in result]
rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1048576
json.dump(dict(tool="sherpa", file=path, speakersGiven=None if speakers < 0 else speakers, audioSeconds=len(audio) / sr,
               loadSeconds=load, wallSeconds=wall, maxRSSMB=rss, segments=segments), open(out, "w", encoding="utf-8"), indent=1)
print(f"sherpa {len(audio)/sr:.0f}s audio in {wall:.1f}s (x{len(audio)/sr/wall:.0f}), {len(segments)} segments, "
      f"{len({s['speaker'] for s in segments})} speakers, rss {rss:.0f} MB")
