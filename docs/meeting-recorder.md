# Meeting recorder

Status: 2026-10-22, spec agreed. Nothing built.

Asked for: a meeting recorder like omarchy-meeting-recorder (an
open-source recorder for Omarchy Linux): your microphone and the
Mac's sound as two tracks, transcribed on this Mac, nothing sent anywhere,
no bot joining the call.

## What skil.li already has

- **Speech to text on this Mac**: `VoiceInput` (macOS 26 `SpeechAnalyzer`,
  `SpeechTranscriber` / `DictationTranscriber`), used by Ask by Voice and
  Dictate. The model is downloaded once by macOS; audio never leaves.
- **The meeting itself**: `Agenda`, `MeetingBar`, `MeetingAlert` know the
  next event, its call link, when it starts and when it is joined (menu bar,
  alerts, Join ↩).
- **The permission**: Screen & System Audio Recording is already in setup
  (for "do it here" and captures).

So the recorder is mostly glue: two audio sources, files, one transcript.

## How it works

1. **Start**: from the launcher ("Record Meeting", `rec`), from the meeting
   card as a call starts (a Record button next to Join, never automatic),
   from a key, a `skilli://record` link or a skillie.
2. **While recording**: the menu bar shows a red dot and the time. The
   same key, or the red dot's menu, stops.
3. **Two tracks, written as they come**: the microphone (AVAudioEngine) and
   the Mac's sound (a Core Audio process tap, macOS 14.2+; audio only, no
   screen). A crash keeps what was recorded.
4. **Transcript at the end**, on this Mac: each track through
   `SpeechTranscriber`, merged by time. The microphone is "Me", the Mac's
   sound is "Them": who spoke, without guessing voices. Several people on
   the other side stay one "Them" (no voice separation in v1).
5. **Then**: the transcript opens in a card: lines with times, click a line
   to hear it from there; ⌘K copies it, saves it, or asks your AI for a
   summary and chapters (see Privacy).

## Where it lives

`~/Library/Application Support/skil.li/Recordings/2026-10-22 14.00 Weekly sync/`:
`me.m4a`, `them.m4a`, `transcript.md` (times, Me/Them), `transcript.json`
(words with times, for agents), `summary.md` when asked.

- The launcher finds recordings by title, date and words said (plain text
  search; by meaning only behind ⇥, as the clipboard).
- Settings → Recorder (its own pane): where to keep them, delete after N
  days, language (else Ask's), record the Mac's sound or the microphone
  only, the meeting card's Record button on or off; the recordings list last.
- Deleting: a recording deleted by hand goes through `UndoableDeletes`
  (Undo ⌘Z for 10 s). Delete after N days works as the clipboard's
  retention: pruned at launch and then hourly, never at the moment the
  setting changes, a line under it says what the next pass removes; an
  expired recording goes to the Trash, not deleted for good.
- Agents: `list_recordings` (titles, dates, lengths) and `get_transcript`
  (and the `$SKILLI_CLI call` equivalents), so Claude Code or Codex can
  write chapters, as omarchy's does with the user's own coding agent.

## Privacy and consent

- Audio never leaves the Mac. A transcript leaves it only by an explicit
  action of the user, each time, and only as text:

  | Flow | Goes to | What is sent | Consent |
  |---|---|---|---|
  | Record, transcribe, play, search | nowhere | nothing | — |
  | "Summary by Claude" | the user's own AI (its provider) | the transcript's text | the button, which names where it goes |
  | `get_transcript` | the agent that calls it (Claude Code, Codex…), then its provider | that recording's transcript | asked every time in the card, naming the recording (`ToolPolicy` `everyTime`: no Always Allow) |
  | `list_recordings` | the agent | titles, dates, lengths, no words | the tool rights of a read |

- Never a hidden recording: the red dot stays while recording, and the
  first time, a card says that the others in the call must agree (in many
  countries, France included, recording a private conversation without
  consent is an offense). No auto-record on meeting start.
- Nothing recorded when the permission is missing: the card says which one,
  ↩ opens it.

## Phases

1. Record two tracks + stop + files + transcript card (no summary).
2. Meeting card's Record button, launcher search, Settings pane, retention.
3. Summary and chapters by the user's AI; agent tools and skillie links.

Each phase checked on the mini with a played-back call (two audio files
standing in for the microphone and the other side), transcript compared
with the script read.

## To check before building

- The Core Audio process tap: which permission macOS 26 asks
  ("System Audio Recording Only" or the full Screen Recording permission), and
  that it hears calls in Zoom, Meet in a browser, Teams and FaceTime.
- `SpeechAnalyzer` on a one-hour file: time and memory on the mini, and
  whether a file input preset beats the live one.
- Headphones: with them, "Them" is only in the tap; without them, the
  microphone also hears the other side. Measure how bad the double
  transcript gets, and drop "Them" words heard again by the microphone.

## Decided (2026-10-22)

1. A recording starts by hand (launcher, key, link, skillie) or from the
   Record button on the meeting card as a call starts. Never automatic.
2. The summary and chapters by the user's AI are a button ("Summary by
   Claude"), never sent on their own.
