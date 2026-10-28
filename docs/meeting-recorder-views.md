# Meeting recorder: the views

Phase 1: spec, 2026-10-23, written before building, then brought in line
with three rounds of captures on the test Mac (light and dark). Phase 2
(the moment, below): spec, 2026-10-24, written before building from the
Moment section of `docs/meeting-recorder.md`. Quit and sleep: 2026-10-25,
from that file's "Quit and sleep". Phase 3 (the webcam and the screen):
spec, 2026-10-25, written before building. Phases 4 and 5 (last): each
written before building, dated in its own section. In the Dock (a
recording's window as a tile with its own icon): 2026-10-28. That file
says what is recorded, kept and measured; this says what each phase
shows. Each
view is drawn by the code that runs it (`remote recorder` saves
`recorder-*.png`).

## The Record card

Opened by the launcher (Record Meeting, `rec`, or `rec Weekly sync`
with its name), a shortcut, `skilli://record?title=…`, or
`record_meeting` from a skillie or an agent. Never anything automatic:
nothing is recorded before ↩.

One glass card in the middle of the screen the pointer is on, the
meeting card's width (520 pt), its type and its keys. It takes the
keyboard: the user opened it to name the recording. Opened by a link or
a tool while the user types in another app, it leaves the keyboard
alone (as the meeting card does), so a Return on its way there records
nothing; a click gives it the keys.

```
┌──────────────────────────────────────────────────────────┐
│ ● RECORD A MEETING                             English ⌃⌄ │
│                                                          │
│ Meeting 14:30▌                                           │  26 pt, editable
│                                                          │
│ 🎙  Microphone      MacBook Pro Microphone      ▮▮▮▮▯▯   │  live
│ 🔊  The Mac's sound  Every app                  ▮▮▯▯▯▯   │  live
│                                                          │
│ ⓘ  The others in the call must agree to be recorded: in │  first time only
│    many countries, France included, recording a private │
│    conversation without consent is an offense.          │
│ ──────────────────────────────────────────────────────── │
│ Cancel esc                                  ( Record ↩ ) │
└──────────────────────────────────────────────────────────┘
```

- **Eyebrow**: a red dot and "RECORD A MEETING", letterspaced, as the
  meeting card's "STARTS IN". On the right, the language as a word and a
  chevron ("English", its region only when this Mac has it in several);
  a click lists the languages this Mac transcribes (`SpeechTranscriber`).
  Ask's language, else the keyboard's (`VoiceInput`'s rule); chosen for
  this recording only.
- **The name**: a field in the meeting card's title type (26 pt
  semibold), its text selected so typing replaces it. "Meeting 14:30"
  (the time the card opened), or what `rec …`, the link or the tool
  gave.
- **The sources**, a row each: a symbol, the source, the device in the
  secondary color, and a level meter on the right (the meeting check's
  capsule, in the accent color). Both run while the card is open,
  nothing written: the meters are the check. macOS asks once, the first
  time the tap starts (System Audio Recording: seen on the test Mac with
  Screen Recording allowed); a tap it does not allow records silence and
  says nothing (Measured), so only the sound tells.
  - The microphone never asked: macOS asks as the card opens (the card
    steps down to the floating level while it does). Not allowed: the
    row says "Not allowed · ⌘↩ opens Privacy", no meter.
  - The Mac's sound: silent for 3 s while an app plays (Core Audio says
    so): "No sound while Music plays: allow skil.li in Screen & System
    Audio Recording · ⌘↩". Silent with nothing playing: the meter
    alone, empty; nothing to say.
  - Neither source: "Nothing to record: allow the microphone or the
    Mac's sound." and Record dims.
- **A language this Mac cannot transcribe** (none of its engines has
  it): one line under the sources, "Italian can't be transcribed on this
  Mac yet: the recording is kept, its transcript waits." ↩ still
  records.
- **Consent**: the paragraph above, the first time the card opens only
  (`Preferences.recorderConsentShown`), for the sound as for the webcam
  and the screen later.
- **Keys**, under a hairline the width of the card: "Cancel esc" on the
  left; Record ↩, the one filled control (the accent, as Join). ⌘↩ opens
  the missing permission's list when one is said.
- ↩: the card goes and the recording starts at that moment; the menu
  bar shows it. Nothing else is said.

## The menu bar while recording

```
 ● 12:04 ⣀⣤⣶⣤   ← mic above, the Mac below
```

