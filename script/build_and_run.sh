#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
SCHEME="Skilli"
PROCESS_NAME="Skilli"
BUNDLE_ID="com.nomdelasociete.Skilli"
CONFIGURATION="${CONFIGURATION:-Debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# In a .noindex folder: Spotlight would list every built copy as an app,
# beside the user's own (four skil.li in Spotlight, the old one opened). The
# folder it had before moves there once, its packages with it.
DERIVED_DATA="$ROOT_DIR/DerivedData.noindex"
PROJECT="$ROOT_DIR/Skilli.xcodeproj"
# This Mac's own skil.li: a release, where its Klipy key is.
OWN_APP="/Applications/$PROCESS_NAME.app"

cd "$ROOT_DIR"
if [[ -d "$ROOT_DIR/DerivedData" && ! -e "$DERIVED_DATA" ]]; then
  mv "$ROOT_DIR/DerivedData" "$DERIVED_DATA"
  # It names the packages' binaries by the old path; read again, they stay
  # (whisper's 65 MB is not fetched again).
  rm -f "$DERIVED_DATA/SourcePackages/workspace-state.json"
fi

# Extra arguments are build settings ("NAME=value"). SKILLI_TEAM signs with
# another Apple team (a contributor's own) instead of the project's.
# SKILLI_KLIPY_KEY puts skil.li's Klipy key in this build, as a release has
# it (Search GIFs then asks Klipy with no setting). Without it, a Release
# build keeps the key of the Release build already here, else takes the one
# of this Mac's skil.li: the benchmark and the Release self-tests rebuild
# the same bundle as `daily`, and one built without the key lost it for
# good (0.3.2 shipped without it).
build_app() {
  local configuration="$1"
  shift
  local klipy_key="${SKILLI_KLIPY_KEY:-}"
  if ! has_key "$klipy_key" && [[ "$configuration" == Release ]]; then
    klipy_key="$(known_klipy_key)"
  fi
  xcodegen generate --spec project.yml --use-cache >/dev/null
  xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$configuration" \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$DERIVED_DATA" \
    ${SKILLI_TEAM:+DEVELOPMENT_TEAM="$SKILLI_TEAM"} \
    ${klipy_key:+SKILLI_KLIPY_KEY="$klipy_key"} \
    build "$@"
}

# A key that is more than spaces: skil.li trims it (GIFLibrary.bundledKey).
has_key() { [[ -n "${1//[[:space:]]/}" ]]; }

# The Klipy key inside a built skil.li, or nothing. PlistBuddy prints its
# errors on stdout: kept only when it succeeds.
klipy_key_in() {
  local key
  [[ -f "$1/Contents/Info.plist" ]] || return 0
  key="$(/usr/libexec/PlistBuddy -c 'Print :SkilliKlipyKey' "$1/Contents/Info.plist" 2>/dev/null)" || return 0
  printf '%s' "$key"
}

# The Klipy key of the Release build here, else of this Mac's skil.li.
known_klipy_key() {
  local key
  key="$(klipy_key_in "$(app_bundle Release)")"
  has_key "$key" || key="$(klipy_key_in "$OWN_APP")"
  printf '%s' "$key"
}

# The self-tests are compiled only with SKILLI_SELFTEST: Debug has it
# (project.yml); a Release build that runs them adds it here. Release builds
# for users (script/release) never do.
build_selftest_app() {
  if [[ "$1" == Release ]]; then
    build_app Release 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) SKILLI_SELFTEST'
  else
    build_app "$1"
  fi
}

app_bundle() {
  echo "$DERIVED_DATA/Build/Products/$1/$PROCESS_NAME.app"
}

# SIGTERM: skil.li routes it through NSApp, so any Caps Lock mapping it
# installed is removed. No Apple Events, so no Automation prompt.
stop_app() {
  pkill -TERM -x "$PROCESS_NAME" >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do
    pgrep -x "$PROCESS_NAME" >/dev/null || return 0
    sleep 0.1
  done
}

# Right after the old instance quit, LaunchServices may still hold it and
# `open` starts nothing: opened again until the process is there.
launch_bundle() {
  local bundle="$1"
  for _ in 1 2 3 4 5; do
    /usr/bin/open "$bundle" || true
    for _ in $(seq 1 20); do
      pgrep -x "$PROCESS_NAME" >/dev/null && return 0
      sleep 0.1
    done
  done
  echo "skil.li did not start: $bundle" >&2
  return 1
}

