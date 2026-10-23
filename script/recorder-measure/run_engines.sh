#!/bin/bash
# Measurement runner (on the test Mac): one engine variant over calls and
# tracks. Writes out/<variant>/<call>/<track>.json (+ .log with timings and
# peak memory of the process doing the work).
#
#   TRACKS="me them" run_engines.sh <variant> <call>...
#   variants: st stw dt0 dtw w0 wv wp wpv q5p (q5p: quantized, names, VAD)
set -u
R=~/recorder-measure
variant=$1; shift
tracks=${TRACKS:-"me them"}
W="$R/bin/whisper-cli -t 4"

# Peak resident memory (MB) of the processes named $2 while pid $1 runs.
peak() {
  local pid=$1 name=$2 max=0 v
  while kill -0 "$pid" 2>/dev/null; do
    v=$(ps -axo rss=,comm= | awk -v n="$name" 'index($0, n) {s += $1} END {print s + 0}')
    [ "$v" -gt "$max" ] && max=$v
    sleep 0.2
  done
  echo $((max / 1024))
}

for call in "$@"; do
  d=$R/audio/calls/$call
  lang=$(/usr/bin/python3 -c "import json;print(json.load(open('$d/truth.json'))['language'])")
  loc=$([ "$lang" = fr ] && echo fr_FR || echo en_US)
  o=$R/out/$variant/$call; mkdir -p "$o"
  for tr in $tracks; do
    f=$d/$tr.wav
    [ -f "$f" ] || continue
    # Already measured: kept (the batch can be run again after a cut).
    grep -q "rc 0$" "$o/$tr.log" 2>/dev/null && [ -f "$o/$tr.json" ] && continue
    start=$(/usr/bin/python3 -c 'import time;print(time.time())')
    case $variant in
      st|stw|dt0|dtw)
        e=${variant:0:2}; words=""
        [ "$variant" = stw ] || [ "$variant" = dtw ] && words="--words $d/vocab.txt"
        $R/bin/speechprobe --engine "$e" --locale "$loc" --file "$f" --out "$o/$tr.json" $words > "$o/$tr.log" 2>&1 &
        pid=$!; mb=$(peak $pid localspeechrecognition); wait $pid; rc=$?
        echo "service_peak_mb $mb" >> "$o/$tr.log" ;;
      w0|wv|wp|wpv|q5p)
        m=$R/models/ggml-large-v3-turbo.bin; [ "$variant" = q5p ] && m=$R/models/ggml-large-v3-turbo-q5_0.bin
        args=(-m "$m" -l "$lang" -ojf -of "$o/$tr" -f "$f")
        [ "$variant" != w0 ] && [ "$variant" != wv ] && args+=(--prompt "$(cat "$d/prompt.txt")" --carry-initial-prompt)
        { [ "$variant" = wpv ] || [ "$variant" = wv ] || [ "$variant" = q5p ]; } && args+=(--vad -vm "$R/models/ggml-silero-v5.1.2.bin")
        /usr/bin/time -l $W "${args[@]}" > "$o/$tr.log" 2>&1; rc=$? ;;
      *) echo "unknown variant $variant"; exit 2 ;;
    esac
    end=$(/usr/bin/python3 -c 'import time;print(time.time())')
    echo "wall $(/usr/bin/python3 -c "print(round($end - $start, 2))") rc $rc" >> "$o/$tr.log"
    echo "$variant $call $tr rc=$rc $(tail -2 "$o/$tr.log" | tr '\n' ' ')"
  done
done
