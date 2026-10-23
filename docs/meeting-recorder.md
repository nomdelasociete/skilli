# Meeting recorder

Status: 2026-10-23, spec agreed, target raised: on par with omarchy's
recorder, then better where skil.li knows the Mac. Nothing built.

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
2. Names heard right: the attendees and the user's contacts go to the
   engine that takes words to expect (see Transcription), as Dictate's
   names do.
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
- **Browser tabs**: `BrowserTabReuse` finds a tab by its address and brings
  it to the front in Safari and Chrome's family (Chrome, Brave, Edge,
  Chromium, Vivaldi). Not Arc: its scripting says nothing reliable about
  tabs.

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
meeting's tab to the front in it (Safari, Chrome's family), and the card
says that another tab picked during the call is recorded too. When it
cannot (Arc, a browser it does not script, its Automation permission not
given, no tab on the meeting's address, a script that fails), the card
says so and asks the user to bring the meeting's tab forward; ↩ then
records the window as it is. Recording one tab whatever is in front would
need a browser extension: not planned.

## During

- The menu bar: a red dot, the time, the two waves (mic above, Mac below).
  Its menu: Pause / Resume, Stop, the webcam and the screen on or off.
- Pause writes nothing to any track until Resume; the clock stops.
- The call ends (the meeting app leaves its call, or the event is over and
  the Mac's sound has been silent for a minute): a card offers Stop ↩.
- Written as it comes: a crash, a logout or a power cut keeps what was
  recorded, and the next launch offers Save, Later or Discard.

## Transcription

On this Mac, at Stop, with progress in the menu bar.

- **Engine**: macOS's `SpeechTranscriber` first. It takes no words to
  expect (`VoiceInput`: only `DictationTranscriber` reads
  `AnalysisContext.contextualStrings`), so before building three are
  measured on the same recorded calls (French and English, accents,
  crosstalk, a one-hour call, attendees with uncommon names):
  `SpeechTranscriber`; `DictationTranscriber` given the attendees' and
  contacts' names; whisper.cpp (large-v3-turbo) given them as its initial
  prompt. Errors per hundred words, names right, time, memory. The best
  one is the default. If it is whisper, it is an optional download for the
  recorder only ("Better transcription, 1.6 GB"), never for Ask or
  Dictate; until then, the best of macOS's two.
- **Who spoke**: the microphone is the user; the Mac's sound is the others.
  Several voices on the other side, and an imported file (one track), are
  told apart by an on-device speaker-separation model, picked the same way:
  candidates measured on the same calls.
- A language this Mac cannot transcribe: the Record card checks it before
  ↩ (`SpeechTranscriber.supportedLocales`, then `DictationTranscriber`'s).
  The first engine that has the language is used; when neither has it,
  the card says so ("Italian can't be transcribed on this Mac yet") and
  ↩ still records: the recording is kept, its transcript pending, made
  from the done window once a language or engine that works is picked.
  `meeting.json`'s `engine` is the engine that made the transcript, after
  a fallback too, and `null` while the transcript is pending.
- Transcribe again in another language, or with the other engine, from the
  done window, with the same check: a language or engine this Mac cannot
  use says why and leaves the current transcript as it is (a pending one
  stays pending until a choice that works is picked).

## Done

The recording's window (a window, not a card: it is read and edited):

- A player with the waveform of both sides; click or drag to seek; click a
  line to play from there; the line playing is lit and followed.
- The webcam and the screen play small beside the transcript, in step.
- Speakers on the left, renamed at any time (the attendees offered first;
  two given the same name become one; the user's own name kept).
- A line: edit it in place, give it to the next speaker, delete it (Undo
  ⌘Z for 10 s).
- Chapters by the user's agent (meetings of three minutes or more, on the
  button): in the list, as headings, as marks on the waveform.
- ⌘K: Copy Transcript (↩), Summary by Claude, Action Items to Reminders,
  Recap Mail to the attendees, Open Folder, Transcribe Again, and the
  user's skillies marked for recordings (omarchy's Actions; one may run on
  its own when a transcript is done, said in its row).
- Import: drop an audio or video file on the window, or Import… in the
  launcher.

## Where it lives

`~/Library/Application Support/skil.li/Recordings/2026-10-22 14.00 Weekly sync/`:
`me.m4a`, `them.m4a`, `webcam.mp4`, `screen.mp4` (when on), `meeting.json`
(title, attendees, speakers, language, engine, chapters), `transcript.md`
(times, speakers, chapters), `transcript.json` (words with times),
`slides.json` (text read on screen, with times), `summary.md` when asked.

- The folder's name is the date and the title. In the title, `/` and `:`
  become `-`, control characters and a leading dot go, and it is cut at 80
  characters; an empty one is "Meeting". A folder of that name already
  there: " 2", " 3"… is added; nothing is ever written into another
  recording's folder. A title renamed later renames the folder by the same
  rules.
- The launcher finds recordings by title, date, attendees and words said
  (plain text search; by meaning only behind ⇥, as the clipboard).
- Settings → Recorder (its own pane): where to keep them, delete after N
  days, language, engine, the sources on by default, the meeting card's
  Record button on or off; the recordings list last.
- Deleting: a recording deleted by hand goes through `UndoableDeletes`
  (Undo ⌘Z for 10 s). Delete after N days works as the clipboard's
  retention: pruned at launch and then hourly, never at the moment the
  setting changes, a line under it says what the next pass removes; an
  expired recording goes to the Trash, not deleted for good.
- Agents: `list_recordings` (titles, dates, lengths) and `get_transcript`
  (and the `$SKILLI_CLI call` equivalents).

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
  | "Summary by Claude", chapters, Ask about a meeting | the user's own AI (its provider) | the transcript's text | the button or the request, which names where it goes |
  | Recap Mail | the attendees, by the user's mail app | the recap the user reads first | Send, in the mail app |
  | `get_transcript` | the agent that calls it (Claude Code, Codex…), then its provider | that recording's transcript | asked every time in the card, naming the recording (`ToolPolicy` `everyTime`: no Always Allow) |
  | `list_recordings` | the agent | titles, dates, lengths, no words | the tool rights of a read |
  | A skillie marked to run when a transcript is done | wherever that skillie sends it (the user's own script) | the recording folder's path, so everything in it | marked once, by the user, in the skillie's row: the one exception to "each time" below |

- Never a hidden recording: the red dot stays while recording, and the
  first time, a card says that the others in the call must agree (in many
  countries, France included, recording a private conversation without
  consent is an offense), for the webcam and the screen as for the sound.
  No auto-record on meeting start.
- Only the sources turned on need their permission. A source whose
  permission is missing shows off in the Record card, with that permission
  named, and ⌘↩ opens it; ↩ records the others. With neither the
  microphone nor the Mac's sound allowed, there is nothing to record and
  the card says so. A missing camera or screen permission never blocks a
  recording with those sources off.

## Phases

1. Record the two tracks, pause, stop, recovery, files, transcript with the
   player (macOS's engine, Me / Them).
2. The Record card from the meeting, the event's title and attendees, stop
   offered at the call's end, launcher search, Settings pane, retention.
3. Webcam and screen (window, meeting browser window), slides read.
4. Speakers told apart, import, edit lines, rename speakers, transcribe
   again; the measured engine choice (whisper as an option if it wins).
5. Chapters, summary, action items, recap mail, skillies on done, agent
   tools.

Each phase checked on the mini with a played-back call (audio and video
files standing in for the microphone, the other side and the camera),
transcript compared with the script read. From phase 3, a test window
shows slides with known text at known times: `slides.json` must hold
that text at those times (within a second), and `screen.mp4` must stay in
step with the sound.

## To check before building

- The Core Audio process tap: which permission macOS 26 asks ("System Audio
  Recording Only" or the full Screen Recording permission), and that it
  hears calls in Zoom, Meet in a browser, Teams and FaceTime.
- The engines and the speaker-separation candidates, measured as above.
- ScreenCaptureKit on a Chrome and an Arc window while another app is in
  front, and the tab brought forward in Chrome.
- Webcam, screen and sound in step over an hour, with pauses.
- Headphones: without them, the microphone also hears the other side.
  Measure the double transcript and drop "Them" words heard again by the
  microphone.

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
