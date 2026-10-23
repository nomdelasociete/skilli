#!/bin/bash
# Chrome: the meeting's tab behind another tab; halfway through a capture
# it is brought forward (as BrowserTabReuse scripts it). What the capture
# shows before and after.
cd ~/recorder-measure
# With LOCK_DIR: only while this run holds it (LOCK_TAG, required then, in its owner file).
[ -z "${LOCK_DIR:-}" ] || { [ -n "${LOCK_TAG:-}" ] && grep -qF "$LOCK_TAG" "$LOCK_DIR/owner" 2>/dev/null; } || { echo "the lock is not ours (or LOCK_TAG unset): nothing run"; exit 3; }
P=file://$HOME/recorder-measure/probe/pages
for run in ${RUNS:-behind:tab covered:tab behind:tabfront covered:tabfront}; do
  mode=${run%%:*}; act=${run#*:}
  osascript -e "tell application \"Google Chrome\"" -e "set w to window 1" -e "set URL of tab 1 of w to \"$P/meeting.html\"" -e "if (count of tabs of w) < 2 then make new tab at end of tabs of w" -e "set URL of tab 2 of w to \"$P/other.html\"" -e "set active tab index of w to 2" -e "activate" -e "end tell" -e "tell application \"Finder\" to activate"
  sleep 2
  pm=$mode; [ $pm = behind ] && pm=asis
  out=$HOME/recorder-measure/out/probe/tab-$mode-$act.json; rm -f $out.go $out
  open -n probe/${PROBE:-A}/SkilliRecorderProbe.app --args recorderprobe window $out com.google.Chrome 16 $pm ext:meeting.html
  # The probe asks halfway: the tab forward, as BrowserTabReuse does (tabfront: the window and Chrome too).
  for i in $(seq 1 600); do [ -f $out.go ] && break; sleep 0.05; done
  front=""; [ $act = tabfront ] && front='-e "set index of w to 1" -e activate'
  eval osascript -e "'tell application \"Google Chrome\"'" -e "'set w to window 1'" -e "'repeat with i from 1 to count of tabs of w'" -e "'if URL of tab i of w contains \"meeting.html\" then set active tab index of w to i'" -e "'end repeat'" $front -e "'end tell'"
  rm -f $out.go
  for i in $(seq 1 120); do [ -f $out ] && break; sleep 0.5; done
  sleep 1
  /usr/bin/python3 -c "
import json,re; d=json.load(open('out/probe/tab-$mode-$act.json')); r=d.get('readings',[]); at=d.get('actionAt')
seen=[(x['t'], 'MEETING' if 'MEETING' in x['text'] else 'OTHER' if 'OTHER' in x['text'] else '?') for x in r]
after=[s for t,s in seen if at is not None and t > at]; first=next((t for t,s in seen if s=='MEETING' and at is not None and t>at), None)
print('$mode $act', 'automation', d.get('automation'), 'result', d.get('actionResult'), 'front', d.get('frontmost'), 'before', sorted(set(s for t,s in seen if at is None or t<=at)), 'after', sorted(set(after)), 'meeting shown', None if first is None else round(first-at,2), 's after the script', d.get('error',''))"
  sleep 1
done
