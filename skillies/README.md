# Community skillies

This folder is the source of truth for the website's Skillies collection.
Each file is a command that skil.li can run locally. Website cards, source
previews, downloads and `catalog.json` are generated from these exact files.

## Contribute

1. Fork this repository. Add one script at `skillies/<category>/<unique-name>.sh`
   (also supported: `.py`, `.js`, `.rb`, `.swift`). Use lowercase hyphenated names.
2. Start with a shebang and the `@skilli` header from an existing example.
   Include `schemaVersion 1`, `title`, `description`, `packageName` and `mode`.
   Keep metadata within the first 60 lines and 8 KB, as required by the app.
3. Include the full MIT license and your copyright notice in the script, so the
   license travels with a downloaded file. Only submit code you can license.
4. Document required applications, external runtimes, network access and effects
   in the description or script comments. Do not embed credentials or personal
   paths. Use arguments for user input (up to three `@skilli.argumentN` JSON
   declarations). Set `@skilli.needsConfirmation true` for commands that change
   or delete data. This asks before the whole script; it is not a sandbox.
5. Try the script on your Mac. In skil.li, open Settings → Launcher → Skillies →
   Show in Finder and put it there. Check arguments, output and failure cases.
6. Run `python3 website/build.py --preview` from the repository root. Open a PR
   describing what you tested and any dependencies. Do not edit generated files
   under `website/skillies/files/` or the generated catalog HTML.

A maintainer reviews the code before merge. The website build validates metadata
and builds the site; **it does not execute contributed scripts**. A merge to
`main` publishes through Workers Builds when `skillies/` changes (see
[`website/README.md`](../website/README.md)). By hand, after the build:
`npx wrangler@4.151.3 deploy --config website/wrangler.jsonc`. A new skillie
needs no manual website edit beyond that publish.

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
"$SKILLI_CLI" call stop_recording        # stops; the transcript is made on this Mac, its window opens
open "skilli://record/stop"              # pause, resume, stop: asked in the card every time
```

`record_meeting` exits 0 once the user pressed ↩ ("Recording “Weekly
sync” started."), 1 when the card was closed. Pausing and stopping ask
in the skillie's card unless the user's tool rights allow them. While a
meeting is on, the card is that meeting's (its title unless one is
given, its attendees, in person the microphone only).

The recordings made, and the recorder's settings (Settings → Recorder,
each asked in the card):

```bash
open "skilli://run/cmd:searchRecordings"   # the launcher, on Search Recordings
"$SKILLI_CLI" call set_setting pane=recorder setting=recorderRetention value=month        # Delete after: 1 month
"$SKILLI_CLI" call set_setting pane=recorder setting=recorderMeetingCard value=false      # no Record ⌘R on the meeting card
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

## Install

Download a script from the collection, inspect it, and put it in your local
skillies folder using Show in Finder above. The app discovers it by its header.
It does not subscribe to the online collection or automatically replace installed
scripts. Website publication and local installation are separate operations.

`skilli://commands/import` imports SI prompt files, not these scripts.
