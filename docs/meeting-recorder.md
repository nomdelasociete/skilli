# Meeting recorder

Status: 2026-10-23, spec agreed, target raised: on par with omarchy's
recorder, then better where skil.li knows the Mac. 2026-10-23: phase 1
built (PR #35). 2026-10-24: phase 2, the Moment below, built (PR #38).
2026-10-25: skil.li quitting and the Mac sleeping during a recording
(Quit and sleep below), and the words said kept out of backups (Where
it lives). 2026-10-25: phase 3, the webcam and the screen, being built;
the Moment checked again for them and their views and states in
`docs/meeting-recorder-views.md` ("Phase 3"). 2026-10-26: phase 4
being built: its moment, views and states in the same file ("Phase
4"), first the voices, import, editing and renaming, then Better
transcription. 2026-10-27: phase 5, the last, being built: its moment,
views and states in the same file ("Phase 5"); ⌘K's order in Done
changed by it (the AI's actions first, the copies after, as every ⌘K
list). Built in two pull requests: first the window's ⌘K, chapters, the
summary, action items and the recap mail; then Ask about a meeting,
skillies for recordings, the agents' tools and the links, which Done,
Where it lives and Privacy name already.

Asked for: a meeting recorder like omarchy-meeting-recorder (an
open-source recorder for Omarchy Linux): your microphone and the
Mac's sound as two tracks, transcribed on this Mac, nothing sent anywhere,
no bot joining the call. Then (2026-10-23): at least what it does, plus the
webcam and the screen (a window, or the browser window of a Chrome, Arc or
Chromium meeting).

## Target

**On par** (omarchy has it, read in its README on 2026-10-23): sound checked
before starting, two tracks, pause, the webcam, import an audio file, a
waveform player that follows the transcript, speakers renamed, lines edited,
moved to another speaker or deleted with undo, chapters by the user's agent,
actions once the transcript is done, an unfinished recording recovered,
transcribed again in another language.

**Better** (skil.li only):

1. It knows the meeting: the event's title names the recording, its
   attendees name the speakers to pick from, and it offers to stop when the
   call ends.
2. Names heard right: with the "Better transcription" download, the
   attendees and the user's contacts go to whisper as its prompt (two
   names in three right, against two in five for macOS's engines, which
   barely gain from names: see Measured).
3. Found from the launcher: words said, by plain search; Ask "what did Paul
   say about the budget?" with the user's AI, on their action.
4. Follow-ups in one key: action items become reminders, a recap mail goes
   to the attendees, each on the user's action.
5. The screen too: a window, or the meeting's browser window, recorded with
   the call; the text of shared slides read on this Mac (Vision) and kept
   with the transcript at the time it appeared, for chapters and search.
6. No 1.6 GB download to start: macOS's own speech engine first (see
   Transcription).

**Left out**: themes, the transcribing animation.

## Moment

The rule (AGENTS.md → A feature's moment): when the recorder is reached
for comes before how it records.

**1. When**: a recording cannot be made afterwards, so the moment is the
start of the meeting, as the user joins or sits down. Each case is told
apart by what macOS and the calendar already say:

| The meeting | How skil.li knows | What the Record card turns on |
|---|---|---|
| A call link (Meet, Zoom, Teams…) | the event's link → the app, or the browser tab | microphone + the Mac's sound; the screen, when on, is that window |
| No link, in an app (Gather, Discord, a Slack huddle, Tuple…) | at the event's time, the app running the microphone's input: `MicrophoneUse` reads, per process, that one runs it (Core Audio's process objects, `kAudioProcessPropertyIsRunningInput`, skil.li left out; no permission) and maps it to its app: itself when it is an app the user sees, else the first such among its parents (a browser's helper to its browser), and that app's front window. Measured with a WebRTC call in Chrome (Measured, "The microphone's app"). A process with no app among its parents (a system service) stays "Nothing to go on". The event's location naming the app confirms which, when two are on the microphone | microphone + the Mac's sound; the screen, when on, is that app's window |
| In person | the event's location is a place and no app runs the microphone | the microphone only, the Mac's sound and the screen off; voices told apart on that one track (SpeakerKit); the card says to set the Mac in the middle of the table |
| A call with no event | a meeting app (one of the known call apps) runs the microphone's input | as for a call link, named after the app |
| Nothing to go on | — | the sources as they are at ↩ |

**2. The path**: one key from where the user already is.

- The meeting card that already shows as the event starts (Dismiss esc,
  Calendar ⌘↩, Join ↩; Got It ↩ without a call) gets **Record ⌘R**:
  with a call, it records and joins; without one, it records ("Record (in
  person)" for a place). ⌘R is free in skil.li and means record wherever
  a meeting shows: ⌘↩ stays Calendar. Record sits next to the button;
  Camera & Mic ⇥ moves up to the call's line (five keys do not fit on
  one line of the card).
- In a call not being recorded (the card has left, as it does once the
  user is in the call): ⌘R on the launcher's meeting row (it joins too
  when the call is not joined yet, as the card's), and Record ⌘R in the
  menu bar's meeting menu.
- At any time: `rec` in the launcher, a key, a link, a skillie. While a
  meeting is on, the Record card is that meeting's: its title, its
  attendees, its case's sources.

**3. An action, never a push**: recording other people needs their
agreement, so it is always the user's own key, and a card of its own on
every call would be noise. Record is a keycap on the card that already
shows at the moment it matters, next to Join. Taught once, then quiet
(MANIFESTO 9): the first meeting card that offers it says in one line
what ⌘R does and that the others must agree; after that only the
keycap, never a count or a badge. The first recording from the
launcher's row or the menu bar, before any card said it, opens the
Record card with its consent instead. ⌘R on the card records only once
the card has had the keyboard for a second (a browser's reload on its
way as the card comes never records); mid-typing the card never takes
the keyboard. Never automatic.

