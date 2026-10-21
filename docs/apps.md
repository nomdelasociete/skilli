# Apps skil.li drives — CleanShot X first

Status: 2026-10-21. Built: CleanShot X's commands in the launcher, the
Catalog, ⌘K, keys, links, Ask and agents, with the front window and the
latest screenshot (Order 1 and 3); Settings → Apps (Order 2); files into
CleanShot: ⌘K on clipboard images and files found, the Finder selection's
rows, agents' and skillies' `file` (Order 4); the user's shortcuts in
Apple's Shortcuts app, the same way (Next apps 1); app files, skil.li's
own (Warp, Zed, Microsoft Teams) and the user's, with `create_app_link` and
`skilli://apps/import` (Next apps 2 and 3). Still proposed: a command's
typed argument.

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

One pane for every app skil.li drives, in the block with Calendar,
Reminders and GitHub. "The apps skil.li drives: their commands in the
launcher, on a key, in Ask." Redesigned on 2026-10-21 (the first version
stacked every app on one page, which does not scale and read badly).

Design spec:

- **The list** (the pane's top): the apps skil.li drives that are on this
  Mac, nothing promised for the others. One row each: the app's own icon
  (32 pt), its name, one status line ("22 commands · 2 on keys"; "14
  shortcuts · 1 on a key"; "Reading your shortcuts…"), a chevron. The
  whole row opens the app's page. The same layout for any number of apps.
- **An app's page**, pushed inside the pane, as System Settings →
  Notifications → an app: "‹ Apps" goes back. In order:
  1. Its header, centered like a pane's: the app's icon (64 pt), its
     name, its version and what it has ("5.0.1 · 22 commands"), the line on
     what it needs (CleanShot: where to allow its API: nothing on the Mac
     says whether it is on, see below), one button that opens the app.
  2. Its options, plain rows (CleanShot: Line breaks in Capture Text).
  3. Its commands by group, the long list last. A row: the command's
     symbol in grey (no tile), its title, and its keys as keycaps only
     when it has some. On hover, a ⋯ button (also on right-click): Add
     Shortcut (or Change / Remove), Add a Shortcut for → each variant, Hide
     from Search / Show in Search. A hidden command is dimmed, with "Hidden
     from search". A variant with its own keys shows under its command,
     indented. Recording happens in the row (the keys as typed, the hint
     under the title); leaving the page, the pane or Settings stops it, and
     a shortcut added for it without keys goes.
  4. At most one short footer line.
- **Shortcuts' page**: the same header (Open Shortcuts); while the list is
  still being read, a "Reading your shortcuts…" row; then every shortcut
  as a row like a command's: ⋯ gives Add Shortcut, Add a Shortcut With the
  Selection, Hide from Search, Edit in Shortcuts.
- Settings' search opens the app's page at the row (a command, a
  shortcut, Line breaks in Capture Text). Keys and the Catalog list the
  same commands; their settings live here.

What CleanShot's API state shows: whether it is on cannot be read (checked
2026-10-21 on CleanShot X 5.0.1): turning Allow URL scheme API off changes
nothing in CleanShot's defaults (`allowURLSchemesAPI` stays as it was),
and a link is then ignored, no question asked. So the page never says
"Ready" or "Off": it says where the switch is.

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

2. Done: **the next apps**, as app files skil.li ships (below). Read in
   each app's own documentation on 2026-10-21; only links that work
   without the user's own ids (a team, a channel, a meeting number).

   | App | Shipped | Its documentation |
   |---|---|---|
   | Warp | Warp Settings, Appearance, MCP Servers, Agent Settings, Environments, Platform, Billing and Usage, Team Settings (`warp://settings`, `warp://settings/<page>`) | docs.warp.dev, "URI Scheme" |
   | Zed | Zed Settings (`zed://settings`), Agent Tool Permissions, Agent Skills, Edit Predictions (`zed://settings/<section>`, the links Zed's own docs use) | zed.dev/docs, "CLI Reference" (URL handling), "Tool Permissions", "Skills", "Edit Prediction" |
   | Microsoft Teams | New Teams Meeting (`msteams:/l/meeting/new`: its scheduling form, every parameter optional) | learn.microsoft.com, "Deep links for workflows in Teams" (`https://teams.microsoft.com/l/meeting/new`) and "Deep links" (the `msteams:` form for the desktop app) |

   Each was run once for real on the test Mac (2026-10-21): every Warp
   link opens its Settings page, every Zed link its settings section, and
   Teams' its "New meeting" form.

   Left out, and why:

   - Slack: without a team id and a channel or user id (Slack accepts no
     names), only `slack://open`, which does what opening Slack does.
     Messages already go through `send_message`.
   - Zoom: Zoom no longer documents its client's scheme (the page is gone;
     `zoomus://` only in its mobile SDK). Joining by number is not
     documented; joins already work from the Agenda.
   - Notion, Discord, Signal, 1Password, Outlook, GitHub Desktop: no app
     link documented by the vendor (Notion's pages open from their https
     address; 1Password's item links need the item; GitHub Desktop's
     `openRepo` is only in its source).
   - WhatsApp: `whatsapp://send` is documented for the iPhone; on the Mac
     it only brings WhatsApp forward (tried), no new message.
   - Docker Desktop: only its extension Marketplace page by extension id,
     in a release note; no reference of its links.
   - Linear: documents `linear://` + a page's address, but its Mac app
     declares no scheme, and an issue needs its id.

   Taking one typed value (a meeting number, an email, a search) would add
   more: Teams' chat and call with an email (`msteams:/l/chat/0/0?users=`,
   `/l/call/0/0?users=`), Warp's settings search (`warp://settings?q=`),
   Things' and Todoist's add and search. That needs a command argument the
   way skillies ask for theirs in the launcher: not built yet.
   Documented and ID-free, not shipped because they are not on the test
   Mac to be run once for real: Things 3 (`things:///show?id=today`…),
   Todoist (`todoist://today`…, 9.2+), Bear (`bear://x-callback-url/today`…),
   Fantastical (`x-fantastical://show/calendar`). An app file of the user's
   adds any of them today.
