# Apps skil.li drives — CleanShot X first

Status: 2026-10-21. Built: CleanShot X's commands in the launcher, the
Catalog, ⌘K, keys, links, Ask and agents, with the front window and the
latest screenshot (Order 1 and 3); Settings → Apps (Order 2); files into
CleanShot: ⌘K on clipboard images and files found, the Finder selection's
rows, agents' and skillies' `file` (Order 4); the user's shortcuts in
Apple's Shortcuts app, the same way (Next apps 1). Still proposed: the
next apps.

Asked for: everything CleanShot X does, from skil.li, so that Raycast is no
longer needed for it; and one place for the apps skil.li drives through
their links, as it does CleanShot X.

## Before (read in the code then)

- 7 of CleanShot's commands, as `SkilliAction.openURL` (`ActionCatalog.cleanShot`):
  Capture Area, Previous Area, Fullscreen, Window, Scrolling, All-In-One,
  Self-Timer.
- Reached only by a shortcut (✦K C · F · S, Keys → Add Shortcut → CleanShot X)
  and by agents (`run_action`, `cleanshot.*`). **Not in the launcher, not in
  the Catalog (`?`), no ⌘K, no `skilli://` link, no parameters.** That is why
  Raycast is still needed: there you type "capture text" and it runs.
- Quicklinks take `http`/`https` only (`Quicklink.swift`), so an app's link
  cannot be added by hand either.

## CleanShot X, all of it

Source: cleanshot.com/docs-api (read 2026-10-20) and Raycast's CleanShot X
extension (23 commands). CleanShot runs these only once its API is allowed
(CleanShot → Settings → Advanced); the first one asks.

Every row below is a launcher row with CleanShot's icon, a Catalog entry, a
`skilli://run/…` link, an Add Shortcut item and an agent action. Rows exist
only while CleanShot X is installed.

| Row | URL | ⌘K |
|---|---|---|
| Capture Area | `capture-area` | Copy · Save · Annotate · Upload · Pin (`action=`) |
| Capture Previous Area | `capture-previous-area` | same |
| Capture Fullscreen | `capture-fullscreen` | same |
| Capture Window | `capture-window` | same |
| **Capture Front Window** (skil.li) | `capture-area?x=&y=&width=&height=&display=` from the front window's frame (Accessibility) | same; nothing to pick |
| Self-Timer | `self-timer` | same |
| Scrolling Capture | `scrolling-capture` | Start at Once (`start=true`) · Auto-Scroll (`autoscroll=true`) |
| All-In-One | `all-in-one` | — |
| Record Screen | `record-screen` | — |
| **Record Front Window** (skil.li) | `record-screen?x=…` from its frame | — |
| Capture Text | `capture-text` | With / without line breaks (`linebreaks=`) |
| Annotate Clipboard Image | `open-from-clipboard` | — |
| **Annotate Latest Screenshot** (skil.li) | `open-annotate?filepath=` | — |
| **Pin Latest Screenshot** (skil.li) | `pin?filepath=` | — |
| **Annotate Selected Image** · **Pin Selected Image** (skil.li) | `open-annotate` · `pin` `?filepath=` the file selected in Finder | — |
| **Add Selected File to Quick Access** (skil.li) | `add-quick-access-overlay?filepath=` the file selected in Finder | — |
| Annotate File… · Pin File… | `open-annotate` · `pin` (CleanShot asks for the file) | — |
| Toggle · Hide · Show Desktop Icons | `toggle-` · `hide-` · `show-desktop-icons` | — |
| Capture History | `open-history` | — |
| Restore Recently Closed | `restore-recently-closed` | — |
| CleanShot Settings | `open-settings` | each tab (`tab=general…about`) |

"Latest screenshot" is the file Paste Latest Screenshot already finds.

Files into CleanShot (built, Order 4): what skil.li already lists, sent to
CleanShot's own windows. The types are CleanShot's (cleanshot.com/docs-api,
read again 2026-10-21): `pin` and `open-annotate` open PNG and JPEG
(`filepath` optional: without it CleanShot asks), `add-quick-access-overlay`
PNG, JPEG and MP4 (`filepath` required, 3.8.1+); a type CleanShot does not
open is never offered.

| Where | What |
|---|---|
| ⌘K on an image in the clipboard history (or one file copied in Finder) | Annotate in CleanShot · Pin in CleanShot · Add to CleanShot Quick Access: the history's own file (`ClipboardStore.imageURL`), nothing copied |
| ⌘K on a file in Search Files | the same, by its type: a PNG or JPEG all three, an MP4 Quick Access only, anything else none |
| The Finder selection | three rows (Annotate Selected Image, Pin Selected Image, Add Selected File to Quick Access), each a key, a link, Ask and agents as every CleanShot command: one file, Finder in front, read through Finder's scripting (its `selection`; macOS asks once, Automation) |
| Agents and skillies | `run_action` with `file` (a full path) on the commands that open one: `cleanshot.open-annotate`, `cleanshot.pin`, `cleanshot.quick-access`, `cleanshot.capture-text` (its text copied, `variant` its line breaks), and the selected and latest ones (the file given instead of what they read) |

The Finder selection is three rows rather than one with ⌘K variants, as
the latest screenshot's two are: each is found by what it does ("annotate
sel…", "pin sel…"), and takes its own key and link.

Raycast's two others, done our way, later:

