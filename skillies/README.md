# Community skillies

This folder is the source of truth for the website's Skillies collection.
Each file is a command that skil.li can run locally. Website cards, source
previews, downloads and `catalog.json` are generated from these exact files.

What a skillie is, every header key, how it runs and every tool it can call
are in the reference: [`docs/`](docs/README.md). This
page is about the collection, and recipes for skil.li's features.

## Contribute

1. Fork this repository. Add one script at `skillies/<category>/<unique-name>.sh`
   (also supported: `.py`, `.js`, `.rb`, `.swift`). Use lowercase hyphenated names.
   Prefer what runs on every Mac (below): a skillie that needs nothing installed
   works for everyone who adds it.
2. Start with a shebang and the `@skilli` header from an existing example
   (every key: [header reference](docs/header.md)).
   Include `schemaVersion 1`, `title`, `description`, `packageName` and `mode`.
   Keep metadata within the first 60 lines and 8 KB, as required by the app.
3. Include the full MIT license and your copyright notice in the script, so the
   license travels with a downloaded file. Only submit code you can license.
4. Document required applications, external runtimes, network access and effects
   in the description or script comments. Say what it calls that macOS does not
   have with `@skilli.requires` (below). Do not embed credentials or personal
   paths. Use arguments for user input (up to three `@skilli.argumentN` JSON
   declarations). Set `@skilli.needsConfirmation true` for commands that change
   or delete data. This asks before the whole script; it is not a sandbox.
   skil.li shows a "Running…" card while a skillie runs; one that shows
   something of its own (confetti) says `@skilli.showsRunning false`, and
   only what it prints at the end, or its error, shows.
5. Try the script on your Mac: copy it as `<name>.skilli` and double-click it
   (or put it in Settings → Skillies → Show in Finder). Check arguments,
   output and failure cases.
6. Run `python3 website/build.py --preview` from the repository root. Open a PR
   describing what you tested and any dependencies. Do not edit generated files
   under `website/skillies/files/` or the generated catalog HTML.

A maintainer reviews the code before merge. The website build validates metadata
and builds the site; **it does not execute contributed scripts**. A merge to
`main` publishes through Workers Builds when `skillies/` changes (see
[`website/README.md`](../website/README.md)). By hand, after the build:
`npx wrangler@4.151.3 deploy --config website/wrangler.jsonc`. A new skillie
needs no manual website edit beyond that publish.

## What runs on every Mac

A skillie runs with what is on the Mac. The website reads its shebang and
`@skilli.requires`, and its card says "Nothing to install" or what is
needed first.

- **Nothing to install**: `/bin/sh`, `/bin/bash`, `/bin/zsh`; `/usr/bin/perl`;
  `/usr/bin/osascript`, AppleScript or, with `#!/usr/bin/osascript -l
  JavaScript`, JavaScript for Automation. That one reaches Cocoa and Core
  Animation (`ObjC.import('Cocoa')`): windows, layers, animations. The
  Confetti Cannon (`everyday/confetti-cannon.js`) is one. Tools such as
  `open`, `curl`, `jq`, `shasum`, `defaults` and `screencapture` are there
  too. `/usr/bin/ruby` is there but old (2.6): avoid it.
- **Xcode's Command Line Tools** (`xcode-select --install`): `swift`,
  `python3`, `git`, `make`, `clang`. `/usr/bin` has them as stubs: until
  the tools are installed, macOS offers to install them and the skillie
  does not run.
- **Homebrew**: Node, a newer Python, and the rest.

The shebang says the first part (`#!/usr/bin/swift`: the Command Line
Tools; `#!/usr/bin/env node`: Node from Homebrew). What the script calls
itself is said in its header, comma-separated:

```bash
# It runs git:
# @skilli.requires xcode-tools
```

```bash
# It runs ffmpeg and jq from Homebrew:
# @skilli.requires homebrew:ffmpeg, homebrew:jq
```

`xcode-tools` and `homebrew:<formula>` are the only values; the website
build refuses others.

## Act in apps, and wait for the step

A skillie can hand a goal to skil.li's "do it here", which reads the app's
window and clicks for you. skil.li runs every skillie with `SKILLI_CLI`, the
path of its own command line. A step waits until it ends, so the script can
branch on it:

```bash
if said=$("$SKILLI_CLI" call do_in_app app=TextEdit goal="exporte en PDF dans mes documents" 2>&1); then
  echo "Exported."
else
  echo "Not exported: ${said%%$'\n'*}"
fi
```

- Arguments are `name=value` words: `app` (by name, opened if needed;
  without it, the app the user was in) and `goal` (written as the user would
  ask it, the exact text to type in « »). Quote each word, so a `$1` in a
  goal stays one value.