open_app() {
  if pgrep -x "$PROCESS_NAME" >/dev/null; then
    echo "skil.li is already running; leaving the existing instance alone (use 'restart')."
    return 0
  fi
  launch_bundle "$(app_bundle "$CONFIGURATION")"
}

# Before building for the other Mac: it must answer SSH and show a
# logged-in, unlocked session, or the self-test waits or aborts there.
# The session's own state, as CoreGraphics keeps it, not the frontmost
# app: with no app active (one quit while in front, skil.li an accessory
# again), NSWorkspace names loginwindow in an unlocked session too.
# Asked after waking the display: a sleeping display can lock it too.
# No session (no answer) counts as the login window: nobody's to ask.
# SKILLI_REMOTE_CHECK=0 skips it, for a host that cannot be asked this way.
check_remote() {
  local host="$1" state status=0
  [[ "${SKILLI_REMOTE_CHECK:-}" == 0 ]] && return 0
  # One word: none (at the login window), away (another user's session on
  # the screen), locked or unlocked. CGSSessionScreenIsLocked is there
  # only while locked.
  local session_script='ObjC.import("CoreGraphics");
var d = $.CGSessionCopyCurrentDictionary();
var s = d ? ObjC.deepUnwrap(ObjC.castRefToObject(d)) : null;
!s || !s.kCGSessionLoginDoneKey ? "none" : !s.kCGSSessionOnConsoleKey ? "away" : s.CGSSessionScreenIsLocked ? "locked" : "unlocked"'
  # ssh exits 255 for its own errors, else with osascript's status; 143
  # when stopped after 20 s (ConnectTimeout covers only the connection).
  # BatchMode: never a prompt, whatever SKILLI_REMOTE's own SSH settings.
  state="$(
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" "caffeinate -u -t 1; osascript -l JavaScript 2>/dev/null" <<<"$session_script" &
    ssh_pid=$!
    { sleep 20; kill "$ssh_pid"; } >/dev/null 2>&1 &
    wait "$ssh_pid"
    ssh_status=$?
    kill $! 2>/dev/null
    exit "$ssh_status"
  )" || status=$?
  # The answer is the last line: a remote shell's startup output comes first.
  state="${state##*$'\n'}"
  if [[ "$status" == 255 ]]; then
    echo "$host does not answer SSH (asleep, off or off the network): wake it, then run again." >&2
    exit 2
  fi
  if [[ "$status" == 143 ]]; then
    echo "$host answers SSH but not within 20 s: look at that Mac, then run again." >&2
    exit 2
  fi
  case "$status:$state" in
    0:unlocked) ;;
    0:locked)
      echo "$host's screen is locked: unlock it, then run again." >&2
      exit 2
      ;;
    0:away)
      echo "$host shows another user's session: switch back to yours there, then run again." >&2
      exit 2
      ;;
    *)
      echo "$host is at the login window: log in on that Mac, then run again." >&2
      exit 2
      ;;
  esac
}