- A red dot (the system's red), the time in monospaced digits, then two
  small waves: the microphone growing up from the middle, the Mac's sound
  down, the last 1.5 s of each track's level as 2 pt bars a point apart
  (sharp on a 1x screen), in the label color.
- Paused: the dot hollow and grey, the time stops, the waves flat.
- Its menu:

  ```
  Recording “Weekly sync” · 12:04      (title, disabled)
  Pause Recording                       (Resume Recording)
  Stop and Transcribe
  ──────────
  Show in Finder
  ```

- After Stop: the dot gives way to a ring that fills as the transcript
  is made, "Transcribing 40 %"; its menu "Transcribing “Weekly sync”…"
  and Show in Finder. Done, the item goes and the recording's window
  opens. A speech model to download first says so there ("Downloading
  English…").

## The recording's window

A window, not a card: it is read and played. Titled, resizable (760 ×
640 to start), its title the recording's; built when opened, released
when closed.

```
┌ Weekly sync ───────────────────────────────────────────────────┐
│ Weekly sync                                                    │  22 pt
│ Wed 22 Oct 2026, 14:00 · 32 min · English                      │
│                                                                │
│ ▶  12:04 / 32:10                                               │
│ Me    ▁▂▅▃▁  ▂▆▇▃▁       ▁▃▂          │                         │  waveform
│ Them      ▃▆▅▂    ▁▂▆▇▅▃▂     ▅▆▃      │                         │  playhead
│ ────────────────────────────────────────────────────────────── │
│ Me    0:00  Hello everyone. Can you all hear me okay?          │
│ Them  0:04  Yes, loud and clear, Camille.                      │
│▐Them  0:07  I can hear you. Ingrid, are you with us?▐          │  playing: lit
│ Me    0:16  That's fine, Ingrid, we don't need to see you…     │
│ ────────────────────────────────────────────────────────────── │
│      Play space   Copy Transcript ⌘C   Show in Finder ⌘↩   Delete ⌘⌫ │
└────────────────────────────────────────────────────────────────┘
```

- **The player**: play/pause and the time; two lanes, Me above in the
  accent color, Them below in the secondary color, the waveform as one
  bar per point column; a click or a drag seeks; the playhead a 1 pt
  line. Both tracks play together, in step (one composition).
- **The lines**: the speaker (Me in the accent, Them secondary), the
  time (monospaced, tertiary), the words (13 pt, wrapped). A click plays
  from the line's start. The line playing is lit (the selection
  capsule) and kept in sight while it plays, unless the user scrolled in
  the last 3 s.
- **Keys**, in a hint bar at the bottom: space plays or pauses (its hint says which), ⌘C
  copies the transcript (as `transcript.md` has it), ⌘↩ shows the folder
  in Finder, ⌘⌫ deletes the recording: at once, to the Trash, the window
  closes and the undo card offers Undo ⌘Z for 10 s (`UndoableDeletes`).
- **Not transcribed yet** (a language this Mac cannot transcribe): in
  place of the lines, that sentence and a pop-up of the languages it can,
  Transcribe ↩.
- **Transcribing** (opened meanwhile): "Transcribing… 40 %" in place of
  the lines.

## An unfinished recording

At launch, a recording that was never stopped (skil.li crashed, the Mac
lost power), or at once after a Stop whose files could not be finished
within 5 s: what was written is kept (the files are readable up to the
last second). The Record card's place and frame:

```
┌──────────────────────────────────────────────────────────┐
│ ● UNFINISHED RECORDING                                   │  orange dot
│                                                          │
│ Weekly sync                                              │
│ 18 min, stopped Wed 22 Oct at 14:48                      │  its files' length
│ ──────────────────────────────────────────────────────── │
│ Later esc    Discard ⌘⌫                       ( Save ↩ ) │
└──────────────────────────────────────────────────────────┘
```

- Save transcribes it and opens its window; Later leaves it for the
  next launch; Discard is a delete (to the Trash, Undo ⌘Z for 10 s).
- It never takes keys from the app the user is typing in: as the meeting
  card, it takes the keyboard only after a second without a key; a click
  does too.

## Said, and not said

- Not said: a recording started, paused, resumed or stopped (the menu
  bar shows it), a device changed (the track goes on).
- Said in the card: a recording that stopped by itself ("Recording
  stopped: the disk is full. What was recorded is kept."), a transcript
  that failed (why, and Transcribe ↩ in the window).

# Phase 2: the moment

What the Moment section of `docs/meeting-recorder.md` says, as views
and states. Nothing new is pushed: Record is a key on what already
shows (the meeting card, the launcher's meeting row, the menu bar's
meeting), and nothing records before the user's key.

## The five cases

Told apart by code, from three things macOS and the calendar already
say, read when a Record key is offered and again when it is pressed
(`MeetingMoment` in SkilliCore, unit-tested; no model):

- **The meeting**: the event on now or starting within 10 minutes
  (all-day and declined ones never), its call link, its location.
- **Who runs the microphone**: each Core Audio process running an input
  (`kAudioProcessPropertyIsRunningInput`), skil.li left out, mapped to
  its app: the process itself when it is an app with a Dock icon, else
  the first of its parent processes that is one (a browser's helper is
  its browser, an Electron app's helper is the app). A process with no
  such parent (a system service, as WebKit's for Safari) is "an app
  skil.li cannot name".
- **The window list**: the app's front window on screen (its owner's
  first normal window, front to back), kept for phase 3's screen and
  checked by the self-test; phase 2 shows no window.

| Case | When | Sources | Named | The call watched |
|---|---|---|---|---|
| A call link | the event has one (Meet, Zoom, Teams…) | microphone + the Mac's sound | the event's title | the app on the microphone, else the one the link opens in (Zoom's or Teams' app, else the browser) |
| In an app | no link; an app runs the microphone at the meeting's time | microphone + the Mac's sound | the event's title | that app (the one the location names first, else a known call app, else the first) |
| In person | no link; the location is a place; no app on the microphone | the microphone only | the event's title | none (the room) |
| A call with no event | no meeting on; a known call app runs the microphone | microphone + the Mac's sound | "Discord call 14:30" | that app |
| Nothing to go on | anything else (no event and no call app; an event with no link and no place; only an app skil.li cannot name on the microphone) | the default sources (Settings → Recorder) | the event's title, else "Meeting 14:30" | the first app that runs the microphone after ↩ |

- **A place**: a location that holds no web address, no phone number,
  names no call app (Gather, Discord, Zoom, Teams…) and is not a word
  for "online" ("online", "remote", "visio", "en ligne", "TBD"…).
- **Known call apps**: by bundle identifier, as each app's Info.plist
  has it (Zoom, Teams, FaceTime, Discord, Slack, WhatsApp, Signal: read
  on the test Mac), else by name (Webex, Skype, Telegram, Tuple,
  Gather…). A browser is not one: a browser on the microphone with no
  meeting on is "Nothing to go on".
- The case is read again at the key: a card shown before the meeting
  started may have had nobody on the microphone yet.

## The meeting card: Record ⌘R

The card that already shows as a meeting starts (Settings → Calendar)
gets Record ⌘R next to its button. Settings → Recorder turns it off.

```
┌──────────────────────────────────────────────────────────┐
│ ● STARTS IN 0:42                            14:00 – 14:30 │
│                                                          │
│ Weekly design review                                     │
│ ▶ Google Meet  ·  Work                  Camera & Mic ⇥   │  the check, moved up
│ (PA)(AL)(CD)(MP)  Paul, Anna and 4 others                │
│                                                          │
│ ⓘ  ⌘R records this call as you join it: your microphone │  first card only
│    and the Mac's sound, on this Mac. Everyone in it     │
│    must agree to be recorded.                           │
│ ──────────────────────────────────────────────────────── │
│ Dismiss esc        Calendar ⌘↩   Record ⌘R  ( Join ↩ )   │
└──────────────────────────────────────────────────────────┘
```

- **Keys**, under the hairline: Dismiss esc on the left (without a
  call: Calendar ⌘↩ there, as now); on the right, Calendar ⌘↩ (calls
  only), Record ⌘R, then the filled button (Join ↩, or Got It ↩). Five
  keys do not fit on one line of the card's 520 pt: Camera & Mic ⇥
  goes up to the call's line, on its right (it is about the call).
- **The label** says the case: "Record ⌘R"; for a place, "Record (in
  person) ⌘R".
- **⌘R**: with a call, the recording starts, then the call is joined
  (its first words are kept); without one, it records. The card goes.
  It starts at once with the case's sources: no Record card. The menu
  bar shows the red dot; nothing is said.
- **Taught once, then quiet**: the first card that offers ⌘R says, in
  one line above the hairline, what it does and that the others must
  agree (`Preferences.recorderCardHintShown`; it also counts as the
  consent told, `recorderConsentShown`). In person: "⌘R records this
  meeting with this Mac's microphone: set it in the middle of the
  table. Everyone in it must agree to be recorded." After that card,
  only the keycap: no line, no count, no badge.
- **Only the user's**: ⌘R records only when the card has the keyboard
  and has been on screen for a second (a ⌘R on its way to a browser,
  its reload, as the card comes never records); before that it does
  nothing. Mid-typing the card never takes the keyboard (as now), so ⌘R
  goes to the app the user types in. A click on the card gives it the
  keys at once.
- **Not offered**: while a recording is on (one at a time), and when
  Settings → Recorder turns it off: no keycap, and ⌘R is not the
  card's.

## The launcher's meeting row

The meeting row the launcher already shows first (the meeting starting
or just started; "join", "réunion" typed; the Calendar mode's meetings
on now):

- ⌘R on it records that meeting as the card's ⌘R does (and joins its
  call when it is not joined yet: `MeetingBar.inCall`). The launcher
  closes.
- ⌘K lists Record ⌘R (Record (in person) ⌘R for a place) after Join,
  for a meeting on now or starting within 10 minutes; ⌘R on a later
  one says "Nothing on ⌘R here" in the list, as any key with no action.
- The footer stays as it is (↩, ⇥, ⌘K): ⌘R is taught by the card.

## ⌘R at any moment

One key, one meaning: ⌘R on a meeting records it, never silently
nothing.

- **The last recording still closing its files** (a second or so after
  Stop): ⌘R is kept and records once they are closed; the menu bar's
  dot stays meanwhile, showing the new one at 0:00 until its first
  second. The Record card asked for then (`rec`, a link, a tool) opens
  once they are closed. Both recordings are whole.
- **Pressed twice** before the recording started: one recording.
- **The Record card open**: ⌘R on a meeting closes it and records that
  meeting.
- **A recording on**: no Record is offered (one at a time); a key or a
  tool asking anyway says "Already recording “…”: stop it from the menu
  bar first."

## The menu bar's meeting

Once in a call (`MeetingBar.joined`: joined from skil.li, or a call
begun on this Mac around its start) and no recording on, its menu gets
Record, with ⌘R shown:

```
Join Google Meet
Record “Weekly design review”   ⌘R
Show in Calendar
──────────
Show Calendar
Dismiss
```

## The first recording, before anyone was told

The others must agree; the first time skil.li records, a card has said
so. The meeting card says it on its first ⌘R. From the launcher's row
or the menu bar before any card said it, ⌘R opens the Record card
instead of starting at once: the event's title, its case's sources, the
consent paragraph; its button is "Record and Join ↩" when the call is
not joined yet. From then on, ⌘R starts at once everywhere.

## The Record card, knowing the meeting

Opened by `rec` (or a link, a key, a tool) while a meeting is on or
starting within 10 minutes, the card is that meeting's:

```
┌──────────────────────────────────────────────────────────┐
│ ● RECORD A MEETING                             English ⌃⌄ │
│                                                          │
│ Budget review▌                                           │  the event's title
│ With Paul, Anna and 2 others                             │  its attendees
│                                                          │
│ 🎙  Microphone      MacBook Pro Microphone      ▮▮▮▮▯▯   │
│ 🔊  The Mac's sound  Off · in person                     │  a click turns it on
│                                                          │
│ ⓘ  In person: set the Mac in the middle of the table.   │
│ ──────────────────────────────────────────────────────── │
│ Cancel esc                                  ( Record ↩ ) │
└──────────────────────────────────────────────────────────┘
```

- **The name**: the event's title (else "Meeting 14:30"), selected;
  the attendees under it in the secondary color ("With Paul, Anna and
  2 others"; first names).
- **The sources**: each row a click away from on or off ("Off" in the
  secondary color, no meter). The case sets them (in person: the Mac's
  sound off); Settings → Recorder sets them when nothing does.
- **In person**: one note line, "In person: set the Mac in the middle
  of the table."
- **The button**: "Record and Join ↩" for a call not joined yet.

## The menu bar while recording

The red dot's menu names each source with its level, and the call:

```
Recording “Weekly design review” · 12:04     (disabled)
Pause Recording
Stop and Transcribe
──────────
✓ Microphone · MacBook Pro Microphone  ▮▮▮▯
✓ The Mac's Sound · Every app          ▮▯▯▯
The Call: Google Chrome                  ▸   ✓ Google Chrome
──────────                                     Discord
Show in Finder                                 ──────
                                               None
```

- **A source** is turned off or on from its item, for the rest of the
  recording: a track turned off writes silence for that time (both
  tracks keep their time), the microphone is released (macOS's orange
  dot goes), the Mac's sound's tap stopped. The levels, four bars after
  the words, move while the menu is open (a menu item's picture does
  not show in menus on macOS 27).
- **The call**: the app watched for the call's end, the apps on the
  microphone to pick from (two apps on it: the one picked is kept). "The
  Call" shows once there is one, or an app on the microphone.
- In person misread: the user turns The Mac's Sound on; that is all.
  Nothing is said in either case.

## The call ends: Stop

While recording, without a poll (Core Audio's process changes, a timer
at the event's end):

- **The call's app leaves its call**: it no longer runs the microphone
  for 5 s (a reconnect is not an end).
- **Or the meeting is over and the sound is quiet**: past the event's
  end, the other side has stayed under -50 dBFS for a minute (the Mac's
  sound; in person, the microphone).

Then a card offers Stop, once for each of these:

```
┌──────────────────────────────────────────────────────────┐
│ ● THE CALL ENDED                                  32:10  │  hollow red dot
│                                                          │
│ Weekly design review                                     │
│ Google Chrome left the call.                             │  or "The meeting
│ ──────────────────────────────────────────────────────── │   ended at 14:30,
│ Keep Recording esc                            ( Stop ↩ ) │   it has been quiet
└──────────────────────────────────────────────────────────┘   for a minute."
```

- It never takes the keys from the app the user types in (as the
  unfinished recording's card); a click does.
- Stop ↩ stops and transcribes, as Stop in the menu bar. Keep Recording
  esc: the recording goes on, nothing asked again for the same reason.
- The call's app back on the microphone before an answer: the card goes
  by itself (a reconnect), and the call's next end is offered again.

## The recording's window

- **The about line** adds the attendees: "Wed 22 Oct 2026, 14:00 · 32
  min · English · with Paul, Anna and 2 others".
- **In person** (the Mac's sound never on): one lane and one speaker,
  "Room" (the microphone holds everyone; phase 4 tells their voices
  apart). A call keeps Me and Them.

## Finding recordings in the launcher

- **Search Recordings** (`recs `, `recordings `, `enregistrements `; in
  the Catalog): every recording, newest first. A row: the title, then
  "Wed 22 Oct · 32 min · Paul, Anna and 2 others"; typing filters by
  title, date and attendees at once, and by the words said once typing
  pauses (100 ms): those rows show the words around the match ("…the
  budget for the third quarter…").
- The words said come from an index on this Mac (SQLite FTS5, beside
  the clipboard's), filled as transcripts are made and caught up when
  the mode opens (a recording added, renamed or deleted in Finder).
- ↩ opens its window; ⌘K: Open ↩, Show in Finder ⌘↩, Copy Transcript ⌘C,
  Delete ⌘⌫ (to the Trash, Undo ⌘Z for 10 s).
- **In root search**: the two recordings whose title or attendees fit
  best, from three letters typed (from memory: the titles, dates and
  attendees are kept, never the words).

## Settings → Recorder

Its own pane, after Calendar. Settings first, the recordings last:

```
Recorder
Your meetings recorded on this Mac, both sides, then written out.

Record Meeting                       (its shortcut, when one is set)
From the launcher                                 rec
Search Recordings                                 recs
[✓] Record ⌘R on the meeting card
    As a meeting starts, its card offers to record it: your key,
    never on its own.

Microphone                                       [✓]
The Mac's sound                                  [✓]
    The sources on when nothing says otherwise (in person: the
    microphone only).
Language                                   [As Ask ⌃⌄]

Keep recordings in        Recordings ⌃ [Change…] [Show in Finder]
Delete after                               [Never ⌃⌄]
    2 recordings are older than a month: they go to the Trash
    within the hour.
    Expired recordings go to the Trash, never deleted for good.

Recordings
  October 2026
    Weekly design review     Wed 22 Oct · 32 min       ⋯
    Budget review            Tue 21 Oct · 48 min       ⋯
  September 2026
    …
```

- **Language**: "As Ask" (Ask's, else the keyboard's, as now), or one
  of the languages this Mac transcribes.
- **Keep recordings in**: a folder; changing it moves the recordings
  there (off the main thread, one by one; refused while one records or
  is transcribed; no recording starts while they move: ⌘R, the card, a
  link or a tool say so). One that cannot move stops it: those moved
  before it go back, the folder stays the one it was, and a line under
  the row says which and why. A recording that cannot go back either is
  named there, to move back in Finder: until it is back in the
  recordings' folder, the lists and the search do not show it.
- **Delete after**: Never, 1 week, 1 month, 3 months, 1 year, Custom
  (days). As the clipboard's: pruned at launch and then each hour, never
  as the setting changes; the line under it says what the next pass
  removes; an expired recording goes to the Trash. A recording being
  made or transcribed, or never stopped, is never pruned.
- **Recordings**, grouped by month: a row each (title; date and length
  in the secondary color); a click opens its window; its menu (⋯ or a
  right click): Open, Show in Finder, Delete (Undo ⌘Z for 10 s).
- No engine row yet: one engine until phase 4's "Better
  transcription" download (its section, phase 4).
- Every setting is an agent's too (`set_setting`), under its own name.

## Said, and not said (phase 2)

- Not said: a recording started from ⌘R (the red dot), a source turned
  off or on, the call picked, a recording moved or pruned (the pane
  shows it).
- Said: a recording that could not start ("The recording could not
  start: …", in the card); a folder move that failed (under its row).

## Not in phase 2

The webcam and the screen (the window found is kept for phase 3),
renaming speakers, editing lines, import, chapters and the ⌘K actions
after a transcript, search by meaning (⇥), the engine choice.

# Quit and sleep

2026-10-25, from "Quit and sleep" in `docs/meeting-recorder.md`.

## skil.li quits while recording

- Nothing is shown: skil.li quits about a second later than it would,
  the time every file being recorded takes to close (the sound's two,
  the webcam's and the screen's when on). The red dot goes with it.
- At the next launch, a few seconds in: the menu bar's ring, "Transcribing
  40 %", its menu "Transcribing “Weekly sync”…", as after Stop. Done, the
  item goes and no window opens: the recording is in Search Recordings
  and Settings → Recorder. Its window opened before then says "Waiting to
  be transcribed…" (and so does one whose turn has not come after
  another Stop).
- Nothing is offered: the Unfinished Recording card stays for a crash or
  a power cut.

## The Mac slept: Resume

As the Mac goes to sleep the recording pauses (the menu bar: the hollow
grey dot, the clock still). At wake, the call's end card's place and
frame:

```
┌──────────────────────────────────────────────────────────┐
│ ○ RECORDING PAUSED                                12:04  │  hollow grey dot,
│                                                          │  as the menu bar's
│ Weekly design review                                     │
│ The Mac went to sleep at 14:32.                          │
│ ──────────────────────────────────────────────────────── │
│ Keep Paused esc   Stop ⌘↩                    ( Resume ↩ )│
└──────────────────────────────────────────────────────────┘
```

- Resume ↩ records again from now; Stop ⌘↩ stops and transcribes, as
  Stop in the menu bar; Keep Paused esc closes the card, the recording
  stays paused (the red dot's menu resumes or stops it).
- It never takes the keys from the app the user types in (the password
  at the lock screen first); a click does, or a second without a key.
- Resumed or stopped from the menu bar meanwhile: the card goes.
- Paused by the user before the sleep: no card at wake.
- A call's end card left from before the sleep gives way to this one;
  the call's end is offered again once this one is answered, if the call
  is still over.

# Phase 3: the webcam and the screen

Spec, 2026-10-25, written before building from `docs/meeting-recorder.md`
(Target, Before, During, Done, Privacy, and Measured's "The screen" and
"In step over an hour"). Two sources more, both off until the user turns
them on, recorded by the same clock as the sound; the text of what the
screen shows read on this Mac.

## The moment, again

Phase 3 changes none of the Moment's answers, checked one by one:

1. **When**: the same moment, the meeting's start. The webcam and the
   screen are never on by themselves: off in every case unless the user
   turns them on (a click in the Record card, the red dot's menu) or set
   them on by default (Settings → Recorder). In person, the screen stays
   off even then (no call's window to record); the webcam follows the
   setting.
2. **The path**: the same keys. ⌘R on the meeting card, the launcher's
   row or the menu bar records with the case's sources plus the webcam
   and the screen as Settings → Recorder has them: the sound from the
   key, the screen joining once the meeting's window is found
   (Automation's question, a browser slow to answer never delay the
   sound); the Record card's rows turn either on with a click; the red
   dot's menu, during the call.
3. **Hint or push**: nothing new is pushed. One thing is said that the
   user would not see otherwise: a screen that stops giving pictures
   (Measured: a minimized or hidden window gives none; Chrome's, fully
   covered, the same one again and again). Said where the recording is
   already shown, the menu bar, never a card during the call.
4. **Deterministic**: the window is the case's app's (its window holding
   the meeting's tab in a browser, else its front window: the window
   list), or the one the user picks; the meeting's tab is found by its
   address (code, `MeetingTab` in SkilliCore). The slides' text is read
   by Vision's text recognition on this Mac: a reading, not a judgment,
   and nothing of it leaves the Mac (Privacy's table: "read slides",
   nowhere).
5. **Wrong**: a wrong window costs that window's pictures until it is
   changed: the red dot's menu picks another (or turns the screen off)
   from then on, nothing asked; the time before stays as recorded. A
   wrong tab: the user picks the right one in the browser, which is
   recorded from then on (macOS records the window, not a tab). The
   webcam not wanted: off from the same menu.

## The Record card: four sources

```
┌──────────────────────────────────────────────────────────┐
│ ● RECORD A MEETING                             English ⌃⌄ │
│                                                          │
│ Weekly design review▌                                    │
│ With Paul, Anna and 4 others                             │
│                                                          │
│ 🎙  Microphone      MacBook Pro Microphone      ▮▮▮▮▯▯   │
│ 🔊  The Mac's sound  Every app                  ▮▮▯▯▯▯   │
│ 📷  Webcam           FaceTime HD Camera          ▕▓▓▓▏   │  live, 46 × 26
│ 🖥  Screen           Google Chrome · Meet ⌃⌄     ▕▓▓▓▏   │  live, its window
│                                                          │
│ ⓘ  The meeting's tab comes forward as recording starts; │
│    a tab you pick later is recorded instead. Keep its   │
│    window in sight.                                     │
│ ──────────────────────────────────────────────────────── │
│ Cancel esc                                  ( Record ↩ ) │
└──────────────────────────────────────────────────────────┘
```

- **Four rows**, the same type and height (26 pt) as phase 1's two; the
  webcam's and the screen's show a picture where the sound shows a
  meter: 46 × 26 pt, corners of 4 pt, a hairline around it, live (the
  webcam mirrored as calls show you; recorded as the camera sees). Off:
  "Off" in the secondary color, no picture, as the sound's rows.
- **A click on a row** turns it on or off, as phase 2's.
- **The webcam**: macOS's preferred camera (`systemPreferredCamera`),
  its name. Asked the first time it is turned on (macOS's question over
  the card, which steps down meanwhile, as for the microphone). Refused:
  "Not allowed · ⌘↩ opens Privacy" in orange, no picture. No camera on
  this Mac: "No camera". The call's app using it too is fine (macOS
  shares a camera).
- **The screen**: the window, named "App · its title" (the title cut to
  fit; read on this Mac, never sent anywhere). Turned on, it is the
  meeting's window when the case has one (the call's app's window; in a
  browser, the window holding the meeting's tab), else the list of
  windows opens under the row and the one picked is recorded; none
  picked, it stays off.
  - **⌃⌄** after the name lists the windows on screen: "The meeting's
    window" first when one is known, then each app's normal windows,
    front to back, "App · title" (skil.li's own left out); the one
    recorded checked. The same list as the red dot's menu.
  - Screen Recording never given: macOS's question as it is turned on;
    refused: "Not allowed · ⌘↩ opens Privacy" in orange. macOS applies
    it once skil.li reopens (`Relaunch`, as for "do it here").
- **A meeting in a browser** (the screen on, its window the meeting's):
  one note line under the sources, in the card's note style.
  - Its tab can be brought forward (Safari, Chrome's family, their
    Automation allowed, a tab on the meeting's address): "The
    meeting's tab comes forward as recording starts; a tab you pick
    later is recorded instead. Keep its window in sight."
  - It cannot, said with what to do:
    - Arc, Firefox, a browser skil.li does not script: "Bring the
      meeting's tab forward in Arc: its window is recorded as it is."
    - No tab on the meeting's address (or the browser not open): "No
      tab of Google Chrome is on the meeting's address: bring it
      forward, its window is recorded as it is."
    - Refused in Privacy & Security → Automation: "Google Chrome said
      no to skil.li · ⌘↩ opens Automation. Bring the meeting's tab
      forward: its window is recorded as it is."
    - The script failed: "Google Chrome did not answer: bring the
      meeting's tab forward, its window is recorded as it is."

    macOS's question for Automation, never asked before, comes as the
    screen is turned on (the card steps down), so ↩ never waits on it.
  - A window of an app (Zoom, Discord…): "Keep the call's window in
    sight: a minimized or hidden window gives no picture."
- **⌘↩** opens the list of the permission a row says is missing (the
  camera, Screen Recording, Automation), the first one down the rows.
- **↩**: everything on records from that moment, and the meeting's tab
  comes forward (selected, never reloaded, the browser left where it is:
  the user's app keeps the keyboard; a browser slow to answer never
  delays the start).
- Consent: phase 1's paragraph already says the others must agree, for
  the webcam and the screen as for the sound; nothing added.

## The menu bar while recording

```
 ● 12:04 ⣀⣤⣶⣤ ▭̸      ← the screen gives no picture: an orange mark
```

- **The label**: as phase 1's; while the screen gives no picture, a
  small screen with a slash, in orange, after the waves (its
  accessibility label "Recording, 12:04, the screen gives no picture").
  It goes when the pictures come back. Nothing else is ever added to
  the label: a source on or off is not shown there.
- **The red dot's menu** adds the two sources after the sound's, the
  screen's window in its submenu:

  ```
  ✓ Microphone · MacBook Pro Microphone  ▮▮▮▯
  ✓ The Mac's Sound · Every app          ▮▯▯▯
  ✓ Webcam · FaceTime HD Camera
  ✓ Screen · Google Chrome · Meet          ▸   The Meeting's Window
  The Call: Google Chrome                  ▸   ✓ Google Chrome · Meet
  ──────────                                     Keynote · Q3 review
  Show in Finder                                 ──────
                                                 Off
  ```

  - **Webcam**: a click turns it off or on for the rest of the
    recording; off, the camera is released (its green light goes) and
    `webcam.mp4` holds its last picture, then black, until it is on
    again. Never on in this recording: no file.
  - **Screen ▸**: the window recorded checked; another picked is
    recorded from then on, in the same `screen.mp4` (its pictures
    scaled into the file's size); Off stops it. The meeting's window
    once known comes first.
  - **No picture**, the item says why, in place of the window's name:
    "Screen · Google Chrome is minimized: nothing recorded until it's
    back", "… is hidden …", "… isn't on screen …" (on another desktop),
    "Screen · Google Chrome stopped painting: keep some of its window
    in sight" (covered whole, no new picture for 5 s since it was),
    "Screen · the window closed: pick another ▸". Said after a second
    (a window being minimized, a desktop changing). Measured
    (Chrome, Arc): a covered window that keeps painting is no failure,
    and a still slide in sight is none either: only a window covered
    whole and giving no new picture for 5 s is.
- Paused: nothing written to any of the four (the pictures as the
  sound), the clock stopped.

## The files

- `webcam.mp4`: H.264, 1280 × 720 at most, 30 pictures a second;
  `screen.mp4`: H.264, 1920 pt wide at most (the window's own pixels,
  scaled to fit), 15 a second. Both written as they come, in fragments
  of a second (a crash keeps what was recorded, as the sound's).
- **In step** (Measured, "In step over an hour"): each picture at its
  own time, the host clock's (the camera's clock converted to it), cut
  where the sound is cut: the start, each pause, the stop, the same host
  moments for the four tracks. A picture between two is held (a still
  slide costs next to nothing); each file ends at the stop.
- `slides.json`: what the screen showed, read on this Mac:
  `[{ "start": 75.4, "lines": ["Q3 review", "Revenue up 12 %"] }]`,
  the time on the recording's clock (pauses out).

## Reading the slides

From the screen's own pictures, on this Mac (Vision's text
recognition), nothing kept but the text:

- Four times a second the picture is compared with the one last read
  (its brightness on a 64 × 40 grid: fine enough that a slide whose
  text alone changes shows, a corner's clock ticking does not); when it
  changed, its text is read, at most once a second, every two seconds
  while readings find nothing new (a video moving).
- The lines new since the last reading are a slide, timed at the last
  change before the reading: between the two readings, so never more
  than two seconds off, within a second when it is the only thing
  changing (the check). A still window gives no new picture: its last
  one is compared again as time goes on, so a change seen while a
  reading waited is read all the same.
- A line is text when it has words: a number alone (the call's clock,
  a counter) is no slide's.
- Lines seen in most of the recording's readings (the browser's tabs,
  the call's own buttons, the people's names under their videos) are
  taken out of every slide at Stop; a slide left with no line goes.
- The webcam is never read.

## The recording's window

```
┌ Weekly design review ─────────────────────────────────────────────────┐
│ Weekly design review                                                  │
│ Wed 22 Oct 2026, 14:00 · 32 min · English · with Paul, Anna and 4…    │
│                                                                       │
│ ▶  12:04 / 32:10                                                      │
│ Me    ▁▂▅▃▁  ▂▆▇▃▁       ▁▃▂          │                                │
│ Them      ▃▆▅▂    ▁▂▆▇▅▃▂     ▅▆▃      │                               │
│ ───────────────────────────────────────────────────────────────────── │
│ Me      0:00  Hello everyone, can you…      ┌──────────────────────┐  │
│ Them    0:04  Yes, loud and clear.          │                      │  │
│ Screen  0:05  Q3 review · Revenue up 12 %   │       screen         │  │
│ Them    0:07  I can hear you. Ingrid…       │                      │  │
│                                             └──────────────────────┘  │
│                                             ┌──────────┐              │
│                                             │  webcam  │              │
│                                             └──────────┘              │
│ ───────────────────────────────────────────────────────────────────── │
│      Play space   Copy Transcript ⌘C   Show in Finder ⌘↩   Delete ⌘⌫ │
└───────────────────────────────────────────────────────────────────────┘
```

- **Beside the transcript**, on its right, a column 260 pt wide: the
  screen at its own shape, the webcam under it (half the column's
  width), corners of 10 pt, black behind the picture. Only what was
  recorded shows; neither: the window as phase 2's. With them it opens
  wider (1020 × 640) and keeps 760 for the lines.
- **In step**: the pictures play with the sound, one clock (each player
  started at the same host time, `setRate(_:time:atHostTime:)`), seeking
  and pausing together; a click on a line or the waveform moves them
  too.
- **The slides** are lines of the transcript at their time: "Screen"
  in the tertiary color where a speaker's name goes, the slide's lines
  joined by " · " in the secondary color. A click plays from there, as
  any line; ⌘C's transcript leaves them out (it is what was said).

## Finding recordings

The slides' words are found as the words said (the same index); a row
found by them says so: "On screen: …Revenue up 12 %…".

## Settings → Recorder

The sources on by default gain two rows, off:

```
Microphone                                       [✓]
The Mac's sound                                  [✓]
Webcam                                           [ ]
Screen                                           [ ]
    The sources on when nothing says otherwise (in person: the
    microphone only; the screen is the meeting's window).
```

Settings → Privacy's Camera and Screen Recording rows name the recorder
among what they turn on.

## Said, and not said (phase 3)

- Not said: the webcam or the screen turned on or off, a window picked,
  the meeting's tab brought forward (all seen).
- Said: in the menu bar, a screen giving no picture and why; in the
  card, a tab that cannot be brought forward and what to do.

## Not in phase 3

A browser's tab recorded whatever is in front (an extension: not
planned), the whole display, the webcam's own sound (the microphone is
the user's side), slides as chapters (phase 5).

# Phase 4: voices, import, editing, Better transcription

Spec, 2026-10-26, written before building from `docs/meeting-recorder.md`
(Target, Transcription, Done, Privacy, and Measured's picks: SpeakerKit,
whisper large-v3-turbo with its VAD and the names, the drop by word
times). Built in two pull requests, one after the other: (a) the voices,
import, editing and renaming, Transcribe Again; (b) the Better
transcription download, its engine, and the echo drop measured with it.

## The moment, again

1. **When**, each case apart:
   - **Voices told apart**: at Stop, while the transcript is made.
     Nothing to reach for: a track that holds several people (the Mac's
     sound in a call, the microphone in person, an imported file) comes
     out with each voice on its own lines.
   - **Import**: after a meeting recorded elsewhere (a phone's voice
     memo, a call app's own recording, a video), at the desk, the file in
     Finder or just downloaded.
   - **Editing and renaming**: reading the transcript in the recording's
     window after the meeting, before quoting it, sending it or keeping
     it.
   - **Transcribe Again**: a transcript in the wrong language, or made
     before Better transcription was downloaded.
   - **Better transcription**: when a transcript got names or words
     wrong. Never at the meeting's moment: nothing about the call
     depends on it, and 1.6 GB is not fetched while someone waits.
2. **The path**:
   - Voices: none, it is part of the transcript.
   - Import: drop the file on a recording's window; Import Recording… in
     the launcher (`import`, the Catalog); `skilli://record/import?file=…`;
     `import_recording` for an agent or a skillie.
   - Editing: in the recording's window, a line selected (a click, or
     ↑ ↓): ↩ edits its words, ⇥ gives it to the next speaker (⇧⇥ the one
     before), ⌘⌫ deletes it. Renaming: a click on a speaker's name, or ⌥↩
     on the selected line.
   - Transcribe Again: its button on the window's about line.
   - Better transcription: Settings → Recorder, its own section.
3. **Hint or push**: nothing is pushed. Better transcription is taught
   once: the first recording's window that opens on a transcript made by
   macOS's engine says it in one line at the bottom of its lines (below);
   never again, in no other window, no badge. The download starts only
   from its button. While it downloads, its progress shows in its row in
   Settings → Recorder and nowhere else; Settings closed, it goes on. A
   failure while Settings is closed is said once in the card (out of
   sight); done, nothing is said (the next transcript is made with it).
4. **Deterministic or AI**: SpeakerKit and whisper are models that run on
   this Mac, in a helper started for the transcript (`skil.li
   Transcriber`); nothing they hear or write leaves the Mac. No voice is
   given a name by guess: the user names them (names put on voices from
   what is said, by the user's AI, are phase 5). The download is one
   request to huggingface.co for two files, nothing sent with it,
   checked by their checksums; Settings → Privacy lists it.
5. **Wrong**: an extra speaker (SpeakerKit's measured mistake): give it
   a name already used, the two become one. A line on the wrong speaker:
   ⇥. Words wrong: ↩. A line nobody said: ⌘⌫, ⌘Z brings it back. The
   wrong language or engine: Transcribe Again, which says first that it
   replaces the lines' changes. A wrong file imported: ⌘⌫ deletes that
   recording (to the Trash, ⌘Z). A download not wanted: Cancel, or Remove
   once done (to the Trash, ⌘Z for 10 s). whisper's two measured
   failures (a line repeated right after itself, an attendee's name
   written as a speaker label) are taken out by code after it.

## Voices told apart

- At Stop, after the words: the track that holds several people goes
  through SpeakerKit (Argmax's, MIT; pyannote community-1 on Core ML),
  the number of voices found by itself. In a call, the Mac's sound; in
  person, the microphone (the room); an import's one track. The
  microphone in a call is the user: never split.
- Each word goes to the voice heard at its time (the voice's stretch
  that holds the word's middle; none: the nearest within a second; else
  the voice of the words around it). A phrase is cut where the voice
  changes; the lines are then made as before.
- **Names until the user gives one**: in a call, Me, then Them when one
  voice is found, else Them 1, Them 2… in the order they first speak; in
  person and in an import, Speaker 1, Speaker 2…; one voice alone in
  person stays Room.
- The colors: Me in the accent color; every other voice in the
  secondary color (the names tell them apart).
- Progress: the menu bar's ring and "Transcribing… 40 %" count the
  voices in (the words first, then the voices).
- SpeakerKit fails on a file (none seen): that track stays one voice,
  logged; the transcript is made.
- `skil.li Transcriber` is a helper inside the app, started for a
  transcript and gone after it: SpeakerKit's memory (0.8 GB at most,
  Measured) never counts against skil.li's. SpeakerKit's models (11 MB)
  ship inside the app: nothing is downloaded for the voices.

## Import

- **Import Recording…** in the launcher (`import`, "importer"; in the
  Catalog), or a file dropped on a recording's window: the open panel
  lists sound and video files (m4a, mp3, wav, aiff, caf, mp4, mov,
  m4v…). Several files dropped: one recording each, in order.
- A recording is made of it in the Recordings folder, as a recording
  made here: its title the file's name without its extension, its date
  the file's creation date (else its last change), its sound as one
  track (`me.m4a`, AAC, as the microphone's), a video's picture kept as
  `screen.mp4` (it plays beside the lines, as phase 3's screen). The
  file itself stays where it was, untouched.
- Its window opens at once: "Importing… 30 %", then "Transcribing…
  40 %", in the language Settings → Recorder sets (As Ask: Ask's), with
  the default engine, voices told apart. The menu bar's ring shows it
  too, as after a Stop.
- **About line**: "Imported from Board call.m4a · Mon 12 Oct 2026, 09:30
  · 48 min · English".
- **Said**: a file with no sound ("“Holiday.mov” has no sound to
  transcribe."), one that cannot be read, a disk full: in the card, the
  recording not made. Nothing else is said: the window shows it.
- While a meeting records: the import is made all the same; its
  transcript waits for the recording's, one at a time.

## The recording's window: a line selected

```
┌ Weekly design review ─────────────────────────────────────────────────┐
│ Weekly design review                                                  │
│ Wed 22 Oct 2026, 14:00 · 32 min · English · with …  Transcribe Again… │
│                                                                       │
│ ▶  12:04 / 32:10                                                      │
│ Me    ▁▂▅▃▁  ▂▆▇▃▁       ▁▃▂          │                                │
│ Them      ▃▆▅▂    ▁▂▆▇▅▃▂     ▅▆▃      │                               │
│ ───────────────────────────────────────────────────────────────────── │
│ Me       0:00  Hello everyone, can you all hear me?                   │
│ Paul     0:04  Yes, loud and clear.                                   │
│(Them 2   0:07  I can hear you. Ingrid, are you with us?)              │  selected: ring
│ Me       0:16  That's fine, Ingrid, we don't need to see you…         │
│ ───────────────────────────────────────────────────────────────────── │
│ Edit ↩   Next Speaker ⇥   Rename ⌥↩   Copy Line ⌘C   Delete Line ⌘⌫    │
└───────────────────────────────────────────────────────────────────────┘
```

- **Selecting**: a click on a line selects it and plays from its start
  (as before); ↑ ↓ move the selection without playing; esc lets go of
  it. The selected line has a 1.5 pt ring in the accent color, the
  selection capsule's shape; the line playing keeps its lit capsule (a
  line can be both).
- **The keys say what they do now**, in the hint bar: with a line
  selected, "Edit ↩ · Next Speaker ⇥ · Rename ⌥↩ · Copy Line ⌘C ·
  Delete Line ⌘⌫" (space still plays); without, as before ("Play space ·
  Copy Transcript ⌘C · Show in Finder ⌘↩ · Delete ⌘⌫": the recording).
  ⌘⌫ removes what is selected, as in Finder: the line when one is, the
  recording when none is.
- **⌘Z** in the window undoes the last change to its lines (an edit, a
  speaker, a name, a line deleted), ⇧⌘Z redoes, as long as the window is
  open. Every change is written at once (`transcript.json`,
  `transcript.md`, `meeting.json`, the words' search index); nothing is
  said.

### Edit ↩

- ↩ (or a double-click): the line's words become a field in place, the
  caret at the end; ↩ keeps, esc puts back what was there, a click
  elsewhere keeps. Emptied, the line is deleted (as ⌘⌫).
- The words kept keep their times (the same words at the start and the
  end of the line); new words share the time of what they replace.
  `meeting.json`'s `edited` turns true: Transcribe Again says it
  replaces the changes.

### Next Speaker ⇥

- The line goes to the next speaker in the speakers' order (Me first,
  then as they first speak), around to the first; ⇧⇥ the one before.
  It stays selected: ⇥ again moves it on. It keeps its place and time;
  it is not joined to the lines around it.

### Delete Line ⌘⌫

- Gone at once; the undo card says "Line Deleted" with its first words
  in bold, Undo ⌘Z for 10 s (`UndoableDeletes`); after the card, ⌘Z in
  the window still brings it back. The selection moves to the next
  line.

### Rename ⌥↩

A click on a speaker's name in any line, or ⌥↩ on the selected line,
opens a menu under the name:

```
Rename “Them 2”                   (title, disabled)
──────────
Paul Arnaud                       the attendees not yet given
Anna Lindqvist
──────────
Camille — joins Camille's lines   names already given: merges
Me — joins your lines
──────────
Other Name…                       typed in place, ↩ keeps
```

- For Me: the user's own name first (My Card in Contacts, when allowed),
  then the same list.
- A name given renames that speaker on every line. Two speakers given
  the same name (case and accents aside) become one: the renamed one's
  lines go to the other, which keeps its name and its place in the
  order. When one of the two is Me, Me is kept (its color, its track):
  the user's own name is never given away. A speaker given the user's own
  name joins Me.
- ⌘Z in the window undoes a rename or a merge, its lines back to the
  speaker they had.

### Copy Line ⌘C

- The selected line as `transcript.md` writes it ("**Paul** · 0:04" and
  its words); without a selection, the whole transcript as before.

## Transcribe Again

On the about line's right, "Transcribe Again…" (not while a transcript
is being made); a panel under it:

```
┌─────────────────────────────────────────────┐
│ Transcribe again                            │
│ Language    English ⌃⌄                      │
│ Engine      Better transcription ⌃⌄         │  macOS · Better transcription
│ Your changes to the lines are replaced.     │  only when there are
│ Cancel esc                  ( Transcribe ↩ )│
└─────────────────────────────────────────────┘
```

- **Used as picked**: the language and the engine chosen, never another
  in their place. The languages listed are the chosen engine's.
- **One that cannot be used** says why under the menus, and Transcribe
  dims: "Better transcription isn't downloaded: Settings → Recorder
  offers it." (a click opens it); "Italian can't be transcribed by
  macOS's engine on this Mac." The transcript stays as it is.
- ↩: the window shows "Transcribing… 40 %"; the transcript before stays
  on disk until the new one is written. A transcript that cannot be made
  again leaves the one before in place, and the card says why ("The
  transcript was not made again: … The one before is kept."). A pending
  one stays pending.
- The names given are kept for the voices found again in the same
  order; `edited` goes back to false; `meeting.json`'s `engine` and
  `language` are the ones used.
- Engine names, everywhere the user reads them: "macOS" (macOS's own
  `SpeechTranscriber`) and "Better transcription" (whisper
  large-v3-turbo).

## Better transcription (Settings → Recorder)

Its own section, after Sources:

```
Better transcription                                 [Download (1.6 GB)]
    whisper large-v3-turbo, on this Mac: 40 % fewer errors than
    macOS's engine, two names in three right. Downloaded from
    huggingface.co, nothing sent. For the recorder only.
```

States of the row, by what is happening:

| State | The row | The button(s) |
|---|---|---|
| Not downloaded | the text above | Download (1.6 GB) |
| Not enough room | "1.7 GB free needed on this Mac: 0.9 GB left." in orange | Download (dimmed) |
| Downloading | a progress bar, "412 MB of 1.6 GB · about 3 min left" | Cancel |
| Checking | "Checking the file…" (its checksum: a few seconds) | – |
| Stopped (network, quit) | "The download stopped: the network went away." in orange | Resume (from where it stopped) |
| Wrong file | "The file downloaded is not the one expected (another checksum): nothing was kept." in orange | Download |
| Downloaded | "Downloaded · 1.6 GB · whisper large-v3-turbo" | Remove |

- **Engine**, under it once downloaded: Better transcription (the
  default from then on) or macOS. Not downloaded: no engine row, macOS
  is used.
- **Download**: the model (1,624,555,275 bytes) and its VAD's (885,098
  bytes), from huggingface.co at a fixed revision, into
  `~/Library/Application Support/skil.li/Models/` (never in a backup).
  Each file's SHA-256 is checked before it is kept; a wrong one is
  thrown away. skil.li quits while downloading: what came is kept and
  Resume goes on from there.
- **Remove**: the model to the Trash at once, the undo card says "Better
  Transcription Removed", Undo ⌘Z for 10 s; the engine goes back to
  macOS.
- **Taught once** (the moment, above): at the bottom of the first
  recording's window that opens on a transcript made by macOS's engine,
  one line in the secondary color: "Names heard wrong? Better
  transcription gets two in three right, on this Mac: Settings →
  Recorder (1.6 GB download)." A click opens the pane. Never again
  (`Preferences.recorderBetterHintShown`).
- Every setting is an agent's too (`set_setting recorderEngine`); the
  download itself is the user's click only (1.6 GB of their disk).

## The engine at work (whisper)

- In `skil.li Transcriber`: whisper.cpp 1.9.5 (MIT, Metal), the full
  model, its Silero VAD on, the names as its prompt ("Attendees: Paul
  Arnaud, Anna Lindqvist. Also: …." in English, "Participants : … Aussi :
  …." in French; 450 characters at most: the event's attendees, then the
  user's contacts in Dictate's order) carried to every 30-second window.
  Peak memory about 2 GB, in the helper only.
- **Times on the recording's clock**: whisper's word times are read with
  its VAD's cuts added back (whisper.cpp's own mapping,
  `whisper_full_get_token_t0`), so they line up with the other track's;
  then the drop by word times takes the other side's words out of the
  user's, as with macOS's engine. Measured with whisper in phase 4 (To
  check).
- **After it**: a segment equal to the one before goes; an attendee's
  name followed by a colon at a segment's start or after a sentence's
  end goes ("Camille Kerjean : …").
- Words: whisper's tokens joined into words (a token starting with a
  space starts a word), each word's time from its first token's start to
  its last's end.

## Said, and not said (phase 4)

- Not said: the voices found, a line edited or given to another
  speaker, a speaker renamed or merged, an import started (its window
  opens), the download done or cancelled.
- Said: a line deleted (the undo card), the model removed (the undo
  card), an import that could not be made (the card), a transcript not
  made again (the card), the download failing while Settings is closed
  (the card, once), not enough room (its row).

## The files (phase 4)

- `transcript.json` version 2: a line's `speaker` is a voice: `me`,
  `them`, `them2`, `them3`… on a call's sides, `s1`, `s2`… on one track
  (in person, an import). Version 1 files read as before.
- `meeting.json`: `speakers` names every voice; `engine` is `macOS` or
  `whisper-large-v3-turbo` (`SpeechTranscriber`, the name phase 1 wrote,
  reads as `macOS`); `edited` once a line was changed by hand;
  `imported` the file's name for an import.

## Not in phase 4

Names put on voices by the user's AI, chapters, the summary, ⌘K's
actions in the window (Transcribe Again gets its key there), the q5_0
model (worse on a bad line, Measured), a voice's lines joined when two
speakers merge (each line keeps its place).

# Phase 5: chapters, the summary, follow-ups, skillies, agents

Spec, 2026-10-27, written before building from `docs/meeting-recorder.md`
(Target's Better 3 and 4, Done, Privacy and consent, Decided 2 and 7).
The last phase: what the user does with a meeting once it is written
out. Built in two pull requests, one after the other: (a) in the
recording's window: ⌘K, chapters, the summary, action items, the recap
mail; (b) from elsewhere: Ask about a meeting, skillies for recordings,
the agents' tools and the links.

## The moment, again

1. **When**, each case apart:
   - **The summary**: right after the meeting, the window open (it opens
     by itself once the transcript is made: the user is already there),
     to read what was decided or pass it on; or days later, before the
     next meeting of the series.
   - **Chapters**: a long meeting read or played again later, to find a
     part of it. Meetings of 3 minutes or more: a shorter one has
     nothing to split.
   - **Action items**: right after the meeting, before the next one
     starts, while the to-dos are fresh.
   - **The recap mail**: right after, to the attendees, while they
     remember the meeting.
   - **Ask about a meeting**: any time later, from where the user looks
     for things already: the launcher ("what did Paul say about the
     budget?"), or the recording's window.
   - **A skillie for recordings**: the user's own next step (a CRM, a
     notes app, a shared folder), from ⌘K on one recording; marked, after
     every transcript.
   - **Agents** (Claude Code, Codex) working for the user: which
     meetings there were, and a transcript when the user lets it go.
2. **The path**: one key from where the user is.
   - ⌘K in the recording's window: every action of this phase, and the
     window's own (Copy Transcript, Show in Finder, Transcribe Again,
     Delete). The window's hint bar says "Actions ⌘K", as the launcher's
     footer does.
   - The launcher: ⌘K on a recording's row (Search Recordings, `recs`, or
     found by its words) gives Ask Claude About This Meeting…; Ask itself
     answers a question about a meeting with the recorder's tools.
   - A link and a tool for each, for skillies and agents. No default
     shortcut for any of them (the user can give one).
3. **Hint or push**: nothing is pushed; no AI runs by itself. The keys
   are where the user looks: ⌘K's list in the window, its row in the
   launcher. Taught by the hint bar's "Actions ⌘K", nothing else: no
   badge, no line offering a summary. The one thing that runs on its own
   is the skillie the user marked to run after every transcript, off
   until marked (Privacy and consent's one exception).
4. **Deterministic or AI**: code does what macOS and the files answer:
   copying, the folder, the mail's addresses (the event's attendees),
   the reminders' fields from what was read, the skillies, the lists the
   tools give. The user's AI (Settings → SI Accounts: Claude, ChatGPT or
   the OpenAI API) does what only a reading of the words tells: the
   summary, the chapters, the action items, an answer. Each button names
   it ("Summary by Claude"). What it is sent: the transcript's text with
   its speakers' names and times, the text read on screen with its times
   (`slides.json`), the title and the date. Never the sound, the
   pictures, the attendees' addresses or the contacts.
5. **Wrong**: chapters or a summary that miss: made again from ⌘K, the
   ones before replaced (a summary replaced goes to the Trash, Undo ⌘Z
   for 10 s); Remove Chapters (Undo ⌘Z). Action items that should not be
   reminders: Undo ⌘Z in the card takes them all back, else each in
   Reminders. The recap mail: nothing leaves before the user's Send in
   the mail app, where the addresses and the words are changed. An
   answer: in the card, nothing kept. A skillie marked by mistake: Undo
   ⌘Z for 10 s, or None in Settings → Recorder; what it did with a
   recording is its own script's. An agent's `get_transcript` not
   wanted: Deny in the card.

## The recording's window: ⌘K

```
┌ Weekly design review ─────────────────────────────────────────────────┐
│ …                                                                     │
│ Me       0:00  Hello everyone, can you all hear me?                   │
│ Paul     0:04  Yes, loud and clear.        ┌──────────────────────────┐│
│ …                                          │ WEEKLY DESIGN REVIEW     ││
│                                            │ ✦ Summary by Claude      ││
│                                            │ ☰ Chapters by Claude     ││
│                                            │ ✓ Action Items to Remi…  ││
│                                            │ ✉ Recap Mail to the At…  ││
│                                            │ ? Ask Claude About Thi…  ││
│                                            │ ▶ Send to Notes          ││
│                                            │ ──────────────────────── ││
│                                            │ ⧉ Copy Transcript    ⌘C  ││
│                                            │ ⧉ Copy Summary           ││
│                                            │ ──────────────────────── ││
│                                            │ 🗑 Delete Recording  ⌘⌫  ││
│                                            │ Search actions…          ││
│ ───────────────────────────────────────────└──────────────────────────┘│
│                           Play space   Copy Transcript ⌘C   Actions ⌘K│
└───────────────────────────────────────────────────────────────────────┘
```

- ⌘K opens the launcher's list (`ActionPanelView`) over the window's
  bottom right, the recording's title on top; with a line selected too
  (they are the recording's actions, not the line's). Its keys are the
  launcher's: typing filters, ↑ ↓ (⌃N ⌃P), ↩ runs, an action's key runs
  it, esc or ⌘K closes it, a click beside it closes it.
- **The list**, doing first: Summary by Claude (or "Summary Again by
  Claude" once there is one), Chapters by Claude (3 minutes or more;
  "Chapters Again by Claude"), Action Items to Reminders by Claude, Recap
  Mail to the Attendees by Claude ("Recap Mail to the Attendees" once
  there is a summary, which goes in the mail as written), Ask Claude About This
  Meeting…, the user's skillies for
  recordings, Transcribe Again…, Show in Finder ⌘↩; then Copy Transcript
  ⌘C, Copy Summary (once there is one); then Remove Chapters (once
  there are some), Delete Recording ⌘⌫. "Claude" is the user's writing
  provider's name (ChatGPT, OpenAI API). Not transcribed yet: the copies
  and the AI's actions are not listed.
- **The hint bar** without a line selected: "Play space · Copy
  Transcript ⌘C · Actions ⌘K" (Show in Finder and Delete keep their keys,
  listed in ⌘K). A line selected: as phase 4 (⌘K still opens the list).

### Working, said in the window

While the AI writes, one line at the bottom of the lines, in the
secondary color, a spinner before it: "Writing the summary with Claude ·
Haiku…", "Finding chapters with Claude · Haiku…", "Reading the action
items with Claude · Haiku…". One at a time: another AI action meanwhile
says so in the list ("Writing the summary with Claude · Haiku: one at a
time."); a link's or Ask's says so in the card, a tool's in its answer. The window
closed meanwhile: the work goes on and lands in the files. A failure is
said in the card (as a transcript that failed): "The summary was not
written: Claude is not set up yet. Settings → SI Accounts." Nothing is
said when it is done: the window shows it.

## Chapters

- **Chapters by Claude** (meetings of 3 minutes or more): the AI reads
  the transcript and the text on screen and splits the meeting into
  parts, about one every five to ten minutes, two at least: each a title
  of a few words in the meeting's language, and where it starts. The
  start is put on the line that starts there (the first line at or after
  it); the first chapter starts at the first line.
- **In the lines**, a heading before each chapter's first line: its
  title, 15 pt semibold, its time on the right in the tertiary color; a
  hairline above it but the first. A click plays from its start.
- **On the waveform**, a mark at each chapter's start: a 1 pt line
  across the lanes in the tertiary color and a small notch on top; the
  pointer over it says the chapter's title.
- **Written**: `meeting.json`'s `chapters` (title, start in seconds),
  and `transcript.md`, a `## Title` heading before the chapter's first
  line. Transcribe Again keeps them (the times are the sound's). Made
  again: replaced. Remove Chapters: gone at once, the undo card "Chapters
  Removed", Undo ⌘Z for 10 s.

## The summary

```
│ ───────────────────────────────────────────────────────────────────── │
│ SUMMARY BY CLAUDE · 14:52                                             │
│ The team agreed to ship the new onboarding on 3 November.             │
│                                                                       │
│ Decided                                                               │
│ • Onboarding ships on 3 November, behind a flag for a week.           │
│ Open                                                                  │
│ • Whether the pricing page changes with it.                           │
│ Next steps                                                            │
│ • Paul: send the final screens by Friday.                             │
│ ───────────────────────────────────────────────────────────────────── │
│ Me       0:00  Hello everyone, can you all hear me?                   │
```

- **Summary by Claude** writes, in the meeting's language: two
  sentences on what it came to, then Decided, Open questions and Next
  steps (who does what, by when), short bullets, in Markdown. Nothing
  more than the transcript says.
- **In the window**, above the lines (the first row, scrolling with
  them): "SUMMARY BY CLAUDE · 14:52" (the provider, when it was
  written), letterspaced in the secondary color, then the summary drawn
  as the card draws Markdown. It shows as it is written. Opened again
  later, the window reads it from `summary.md`.
- **Written**: `summary.md` in the recording's folder (a `# Summary of
  Weekly design review` heading, then the summary). Made again: the one
  before goes to the Trash, the undo card "Summary Replaced" (Undo ⌘Z
  for 10 s puts it back). Copy Summary copies it as the card copies an
  answer (rich text, and plain text without its marks).

## Action items to Reminders

- **Action Items to Reminders**: the AI reads the to-dos said in the
  meeting: what, who, by when when said. Each becomes a reminder at once,
  in the list Settings → Reminders adds to: "Send the final screens" when
  it is the user's, "Paul: send the final screens" when it is someone
  else's (to follow up); due when a date was said ("by Friday": that
  Friday, from the meeting's date); its notes "From “Weekly design
  review”, 22 Oct, at 12:04"; its link the recording
  (`skilli://record/open?recording=…`: its window at that line).
- **Said**: the undo card, "4 Reminders Added" and their titles, Undo
  ⌘Z for 10 s takes them all back. None found: the card says "No action
  items in “Weekly design review”." Reminders not allowed: macOS's
  question, as Ask's reminders ask it.

## The recap mail

- **Recap Mail to the Attendees**: a new message in the user's mail app
  (a `mailto:` link, as Email on a contact), nothing sent: to the
  event's attendees' addresses (the user's own left out, by My Card),
  the subject "Recap: Weekly design review", the summary as plain text
  under one line ("Here is the recap of Weekly design review, Wed 22
  Oct."). No summary yet: it is written first (the window's line says
  so), then the mail opens. No addresses (no event, attendees without
  one): the message opens with no one in To. The user reads it, changes
  it, sends it.

## Ask about a meeting

- **In the window**: Ask Claude About This Meeting… in ⌘K turns the
  list into a field ("Ask about “Weekly design review”"); ↩ sends the
  question with the transcript to the user's AI, and the answer shows
  in the card, as Ask's answers do: its status says who answered ("Claude
  · Haiku · 2.1 s"), ⇥ follows up, ⌘C copies. Nothing is kept.
- **In the launcher**: the same on a recording's row (⌘K → Ask Claude
  About This Meeting…). And Ask: a question about a meeting ("what did Paul
  say about the budget on Monday?") is Ask's agent's to answer with the
  recorder's tools: it finds the recording (`list_recordings`) and reads
  its transcript (`get_transcript`), which the card asks every time,
  naming the recording. The route is measured on the volume corpus
  (`remote routes`, AskRouteCorpus's held-out half), never tuned on
  one sentence.

## Skillies for recordings

- A skillie says it is for recordings in its header:
  `@skilli.forRecordings true`. Run on a recording, it gets the
  recording's folder in `SKILLI_RECORDING` (its arguments empty); run
  elsewhere, `SKILLI_RECORDING` is not set.
- **In ⌘K**: each, by its title, after the AI's actions; ↩ runs it on
  this recording, as the launcher runs a skillie (its own "ask first"
  kept, the card while it runs, its last line). A skillie that needs an
  argument is not listed (nothing would give it one).
- **After every transcript**: Settings → Recorder, "After each
  transcript": None (the default) or one of them that runs without
  asking (not one with `needsConfirmation`: after a transcript nobody is
  there to answer it). Picked, the line under
  it says "“Send to Notes” gets every recording from now on: its
  folder, with the sound, the pictures and the words. What it does with
  them is its own script's.", and the undo card says the same, Undo ⌘Z
  for 10 s (back to None). Its row in ⌘K says it: "Send to Notes · after
  every transcript". Not an agent's setting (`set_setting` does not
  reach it): marking it is the user's.
- **It runs** once per recording, when its transcript is first made
  (after Stop, an import, a launch's transcript), not on Transcribe
  Again, with no card while it runs (out of sight, the window already
  showing). A failure is said in the card ("“Send to Notes” failed after
  the transcript of “Weekly sync”: …"). The window says it ran, at the
  bottom of the lines: "“Send to Notes” ran after the transcript at
  14:52: Sent." (its last line), or "… failed at 14:52: …". Kept in
  `meeting.json`'s `skillies` (title, when, whether it ran on its own,
  exit status, last line).

## The agents' tools

- `list_recordings`: the recordings, newest first: each its id (the
  folder's name), title, date, length, state, whether it has a summary
  and chapters. No words. A read: the tool rights of a read.
- `get_transcript` (`recording`: an id or a title, the newest of that
  title; empty: the newest): its transcript as `transcript.md` has it.
  Asked in the card every time, naming the recording ("Give a
  recording's transcript", under it "“Weekly sync” · Wed 22 Oct, 14:00 ·
  32 min. Its whole transcript goes to the agent asking, then to its
  provider."): `ToolPolicy`'s `everyTime`, Allow and Deny only, no right
  or mode makes it silent; only Block refuses it without asking.
- `recording_followup` (`recording`, `action`: `summary`, `chapters`,
  `action_items`, `recap_mail`, `ask` with `question`): what ⌘K does, its
  answer the summary, the chapters, the reminders added, "The mail is
  open in Mail", the answer. Asked every time too, naming the recording
  and the provider (it sends the transcript to the user's AI, and its
  answer to the agent).
- Links (`skilli://record/…?recording=…`): `open` (its window; `at=` a
  time in seconds plays from there), `summary`, `chapters`,
  `actions`, `recap`, `ask?question=…`: each but `open` asked in the
  card every time, as the recording's pause and stop are. A skillie
  calls the tools with `"$SKILLI_CLI" call …` (`skillies/README.md`).

## Said, and not said (phase 5)

- Not said: chapters made, a summary written, the mail opened, a
  skillie run from ⌘K beyond its own last line (each seen).
- Said: the reminders added (the undo card), a summary replaced and
  chapters removed (the undo card), a skillie marked (the undo card), an
  AI action that failed (the card), a marked skillie that failed (the
  card), no action items found (the card).

## The files (phase 5)

- `meeting.json`: `chapters` (`title`, `start` in seconds), `summarized`
  (when `summary.md` was written, and by whom: "Claude · Haiku"),
  `skillies` (the skillies run on it), `addresses` (the attendees' mail
  addresses, from the event, for the recap; never sent elsewhere).
- `summary.md`, when asked.
- `transcript.md`: a `## Title` heading at each chapter.

## Not in phase 5

Names put on voices by the user's AI (the user names them, phase 4),
a chapter renamed by hand, a summary edited in the window (edit
`summary.md`, the window reads it again when opened), several skillies
after every transcript (one).

# In the Dock

Spec, 2026-10-28, written before building, after the first real
recording: its window had no tile in the Dock and no place in ⌘⇥, so
once another app's window covered it, it was easy to lose.

## The moment

1. **When**: a recording's window is open (opened by itself once the
   transcript is made, from `recs`, a reminder's link, an import) and the
   user goes to another app: to write the follow-up mail, to join the
   next call, to look something up. Then back to the window, the way back
   to any Mac window.
2. **The path**: skil.li's tile in the Dock, with the recorder's icon,
   and its place in ⌘⇥. A click on the tile, or ⌘⇥ to skil.li, brings the
   recording's window forward (minimized, it comes back out of the Dock).
   Nothing new to learn: the ways every app's window comes back.
3. **Hint or push**: neither taught nor pushed. The tile comes as the
   window opens and goes as it closes, where the user looks for open
   windows already. No badge, no bounce, no sound.
4. **Deterministic**: the windows open decide it, in code
   (`DockPresence`); no AI, nothing leaves the Mac.
5. **Wrong**: a tile that never comes leaves the window as easy to lose
   as before (the menu bar's recorder and `recs` still reach it). A tile
   left after the last window closed is a stray app in the Dock and ⌘⇥
   (a click on it shows Settings, as opening skil.li again does). The
   recorder's icon left after the windows closed shows on skil.li's own
   alerts and in the Dock next time Settings opens. Two windows undoing
   each other: before, closing Settings took skil.li out of the Dock
   while a recording's window was open; one place now decides for every
   window. `remote recorder` checks each of these.

## The tile

- skil.li is in the Dock and ⌘⇥ (`.regular`) while at least one window
  that needs it is open: Settings, or a recording's window (any number,
  minimized ones included). It is an accessory again, in the menu bar
  only, once the last of them closes. While it is in front, its own menus
  are in the menu bar, as with Settings.
- **The icon**: the recorder's while any recording's window is open,
  Settings in front or not; skil.li's own while only Settings is.
  Decided: the tile says a recording is open; an icon that changed as the
  focus moved between skil.li's own windows would flicker in the Dock and
  in ⌘⇥ for nothing, and the recording's window is the one the tile is
  there for (Settings is a menu bar click away).
- **A click on the tile** brings skil.li's window last in front, a
  recording's or Settings, out of the Dock when minimized. With none
  open (skil.li opened again from Finder, Spotlight, `open -a`),
  Settings, as before. **⌘⇥** to skil.li brings all its windows forward,
  the one last in front on top, as for any app.

## The recorder's icon

skil.li's icon, its glass S as it is on the petrol squircle; its dot
becomes the recording light: a red disc (the menu bar's red dot while
recording) in a thin white glass ring, a little larger than the dot so it
reads in the Dock and ⌘⇥.

- Made in Icon Composer: `assets/brand/recorder-icon/RecorderIcon.icon`
  (the S's path from `AppIcon.icon`; the light and its ring in a group of
  their own, not translucent, so the red stays red).
- Shipped as `Sources/Skilli/Resources/RecorderIcon.icns`, 16 to 1024 px,
  made by `assets/brand/recorder-icon/make-icns.swift`. A picture set
  with `NSApp.applicationIconImage` is drawn by the Dock as given, so
  each size carries the macOS icon grid's margins and the shadow of
  Xcode's own icns for the app icon; read when a recording's window first
  shows, let go once the last closes (`applicationIconImage = nil` puts
  skil.li's own icon back).
- The Default look only: the Dock draws skil.li's own icon in its Default
  look in dark mode too. One picture is set, so the Dark, Clear and
  Tinted icon styles are not followed.

# A track that records nothing

Spec, 2026-10-28, from `docs/meeting-recorder.md`'s "A track that
records nothing" (when it is said, and why a card): a call recorded
with a Bluetooth headset lost the user's side whole and nothing said so.
Shown while recording only; nothing changes in the Record card, which
already says the Mac's sound blocked before ↩.

## The menu bar

```
 ● 12:04 ⣀⣤⣶⣤ 🎙̸      ← the microphone records nothing: an orange mark
```

- **The label**: the dot, the time and the waves as before; after the
  waves, for each track that records nothing, its symbol struck through
  in orange (the microphone `mic.slash.fill`, the Mac's sound
  `speaker.slash.fill`), before the screen's mark when both show. Its
  accessibility label adds "the microphone records nothing" (or "the
  Mac's sound records nothing"). It goes once the track records
  something.
- **The red dot's menu**: the track's item says why in place of its
  device, that part in orange, its level after it as before:

  ```
  ✓ Microphone · nothing comes from AirPods Pro   ▂▄▆█
  ✓ The Mac's Sound · Every app                   ▂▄▆█
  ```

  "nothing comes from AirPods Pro" (no buffer for 3 s), "only silence
  from AirPods Pro" (exact zeros since it started); the Mac's sound:
  "nothing comes", "only silence". A click turns it off as before
  (turned on again, it starts afresh).

## The card

The call's end card's place, frame and type, once for a stretch:

```
┌──────────────────────────────────────────────────────────┐
│ ● NOTHING RECORDED                                12:04  │  orange dot
│                                                          │
│ Weekly design review                                     │
│ Nothing comes from AirPods Pro: what you say isn't       │
│ recorded.                                                │
│ ──────────────────────────────────────────────────────── │
│ Keep Recording esc                       ( Start Again ↩ )│
└──────────────────────────────────────────────────────────┘
```

- **The line**, by track and reason:
  - "Nothing comes from AirPods Pro: what you say isn't recorded."
  - "AirPods Pro gives only silence: what you say isn't recorded."
  - "Nothing comes from the Mac's sound: the others aren't recorded."
  - "The Mac's sound gives only silence while Google Chrome plays: allow
    skil.li in Screen & System Audio Recording." with Privacy ⌘↩ beside
    Keep Recording esc, opening that list.
- **Start Again ↩**: that source made afresh (the microphone: a new
  engine; the Mac's sound: the tap and its aggregate again), counted from
  then: still nothing after 3 s (5 s of silence), the card comes again.
- **Keep Recording esc**: the card goes; not offered again until the
  track gives sound, the mark staying meanwhile.
- The track records something again: the card goes by itself.
- Never over another card (the call's end, the wake card, the Record
  card): it comes once that one has gone; the call's end offered while
  it shows comes once it has gone too. Never while paused: a pause
  closes it, offered again at Resume if the track still records
  nothing. It never takes the keys from the app the user types in; a
  click does, or a second without a key.
- The line wraps: the card grows to hold all of it (what to allow
  included).

## Said, and not said

- Said: no buffer for 3 s; exact zeros for 5 s since the source started
  (the Mac's sound: while an app has played sound for 5 s).
- Not said: a quiet stretch after the track gave sound since its source
  started (muted, nobody talking), a source turned off, a paused
  recording (the mark goes at the pause, each track is read again at
  Resume), the Record card's meters (the card says it there already).