**4. Deterministic, no Jev**: the case, the app and the window come from
the event (link, location), Core Audio (which app runs the microphone)
and the window list. A model would add a delay, send window titles off
the Mac and sometimes be wrong, for nothing gained. AI comes after the
meeting and only on the user's action: the summary, action items (and,
later, names put on voices from what is said: not in phase 5), by the
user's AI (Claude). What it is
sent: the transcript's text with its speaker labels and times, the
event's title, and for names on voices the attendees' names. Never the
audio, the video or the screen, window titles or the contacts (as in
Privacy and consent's table).

**5. Wrong**: nothing is recorded before the user's key, so a wrong
guess records nothing. ⌘R from the meeting card starts at once with the
sources found; the menu bar names each with its level, and a wrong one
(two apps on the microphone, "in person" misread) is changed from the red
dot's menu, kept from then on. A recording started wrong is thrown away
after Stop: ⌘⌫ in its window deletes it, to the Trash, with ⌘Z for 10 s
(`UndoableDeletes`). A keycap not wanted costs nothing: it is not
pressed.

## What skil.li already has

- **Speech to text on this Mac**: `VoiceInput` (macOS 26 `SpeechAnalyzer`,
  `SpeechTranscriber` / `DictationTranscriber`, the latter with a vocabulary),
  used by Ask by Voice and Dictate.
- **The meeting itself**: `Agenda`, `MeetingBar`, `MeetingAlert` know the
  next event, its attendees, its call link, when it starts and when it is
  joined.
- **Camera and microphone shown live**: `MeetingCheck` (the meeting card's
  Check Camera & Mic), the sound check before a recording starts.
- **Screen capture and reading**: ScreenCaptureKit (`WindowCapture`,
  `ScreenSight`) and Vision text recognition; Screen & System Audio Recording
  is already in setup.
- **Browser tabs**: `BrowserTabReuse` finds a tab by its address in Safari
  and Chrome's family (Chrome, Brave, Edge, Chromium, Vivaldi); not Arc,
  whose scripting says nothing reliable about tabs. It loads the address
  in that tab (`set URL of tab`), which for a meeting would reload the page
  and leave the call: the recorder only selects the tab (`set active tab
  index`), without bringing the browser forward.

## Before

The Record card (launcher "Record Meeting", `rec`; the meeting card's
Record button as a call starts; a key; a `skilli://record` link; a
skillie):

- The name: the event's title when a meeting is on, else "Meeting 14:30";
  editable all along.
- Sources, each a row with its live meter or picture: the microphone, the
  Mac's sound, the webcam (off by default), the screen (off by default:
  a window to pick, or the meeting's browser window, found from the event's
  call link).
- The language: Ask's, else the keyboard's.
- ↩ starts. Never automatic.