case "$MODE" in
  run)
    build_app "$CONFIGURATION"
    open_app
    ;;
  build)
    build_app "$CONFIGURATION"
    echo "Built: $(app_bundle "$CONFIGURATION")"
    ;;
  restart)
    build_app "$CONFIGURATION"
    stop_app
    open_app
    ;;
  daily)
    # The developer's own skil.li, as fast as shipped: Release, with the
    # dev traces kept (SKILLI_TRACE) to diagnose from this Mac's logs.
    # skil.li's Klipy key carries over from the build already here, else
    # from this Mac's skil.li (none in the repository, none in the keychain;
    # build_app); the first came from SKILLI_KLIPY_KEY. Never a daily without it: Search GIFs would find
    # only the GIFs on the Mac, and the next release could take that.
    no_klipy="No Klipy key for daily: SKILLI_KLIPY_KEY=<key> ./script/build_and_run.sh daily (a release's Info.plist has it, SkilliKlipyKey), or SKILLI_NO_KLIPY=1 to build anyway (without a key, Search GIFs finds only the GIFs on the Mac)."
    if ! has_key "${SKILLI_KLIPY_KEY:-}" && ! has_key "$(known_klipy_key)" && [[ "${SKILLI_NO_KLIPY:-}" != 1 ]]; then
      echo "$no_klipy" >&2
      exit 2
    fi
    # Signed as a release is (script/release/build.sh): macOS ties
    # Accessibility, Screen Recording and the other grants to the signature,
    # so a daily signed differently loses them to the downloaded skil.li and
    # back. Apple Development only without the team's Developer ID here.
    signing=()
    daily_team="${SKILLI_TEAM:-JSFMAD28GS}"
    # Read whole first: `grep -q` quitting early fails the pipe (pipefail).
    identities="$(security find-identity -v -p codesigning)"
    if [[ "$identities" == *"Developer ID Application: "*"($daily_team)"* ]]; then
      signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application")
    else
      echo "No Developer ID for team $daily_team in this keychain: daily signed Apple Development, so its permissions are not the downloaded skil.li's." >&2
    fi
    build_app Release 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) SKILLI_TRACE' ${signing[@]+"${signing[@]}"}
    # Checked in what was built, before the running skil.li is replaced.
    if ! has_key "$(klipy_key_in "$(app_bundle Release)")" && [[ "${SKILLI_NO_KLIPY:-}" != 1 ]]; then
      echo "The build has no Klipy key. $no_klipy" >&2
      exit 2
    fi
    stop_app
    launch_bundle "$(app_bundle Release)"
    ;;
  test)
    swift test
    ;;
  selftest)
    # Full app with event tap, driven by synthetic keys: test window, TextEdit,
    # Safari. Needs Accessibility for this signed build. Launched with `open`
    # so skil.li is its own responsible process for TCC.
    # `selftest settings` runs only the Settings checks.
    # `selftest glass` runs only the on-screen glass checks (Screen Recording).
    # `selftest ai` runs only the AI checks (one real Claude request).
    # On this Mac, only the scopes without keys or windows: the others
    # take the keyboard and the screen of whoever uses it (`remote`).
    case "${2:-all}" in
      clipboard|setup|decide|clipmeaning) ;;
      *)
        if [[ "${SKILLI_LOCAL_UI:-}" != 1 ]]; then
          echo "selftest ${2:-all} takes this Mac's keyboard and screen: run 'remote ${2:-all}' (the Mac mini), or set SKILLI_LOCAL_UI=1 on a Mac nobody is using." >&2
          exit 2
        fi
        ;;
    esac
    build_selftest_app "$CONFIGURATION"
    was_running=0
    pgrep -x "$PROCESS_NAME" >/dev/null && was_running=1
    stop_app
    mkdir -p "$ROOT_DIR/dist"
    rm -f "$ROOT_DIR/dist/selftest.json"
    /usr/bin/open -W -n "$(app_bundle "$CONFIGURATION")" --args --selftest --output "$ROOT_DIR/dist/selftest.json" --scope "${2:-all}"
    cat "$ROOT_DIR/dist/selftest.json"
    if [[ "$was_running" == 1 ]]; then
      # LaunchServices needs a moment after `open -W` returns (error -600).
      for _ in 1 2 3 4 5; do
        sleep 1
        open_app && break
      done
    fi
    python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); sys.exit(1 if r["failed"] else 0)' "$ROOT_DIR/dist/selftest.json"
    ;;
  remote)
    # Keyboard self-tests on another Mac, so this one stays free: builds
    # here, copies the app, runs it in that Mac's logged-in session (kept
    # awake while it runs), brings back the report and captures into
    # dist/remote. `remote ai`, `remote settings`… like `selftest`.
    # `remote guides`: the user guides' pictures, into dist/remote/guides
    # (script/guide-images.sh copies them to website/guides/images).
    # SKILLI_REMOTE names the SSH host (default `skilli-mini`); that Mac
    # needs skil.li in Accessibility and Screen Recording (`remote-app`).
    host="${SKILLI_REMOTE:-skilli-mini}"
    scope="${2:-all}"
    # It goes into a remote shell command: a scope is one word.
    [[ "$scope" =~ ^[a-z]+$ ]] || { echo "unknown scope: $scope" >&2; exit 2; }
    check_remote "$host"
    build_selftest_app "$CONFIGURATION"
    was_running=0
    ssh "$host" "pgrep -x $PROCESS_NAME" >/dev/null && was_running=1
    ssh "$host" "pkill -TERM -x $PROCESS_NAME; mkdir -p ~/skilli-selftest; true"
    rsync -a --delete "$(app_bundle "$CONFIGURATION")" "$host:skilli-selftest/"
    ssh "$host" "rm -rf ~/skilli-selftest/out && mkdir -p ~/skilli-selftest/out && caffeinate -u -t 1 && caffeinate -dis /usr/bin/open -W -n ~/skilli-selftest/$PROCESS_NAME.app --args --selftest --output ~/skilli-selftest/out/selftest.json --scope $scope"
    if [[ "$was_running" == 1 ]]; then
      # skil.li was open there (Settings, keys): open it again.
      ssh "$host" "sleep 2; /usr/bin/open ~/skilli-selftest/$PROCESS_NAME.app"
    fi
    rm -rf "$ROOT_DIR/dist/remote"
    mkdir -p "$ROOT_DIR/dist/remote"
    rsync -a "$host:skilli-selftest/out/" "$ROOT_DIR/dist/remote/"
    cat "$ROOT_DIR/dist/remote/selftest.json"
    python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); sys.exit(1 if r["failed"] else 0)' "$ROOT_DIR/dist/remote/selftest.json"
    ;;
  remote-app)
    # Copies the app to the other Mac and opens it normally: its setup
    # window asks for the permissions the self-tests need there.
    host="${SKILLI_REMOTE:-skilli-mini}"
    check_remote "$host"
    build_selftest_app "$CONFIGURATION"
    ssh "$host" "pkill -TERM -x $PROCESS_NAME; mkdir -p ~/skilli-selftest; true"
    rsync -a --delete "$(app_bundle "$CONFIGURATION")" "$host:skilli-selftest/"
    ssh "$host" "caffeinate -u -t 1; /usr/bin/open ~/skilli-selftest/$PROCESS_NAME.app"
    ;;
  benchmark)
    # Release build, no event tap, no key remapping: measures the launcher
    # hot paths and prints a JSON report. It shows the launcher again and
    # again: only on a Mac nobody is using (`remote-benchmark`).
    if [[ "${SKILLI_LOCAL_UI:-}" != 1 ]]; then
      echo "benchmark shows skil.li on this Mac again and again: run 'remote-benchmark' (the Mac mini), or set SKILLI_LOCAL_UI=1 on a Mac nobody is using." >&2
      exit 2
    fi
    build_app Release
    mkdir -p "$ROOT_DIR/dist"
    "$(app_bundle Release)/Contents/MacOS/$PROCESS_NAME" --benchmark --output "$ROOT_DIR/dist/benchmark.json"
    ;;
  remote-benchmark)
    # The benchmark on the other Mac (take its lock first): builds Release
    # here, runs it there in the logged-in session, brings the report back
    # to dist/benchmark.json. skil.li there is stopped for it and opened
    # again after.
    host="${SKILLI_REMOTE:-skilli-mini}"
    check_remote "$host"
    build_app Release
    was_running=0
    ssh "$host" "pgrep -x $PROCESS_NAME" >/dev/null && was_running=1
    ssh "$host" "pkill -TERM -x $PROCESS_NAME; mkdir -p ~/skilli-bench; rm -f ~/skilli-bench/benchmark.json; true"
    rsync -a --delete "$(app_bundle Release)" "$host:skilli-bench/"
    ssh "$host" "caffeinate -u -t 1 && caffeinate -dis /usr/bin/open -W -n ~/skilli-bench/$PROCESS_NAME.app --args --benchmark --output ~/skilli-bench/benchmark.json"
    if [[ "$was_running" == 1 ]]; then
      ssh "$host" "sleep 2; /usr/bin/open ~/skilli-selftest/$PROCESS_NAME.app"
    fi
    mkdir -p "$ROOT_DIR/dist"
    scp -q "$host:skilli-bench/benchmark.json" "$ROOT_DIR/dist/benchmark.json"
    cat "$ROOT_DIR/dist/benchmark.json"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    build_app "$CONFIGURATION"
    open_app
    sleep 1
    pgrep -x "$PROCESS_NAME" >/dev/null && echo "skil.li is running."
    ;;
  *)
    echo "usage: $0 [run|build|restart|daily|test|benchmark|remote-benchmark|selftest|remote|remote-app|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