- Exit 0: done, its steps on standard output. Exit 1: not done (stopped,
  declined, esc, no such app), why on the first line of standard error.
  Exit 2: the call is written wrong.
- Each step is asked in skil.li's card as any agent's call is, unless the
  user's tool rights allow "Do it in an app"; what sends, deletes or pays is
  asked again during the step. `needsConfirmation` replaces none of these:
  it asks before the script runs.
- 120 s for the whole script; a step it is waiting for stops with it. A step
  whose result does not matter can open
  `skilli://do?app=…&goal=…` instead: asked first, and the script does not
  wait for it.

`SKILLI_SOCKET` and `SKILLI_SKILLIE` are read by `$SKILLI_CLI` itself:
nothing to do with them. Details: [`docs/do-it-here-from-anywhere.md`](../docs/do-it-here-from-anywhere.md).

## Use skil.li's other features

Everything the launcher runs, a skillie runs too, two ways:

- **Wait for it**: `"$SKILLI_CLI" call <tool> name=value…`, any of the tools
  agents get (the same exits as above). CleanShot X's commands are
  `run_action`, with what happens to the capture as `variant`:

  ```bash
  "$SKILLI_CLI" call run_action id=cleanshot.capture-front-window variant=copy
  "$SKILLI_CLI" call run_action id=cleanshot.scrolling-capture variant=autoscroll
  "$SKILLI_CLI" call run_action id=cleanshot.capture-text variant=nolinebreaks
  ```

  `variant` takes `copy`, `save`, `annotate`, `pin` or `upload` on a capture
  (upload asks every time: the capture leaves the Mac), `start` or
  `autoscroll` on Scrolling Capture, `linebreaks` or `nolinebreaks` on
  Capture Text, a tab on CleanShot Settings. A wrong one is said, with the
  ones it takes.

  A file goes to CleanShot with `file`, its full path:

  ```bash
  "$SKILLI_CLI" call run_action id=cleanshot.open-annotate file="$HOME/Desktop/Shot.png"  # its editor
  "$SKILLI_CLI" call run_action id=cleanshot.pin file="$PWD/$1"                          # pinned above every window
  "$SKILLI_CLI" call run_action id=cleanshot.quick-access file=/Users/me/Movies/Demo.mp4  # a Quick Access Overlay
  ```

  Annotate, Pin and Capture Text (the text in it copied; `variant` still
  says the line breaks) open PNG and JPEG images, Quick Access those and
  MP4 videos. The Finder selection's and the latest screenshot's commands
  take `file` too, instead of what they read. A type CleanShot does not open, a
  file that is not there, a path that is not full or an empty `file` exits 1
  and says why; nothing opens.
  The other apps skil.li drives (Warp, Zed, and any app in your app
  files) are `run_action` too, by `<app id>.<command id>`; a variant goes
  in `variant` the same way:

  ```bash
  "$SKILLI_CLI" call run_action id=warp.mcp                  # Warp's MCP servers
  "$SKILLI_CLI" call run_action id=zed.tool-permissions      # Zed's agent tool permissions
  ```

  A command its app file says asks first (it sends, deletes or calls
  someone) asks in skil.li's card every time; declined, the call exits 1.
- **Fire and forget**: `open "skilli://run/<entry>"`, the link ⌘K → Copy Link
  gives on any row (`skilli://run/system:link:cleanshot.capture-area`,
  `skilli://run/system:link:warp.settings`). What could change the Mac
  asks first, as for any link.

## Arrange the windows

Arrange Windows puts every window where you usually put it (learned on
the Mac from your own moves), or applies the layout saved for the apps
open. Run it again within 10 seconds and every window goes back where it
was before:

```bash
"$SKILLI_CLI" call run_mac_command command=arrangeWindows
open "skilli://run/system:arrangeWindows"   # asks first, as Show Desktop does
```

## Keep the Mac awake

A long job can keep the Mac awake while it runs, then turn it off:

```bash
"$SKILLI_CLI" call keep_awake minutes=90   # awake 1 h 30 (or until=18:30)
"$SKILLI_CLI" call keep_awake more=60      # one hour longer than set now; with no end set, Turn Off in 1 h
"$SKILLI_CLI" call keep_awake sleep=true   # Turn Off Keep Awake
open "skilli://run/system:keepAwake"       # Keep Awake on, or Turn Off Keep Awake while it is
```

Lengths go up to a week. While it is kept awake, the cup shows in the menu
bar and at the right of the launcher's empty field, with the time left (the
cup alone when it has no end).

## Convert a currency

The launcher's conversion, waited for, at the day's rates (central banks,
else the ECB), computed on the Mac:

