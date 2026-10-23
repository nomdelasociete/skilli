#!/bin/bash
# The batch on the test Mac, one variant at a time. With LOCK_DIR set (a
# directory several runs on that Mac agree to use as a lock), each variant
# runs only once it holds the lock, and lets it go after: nothing else runs
# while the engines load the Mac. Variants: run_engines.sh's and
# diar_run.sh's.
#   [LOCK_DIR=…] [TRACKS="me them"] batch.sh "<variant>:<call,call…>" ...
R=~/recorder-measure
TAG="${LOCK_TAG:-recorder-measure $$}"
take() {
  [ -n "${LOCK_DIR:-}" ] || return 0
  for i in $(seq 1 240); do
    if mkdir "$LOCK_DIR" 2>/dev/null; then echo "$TAG since $(date +%H:%M): speech engines, no skil.li" > "$LOCK_DIR/owner"; return 0; fi
    sleep 30
  done
  return 1
}
# Only a lock this batch took.
release() { [ -n "${LOCK_DIR:-}" ] && grep -q "$TAG" "$LOCK_DIR/owner" 2>/dev/null && rm -rf "$LOCK_DIR"; }
trap release EXIT
for job in "$@"; do
  variant=${job%%:*}; calls=${job#*:}
  take || { echo "lock not free after 2 h: stopped before $variant"; exit 3; }
  echo "== $variant $(date +%H:%M)"
  case $variant in
    fluid*|sk*|sherpa*) $R/bin/diar_run.sh $variant $(echo $calls | tr , ' ') | grep -v 'rc=0' || true ;;
    *) TRACKS=${TRACKS:-"me them"} $R/bin/run_engines.sh $variant $(echo $calls | tr , ' ') | grep -v 'rc=0' || true ;;
  esac
  release
  echo "== $variant done $(date +%H:%M)"
  sleep 20
done