- "Send Captured Area to AI Chat" → **Capture and Ask**: `capture-area?action=copy`,
  then the next image copied goes to Ask with the question. Claude already
  takes pictures (`AIRequest.images`, do it here's windows); Ask does not
  take one from the user yet.
- "Record Screen at Preset" → Record Front Window, or a saved window layout's
  frame, instead of sizes typed by hand.

Rules:

- A shortcut can point at a variant: "Capture Area → Copy" on ✦K C is
  `cleanshot://capture-area?action=copy`.
- `action=`, `start=`, `autoscroll=` and frames need CleanShot 4.7+: older
  versions get the plain rows only (version read from its bundle).
- CleanShot's coordinates start at the bottom left of a display; Accessibility's
  at the top left of the main one. The conversion is tested with a real
  capture before Capture Front Window ships.
- Links from a web page: captures, history, icons and settings run at once
  (seen, undone as easily). **Upload asks first**: the capture leaves the Mac
  through CleanShot Cloud. Never trusted with Always.
- Nothing is drawn by skil.li: CleanShot's own windows do the work. No capture,
  annotate or recording editor of our own.

## Settings → Apps

One pane for every app skil.li drives through its links, in the block with
Calendar, Reminders and GitHub. "The apps skil.li drives: their commands in
the launcher, on a key, in Ask."

- One row per installed app it knows: icon, name, version, one line on
  where to allow it, and Open, which opens CleanShot itself: its own
  settings link needs the API already allowed.
- Whether the API is on cannot be read (checked 2026-10-21 on CleanShot X
  5.0.1): turning Allow URL scheme API off changes nothing in CleanShot's
  defaults (`allowURLSchemesAPI` stays as it was), and a link is then
  ignored, no question asked. So the line never says "Ready" or "Off": it
  says where the switch is.
- An app's page: its own options first (CleanShot: Line breaks in Capture
  Text: as set in CleanShot, kept, or joined on one line, for its row, a
  key and Ask; ⌘K still offers both), then its commands by group (Capture,
  Record, Annotate and Pin, Desktop Icons, History and Settings), a long
  list last: each with its key and Show in search; a right-click gives a
  variant a key (Capture and Copy…), shown under its command.
- Apps not installed are not listed: no promises.
- Keys and the Catalog index the same commands; their settings live here
  only. Settings' search opens a command here.

## Next apps

The layer is generic (`LinkedApp` and `AppLinkCommand` in SkilliCore: bundle
id, scheme, minimum version, commands with title, words in English and
French, symbol, URL template, variants, what asks first). Each app is added
only after its link format is read in its own documentation and run once for
real.

1. Done: **Shortcuts** (Apple, `/usr/bin/shortcuts list` / `run`): every
   shortcut in the user's Shortcuts library (made, or added from its
   Gallery) is a row. That reaches every app's App Intents
   without skil.li knowing them. Read in `shortcuts help run` / `list` and
   the Shortcuts User Guide ("Run shortcuts from the command line", "Open
   and create a shortcut using a URL scheme", 2026-10-21):
   - `shortcuts list --show-identifiers`: "Name (identifier)" a line. Read
     as the launcher opens, off the main thread; rows run by identifier.
   - `shortcuts run <identifier>`: exits 0, or 1 with its error. Its input
     is the standard input, read as text ("a path piped is treated as
     text"; `-i` would make files of it); its output, what it prints.
   - A shortcut that asks for something waits for the user: 300 s at most.
   - Seen on macOS 27 (not in the guide): the first time a shortcut hands
     what it made to the tool, Shortcuts asks in its own window ("Allow
     “…” to produce 1 text item?": deny, allow once, always allow);
     the run waits for the answer. The input asks nothing.
   - `shortcuts://open-shortcut?name=…` opens its editor (Edit in
     Shortcuts).

   | Where | What |
   |---|---|
   | Launcher | a row each, by name, Shortcuts' icon; ↩ runs it, its text in the card |
   | ⌘K | Run with the Selection (the text read as the launcher opened), Edit in Shortcuts |
   | Catalog | In Your Apps, `system:shortcut:<identifier>`: alias, pin, Off |
   | Keys | Add Shortcut → Shortcuts → each: as it is, With the Selection |
   | Links | `skilli://run/system:shortcut:<identifier>`, asked first, Always offered |
   | Ask | by name, its own question; unsure (under 85 %): asked first |
   | Agents | `list_shortcuts`, `run_shortcut` (name, input or selection): the text it gave back |
   | Skillies | `open` its link, or `"$SKILLI_CLI" call run_shortcut name=… input=…` (waits, exit 0/1/2; skillies/README.md) |

2. Apps with documented schemes, to check one by one: Slack, Zoom (already
   parsed in Agenda), Notion.
3. App files: `~/Library/Application Support/skil.li/Apps/*.json`, written by
   an agent (`create_app_link`, like `create_skillie`) or a `skilli://` import,
   shown whole before Add, as Commands imports are.

## Order

1. Done: CleanShot rows in the launcher, Catalog, ⌘K variants, links, agents
   (replaces `ActionCatalog.cleanShot`).
2. Done: Settings → Apps with CleanShot's page.
3. Done: Capture / Record Front Window, Latest Screenshot rows (the frame
   checked with a real capture, one display).
4. Done: files into CleanShot (⌘K on clipboard images and files found, the
   Finder selection's rows, `run_action` with `file`).
5. Done: Shortcuts. Then the next apps.