**A browser tab**: macOS records a window, not a tab inside it. The
meeting's window is recorded; when the recording starts skil.li brings the
meeting's tab to the front in it (Safari, Chrome's family; the tab
selected, never reloaded, the user's app keeping the keyboard), and the
card says that another tab picked during the call is recorded too.
Chrome's window records only while some of it is in sight (fully
covered, the same picture again and again; Arc keeps painting), and no
browser's records minimized or hidden: the card says "keep the meeting's
window in sight", and the recording notices a window that stops giving
pictures and says so in the menu bar. When it
cannot (Arc, a browser it does not script, its Automation permission not
given, no tab on the meeting's address, a script that fails), the card
says so and asks the user to bring the meeting's tab forward; ↩ then
records the window as it is. Recording one tab whatever is in front would
need a browser extension: not planned.

## During

- The menu bar: a red dot, the time, the two waves (mic above, Mac below).
  Its menu: Pause / Resume, Stop, the webcam and the screen on or off.
- Pause writes nothing to any track until Resume; the clock stops.
- Each track keeps its own clock (measured in step over an hour with
  pauses, and failing without each of these): the tap's IO on Core Audio's
  real-time thread under an activity that keeps macOS from napping it;
  sound written by the device's sample time, a missed cycle written as
  silence of its length; every `AVAudioEngine` started again after a
  change of the audio setup; the display kept on while recording.
- The call ends (the meeting app leaves its call, or the event is over and
  the Mac's sound has been silent for a minute): a card offers Stop ↩.
- Written as it comes: a crash or a power cut keeps what was recorded,
  and the next launch offers Save, Later or Discard. A Stop whose files
  are not written and finished within 5 s (the encoder or the disk stuck),
  or whose writer ends without a completed file, is never transcribed as if whole: `meeting.json` keeps the state it had
  while recording, no transcript starts, and the same card offers it at
  once. skil.li quitting (a
  logout too) stops it as Stop does, and the Mac going to sleep pauses it:
  see Quit and sleep.

## Quit and sleep

2026-10-25: two moments a recording meets that phase 1 left to the crash
path. Each by the Moment rule (AGENTS.md → A feature's moment).

**skil.li quits during a recording**: the user quits it (its menu,
`pkill`), macOS quits it (a logout, a restart), an update is installed,
or System Settings quits it to apply a permission (Quit & Reopen).

1. **When**: mid-meeting or once it is over, the recording cannot go on
   past the quit. Nothing about it is lost if it is closed properly.
2. **The path**: none to add. The quit is the user's action (or macOS's)
   and goes through at once: no question in its way (MANIFESTO 6: what is
   kept needs no question).
3. **Neither hint nor push**: the recording is stopped as Stop stops it,
   every track on (the sound's two, the webcam and the screen when on)
   closed at the same moment (whole files: about a second, the last
   buffers), `meeting.json` written `stopped`. Its transcript is left
   for the next launch, made then a few seconds in without asking, the
   menu bar's ring showing it while it is made; done, no window opens (it
   was not asked for at that moment): the recording is in the launcher
   (`recs`) and Settings → Recorder. Never at the quit itself: a meeting's
   transcript takes minutes, and a logout or a restart does not wait for
   it. A transcript being made, or waiting its turn, as skil.li quits is
   left the same way and made at the next launch.
4. **Deterministic**: nothing to judge; macOS asks skil.li whether it
   may quit (`applicationShouldTerminate`), and skil.li answers once the
   files are closed.
5. **Wrong**: a quit the user did not mean during a meeting ends the
   recording there; the next launch never records again by itself
   (recording others is always the user's key): ⌘R makes a second
   recording. A crash or a power cut is not a quit: what was written is
   kept and offered at the next launch (Save, Later or Discard), as
   before. The one exception to `stopped`: if either track is not
   written and finished within 5 s of the quit (the encoder or the disk
   stuck), or its writer ends without a completed file, `meeting.json` keeps the state it had while recording
   (`recording`, or `paused`), no transcript starts, and the next launch
   takes it through the same recovery as after a crash (offered: Save,
   Later or Discard, its length read from its files). The quit does not
   wait longer: a logout would not.

**The Mac goes to sleep during a recording**: the lid closed, Sleep in
the Apple menu, the battery run out. A recording keeps the Mac and its
display from sleeping when idle (During), so this sleep is always the
user's act or the battery's.

1. **When**: most often the meeting is over and the lid is closed
   without Stop; or the user moves with the Mac shut (to another room,
   in person) and the meeting goes on; or the battery runs out.
2. **The path**: at wake, the card the call's end uses, in its place:
   Resume ↩, Stop ⌘↩ (stops and transcribes), Keep Paused esc. Resume
   and Stop are also where they always are, the red dot's menu.
3. **Paused, then a push at wake**: as the Mac goes to sleep the
   recording is paused, every track on at the same moment, as Pause does
   (the time asleep and the time paused after it are in no track).
   Nothing resumes by itself: whoever is in the room at wake has not
   agreed to be recorded then. The card at wake is a push, because the
   rest of a meeting that goes on is lost if missed and due now, and the
   pause happened out of sight (MANIFESTO 8). Like the call's end card,
   it never takes the keys from the app the user is typing in (the
   password at the lock screen first): a click, or a second without a
   key. A recording the user had paused before the sleep stays paused,
   and nothing is shown at wake: it was their choice.
4. **Deterministic**: macOS says when it sleeps and wakes
   (`NSWorkspace.willSleepNotification`, `didWakeNotification`).
5. **Wrong**: the meeting was over: ⌘↩ stops it, esc leaves it paused
   (the call's end card follows if the meeting is over and quiet). The
   meeting goes on and the card was missed: the hollow grey dot and the
   still clock in the menu bar, Resume Recording in its menu. Not
   measured: what a real sleep does to the sources after wake (the test
   Mac cannot be woken without a person); the microphone's engine is
   started again on the change of audio setup a wake brings, as for any
   other.

## Transcription

On this Mac, at Stop, with progress in the menu bar.

- **Engine** (measured, see Measured): whisper.cpp large-v3-turbo, the
  full model, as the optional "Better transcription" download (1.6 GB,
  for the recorder only, never Ask or Dictate): with its VAD, the
  attendees' and contacts' names as its prompt carried to every window,
  and two of its failures taken out after it (a segment repeated right
  after itself; an attendee's name written as a speaker label). 40 %
  fewer errors than macOS's best, two names in three right. Until it is
  downloaded: `SpeechTranscriber`, given no names (it ignores them).
  `DictationTranscriber` is not a choice of engine (more errors
  everywhere, little gain on names); its one use is the language fallback
  below, for a language `SpeechTranscriber` does not have.
- **Who spoke**: the microphone is the user; the Mac's sound is the others.
  Several voices on the other side, and an imported file (one track), are
  told apart by SpeakerKit (MIT, pyannote on Core ML, 11 MB), the number
  of speakers found by itself (measured: the fewest errors, the fastest).
  Its mistake is an extra speaker with a few lines, which the user merges
  by giving it a name already used.
- **No headphones**: the microphone also hears the other side (78 to 88 %
  of its words came back in the user's transcript). Those words are
  dropped from Me by each word's time against Them. Measured: 3 % left
  with `SpeechTranscriber`, which gives each word's time; 30 to 37 % with
  whisper, whose times are per line and on the audio without its VAD's
  silences. For whisper, the times are put back on the recording's clock
  first (the VAD's cuts added back): 15 % left (Measured, phase 4),
  half as many, still well behind `SpeechTranscriber`.
- A language this Mac cannot transcribe: the Record card checks it before
  ↩, the default engine first (whisper when it is the one downloaded and
  set), then the others (`SpeechTranscriber.supportedLocales`,
  `DictationTranscriber`'s). The first engine that has the language is
  used; when none has it,
  the card says so ("Italian can't be transcribed on this Mac yet") and
  ↩ still records: the recording is kept, its transcript pending, made
  from the done window once a language or engine that works is picked.
  `meeting.json`'s `engine` is the engine that made the transcript, after
  a fallback too, and `null` while the transcript is pending.
- Transcribe again in another language, or with another engine, from the
  done window: the language and the engine picked are used as picked,
  never another in their place. One this Mac cannot use says why and
  leaves the current transcript as it is (a pending one stays pending
  until a choice that works is picked).

## Done

The recording's window (a window, not a card: it is read and edited):

- A player with the waveform of both sides; click or drag to seek; click a
  line to play from there; the line playing is lit and followed.
- The webcam and the screen play small beside the transcript, in step.
- Speakers on the left, renamed at any time (the attendees offered first;
  two given the same name become one; the user's own name kept).
- A line: edit it in place, give it to the next speaker, delete it (Undo
  ⌘Z for 10 s).
- Chapters by the user's AI (meetings of three minutes or more, on the
  button): in the list, as headings, as marks on the waveform.
- ⌘K: Summary by Claude (↩), Chapters by Claude, Action Items to
  Reminders by Claude, Recap Mail to the Attendees (by Claude while there
  is no summary yet), Ask Claude About This Meeting…,
  the user's skillies for recordings (omarchy's Actions; one may run on
  its own when a transcript is done, said in its row), Transcribe Again,
  Show in Finder, then Copy Transcript and Copy Summary, then Delete
  (docs/meeting-recorder-views.md, "Phase 5").
- Import: drop an audio or video file on the window, or Import… in the
  launcher.

## Where it lives

`~/Library/Application Support/skil.li/Recordings/2026-10-22 14.00 Weekly sync/`:
`me.m4a`, `them.m4a`, `webcam.mp4`, `screen.mp4` (when on), `meeting.json`
(title, attendees and their addresses, speakers, language, engine,
chapters, the skillies run on it), `transcript.md` (times, speakers,
chapters), `transcript.json` (words with times), `slides.json` (text read
on screen, with times), `summary.md` when asked.

- The folder's name is the date and the title. In the title, `/` and `:`
  become `-`, control characters and a leading dot go, and it is cut at 80
  characters; an empty one is "Meeting". A folder of that name already
  there: " 2", " 3"… is added; nothing is ever written into another
  recording's folder. A title renamed later renames the folder by the same
  rules.
- The launcher finds recordings by title, date, attendees and words said
  (plain text search; by meaning behind ⇥, as the clipboard: later, not
  built yet).
- Settings → Recorder (its own pane): where to keep them, delete after N
  days, language, engine, the sources on by default, the meeting card's
  Record button on or off; the recordings list last.
- Deleting: a recording deleted by hand goes through `UndoableDeletes`
  (Undo ⌘Z for 10 s). Delete after N days works as the clipboard's
  retention: pruned at launch and then hourly, never at the moment the
  setting changes, a line under it says what the next pass removes; an
  expired recording goes to the Trash, not deleted for good.
- Agents: `list_recordings` (titles, dates, lengths), `get_transcript`,
  `recording_followup` and `rename_recording` (and the `$SKILLI_CLI call`
  equivalents); `skilli://record/rename?recording=…&title=…` too, asked
  first. Rename… in a recording's window and on its row in the launcher.
- The words said, for the launcher's search, are also in
  `recordings-index.sqlite`, in Application Support's `skil.li` folder,
  where it stays when the Recordings folder is moved (with SQLite's
  `-wal`, `-shm` and `-journal` files). Like the recordings, never in a
  backup (Settings → Backup: "never what you copied or recorded"), and a
  restore leaves it as it is, each of those four names by its exact name
  (`BackupPlan.neverCopied`). It is only a copy: one out of step with the
  recordings (a transcript made again, a recording renamed, deleted or
  brought back) is caught up from the recordings before each search, and
  one that is not a database it can read is made again from them.

## Privacy and consent

- skil.li never sends audio, video or the screen anywhere. A transcript
  leaves the Mac only by an explicit action of the user, each time, and
  only as text, with one exception: a skillie the user marked to run on
  its own when a transcript is done. It gets the recording's folder, media
  included, and does whatever the user's own script does with it. Marking
  it says, in its row, that it will get every recording from now on (Undo
  ⌘Z for 10 s); the done window shows that it ran and when; unmarking
  stops it.

  | Flow | Goes to | What is sent | Consent |
  |---|---|---|---|
  | Record, transcribe, play, search, read slides | nowhere | nothing | — |
  | "Summary by Claude", chapters, action items, Ask about a meeting, names put on voices (later) | the user's own AI (its provider) | the transcript's text with its speaker labels and times, the text read on screen with its times, the event's title and date, and for names on voices the attendees' names | the button or the request, which names where it goes |
  | Recap Mail | the attendees, by the user's mail app | the recap the user reads first | Send, in the mail app |
  | `get_transcript` | the agent that calls it (Claude Code, Codex…), then its provider | that recording's transcript | asked every time in the card, naming the recording (`ToolPolicy` `everyTime`: no Always Allow) |
  | `recording_followup` | the user's own AI, then the agent that calls it | the transcript as for "Summary by Claude"; the agent gets the summary, chapters, reminders or answer | asked every time in the card, naming the recording and the provider (`everyTime`) |
  | `list_recordings` | the agent | titles, dates, lengths, no words | the tool rights of a read |
  | A skillie marked to run when a transcript is done | wherever that skillie sends it (the user's own script) | the recording folder's path, so everything in it | marked once, by the user, in the skillie's row: the one exception to "each time" below |

- Never a hidden recording: the red dot stays while recording, and the
  first time, a card says that the others in the call must agree (in many
  countries, France included, recording a private conversation without
  consent is an offense), for the webcam and the screen as for the sound.
  No auto-record on meeting start.
- The Mac's sound has no error to show: without its permission the tap
  records silence and every call succeeds. Screen Recording (which skil.li
  asks for "do it here") covers it; with `NSAudioCaptureUsageDescription`
  a Mac without it gets System Audio Recording Only at once. The Record
  card's live meter is the check: silence while the call talks.
- Only the sources turned on need their permission. A source whose
  permission is missing shows off in the Record card, with that permission
  named, and ⌘↩ opens it; ↩ records the others. With neither the
  microphone nor the Mac's sound allowed, there is nothing to record and
  the card says so. A missing camera or screen permission never blocks a
  recording with those sources off.

## Phases

1. Record the two tracks, pause, stop, recovery, files, transcript with the
   player (macOS's engine, Me / Them).
2. The Moment: Record ⌘R on the meeting card, the launcher's meeting
   row and the menu bar's meeting menu, the five cases (link, in an app,
   in person, no event, nothing); the event's title and attendees, stop
   offered at the call's end, launcher search, Settings pane, retention.
3. Webcam and screen (window, meeting browser window), slides read.
4. Speakers told apart (SpeakerKit), import, edit lines, rename
   speakers, transcribe again; the "Better transcription" download
   (whisper).
5. Chapters, summary, action items, recap mail, Ask about a meeting,
   skillies on done, agent tools (docs/meeting-recorder-views.md,
   "Phase 5").

Each phase checked on the mini with a played-back call (audio and video
files standing in for the microphone, the other side and the camera),
transcript compared with the script read. From phase 3, a test window
shows slides with known text at known times: `slides.json` must hold
that text at those times (within a second), and `screen.mp4` must stay in
step with the sound.

## To check before building

Measured on 2026-10-23 on macOS 27.0.1 (the test Mac's), not on 26: see
Measured below. Still open:

- The microphone's app in a desktop call app's real call (Discord, a
  Slack huddle, Teams) and in Safari: not run on the test Mac (a
  signed-in account and a call needed; Safari's own question for the
  page needs a click). Measured: a WebRTC call in Chrome (Measured, "The
  microphone's app"), and the process trees of Arc's and Slack's helpers.
- The tap on a real Zoom, Teams and FaceTime call (no account and no
  second device on the test Mac); a WebRTC call in Chrome, Meet's way, was
  measured.
- The webcam in step with the rest (the test Mac has no camera), and a
  USB or Bluetooth microphone's clock.
- No headphones with real speakers and a real microphone (the test Mac
  has neither): macOS's own echo cancellation (`AVAudioEngine`'s voice
  processing) against the word-level drop measured below.
- Whether whisper's drop (15 % of the other side left with its times on
  the recording's clock, Measured) gains from whisper.cpp's DTW word
  times, or whether macOS's engine should make the microphone's track
  when no headphones are worn.

## Measured

2026-10-23 (and 2026-10-24 for the microphone's app; 2026-10-26 for
phase 4's runs through the app, each dated where it is), on the test Mac
(Mac mini, M4, 24 GB, macOS 27.0.1), with
`script/recorder-measure/` (its README says how to run it again). None of
it is in the app: whisper.cpp and the speaker-separation packages were
built in that folder's `work/`, which git ignores; the app probe
(`Sources/Skilli/Support/RecorderProbe.swift`, `RecorderSyncProbe.swift`)
compiles only with `SKILLI_SELFTEST`.

### The calls

Sixteen scripted calls with invented people: 107 min, 19,226 words, 1,029
of them in names (`script/recorder-measure/corpus/`).

- English: eight calls (44 min), 22 people, 28 voices: macOS's American,
  British, Irish, Australian, South African and Indian voices, and Piper's
  (VCTK and LibriTTS speakers); in two calls the user is a French voice
  reading English (`en03`, `en07`), the strongest accent of the set.
- French: the eight parts of one committee (63 min), six people, a
  Canadian voice among them and an English voice reading French (Ysaline
  Vandevelde).
- The hour: the eight French parts as one call (63 min).
- Each turn read by its person's voice; the other side through each
  person's room and noise, then Opus at 24 or 32 kb/s (12 kb/s in `en02`
  and `fr04`: a bad line); the user through a room and a noise floor. One
  turn in eight starts before the last one ends (crosstalk).
- Uncommon names (Kwabena Mensah, Zbigniew Kowalczyk, Maëlys Le Guennec,
  Tancrède Abgrall, Atelier Quillard, Ostréa…), each said four times or
  more.
- Every candidate voice first read the same paragraph; one family no
  engine could follow was left out (Piper's MLS French voices babble for
  seconds on short sentences). Voices speak cleaner than people and do
  not know the names either: real calls will score worse for every
  engine. The choices rest on the ranking.

### Speech engines

Each track transcribed alone, as the recorder will: the microphone (me)
and the Mac's sound (them). Errors per hundred words (substitutions,
deletions and insertions against the script; case, punctuation, hyphens,
fillers and how a number is written left out), pooled over the calls.
Clean: words nobody else says at the time, by neither of the strongest
accents, not on the bad line. Names right: each word of a name spelled as
the script has it. Speed: seconds of audio per second of work on the M4,
the model's load left out (whisper's: 0.4–1 s). Memory: the peak of the
process doing the work (Apple's engines run in `localspeechrecognition`;
the probe beside it stays at 20 MB). The names: the event's attendees
first, then the contacts in no particular order, 100 at most (as
`DictationVocabulary`), for `DictationTranscriber`; whisper's prompt, 450
characters at most ("Attendees: …. Also: …."), holds the attendees and
about 20 contacts, and is carried to every 30-second window
(`--carry-initial-prompt`). VAD: whisper.cpp's Silero VAD.

The sixteen calls (32 tracks, 19,226 words, 1,029 of them in names),
errors per hundred words up to Bad line:

| Engine | EN me | EN them | FR me | FR them | All | Clean | Crosstalk | Strong accent | Bad line | Names right | × real time | Peak memory |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `SpeechTranscriber` | 26.4 | 11.3 | 8.7 | 22.6 | **17.9** | 8.4 | 53.9 | 80.6 | 14.4 | 38.7 % | 122 | 0.3 GB |
| `DictationTranscriber` | 26.7 | 18.0 | 10.6 | 29.7 | **23.4** | 13.8 | 75.9 | 79.1 | 23.1 | 38.8 % | 44 | 0.6 GB |
| `DictationTranscriber` + names | 26.1 | 17.9 | 10.2 | 29.6 | **23.2** | 13.5 | 76.1 | 79.1 | 22.9 | 42.5 % | 40 | 0.6 GB |
| whisper turbo + VAD | 12.9 | 6.5 | 7.8 | 18.2 | **12.6** | 5.8 | 35.6 | 58.4 | 11.1 | 51.5 % | 21 | 2.0 GB |
| whisper turbo + VAD + names | 12.2 | 5.6 | 5.9 | 15.4 | **10.8** | 5.4 | 31.1 | 47.3 | 8.7 | 66.9 % | 27 | 2.0 GB |
| whisper turbo q5_0 + VAD + names | 12.8 | 5.3 | 5.3 | 18.5 | **12.1** | 4.8 | 30.4 | 52.2 | 24.4 | 65.9 % | 28 | 0.9 GB |

The hour (the French committee as one call), errors per hundred words:

| Engine | Me | Them | All | Names right | × real time | Peak memory |
|---|---|---|---|---|---|---|
| `SpeechTranscriber` | 8.7 | 22.5 | **19.4** | 37.4 % | 123 | 0.2 GB |
| `DictationTranscriber` + names | 10.9 | 30.5 | **26.1** | 42.0 % | 52 | 0.5 GB |
| whisper turbo + VAD + names | 6.0 | 16.2 | **13.9** | 64.0 % | 28 | 2.6 GB |

- `SpeechTranscriber` ignores the names: given or not, the same text,
  word for word, in every call.
- `DictationTranscriber` reads them, for little: names right 38.8 →
  42.5 %. It makes more errors than `SpeechTranscriber` everywhere (23.2
  against 17.9 per hundred; 76 against 54 in crosstalk), at a third of its
  speed.
- whisper large-v3-turbo with VAD and the names: the fewest errors in 31
  of the 32 tracks, two thirds of the names right (72 % of the
  attendees'): 69 % of the names in its prompt, 56 % of the others. It
  gains most where the others fail: crosstalk, the strong accents, the bad
  line.
- The hour: every engine within a point of the eight parts heard alone;
  nothing drifts over an hour. whisper took 4.6 min for both tracks (2.6 GB),
  `SpeechTranscriber` 1 min.
- Without VAD, whisper cannot take the microphone's track: it loops on
  the silences while the others talk, the same line up to 324 times. On
  four calls (`en01`, `en05`, `fr01`, `fr05`): 97.8 errors per hundred
  words on that track (225.9 with the names), against 8.0 (5.5) with VAD.
- The q5_0 model (0.57 GB to download instead of 1.62, 0.9 GB of memory
  instead of 2): as good on clean speech (4.8 against 5.4), worse overall
  (12.1 against 10.8), above all on the bad line, where it looped.
- whisper's two failures: a line repeated over and over (the full model
  on 1 track of 34, the hour's other side, 5 times; q5_0 on 2 of 32, up to
  52 times), and once, with the names, attendees' names written as
  speaker labels ("Camille Kerjean : …", 46 times in one track). Taking
  both out after it (a line equal to the one before; "‹attendee› :"):
  10.8 → 10.4 errors per hundred.

**Pick: whisper large-v3-turbo, with VAD and the names, as the optional
"Better transcription" download; `SpeechTranscriber`, without names,
until it is downloaded.** whisper makes 40 % fewer errors and gets 1.7
times as many names right. `DictationTranscriber` is worse than
`SpeechTranscriber` on everything but names, and gains little there.

### Telling voices apart

On the Mac's sound (several people on one track) and on the one-track
import (`mix`). Diarization error rate: missed speech, false alarms and
speech given to the wrong speaker, over the script's speech (overlap
counted, no collar; the reference marks where each synthesized turn
sounds, so about 8 points of misses and false alarms are the reference's
own, the same for all). Count right: calls where the number of speakers
found is the real one. Told the count: given the event's attendees (less
the user on the Mac's sound); every attendee speaks in these calls.

| Candidate | The Mac's sound | Of it, wrong speaker | Count right | Told the count | One-track import | Count right | Told the count | × real time | Peak memory |
|---|---|---|---|---|---|---|---|---|---|
| SpeakerKit (Argmax's open-source SDK 1.1.1, MIT: pyannote community-1 on Core ML, 11 MB of models) | **10.8 %** | 3.4 % | 11 of 17 | 11.2 %, 17 of 17 | **12.7 %** | 9 of 17 | 12.7 %, 17 of 17 | 380 | 0.8 GB |
| FluidAudio 0.17.7, offline (Apache 2.0: pyannote community-1 and VBx on Core ML, 21 MB) | 13.1 % | 4.7 % | 14 of 17 | 12.5 %, 17 of 17 | 14.7 % | 13 of 17 | 14.4 %, 17 of 17 | 260 | 0.5 GB |
| sherpa-onnx 1.13.8 (Apache 2.0: pyannote segmentation 3.0 and WeSpeaker ResNet34, ONNX on the CPU; the 16 calls, not the hour) | 28.1 % | 21.6 % | 4 of 16 | – | 31.4 % | 5 of 16 | – | 16 | 0.3 GB |

- SpeakerKit's wrong counts are one or two speakers too many, six times,
  each holding 1 to 3 % of the speech; it never found too few on the
  Mac's sound. FluidAudio's are one too few, three times: two people as
  one.
- Told the count, both find it every time, but every attendee speaks in
  these calls; a real one has attendees who stay silent, and an exact
  count then splits someone. FluidAudio told "at most one more than the
  event has" does exactly as untold.

**Pick: SpeakerKit, the count found by itself.** The fewest errors, the
fastest, and its mistakes are an extra speaker with a few lines, which
the user merges by giving it a name already used (Done), where
FluidAudio's are two people under one name, which no rename undoes.

### The Mac's sound: the Core Audio process tap

A tap on every process but the probe's
(`CATapDescription(stereoGlobalTapButExcludeProcesses:)`, a private
aggregate device, one IO block), 5 to 8 s each, while something played.
The test Mac's speakers were muted: the tap heard all the same (it takes
the sound before the volume). What macOS checked is read in its privacy
log (`tccd`), what the tap heard in its samples.

| The app | What macOS checked | The tap |
|---|---|---|
| skil.li, Screen & System Audio Recording on (as for "do it here"), no `NSAudioCaptureUsageDescription` | Screen Recording (`kTCCServiceScreenCapture`, asked by `coreaudiod`): allowed | heard, every run, no prompt |
| A new app, nothing allowed, with `NSAudioCaptureUsageDescription` | System Audio Recording Only (`kTCCServiceAudioCapture`): allowed at once, no window on screen (two new apps; 5 ms in the log for the first) | heard |
| A new app, nothing allowed, without it | nothing | silence; every call returns `noErr` |

| What played | The process playing | Tap on every process | Tap on the app's processes |
|---|---|---|---|
| A WebRTC call in Chrome: the other side's voice sent and received over `RTCPeerConnection`, as Meet does | `com.google.Chrome.helper` | heard, 3 of 3 | heard, 3 of 3 (with its helper) |
| A recording played in a Chrome tab | `com.google.Chrome.helper` (Chrome's own process plays nothing) | heard, 3 of 3 | heard, 6 of 6 |
| `afplay`, `say` | the tool | heard | – |
| `say` to another output (a virtual device), the default output being the speakers | the tool | heard | – |
| A Zoom, Teams or FaceTime call | – | not measured | – |

ScreenCaptureKit's own sound (`capturesAudio`, the whole display) heard
the same, 3 of 3, but only with Screen Recording itself.

**Pick: one tap on every process but skil.li's.** It hears whatever app
and whatever output the call uses; a tap on the meeting app has to find
the app's helper processes (Chrome's sound is its helper's) and would
miss what another process plays; ScreenCaptureKit's sound would make
Screen Recording a must even with the screen off. The Screen Recording
permission skil.li already asks for covers it.
`NSAudioCaptureUsageDescription` goes in Info.plist for whoever never
gave Screen Recording: without it the tap records silence and nothing
says so.

### The screen: ScreenCaptureKit on a browser's window

A test page counting its frames (`requestAnimationFrame`), its window
captured at four pictures a second for 14 s, the count read on each
picture (Vision). Painting: the count goes up; frozen: the same count on
every picture; another app in front: Finder.

| The window | Chrome | Arc |
|---|---|---|
| In front | painting | painting |
| Another app in front, the window in sight | painting | painting |
| Half covered by another window | painting | painting |
| Fully covered by another window | **frozen**, 3 runs of 3 | painting, 3 of 3 |
| Minimized | no picture (the stream is suspended) | no picture |
| Hidden (⌘H) | no picture | no picture |

The meeting's tab brought forward in Chrome while its window is captured,
by `BrowserTabReuse`'s script (`set active tab index`), run from the
test's shell (skil.li had no Automation right for Chrome on the test Mac):

| Chrome | The meeting's tab in the capture |
|---|---|
| Another app in front, the window in sight; the tab only | after 0.35, 0.50, 0.88 s |
| The same, the window and Chrome brought forward too (`set index`, `activate`, as `BrowserTabReuse` does) | after 0.42, 0.52, 0.52 s |
| Fully covered | never, 3 of 3: Chrome does not paint it |

**Pick: the meeting's window as specified, with two rules.** Its tab is
brought forward without bringing Chrome forward (the tab shows within a
second, the user's app keeps the keyboard), and the recording watches its
pictures: a window minimized or hidden gives none, and Chrome's, fully
covered, gives the same picture again and again.

### In step over an hour

The probe's window (ScreenCaptureKit, each picture at its own time) went
to an MP4 file, the Mac's sound (the tap) to a WAV file sample after
sample, as the recorder would write them; every 10 s the window flashed
white and a click played; a 30 s pause every 10 minutes, nothing written
during it, the pauses taken out of both files' time. Then where each
flash and each click landed in the files (a flash: a picture whose mean
brightness jumps; a click: the sound over -40 dBFS).

The first hour failed three ways, each a rule for the recorder:

- The tap's IO block ran on a dispatch queue: macOS let it fall behind
  while the display was off (23 min of the hour), 16,022 cycles never came,
  and a file written sample after sample came out 23 minutes short of the
  picture. On Core Audio's real-time thread (its IO block given no
  queue), under a `beginActivity` (`.latencyCritical`,
  `.idleSystemSleepDisabled`), and with a missed cycle written as silence
  of its length (by the device's sample time), the second hour missed
  no cycle.
- The microphone's `AVAudioEngine` stopped after 62 s, and the probe's own
  click player after about two minutes: a change of the audio setup
  stops an engine and nothing starts it again. Started again on
  `AVAudioEngineConfigurationChange`, the second hour's microphone went
  on to the end (12 restarts). The recorder does the same and keeps the
  track's time by the device's clock, not by the samples it got.
- The display off, the picture stops too: no frames for those 23 min. A
  recording keeps the display on, as a call does.

| | First hour | Second hour |
|---|---|---|
| Clicks found in the sound file | 34 of 345 | **345 of 345** |
| Flashes found in the picture | 195 of 345 | **345 of 345** |
| The tap's cycles missed | 16,022 (23 min) | 0 |
| The sound file against the picture | 23 min short | the same length |
| Sound minus picture, 10-minute means | – | 233, 231, 224, 214, 222, 216 ms (each click ±14 ms) |
| The output's clock against the Mac's | −11 ppm | −5.3 ppm: −19 ms an hour |
| The microphone | stopped after 62 s | to the end, 12 restarts |

The constant part of the offset (about 0.2 s) is the time `afplay` takes
to play, the test's own. What the recorder would add is the change over
the hour: 17 ms less at the end, as the output's clock predicts, and no
step at any of the five pauses. In step means: well under one picture
(33 ms at 30 pictures a second) after an hour, with no resampling.

**Pick: each track by its own clock.** The sound written by the device's
sample time (a missed cycle is silence of its length), the tap's IO on
Core Audio's real-time thread under an activity that keeps macOS from
napping it, every `AVAudioEngine` started again after a change of the
audio setup, the pictures at their own times, a pause cut from all of
them at the same moment, the display kept on while recording. The
webcam is not measured (no camera on the test Mac).

### No headphones

The microphone's track with the other side heard again from the
speakers (12 or 20 dB under the user's voice, 45 ms late, through a small
speaker's band and the room), each engine on it and on the Mac's sound,
then the drop the spec asks for: a word of the microphone's track goes
when the Mac's sound has the same word from 0.5 s before to 2 s after, in
runs of two words or more (a lone "yes" stays). The rule and its window
were set before the runs, not tuned. The sixteen calls, the user's 5,008
words; the other side's 14,218.

| Engine | The other side | The user's errors per hundred words: headphones | No headphones | After the drop | The other side's words in the user's transcript: no headphones | After the drop |
|---|---|---|---|---|---|---|
| `SpeechTranscriber` | 12 dB under | 18.0 | 266.3 | **33.0** | 80.9 % | **2.7 %** |
| `SpeechTranscriber` | 20 dB under | 18.0 | 260.7 | **38.1** | 77.8 % | **3.0 %** |
| `DictationTranscriber` + names | 12 dB under | 19.0 | 198.6 | 49.5 | 58.9 % | 9.4 % |
| `DictationTranscriber` + names | 20 dB under | 19.0 | 145.6 | 67.9 | 41.4 % | 15.6 % |
| whisper turbo + VAD + names | 12 dB under | 9.2 | 281.8 | 130.4 | 88.1 % | 36.8 % |
| whisper turbo + VAD + names | 20 dB under | 9.2 | 291.5 | 134.7 | 82.9 % | 30.4 % |
| whisper, times on the recording's clock (phase 4, through the app) | 12 dB under | 8.8 | 285.7 | 64.6 | 90.3 % | 15.3 % |
| whisper, times on the recording's clock (phase 4, through the app) | 20 dB under | 8.8 | 276.0 | 68.2 | 84.0 % | 13.9 % |

- Without headphones the user's transcript holds most of the other side's
  words again, even 20 dB under the voice: the transcript doubles.
- With each word's time (Apple's engines), the drop takes most of them
  out: 3 % left with `SpeechTranscriber`, 9 to 16 % with
  `DictationTranscriber` (its two tracks agree less on the same words),
  and at most 1.5 % of the user's own words go with them.
- whisper gives times per line, not per word, once its VAD has cut the
  silences (whisper.cpp 1.9.5's word times are then those of the audio
  without its silences): the drop misses a third of the other side.
- 2026-10-26 (phase 4): with each token's time read through whisper.cpp
  1.9.5's `whisper_full_get_token_t0/t1`, which put its VAD's cuts back,
  through the app's own transcript (`remote whisper`, scored by
  `echo_dedup.py`; the tracks written as the recorder writes them): 15.3
  and 13.9 % of the other side left, against 36.8 and 30.4 % with the
  times off. Its two tracks agree less on the same words than
  `SpeechTranscriber`'s do, as `DictationTranscriber`'s: the rule and its
  window stay as they were set, not tuned on this.

**Pick: the drop by words, on each word's time.** Apple's engines give
them; whisper's are put back on the recording's clock first (the VAD's
cuts added back: measured in phase 4, 15 % left). macOS's own echo
cancellation is still to measure on a Mac with speakers and a
microphone (To check).

### The microphone's app

2026-10-24, on the test Mac (macOS 27.0.1, one input: a virtual audio
device), for phase 2's "in an app" case: which app Core Audio's
process running the input belongs to. `remote moment` runs it each
time.

| The call | The process running the input (Core Audio) | Its app | Mapped to |
|---|---|---|---|
| A WebRTC call in a scratch Chrome (its own profile; `getUserMedia` on a localhost page, standing in for Gather), the user's Chrome also open | `com.google.Chrome.helper`, a child of the scratch Chrome's own process | none (a helper) | the scratch Chrome by its parent, not the user's Chrome; its front window from the window list, owned by it |
| Arc, Slack (their helpers, read in the process tree, no call) | `Browser Helper`, `Slack Helper`, children of the app | none | the app, by the same rule |
| Safari (read in the process tree, no call) | WebKit's services are launchd's children | none | nothing: "Nothing to go on" |

- A device says it runs a moment before its process does, and an app
  just launched is named once it finished launching: the reading is
  taken again half a second after each Core Audio change, and read
  afresh when a key is pressed.
- When Chrome quits (the call's end), "Google Chrome left the call."
  comes a second later (the self-test's 1 s grace; 5 s in use).

### Through the app (phase 4)

2026-10-26, `remote whisper` and `remote voices` on the test Mac: the
sixteen calls through the recorder's own transcript (`MeetingTranscriber`,
`skil.li Transcriber`), their tracks written as the recorder writes them
(AAC, 48 kHz, 64 kb/s), scored by this kit's scorers:

| | Errors per hundred words | Names right | Attendees right |
|---|---|---|---|
| macOS's engine (`SpeechTranscriber`) | 17.7 (Measured 17.9) | 38.3 % (38.7 %) | – |
| whisper turbo + VAD + names, both failures taken out | 10.6 (10.4) | 69.0 % (66.9 %) | 75.7 % (72 %) |

SpeakerKit through the helper: 9.5 % DER on the Mac's sound (Measured
10.8 % with the hour), 11.8 % on the one-track mix (12.7 %), never fewer
voices than people on the Mac's sound. whisper's prompt is handed to the
helper in a UTF-8 file: as a process argument it arrived decomposed
(NFD), and the accented names fell to 60 %.

### What the measurements changed

Applied to the spec above on 2026-10-23 (Decided 6): the engine and the
speaker separation picked, Better 2 tied to the download, the tab
selected without a reload, Chrome's window kept in sight, the Mac's sound
checked by its meter, the clock rules of During, the drop by word times.

## Decided

2026-10-22:

1. A recording starts by hand (launcher, key, link, skillie) or from the
   Record button on the meeting card as a call starts. Never automatic.
2. The summary and chapters by the user's AI are a button ("Summary by
   Claude"), never sent on their own.

2026-10-23:

3. On par with omarchy's recorder, then better (the list above); no themes,
   no transcribing animation.
4. The webcam and the screen are recorded too: a window, or the meeting's
   browser window.
5. macOS's speech engine first; a better one (whisper or other) is fine for
   the recorder only, if measured better.

2026-10-23 (after Measured):

6. The measured picks are the spec: whisper large-v3-turbo as the
   optional download, `SpeechTranscriber` until then, SpeakerKit, one tap
   on every process but skil.li's, and the rules above.

2026-10-24:

7. The Moment above: an action, never a push; Record ⌘R on the meeting
   card (⌘↩ stays Calendar), taught once, then quiet; the five cases told
   apart by the event, Core Audio and the window list, no model; AI only
   after the meeting, on the user's action.

2026-10-25:

8. Quit and sleep above: a quit closes the recording whole, its
   transcript made at the next launch without asking and without opening
   its window; a sleep pauses it, never resumed by itself, a card at wake
   offers Resume ↩. The words said (`recordings-index.sqlite`) are never
   in a backup.
