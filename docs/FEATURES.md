# skil.li features

Everything skil.li does, one area per section, in the order of Settings'
sidebar: one feature, one place. Each section says how to reach the
feature, what it does, then its settings (Settings → that pane). How to
use each area, step by step with screenshots: the
[guides](../website/guides/README.md) (skil.li/guides).

✦ is the Hyper Key: Caps Lock held. Keys are the defaults; every one can
be changed in Settings → Keys. Whatever of yours you delete (a copy, a
file moved to the Trash, a reminder, a snippet, a command, a quicklink,
a saved IBAN, a key, a server…) goes at once, nothing asked, and ⌘Z
brings it back for 10 s. "SI" is skil.li's name for the AI it
uses; it writes with your own Claude or ChatGPT and chooses with your
TypeSafe Jev or OpenAI Decisions key.

`FeaturesDocTests` keeps this file complete: every entry of the Catalog
(`FeatureCatalog`) and every setting (`SettingsTable`) must be here, in
its pane's section. Add a feature here when you build it.

## Contents

1. [General](#general)
2. [Keys](#keys)
3. [Privacy](#privacy)
4. [Backup](#backup)
5. [Launcher](#launcher)
6. [Clipboard](#clipboard)
7. [Snippets](#snippets)
8. [Emoji](#emoji)
9. [GIFs](#gifs)
10. [Windows](#windows)
11. [Mac](#mac)
12. [Calendar](#calendar)
13. [Reminders](#reminders)
14. [GitHub](#github)
15. [Apps](#apps)
16. [Your Details](#your-details)
17. [Ask](#ask)
18. [Commands](#commands)
19. [Tools](#tools)
20. [Skillies](#skillies)
21. [SI Accounts](#si-accounts)
22. [Catalog](#catalog)
23. [About](#about)

<!-- pane: general -->
## General

Ready as soon as you log in, in the glass you like.

- **Menu bar**: skil.li's S, with Open skil.li (its real keys), Settings…,
  Privacy… and Quit; it also shows what is running (timers, Keep Awake,
  the next meeting, a skillie's line).
- **skil.li Settings**: every option, shortcut and account. ⌘, in the
  launcher, the menu bar, or reopening skil.li while it runs.
- **Quit skil.li**: its shortcuts stop until you open it again.
- **Welcome to skil.li**: the first launch's welcome, a minute of doing:
  Accessibility turned on with a guide at System Settings' switch, Caps
  Lock held to feel the Hyper Key, the launcher's keys chosen (⌘Space
  instead of Spotlight, ✦Space, or your own) and pressed, your SI
  found or connected, a sentence fixed with ✦K G and taken back with ⌘Z,
  then what it set up, line by line (missing ones say where to set them).
  Your SI's step has both: the SI that writes (Claude Code, Codex, a key)
  and the one that chooses (a TypeSafe Jev key, recommended). It asks for
  no other permission:
  each is asked where you first use what needs it (macOS's own question,
  right there). Closed with ✕ or Later, it never comes back by itself:
  Set Up skil.li… stays in the menu bar and here until Accessibility is
  on, and Welcome to skil.li in the launcher shows it again.

Settings: Open skil.li at login · Show in menu bar · Glass (Regular or
Clear, with a live preview) · Launcher position (Reset).

<!-- pane: keys -->
## Keys

Caps Lock becomes your Hyper Key, ✦, and every shortcut is yours to
change.

- **Hyper Key**: Caps Lock held is ✦ (⌘⌃⌥⇧); tapped alone it sends
  Escape. Works alongside Raycast's own Hyper Key.
- **Shortcuts**: one key (✦A) or a chain (✦K then U), several per
  command; a panel shows what comes next in a chain (✦K, ✦W).
- **No shared keys**: a shortcut is refused when macOS, the launcher or
  another skil.li shortcut already uses its key; the refusal says who and
  where to turn it off. Two exceptions, each doing the same thing as
  macOS's: Search Emoji may take ⌃⌘Space from Emoji & Symbols, and the
  launcher ⌘Space from Spotlight (the welcome recommends it): skil.li then
  turns Spotlight's own ⌘Space off, and back on if the launcher leaves it.

Default keys:

| Keys | Does |
|---|---|
| ✦Space | Open skil.li (the launcher) |
| ✦A | Ask |
| ✦V | Ask by Voice |
| ✦D | Dictate |
| ✦C | Clipboard History |
| ⌃⌘Space | Search Emoji |
| ✦U | UPPERCASE Selection |
| ✦K U · L · T | UPPERCASE · lowercase · Title Case |
| ✦K G · I | Fix Spelling & Grammar · Improve Writing |
| ✦K E · R | Translate to English · Translate to French |
| ✦K V | Paste in Sequence |
| ✦K C · F · S | CleanShot: Capture Area · Fullscreen · Scrolling Capture |
| ✦W ← → ↑ ↓ | Left · Right · Top · Bottom Half (again: ⅔, then ⅓) |
| ✦W F · A · C | Maximize · Almost Maximize · Center |
| ✦W U · I · J · K | The four quarters |
| ✦W 1 · 2 · 3 · 4 · 5 | Thirds, then left and right two thirds |
| ✦W N · P · R | Next · Previous Display · Restore |
| ⌘, (in the launcher) | Open Settings from the launcher |

Settings: Hyper Key · Advanced: Tap Caps Lock alone to send Escape ·
Shortcuts (every one, recorded by pressing the keys) · Add Shortcut
(apps, URLs, CleanShot, Shortcuts, System Settings panes, sound devices,
layouts, skillies, projects, every launcher command, snippets,
quicklinks).

<!-- pane: privacy -->
## Privacy

What skil.li may use on this Mac, and all it sends out: what, when,
where.

- **Permissions**: each one with what it turns on, its state live and
  its one button; the apps skil.li sends commands to.
- **What Leaves This Mac**: every feature that sends anything, grouped
  by where it goes (Claude, ChatGPT, OpenAI, TypeSafe Jev, GitHub,
  Frankfurter and the ECB, your servers, websites, Apple): what, when,
  and whether its switch is on.
  Each pane ends with its own line of it.
- skil.li reopens itself when System Settings quits it to apply a
  permission.

Settings: Permissions · Apps skil.li Sends Commands To · What Leaves
This Mac.

<!-- pane: backup -->
## Backup

A copy of everything skil.li keeps, in a folder you choose.

- **Back Up skil.li Now**: saves your settings and files (snippets,
  commands, layouts, skillies…) to the folder; never the clipboard
  history nor the meeting recordings, nor the words said in them. From
  the launcher or Settings.
- **Scheduled backups** and **Restore** from a backup.

Settings: Back up to · How often · Keep · Back Up Now · Backups.

<!-- pane: launcher -->
## Launcher

The search panel you open from anywhere. ✦Space.

- **Apps, commands and everything below**, by a fuzzy search that learns
  what you pick; a name typed whole comes first.
- **Recent searches** with ↑ in the empty field; **Pin** a row from ⌘K
  to keep it first.
- **⌘K Actions** on every row: what the row can do, Copy Link, Set
  Alias…, Set Shortcut…, Pin; ⌘↩ the second action; ⌃N / ⌃P move.
- **The same keys everywhere**: the footer names the selected row's ↩
  ("Paste ↩", "Join ↩", "Quit ↩"), ⇥ where it does something, and ⌘K;
  ⌘C copies the row's value (its name when it has nothing else), silently;
  ⇥ in a mode shows the row's actions, never Ask; esc steps back (out of a
  mode to what you had typed, then closed). What fails says why in a line,
  never a beep.
- **Modes** by a prefix, each with a chip: see their sections (Clipboard
  `cb`, Snippets `snip`, Emoji `:`, GIFs `gif`, Calendar `cal`, Reminders `todo`,
  GitHub `pr`, the Catalog `?`).
- **Search Files** (`f`): by name with Spotlight, or by what it was about
  with ⇥. ↩ opens, ⌘↩ shows in Finder; with CleanShot X, ⌘K on an image
  or an MP4 sends it there (annotate, pin, Quick Access).
- **Search Tabs** (`tab`): any tab open in Safari, Chrome, Arc, Brave,
  Edge…; ↩ shows it.
- **Search Browser History** (`hist`): a page you visited, by its words
  or by meaning with ⇥ (Safari, Chrome, Arc, Brave, Edge, Vivaldi, Opera,
  Firefox, Zen).
- **Search Contacts** (`@`): by name, company, email, number or city; the
  card writes a mail or opens Contacts.
- **Search Projects**: recent folders of Cursor, VS Code, Windsurf, Zed,
  Sublime Text, JetBrains; ↩ opens in the editor.
- **Homebrew** (`brew`): search, install, upgrade, uninstall formulae and
  casks; Upgrade All.
- **Calculator**: math as typed (French decimals, percentages), units,
  time in a city; ↩ pastes the result in your app, ⌘↩ or ⌘C copies it.
- **Convert Currencies**: "800 TRY" (to your currency), "800 TRY in €",
  "49 £ en dollars", "100 usd in eur, gbp", "120 € + 30 $", "49 $ * 12",
  answered as you type at the
  day's mid-market rates (central banks through Frankfurter, else the
  ECB); the row says the rate and its day. A price selected where the
  launcher opens comes first, converted. ⌘K: Copy with Currency ⇧⌘C,
  Copy Rate. Converted on this Mac; only the day's table is downloaded.
- **Kill a Process** (`kill`): quits an app and its helpers, or what
  listens on a port; ⇧↩ forces. A running app's row says "· running" and
  its ⌘K adds Quit and Force Quit.
- **Switch Window**: any open window, by title or app.
- **Search Menu Items** (`m`): every menu item of the app in front, by its
  name as typed, without SI ("m export pdf"); each row says where it is
  and its keys; ↩ chooses it (refused by the app, a line says so).
  Ask finds one by meaning instead.
- **System Settings Panes**: "displays", "night shift", "bluetooth"…
  opens that pane.
- **Links**: `skilli://run/…` runs any Catalog row from any app (⌘K →
  Copy Link); what takes the Mac away asks first, and Always ⌘↩ in that
  card lets links run that entry at once (Settings → Catalog → Trusted
  Links).
- **Reset Launcher Position**: drag the launcher by its glass anywhere
  (guides pull it to the middles); this puts it back.

Settings: the launcher's keys and Open Settings from the launcher ·
Search browser history by meaning with ⇥ · Search files by meaning with
⇥ · Advanced: Opens on · Starts again empty · Type in English while
open.

<!-- pane: clipboard -->
## Clipboard

Everything you copy, and your screenshots, ready to paste again.

- **Clipboard History** (✦C, `cb`): text, images and files; search
  without accents, even words inside images; ⇥ by meaning ("my train
  ticket from yesterday") or by what a copy is ("email", "a link"). ↩ pastes, ⇧↩ plain text, ⌘↩ copies, ⌘⌫ forgets
  (⌘Z brings it back for 10 s). With CleanShot X, ⌘K on an image
  annotates it, pins it or adds it to Quick Access.
- **Previews** by kind: a link's card (picture, title, site), a color's
  swatch with Hex, RGB, HSL, an image with what SI sees and its words, a
  file's thumbnail, an email, phone or address, code, long text.
- **Paste in Sequence** (✦K V): your last copies one after another, a key
  each, newest first.
- **Paste Latest Screenshot**: your last screenshot in the app in front.
- Passwords marked secret by password managers are never kept.

Settings: Keep clipboard history · Keep screenshots too · Folder · Keep
copies for · Clear History · Advanced: Search by meaning with ⇥ · Show
link previews · Read text in images · Images you copy, by what they
show · Screenshots, by what they show · Never keep copies from.

<!-- pane: snippets -->
## Snippets

Text you type often, from a keyword or the launcher.

- **Snippets**: saves a text once (with `{date}`, `{clipboard}`,
  `{cursor}`…); its keyword types it anywhere, at once or after a space
  or ↩, and so does a shortcut of its own. Never in password fields.
- **Search Snippets** (`snip`): by name, or by what you need with ⇥
  ("my iban"). Beside the list, the snippet as it would type now (today's
  date, where the caret ends, the copy on the clipboard when Paste from
  Other Apps allows skil.li; otherwise `{clipboard}` stays as written and
  the clipboard is not read) and its keyword, when it expands, alias,
  shortcut and size. ↩ types it, ⌘↩ copies it.
- **New Snippet** in the launcher: this pane, its editor open on a new
  snippet.

Settings: Expand keywords as you type · Expand (with a preview) · Find
snippets by meaning with ⇥ · Snippets (each in its editor) · Advanced:
Keywords stay as typed in.

<!-- pane: emoji -->
## Emoji

Every emoji and symbol, by its name or by how you feel, typed where you
are.

- **Search Emoji** (⌃⌘Space, replacing macOS's Emoji & Symbols; `:` in
  the launcher): a grid, eight across. Nothing typed, every emoji: Recently
  Used, then Unicode's groups (Smileys & Emotion, People & Body…), then
  the symbols' (Mac Keys, Typography, Arrows, Math, Currencies, Signs &
  Shapes); typed, by name in your language and in English. ←→↑↓ move, the
  name shows at the top; ↩ types it, ⌘↩ copies it.
- **Symbols**: ⌘ ⌥ ⇧ ⎋, the Apple logo, — « » …, → ⇒, ≠ ≤ ∞, € £ ₿, ✓ ★,
  found by their names and the words people use ("cmd", "logo pomme",
  "au carré"); typed itself (→), a symbol finds itself. Every other
  symbol Unicode names is found by that name ("three rightwards arrows").
  Beside a symbol's name, the keys that type it on your keyboard (⌥⇧K
  for the Apple logo on a U.S. layout): next time, no picker.
- **By feeling**: say it ("trop content mais crevé"), then ⇥; it also
  asks by itself when no name fits.
- **Skin tone** for the emoji that come in tones (a family stays as it
  is).
- **Words learned**: an emoji picked after ⇥ comes at once next time by
  the same words, without asking.

Settings: Search Emoji's shortcut · Skin tone · Find emoji by feeling
with ⇥ · Words Learned (Forget, ⌘Z brings them back).

<!-- pane: gifs -->
## GIFs

A GIF where you are, animated: from Klipy, or from the ones on this Mac.

- **Search GIFs** (`gif` in the launcher): a grid, four across, the
  selected one playing. Nothing typed: Recently Used, then Klipy's
  Trending; typed, Klipy's GIFs for the words, then the GIFs on this Mac
  whose name has them. ↩ pastes it animated (Markdown in a terminal or a
  code editor), ⌘↩ copies it, ⇧⌘C copies its link.

Settings: Search GIFs' shortcut · Klipy key (Your Own).

<!-- pane: windows -->
## Windows

Where your windows go, the layouts you saved, and the apps you stopped
using.

- **Window places** (✦W then a key, the launcher, Ask): **Left Half**,
  **Right Half**, **Top Half**, **Bottom Half** (again: ⅔, then ⅓),
  **Top Left Quarter**, **Top Right Quarter**, **Bottom Left Quarter**,
  **Bottom Right Quarter**, **Left Third**, **Center Third**, **Right
  Third**, **Left Two Thirds**, **Right Two Thirds**, **Maximize Window**
  (again puts it back), **Almost Maximize**, **Center Window**, **Move to
  Next Display**, **Move to Previous Display**, **Restore Window**.
- **Window layouts**: **New Window Layout** saves where every window is
  ("save layout Coding"); **New Empty Window Layout** builds one app by
  app. Typing its name puts every window back, apps and files opened,
  displays known by who they are. Edited on the displays in an editor.
- **A display plugged in** asks, in its middle, which of its layouts to
  put back, or to Arrange as Usual when skil.li learned where at least
  half of the windows open go (⌘K: Never Arrange on These Displays).
- **Arrange Windows** (the launcher, Ask, ⌘K on a window, a shortcut you
  give it): every window where you usually put it, learned on this Mac
  from your own moves and ✦W; a layout saved for the apps open comes
  first. Again within 10 seconds puts them back. **Place new windows
  where you usually put them** (off by default) does the same for a
  window as it opens. How both work: the [Windows guide](../website/guides/windows.md).
- **Switch Window**: see Launcher.
- **Auto Quit**: quits the apps you stopped using after a delay you
  choose; never the front app, unsaved work, sound or a call.

Settings: Space between windows (with a preview) · Arrange Windows:
Learn where you put windows · Place new windows where you usually put
them · Forget What skil.li Learned · Layouts ·
Never place · Always leave out of layouts · Monitors ignored when plugged
in · Displays never arranged when plugged in · Apps You Stopped Using: Quit apps you stopped using · Unused for ·
Never quit.

### Windows that go where you put them

How Arrange Windows, Arrange as Usual and Usual places learn and act, in
full: the [Windows guide](../website/guides/windows.md) (also on skil.li, under
Guides).

<!-- pane: none -->
## Mac

Commands for the Mac itself, from the launcher, Ask ("mets la musique en
pause") or a shortcut. Irreversible ones ask first.

- **Power and screen**: **Lock Screen**, **Sleep**, **Sleep Displays**,
  **Restart**, **Shut Down**, **Log Out**, **Keep Awake** (until turned
  off), **Keep Awake for a While** (`awake 2h`, "until 6pm"; a cup in the
  menu bar, its menu: **Turn Off Keep Awake**). While it is kept awake,
  the cup shows at the right of the launcher's empty field, with the time
  left ("42 min") or alone when it has no end; under the pointer it says
  "42 min · Turn Off", and a click turns Keep Awake off. Typing `awake`
  lists it running ("Keep Awake on · until 14:05 (42 min left)", or "Keep
  Awake on · until you turn it off"): ↩ Turn Off Keep Awake, ⌘K Keep
  Awake 1 h Longer, or Turn Off in 1 h when it has no end. `turn off
  awake`, `awake off`, `coupe awake` turn it off too.
- **Appearance and Finder**: **Toggle Dark Mode**, **Toggle Hidden
  Files**, **Show Desktop**, **Eject All Disks**, **Empty Trash**.
- **Apps**: **Quit All Apps**, **Quit Other Apps**, **Hide Other Apps**,
  **Show All Apps**.
- **Sound**: **Play / Pause**, **Next Track**, **Previous Track**,
  **Volume Up**, **Volume Down**, **Mute / Unmute**, **Set Volume**
  (`volume 30`), **Sound Output** (speakers, AirPods, a display…),
  **Microphone**, **Mute / Unmute Microphone**.
- **Connections**: **Turn Wi-Fi On**, **Turn Wi-Fi Off**, **Bluetooth
  Devices** (connect or disconnect AirPods, a keyboard…), **Test Internet
  Speed**.
- **Tools**: **Timer** (`timer 10 min tea`; counts down in the menu bar,
  rings with a card), **Pick a Color** (copies its hex), **System Info**
  (battery, disk, memory, Wi-Fi, IP, uptime), **Clean Keyboard** (every
  key off for a minute to wipe it).
- **Auto Quit**: see Windows.

<!-- pane: calendar -->
## Calendar

Your next meeting, one key away, in the launcher and the menu bar.

- **Calendar** (`cal`): your coming events; ↩ joins a call; ⌘⌫ deletes
  one at once (⌘Z brings it back; one with invitees asks first).
- **Add an Event** (`event lunch with Paul tomorrow 1pm`) and **Copy
  Availability** (your free time in the next five working days); Ask
  does both in your words, and blocks time.
- **The menu bar**: the next meeting, at a glance before ("in 12 min"),
  late and not joined (a red camera), and during (a ring, "20 min
  left"), with the next one beside it.
- **The launcher** shows the coming meeting before you type, in the
  minutes before it.
- **Alerts before a meeting**: a card, or screens going dark, with Join
  and **Check Camera & Mic** (the camera live and the microphone's
  level). None once you are in the call, and a card still up goes as you
  join.
- **Record ⌘R** on the meeting's card, its launcher row and its menu
  (see Recorder).

Settings: Next meeting in the menu bar · Only meetings with a call in
the menu bar · Count down to its end · Leaves the menu bar · The next
one too, during a meeting · Alerts (with Try) · Alerts for events
without a call too · When a meeting starts · Before you type, the
meeting shows · Open events in · Google Meet opens in · Calendars turned
off (by account).

<!-- pane: recorder -->
## Recorder

Your meetings recorded on this Mac, both sides, then written out.

- **Record ⌘R** where the meeting already shows: its card as it starts
  (records, then joins the call), the launcher's meeting row, and the
  menu bar's meeting once you are in the call. Never on its own; the
  first card that offers it says once what it does and that the others
  must agree. Which meeting it is comes from the event and the Mac, no
  model: a call link, a call in an app (the app running the microphone,
  a browser's helper counted as its browser), in person (a place, nobody
  on the microphone: the microphone only), a call app with no event
  ("Discord call 14:30"), or nothing to go on. The recording takes the
  event's title and attendees.
- **Record Meeting** (`rec`, or `rec Weekly sync` with its name): your
  microphone and the Mac's sound, two tracks written as they come,
  transcribed on this Mac when you stop (docs/meeting-recorder.md). Its
  card shows both sources live (a click turns one off) and records
  nothing before ↩; during a meeting, it is that meeting's. While it
  records, a red dot, the time and both sides' waves in the menu bar,
  whose menu pauses, resumes and stops, turns a source off or on, and
  says which app the call is in. When that app leaves the call, or the
  meeting is over and quiet for a minute, a card offers Stop. Then its
  window: both sides' waveforms, played in step, and the transcript line
  by line, Me and Them (Room in person); a click plays from a line; ⌘C
  copies it, ⌘⌫ deletes the recording (⌘Z brings it back). While it is
  open, skil.li is in the Dock and ⌘⇥ with the recorder's icon (its dot
  a red recording light): a click there brings the window back. Without
  headphones, the other side the microphone heard again is left out of
  your lines. Quitting skil.li (a logout too) stops it whole, its
  transcript made at the next launch without asking. The Mac asleep (the
  lid closed) pauses it, never resumed by itself: at wake a card offers
  Resume ↩ or Stop ⌘↩. One never stopped (a crash, a power cut) is
  offered at the next launch: Save, Later or Discard. Nothing leaves the
  Mac. Also
  `skilli://record` and the Meeting Recorder tools (`record_meeting`,
  `stop_recording`…).
- **The webcam and the screen**, off until you turn them on (a click in
  the card, the red dot's menu, or on by default in Settings): the
  webcam, and the meeting's window (in a browser, the window holding its
  tab, which comes forward without a reload) or one you pick, recorded
  in step with the sound. The menu bar says when that window gives no
  picture (minimized, hidden, covered whole and still). The text the
  screen shows is read on this Mac and kept with its time
  (`slides.json`): the window plays both small beside the transcript,
  the slides among the lines.
- **Voices told apart**: the track that holds several people (the other
  side of a call, the room in person, an import) comes out with each
  voice on its own lines (SpeakerKit, on this Mac, in a helper that is
  gone once the transcript is made), Them 1, Them 2… until you name them.
- **Editing the transcript**, in the recording's window: a line selected
  (a click, ↑ ↓), ↩ edits its words in place, ⇥ gives it to the next
  speaker (⇧⇥ the one before), ⌘⌫ deletes it (⌘Z for 10 s), ⌥↩ or a
  click on a speaker's name renames it: the attendees first, and a name
  another speaker has makes the two one (Me is kept). ⌘Z and ⇧⌘Z undo
  and redo while the window is open; every change is written at once.
  **Transcribe Again…** in the language and with the engine picked (one
  asked as skil.li quits is made at the next launch). **Rename…** in its
  ⌘K, or **Rename Recording…** on its row in the launcher: its title and
  its folder (`rename_recording`, `skilli://record/rename`). A transcript
  that failed says why in its window, which offers the engines and their
  languages, then Transcribe ↩. macOS's engine transcribes the languages
  of macOS's dictation too (Dutch, Polish, Swedish…).
- **Better transcription**, a download in Settings → Recorder (1.6 GB,
  from huggingface.co, nothing sent): whisper large-v3-turbo on this Mac,
  40 % fewer errors than macOS's engine and two names in three right, the
  event's attendees and your contacts given as names to expect. Once
  downloaded, the default engine (Settings → Recorder → Engine); Remove
  puts it in the Trash (⌘Z brings it back). The first recording's window
  made with macOS's engine says it once.
- **After the meeting, ⌘K** in its window: **Summary by Claude** (above
  the lines, kept in `summary.md`), **Chapters by Claude** (3 minutes or
  more: headings in the lines, marks on the waveform), **Action Items to
  Reminders** (each at once, someone else's with their name, ⌘Z takes
  them back; each links back to the moment it was said), **Recap Mail to
  the Attendees** (a new message in your mail app: you send it). Each
  goes to the SI you write with (Settings → SI Accounts), only when you
  pick it: the transcript's words, never the sound or the pictures.
  **Ask Claude About This Meeting…** there and on a recording's row in
  the launcher: the answer in the card. Your **skillies for recordings**
  (`@skilli.forRecordings true`) run on it from ⌘K, getting its folder;
  one can run after each transcript (Settings → Recorder, off until you
  pick it). Agents: `list_recordings`, and `get_transcript`, asked each
  time.
- **Import Recording** (`import`): a sound or video file (a voice memo,
  a call app's own recording) made a recording, transcribed on this Mac,
  voices told apart; or drop the file on a recording's window. The file
  stays where it is; one imported while a meeting records waits for that
  meeting's transcript. Also `skilli://record/import` and `import_recording`.
- **Search Recordings** (`recs`): by title, date, attendees, the words
  said and the text read on screen; the best two show in any search too.

Settings: Record ⌘R on the meeting card · Microphone · The Mac's sound
· Webcam · Screen · Language · Better transcription · Engine · After each
transcript · Keep recordings in · Delete after · the recordings, by
month.

<!-- pane: reminders -->
## Reminders

What you have to do, said in one sentence.

- **Reminders** (`todo`): what you have to do; check it off from the
  launcher; ⌘⌫ deletes one at once (⌘Z brings it back).
- **Remind Me** (`remind me to call Paul at 9am`): one line, any words;
  Ask too ("rappelle-moi dans une heure trente"). Places (home, work)
  from your card.
- **Today's reminders in the menu bar**.

Settings: Said reminders go to · Today's reminders in the menu bar ·
Places.

<!-- pane: github -->
## GitHub

Your pull requests and notifications in the launcher: what is ready,
what waits for you.

- **GitHub Inbox** (`pr`): pull requests in four groups (ready to merge
  only when you can), unread notifications; ↩ opens, ⇥ merges (asked
  twice), updates the branch or shows the checks, ⌘⌫ marks read.
- **The strip** under the launcher's search field.
- Sign in with GitHub (device flow); authorize this Mac in the browser for live updates. Access renews automatically and can be revoked independently of GitHub sign-in. If live updates are unavailable, the inbox keeps polling.
- **Server sync** (off by default): the relay reads your pull requests
  and notifications on GitHub with its own authorization, given in the
  browser, and keeps one copy for all your Macs; this Mac only acts
  (merge, update a branch, mark read). A relay that cannot answer is
  said, never read around. Turn it off on one Mac, or delete it for all.

Settings: GitHub (sign in) · Show under the search field · Live updates
from · Live updates token · Server sync.

<!-- pane: apps -->
## Apps

The apps skil.li drives: their commands in the launcher, on a key, in Ask.
Only the apps installed on this Mac are listed: a row each (its icon, how
many commands, how many on keys); a click opens its page, "‹ Apps" goes
back.

- **CleanShot X**: every command its API documents is a launcher row with
  its icon, under "In Your Apps" in the Catalog: Capture Area, Window,
  Fullscreen, Previous Area, Self-Timer, Scrolling Capture, All-In-One,
  Record Screen, Capture Text, Annotate Clipboard Image, Annotate Image…,
  Pin Image…, the desktop icons, Capture History, Restore Recently Closed,
  CleanShot Settings. skil.li adds Capture and Record Front Window (its
  frame, nothing to pick), Annotate or Pin Latest Screenshot, and for the
  file selected in Finder Annotate Selected Image, Pin Selected Image and
  Add Selected File to Quick Access. ⌘K on a
  capture: Copy, Save, Annotate, Pin or Upload it; on Scrolling Capture:
  start at once, auto-scroll; on Capture Text: with or without line
  breaks; on CleanShot Settings: each tab. Each one, variants too, takes a
  shortcut, a link, Ask ("fais une capture de la fenêtre"), agents and
  skillies (`run_action` with its variant; an upload asks every time).
- **Files into CleanShot**: ⌘K on an image in the clipboard history or a
  file in Search Files: Annotate in CleanShot, Pin in CleanShot (PNG and
  JPEG), Add to CleanShot Quick Access (PNG, JPEG, MP4), only what its
  type allows. Agents and skillies give a file: `run_action` with `file`.
- **Where to allow it**: CleanShot runs them while its API is allowed
  (CleanShot → Settings → Advanced → Allow URL scheme API); while it is
  off, CleanShot ignores them without a word. Its page says where to turn
  it on, and Open CleanShot opens it.
- **Shortcuts**: every shortcut in your Shortcuts library is a
  launcher row by its name, with Shortcuts' icon, under "In Your Apps" in the
  Catalog; through them, whatever an app lets Shortcuts do. ↩ runs it;
  what it gives back shows in the card (a line for a moment, more for
  longer; the first time, Shortcuts asks before handing it over);
  nothing given back, nothing said. ⌘K: Run with the Selection
  (the text selected where the launcher opened is its input), Edit in
  Shortcuts. Each one takes an alias, a key (its row's ⋯ in Settings →
  Apps → Shortcuts, or Keys → Add Shortcut → Shortcuts; as it is or with
  the selection), a link (asked first: a
  shortcut can do anything), Ask ("lance mon raccourci du matin"),
  agents and skillies (its link, or `$SKILLI_CLI call run_shortcut` with
  an input or the selection). A shortcut made, renamed or deleted shows
  the next time the launcher opens.
- **Warp, Zed and Microsoft Teams**: the links each documents itself, as
  skil.li's own app files. Warp: Warp Settings, Appearance, MCP Servers,
  Agent Settings, Environments, Platform, Billing and Usage, Team
  Settings. Zed: Zed Settings, Agent Tool Permissions, Agent Skills, Edit
  Predictions. Teams: New Teams Meeting (its scheduling form). Rows,
  Catalog, keys, links, Ask, agents and skillies as CleanShot's.
- **Your app files**: any other app that documents its links, in a file
  of your own (`~/Library/Application Support/skil.li/Apps/*.json`: the
  app's bundle id, scheme, name and oldest version, then its commands with
  their path, title, words in English and French, symbol, parameters,
  variants and what asks first). Each one gets everything CleanShot has:
  rows, Catalog, ⌘K variants, keys, links, Ask, agents and skillies
  (`run_action`), a page here. Your SI adds one ("ajoute les liens de
  Warp": `create_app_link`, the app shown whole in the card), or a
  `skilli://apps/import` link does (the app and every link it opens shown
  before Add). A file skil.li cannot read, or one naming an app it drives
  already (CleanShot X wins), is left out and said at the bottom of the
  list, with why; fixed and saved, it is read again as the launcher opens.
  A command that sends, deletes or calls asks first from links, Ask and
  agents, every time.

Settings: each app's page: its version and what it has, Open, its
links' documentation and your file (Documentation, Show File), its
options (CleanShot: Line breaks in Capture Text), then its commands (or
shortcuts), each with its keys; ⋯ on a row (or a right-click): Add
Shortcut, Add a Shortcut for a variant (Capture and Copy…, With the
Selection), Hide from Search; a hidden one is dimmed, "Hidden from
search".

<!-- pane: yourDetails -->
## Your Details

Forms filled in for you and your people, and commands that know who you
are.

- **Forms**: Do It Here fills a form with your details (and those of
  the people and companies you add); sensitive ones stay in the
  Keychain and wait for one ↩ for the whole form.
- **About You**: what commands may know about you, included when a
  command says so.

Settings: Your other details · People and companies · About You.

<!-- pane: ask -->
## Ask

Say what you want, in any app: skil.li answers, or does it for you.

- **Ask** (✦A, or ⇥ in the launcher): SI answers, rewrites the
  selection, or acts. It reads what you mean, never a pattern: lengths,
  times, people, places. It opens apps, files, projects, panes, menus,
  quits or uninstalls an app, runs a Mac command or a skillie, sets a
  timer or Keep Awake, adds an event or a reminder, writes a mail to a
  contact. Unsure, the card asks. Something you did not say (how long,
  which app, when) is asked in the card: answer just that, the rest is
  kept. A menu item it is sure of is chosen at once; one that quits,
  closes, deletes or sends waits for ↩.
- **Ask by Voice** (✦V): say it; the text appears live, ↩ runs it.
  Speech stays on this Mac.
- **Dictate** (✦D): types what you say into any app, on this Mac,
  knowing your contacts' names.
- **Do It Here**: clicks and types for you in the window in front ("fill
  this form"), step by step, risky steps asked first; a form's sensitive
  details asked once, together.
- **Ask on a Schedule**: "every Monday at 9am sum up my PRs".
- **The card**: answers in Markdown, follow-ups with ⇥ (a changed text too:
  "plus formel", "keep the line breaks", then ↩ puts the new version in
  place), ⌘↩ continues the conversation in Claude Code or Codex.
- **Your Rules**: what agents may do, in your words (Allow, Ask First,
  Never), checked before each step.

Settings: When It Acts: Approvals · Your rules · Keep Claude ready ·
Voice language · Continue in · Terminal · Use Claude Code's skills too ·
Skills · On a Schedule.

<!-- pane: commands -->
## Commands

Your prompts, on any text, from any app.

- **SI Commands** on the selection, from a shortcut or the launcher:
  Fix Spelling & Grammar, Improve Writing, Translate to English,
  Translate to French, and yours. The card shows the changes; ↩ replaces,
  ⌘C copies.
- Each command: its prompt with variables, questions, output (replace,
  insert after, copy, card), model, tools; imported and shared by file or
  link.
- **New Command** in the launcher: this pane, its editor open on a new
  command.
- **Case changes** without SI: **UPPERCASE Selection**, **lowercase
  Selection**, **Title Case Selection**.

Settings: Commands (each in its editor) · Built In.

<!-- pane: tools -->
## Tools

What commands and agents may do on your Mac.

- **skil.li's tools** for agents (Claude Code, Codex, any MCP client):
  the selection, clipboard, apps, menus, windows, files, calendar,
  reminders, contacts, your shortcuts, the screen's controls… through skil.li's MCP
  server.
- **Rights** per tool: Default, Always Ask, Always Allow, Block; Set
  Rights With Claude Code / Codex….
- **Connected Servers**: your MCP servers (token or OAuth), imported from
  Claude Code, Claude for Mac, Codex and Cursor.
- **Your Tools**: webhooks commands can call.

Settings: skil.li Tools · Connected Servers · Your Tools.

<!-- pane: skillies -->
## Skillies

Your own scripts, run from the launcher like any command.

- **Skillies**: scripts with a title and arguments, run from the
  launcher, a shortcut, Ask or agents; output silent, compact, full or
  inline.
- **In the menu bar**: a skillie's last line, refreshed on its own.
- **Skillie files**: double-click a `.skilli` file (or open a
  `skilli://skillies/import?url=…` link) and Settings → Skillies shows
  it whole, where it came from and every line; ↩ adds it, and one with
  the same title as yours replaces it after you say Replace. Nothing runs
  on add; an inline one with no argument then runs as the launcher opens,
  which the sheet says.

Settings: Your Skillies · In the menu bar.

<!-- pane: aiAccounts -->
## SI Accounts

skil.li writes with your own Claude or ChatGPT, already paid for.

- **Writing**: your Claude subscription (Claude Code) or API key, your
  ChatGPT subscription (Codex) or OpenAI API key; a model per command.
- **Choosing**: your TypeSafe Jev or OpenAI Decisions key decides what
  Ask does and finds things by meaning.

Settings: Writing: Model · Pay for Claude with · Claude subscription ·
Claude API key · ChatGPT subscription · OpenAI API key · Choosing:
TypeSafe Jev key.

<!-- pane: catalog -->
## Catalog

Everything skil.li can do, and how you reach each one.

- **What skil.li Can Do** (`?` in the launcher): every entry by group,
  with its prefix, alias and shortcut; ↩ runs it. Every launcher command
  and Mac command takes a shortcut, and so do your snippets, quicklinks,
  layouts, commands and the skillies that need no argument (⌘K → Set
  Shortcut…, or the entry's popover here): Search Snippets opens
  straight in your snippets. What only types the start of words (Timer)
  or opens where the first of something is made takes none.
- **Aliases**: your own short names for any result.
- **Quicklinks**: search a site from the launcher (`g skilli`, `yt lofi`);
  the selection is the query when none is typed; a shortcut of its own
  opens the launcher with its keyword typed; Add from Library….
  **New Quicklink** in the launcher opens its editor on a new one.
- **From other apps**: every entry's `skilli://` link (⌘K → Copy Link)
  for Shortcuts, a Stream Deck or a page. What could change your Mac
  asks first; Always ⌘↩ trusts that entry only, a skillie with the same
  arguments. Empty Trash, Restart, Shut Down, Log Out, Quit All Apps,
  Quit Other Apps, settings and pastes of your copies (Paste in
  Sequence, Paste Latest Screenshot) are never trusted.
- **Do it here from a link**: `skilli://do?app=TextEdit&goal=…` does
  what the goal says in that app, as Ask's "do it here" would; always
  asked first (Always trusts that goal in that app). A skillie chains
  steps with one link a line, run one after the other; a step that did
  not finish drops the rest. Agents get the same as `do_in_app`.

Settings: Show in search (per entry) · Quicklinks · Reuse an open tab ·
Aliases · Trusted Links (− asks again).

<!-- pane: about -->
## About

Whether each part of skil.li works now, and where to fix it.

- **Health**: one line per feature with where to fix it.
- **Copy Diagnostics**: version, macOS and the lines; nothing personal.

Settings: Health · Copy Diagnostics.

GitHub live updates: authorize multiple accounts and organizations in the browser; manage the selected accounts from Settings → GitHub. The existing pairing remains until authorization succeeds.
