#!/bin/bash
# Window probes for one browser: each mode 14 s, the page's frame counter read on every picture.
cd ~/recorder-measure
app=$1; name=$2
# With LOCK_DIR: only while this run holds it (LOCK_TAG, required then, in its owner file).
[ -z "${LOCK_DIR:-}" ] || { [ -n "${LOCK_TAG:-}" ] && grep -qF "$LOCK_TAG" "$LOCK_DIR/owner" 2>/dev/null; } || { echo "the lock is not ours (or LOCK_TAG unset): nothing run"; exit 3; }
for m in ${MODES:-front behind covered minimized hidden}; do
  case $m in front) osascript -e "tell application id \"$app\" to activate" ;; behind*|covered*|half*) osascript -e "tell application id \"$app\" to activate" -e "tell application \"Finder\" to activate" ;; esac; pm=${m%-*}; [ $pm = behind ] && pm=asis
  sleep 1
  open -W -n probe/${PROBE:-A}/SkilliRecorderProbe.app --args recorderprobe window $HOME/recorder-measure/out/probe/$name-$m.json $app 14 $pm
  /usr/bin/python3 -c "
import json,re; d=json.load(open('out/probe/$name-$m.json')); r=d.get('readings',[]); f=[int(x) for t in r for x in re.findall(r'F (\d+)', t['text'])]
print('$name $m', 'front:', d.get('frontmost'), 'statuses', d.get('statuses'), 'pictures', len(r), 'F', f[:1], f[-1:], 'advancing' if len(set(f))>1 else 'FROZEN' if f else '-', d.get('window',{}).get('title',''), d.get('error',''))"
  sleep 1
done
