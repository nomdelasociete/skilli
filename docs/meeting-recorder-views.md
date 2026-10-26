# Meeting recorder: the views

Phase 1: spec, 2026-10-23, written before building, then brought in line
with three rounds of captures on the test Mac (light and dark). Phase 2
(the moment, below): spec, 2026-10-24, written before building from the
Moment section of `docs/meeting-recorder.md`. Quit and sleep: 2026-10-25,
from that file's "Quit and sleep". Phase 3 (the webcam and the screen,
last): spec, 2026-10-25, written before building. That file says what
is recorded, kept and measured; this says what each phase shows. Each
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

At launch, a recording that was never stopped (skil.li quit, the Mac
lost power): what was written is kept (the files are readable up to the
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
  transcription" download.
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
  the time the two files take to close. The red dot goes with it.
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
   and the screen as Settings → Recorder has them; the Record card's
   rows turn either on with a click; the red dot's menu, during the
   call.
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
  (its brightness on a 32 × 20 grid); when it changed, its text is
  read, at most once a second, less often while readings find nothing
  new (a video moving: up to every 8 s), at once again for a change of
  a quarter of the picture.
- The lines new since the last reading are a slide, timed at the
  change: the picture that changed most from the one before since the
  last reading (a slide, not a video moving around it; so a slide shown
  at 1:15.4 is at 1:15.4 or a sample later; the check: within a
  second). A still window gives no new picture: its last one is
  compared again as time goes on, so a change seen while a reading
  waited is read all the same.
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