```bash
"$SKILLI_CLI" call convert_currency amount=800 from=TRY to=EUR
# {"amount":"800","from":"TRY","rate":"1 TRY = 0.01796 EUR","rateDay":"2026-10-27","result":"14.37","source":"central banks","to":"EUR"}
"$SKILLI_CLI" call convert_currency amount=49.90 from=GBP   # to the user's own currency
```

`result` has the target currency's decimals (none for JPY). Exit 1 when a
currency is not in the day's table, when there is no table yet, or when
Convert Currencies is off in Settings → Catalog. The launcher has no link
that opens it on a query yet: a link runs the Catalog entry, which opens
the launcher for typing.

## Record a meeting

A skillie opens the Record card; the user starts the recording with ↩
in it (recording someone needs their consent: nothing records on its
own):

```bash
said=$("$SKILLI_CLI" call record_meeting title="Weekly sync")  # waits for ↩ or esc in the card
open "skilli://record?title=Weekly%20sync"  # the card, without waiting
```

Later, while it records (another skillie, or a later step of this one):

```bash
"$SKILLI_CLI" call recording_status      # Recording “Weekly sync” · 12:04, and its folder
"$SKILLI_CLI" call pause_recording       # nothing written until resume_recording
"$SKILLI_CLI" call set_recording_source source=screen on=true   # the meeting's window; webcam, microphone, mac_sound too
"$SKILLI_CLI" call set_recording_source source=screen on=true display=main   # the whole main screen instead
"$SKILLI_CLI" call set_recording_source source=screen on=true display="LG UltraFine"   # that screen, by its name
open "skilli://record/source?source=screen&display=main"   # the same from a link: asked in the card every time
"$SKILLI_CLI" call stop_recording        # stops; the transcript is made on this Mac, its window opens
open "skilli://record/stop"              # pause, resume, stop: asked in the card every time
```

A sound or video file made a recording (a voice memo, a call app's own
recording), transcribed on this Mac with its voices told apart; the file
stays where it is:

```bash
"$SKILLI_CLI" call import_recording path=~/Downloads/Board\ call.m4a   # its folder once its sound is copied
open "skilli://record/import?file=%2FUsers%2Fme%2FCall.m4a"       # Import Recording's panel on that file: ↩ imports
```

`record_meeting` exits 0 once the user pressed ↩ ("Recording “Weekly
sync” started."), 1 when the card was closed. The whole screen records
every app on it, notifications included (skil.li's own windows are left
out): turn it on only when the user asked for it. `display=meeting` is
the screen the meeting's window is on (else the main one); a name no
screen has exits 1 with the screens' names. The link takes the tool's
parameters (`on=false` turns a source off). Pausing and stopping ask
in the skillie's card unless the user's tool rights allow them. While a
meeting is on, the card is that meeting's (its title unless one is
given, its attendees, in person the microphone only).

Once a transcript is made, what its window's ⌘K does, with your own SI
(Settings → SI Accounts) reading the transcript, asked in the card every
time, the recording named:

```bash
"$SKILLI_CLI" call list_recordings                                   # ids, titles, dates, lengths: no words
"$SKILLI_CLI" call get_transcript recording="Weekly sync"            # its transcript.md (empty: the newest)
"$SKILLI_CLI" call recording_followup action=summary recording="Weekly sync"       # written to summary.md, and printed
"$SKILLI_CLI" call recording_followup action=chapters                              # the newest recording's
"$SKILLI_CLI" call recording_followup action=action_items recording="Weekly sync"  # each added to Reminders
"$SKILLI_CLI" call recording_followup action=recap_mail recording="Weekly sync"    # a mail to the attendees opens: you send it
"$SKILLI_CLI" call recording_followup action=ask question="Who sends the deck?"
open "skilli://record/summary?recording=Weekly%20sync"   # …/chapters, …/actions, …/recap, …/ask?question=…
open "skilli://record/open?recording=Weekly%20sync&at=724"   # its window, playing from 12:04
"$SKILLI_CLI" call rename_recording recording="Weekly sync" title="Weekly sync with legal"   # its folder too
open "skilli://record/rename?recording=Weekly%20sync&title=Weekly%20sync%20with%20legal"   # asked first
```

A skillie made for recordings says so in its header; a recording's ⌘K
lists it and runs it with the recording's folder in `SKILLI_RECORDING`.
Settings → Recorder → After each transcript marks one to run on every
recording once its transcript is made (off until you pick it; the
recording's window says when it ran):

```bash
# @skilli.forRecordings true
[ -n "$SKILLI_RECORDING" ] || { echo "Run me from a recording's ⌘K."; exit 1; }
# One file per recording, named after its folder ("2026-10-22 14.00 Weekly sync.md").
mkdir -p ~/Documents/Meetings &&
  cp "$SKILLI_RECORDING/transcript.md" ~/Documents/Meetings/"$(basename "$SKILLI_RECORDING").md" && echo "Copied."
```

The recordings made, and the recorder's settings (Settings → Recorder,
each asked in the card):

