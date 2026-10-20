# Apps skil.li drives — CleanShot X first

Status: 2026-10-20. Built: CleanShot X's commands in the launcher, the
Catalog, ⌘K, keys, links, Ask and agents, with the front window and the
latest screenshot (Order 1 and 3). Still proposed: Settings → Apps, files
into CleanShot, Shortcuts and the next apps.

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
| Annotate File… · Pin File… | `open-annotate` · `pin` (CleanShot asks for the file) | — |
| Toggle · Hide · Show Desktop Icons | `toggle-` · `hide-` · `show-desktop-icons` | — |
| Capture History | `open-history` | — |
| Restore Recently Closed | `restore-recently-closed` | — |
| CleanShot Settings | `open-settings` | each tab (`tab=general…about`) |

"Latest screenshot" is the file Paste Latest Screenshot already finds.

Phase 2, files into CleanShot (⌘K on what skil.li already lists): an image in
the clipboard history, an image or MP4 in Search Files, the Finder selection →
Annotate in CleanShot · Pin in CleanShot · Quick Access Overlay
(`add-quick-access-overlay?filepath=`, PNG, JPEG, MP4).

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

- One row per installed app it knows: icon, name, version, one state line
  ("Ready", or "Allow skil.li in CleanShot → Advanced" with Open, which opens
  CleanShot itself: its own settings link needs the API already allowed).
- An app's page: its own options first (CleanShot: Capture Text keeps line
  breaks), then its commands, a long list last: each with its key and Show in
  search.
- Apps not installed are not listed: no promises.
- Keys and the Catalog index the same commands; their settings live here only.

## Next apps

The layer is generic (`LinkedApp` and `AppLinkCommand` in SkilliCore: bundle
id, scheme, minimum version, commands with title, words in English and
French, symbol, URL template, variants, what asks first). Each app is added
only after its link format is read in its own documentation and run once for
real.

1. **Shortcuts** (Apple, `/usr/bin/shortcuts list` / `run`): every shortcut the
   user made is a row. That reaches every app's App Intents without skil.li
   knowing them.
2. Apps with documented schemes, to check one by one: Slack, Zoom (already
   parsed in Agenda), Notion.
3. App files: `~/Library/Application Support/skil.li/Apps/*.json`, written by
   an agent (`create_app_link`, like `create_skillie`) or a `skilli://` import,
   shown whole before Add, as Commands imports are.

## Order

1. Done: CleanShot rows in the launcher, Catalog, ⌘K variants, links, agents
   (replaces `ActionCatalog.cleanShot`).
2. Settings → Apps with CleanShot's page.
3. Done: Capture / Record Front Window, Latest Screenshot rows (the frame
   checked with a real capture, one display).
4. Files into CleanShot (⌘K on clipboard images, files, Finder selection).
5. Shortcuts, then the next apps.