3. Done: **app files** (below).

## App files

Any app that documents its links is one JSON file: skil.li's own in its
bundle (`Contents/Resources/Apps`: Warp, Zed, Teams), the user's in
`~/Library/Application Support/skil.li/Apps/*.json`. Each one gets
everything CleanShot X has: launcher rows (its icon, its name as the
accessory), the Catalog (In Your Apps), ⌘K variants, keys (Add Shortcut →
the app), links (`skilli://run/system:link:<app>.<command>`), Ask, agents
and skillies (`run_action`), and a page in Settings → Apps.

```json
{
  "id": "nimbus",
  "name": "Nimbus Notes",
  "shortName": "Nimbus",
  "bundleID": "com.example.Nimbus",
  "scheme": "nimbus",
  "minimumVersion": "2.0",
  "documentation": "https://example.com/nimbus/links",
  "note": "What the app needs first, one line, on its page",
  "commands": [
    {
      "id": "new-note",
      "path": "x-callback-url/create",
      "title": "New Nimbus Note",
      "description": "Opens a new note",
      "words": ["note", "new", "nouvelle", "note"],
      "symbol": "square.and.pencil",
      "query": [{ "name": "open_note", "value": "yes" }],
      "variants": [{ "id": "pinned", "title": "New Pinned Note", "label": "Pinned", "symbol": "pin",
                     "query": [{ "name": "pin", "value": "yes" }], "since": "2.4" }],
      "group": "Write"
    },
    {
      "id": "share",
      "path": "/share/all",
      "title": "Share All Notes",
      "description": "Sends every note to the team",
      "asksFirst": true,
      "group": "Write"
    }
  ]
}
```

(A made-up app: `nimbus://x-callback-url/create?open_note=yes`, with
`&pin=yes` for its variant, and `nimbus:/share/all`, which asks first.)

- Required: `id` (lowercase, digits, hyphens; a command's id is
  `<id>.<command id>`), `name`, `bundleID`, `scheme`, `commands` (1 to
  60), and each command's `id`, `path`, `title`, `description` (one line,
  its period dropped); a variant's `id`, `title`, `label`, `query`.
- `path`: what follows `scheme://`, a host then a path
  (`zoom.us/join`); one that starts with "/" has no host
  (`msteams:/l/meeting/new`). Its parameters go in `query`, in order;
  a variant's come after its command's. `+` is sent encoded.
- `minimumVersion` and `since`: the app's version from its bundle; a
  command the installed version does not take is not listed.
- `asksFirst`: asked in skil.li's card every time a link, Ask or an agent
  runs it (also when an agent opens the same raw link), never trusted with
  Always; for what sends, deletes, pays or calls someone. Picked in the
  launcher or on a key, it runs.
- Read strictly: a key skil.li does not read, a value of the wrong kind,
  past its length, two lines, a reserved scheme (`http`, `https`, `file`,
  `mailto`, `tel`, `skilli`…) or id, an SF Symbol macOS does not have, and
  the whole file is left out. So is a file that names an app skil.li
  drives already (id, bundle id or scheme): CleanShot X first, then
  skil.li's files, then the user's by name. Settings → Apps lists each
  file left out with why, at the bottom of the list; fixed and saved, it
  is read again as the launcher opens.
- Added three ways: written by hand; by the user's SI (`create_app_link`:
  the installed app by name, its scheme, which the app must declare, the
  address of its documentation, the commands; the approval card shows
  every link); or by a link, `skilli://apps/import?app=<the file>` (repeatable)
  or `?url=https://…/app.json`, which opens Settings → Apps with each app
  and every link it opens, Add or Cancel. Nothing replaces a file: one
  whose app is driven already is refused, said.
- Opened in the app the file names, whichever app macOS gives the scheme
  to. A file removed takes its rows with it; keys on its commands come
  back with it.

## Order

1. Done: CleanShot rows in the launcher, Catalog, ⌘K variants, links, agents
   (replaces `ActionCatalog.cleanShot`).
2. Done: Settings → Apps with CleanShot's page.
3. Done: Capture / Record Front Window, Latest Screenshot rows (the frame
   checked with a real capture, one display).
4. Done: files into CleanShot (⌘K on clipboard images and files found, the
   Finder selection's rows, `run_action` with `file`).
5. Done: Shortcuts.
6. Done: app files; Warp's, Zed's and Teams' links.
7. Next: one typed argument on a command (Teams' chat and call, Warp's
   settings search, a Things to-do), the way skillies ask for theirs.