```bash
open "skilli://run/cmd:searchRecordings"   # the launcher, on Search Recordings
"$SKILLI_CLI" call set_setting pane=recorder setting=recorderRetention value=month        # Delete after: 1 month
"$SKILLI_CLI" call set_setting pane=recorder setting=recorderMeetingCard value=false      # no Record ⌘R on the meeting card
"$SKILLI_CLI" call set_setting pane=recorder setting=recorderScreen value=true             # every call's window recorded too
"$SKILLI_CLI" call set_setting pane=recorder setting=recorderFolderPath value=~/Documents/Meetings  # moves them there
```

## Add an app's links

An app that documents its own links (its URL scheme) can be driven like
CleanShot X: put an app file in `~/Library/Application Support/skil.li/Apps`
(docs/apps.md, "App files", gives the format), ask your SI to add it
(`create_app_link`), or share it as a link that shows it whole before Add:
`skilli://apps/import?app=<the file, percent-encoded>` or
`skilli://apps/import?url=https://example.com/app.json`.

## Run the user's shortcuts

Every shortcut in the user's Shortcuts library is a skil.li row. A skillie
runs one in two ways:

```bash
open "skilli://run/system:shortcut:0B7E5C2A-1D34-4E6F-8A90-B1C2D3E4F501"  # its row's link (⌘K → Copy Link)
said=$("$SKILLI_CLI" call run_shortcut name="Morning Routine" input="$1")  # waits, its text in $said
```

- The link runs it as its row does, asked first in skil.li's card (a
  shortcut can do anything; Always there lets links run it at once). The
  script does not wait for it.
- `call run_shortcut` waits: `name` as the launcher shows it, `input` the
  text it works on, or `selection=true` for the text selected in the app
  in front. Exit 0: done, what it gave back on standard output. Exit 1: not
  run or failed (declined, no such shortcut, nothing selected, Shortcuts'
  own error), why on the first line of standard error. Exit 2: the call
  is written wrong. Asked in the skillie's card as any agent's call is,
  unless the user's tool rights allow "Run a shortcut".
- The first time a shortcut hands its result back, Shortcuts itself asks
  ("Allow … to produce 1 text item?"); the call waits for that answer too.

## Start a GitHub workflow and follow it

A workflow with `workflow_dispatch` (a release, a deploy) started with its
inputs, with the user's GitHub sign-in in skil.li (Settings → GitHub). The
card asks every time, naming the workflow and its inputs; that answer also
approves the run's environment when GitHub says the user may approve it.
Then a box in the menu bar shows the step it is on, its menu every job and
step, and a card says at the end where the release is, or which step
failed:

```bash
"$SKILLI_CLI" call run_github_workflow repo=nomdelasociete/skilli workflow=release.yml ref=main \
  inputs='{"bump":"patch","critical":false}'
# Started. skil.li follows it in the menu bar and says how it ended.
# Release patch #12 · queued
# https://github.com/nomdelasociete/skilli/actions/runs/123
"$SKILLI_CLI" call get_github_workflow_run run=https://github.com/nomdelasociete/skilli/actions/runs/123
open "skilli://github/workflow?repo=nomdelasociete/skilli&workflow=release.yml&ref=main&bump=patch"  # every other item is an input
```

The call answers once the run started (it does not wait the run out:
120 s is a skillie's whole time); exit 1 when the card was declined, the
workflow or an input is wrong, or GitHub refused (its message on the first
line of standard error). skil.li's own release is one:
[`script/release/release.skilli`](../script/release/release.skilli),
"Release skil.li", with Patch, Minor and Critical patch.

## Install

Double-click a `.skilli` file: skil.li opens Settings → Skillies and shows
the skillie whole (where it came from, every line of its code) before you
add it. A `.skilli` file is the script itself, renamed; rename any script
from the collection to `<name>.skilli` to add it this way. A link does the
same: `skilli://skillies/import?url=https://…/the-script.sh`. A skillie with
the same title as one you have replaces it, after you say Replace. Nothing
runs when it is added.

You can still put a script in your local skillies folder by hand (Settings →
Skillies → Show in Finder); the app discovers it by its header. It does not subscribe to
the online collection or replace installed scripts on its own. Website
publication and local installation are separate operations.

`skilli://commands/import` imports SI prompt files, not these scripts.
