#!/bin/bash
# Speaker separation runs (on the test Mac): one tool over calls, on the
# Mac's sound (them) and the one-track import (mix). "N" variants are told
# how many people the event has (the other side: attendees less the user).
#   diar_run.sh fluid|fluidN|fluidM|sk|skN|sherpa|sherpaN <call>...
# fluidM: at most one more than the event has (an attendee who never speaks).
set -u
R=~/recorder-measure
variant=$1; shift
for call in "$@"; do
  d=$R/audio/calls/$call
  o=$R/out/diar/$variant/$call; mkdir -p "$o"
  for tr in them mix; do
    grep -q "rc 0$" "$o/$tr.log" 2>/dev/null && [ -f "$o/$tr.json" ] && continue
    n=$(/usr/bin/python3 -c "import json;a=len(json.load(open('$d/truth.json'))['attendees']);print(a-1 if '$tr'=='them' else a)")
    given=""; case $variant in *N) given=$n ;; esac
    most=""; [ "$variant" = fluidM ] && most=$((n + 1))
    case $variant in
      fluid*) $R/bin/diarprobe --tool fluid --file "$d/$tr.wav" --out "$o/$tr.json" ${given:+--speakers $given} ${most:+--max-speakers $most} > "$o/$tr.log" 2>&1 ;;
      sk*) $R/bin/diarprobe --tool speakerkit --file "$d/$tr.wav" --out "$o/$tr.json" ${given:+--speakers $given} > "$o/$tr.log" 2>&1 ;;
      sherpa*) $R/venv/bin/python $R/bin/sherpa_diar.py $R/models/sherpa "$d/$tr.wav" "$o/$tr.json" $given > "$o/$tr.log" 2>&1 ;;
    esac
    rc=$?; echo "rc $rc" >> "$o/$tr.log"
    echo "$variant $call $tr rc=$rc $(grep -E 'audio in' "$o/$tr.log" | tail -1)"
  done
done
