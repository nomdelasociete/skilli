# Meeting recorder measurements

What `docs/meeting-recorder.md` → Measured was measured with, to run again.
Nothing here is in the app: the speech engines, whisper.cpp and the
speaker-separation packages are built in `work/` (git ignores it), the app
probe compiles only with `SKILLI_SELFTEST`
(`Sources/Skilli/Support/RecorderProbe.swift`, `RecorderSyncProbe.swift`).

## The calls

`corpus/*.json`: sixteen scripted calls with invented people (rules in
`corpus/FORMAT.md`): `en01`–`en08`, eight English calls; `fr01`–`fr08`, the
eight parts of one French committee, also joined as `fr-hour` (63 min).
Each turn is read by its person's voice (`mix.py`: macOS `say` voices and
Piper voices, accents included, one voice per person), the other side
goes through its own room, noise and Opus at 24–32 kb/s (12 kb/s in `en02`
and `fr04`), the user's side through a room and a laptop-like noise floor;
turns the script marks overlap. Per call in `work/calls/<call>/`:
`me.wav`, `them.wav`, `mix.wav` (one track, an import), `echo-12.wav` and
`echo-20.wav` (the microphone without headphones: the other side heard
again 12 or 20 dB under the user's voice), `truth.json`, `vocab.txt`
(attendees, then contacts, 100 at most), `prompt.txt` (the names for
whisper's prompt).

```sh
./setup.sh                     # work/: venv, voices, whisper.cpp v1.9.5, models, probes
work/venv/bin/python calib.py work/calib     # each candidate voice reads one paragraph
work/venv/bin/python mix.py    # all calls and fr-hour (TTS cached: built again, the same)
work/venv/bin/python refine.py work/calls    # where each turn's voice sounds (speaker reference)
work/venv/bin/python prep_vocab.py work/calls
```

## On the test Mac

`./push.sh` copies the probes, models and calls to `~/recorder-measure` on
`SKILLI_REMOTE` (default `skilli-mini`). There, `bin/batch.sh` runs
variants over calls, one at a time (`LOCK_DIR`: a directory used as a lock
when the Mac is shared):

```sh
bin/batch.sh st:en01,en02 dtw:en01 wpv:fr-hour fluidN:fr-hour   # out/<variant>/<call>/<track>.json
TRACKS="echo-12 echo-20" bin/batch.sh st:en01 dtw:en01 wpv:en01  # no headphones
```

| Variant | What |
|---|---|
| `st`, `stw` | `SpeechTranscriber`, without and with the names (it does not read them) |
| `dt0`, `dtw` | `DictationTranscriber`, without and with the names (`contextualStrings`) |
| `w0`, `wv`, `wp`, `wpv`, `q5p` | whisper large-v3-turbo: plain, VAD, names prompt (carried to every window), both, both on the q5_0 model |
| `fluid`, `sk`, `sherpa` (+`N`), `fluidM` | FluidAudio's offline diarizer, Argmax SpeakerKit, sherpa-onnx; `N`: told the event's attendee count; `fluidM`: told at most one more |

Back here (`rsync` the `out` folder into `work/runs`):

```sh
work/venv/bin/python score_engines.py work/calls work/runs st dtw wpv --calls en01,fr01 --json short.json  # --tidy: whisper's repeats and labels out
work/venv/bin/python tables.py short.json hour.json          # the doc's tables
work/venv/bin/python der.py work/calls work/runs/diar fluid fluidN sk skN
work/venv/bin/python echo_dedup.py work/calls work/runs st dtw wpv
```

## The app probe

`./mkprobe.sh` (after `./script/build_and_run.sh build`) makes
`work/probe/{A,B}/SkilliRecorderProbe.app`: the Debug build under another
process name, signed again with the same identity, so macOS gives it
skil.li's permissions; B has `NSAudioCaptureUsageDescription`. On the test
Mac, opened through LaunchServices:

```sh
open -W -n probe/A/SkilliRecorderProbe.app --args recorderprobe tap ~/recorder-measure/out/tap.json 8 global
open -W -n probe/A/SkilliRecorderProbe.app --args recorderprobe window ~/recorder-measure/out/w.json com.google.Chrome 14 covered
open -W -n probe/A/SkilliRecorderProbe.app --args recorderprobe sync ~/recorder-measure/out/sync 3600 600 30
bin/winrun.sh com.google.Chrome chrome     # front, behind, covered, minimized, hidden
bin/tabrun.sh                              # the meeting's tab brought forward during a capture
```

`pages/`: the test pages (a frame counter read on every captured
picture; `webrtc.html`, a WebRTC call in one page, for a Chrome started
with `--use-file-for-fake-audio-capture` on a 48 kHz WAV and
`--disable-features=AudioServiceSandbox`, its own `--user-data-dir`).
