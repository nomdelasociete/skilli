# Meeting recorder: the views of phase 1

Spec, 2026-10-23, written before building, then brought in line with
three rounds of captures on the test Mac (light and dark). `docs/meeting-recorder.md`
says what is recorded, kept and measured; this says what phase 1 shows.
Each view is drawn by the code that runs it (`remote recorder` saves
`recorder-*.png`).

## The Record card

Opened by the launcher (Record Meeting, `rec`, or `rec Weekly sync`
with its name), a shortcut, `skilli://record?title=…`, or
`record_meeting` from a skillie or an agent. Never anything automatic:
nothing is recorded before ↩.

One glass card in the middle of the screen the pointer is on, the
meeting card's width (520 pt), its type and its keys. It takes the
keyboard: the user opened it to name the recording.

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
  nothing written: the meters are the check. A tap macOS does not allow
  records silence and says nothing (Measured), so only the sound tells.
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
- **Keys**, in a hint bar at the bottom: space plays or pauses, ⌘C
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

## Not in phase 1

The webcam and the screen, the event's title and attendees, stopping at
the call's end, Settings → Recorder and retention, finding recordings in
the launcher, renaming speakers, editing lines, import, chapters and the
⌘K actions after a transcript.
