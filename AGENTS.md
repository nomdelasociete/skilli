# AGENTS.md

Guidance for AI assistants working on **skil.li**.

Website design, copy, demos, navigation, social previews or legal pages: read
[`docs/website-design.md`](docs/website-design.md) before editing. For website
build/publishing, use [`website/README.md`](website/README.md); website-only work
does not require Swift tests, native benchmarks or app self-tests.

## This repository is public

Everything here, its history, pull request texts, comments and the apps built
from it are public (GPL-3.0). Never add real people (the developer, family,
contacts), how a machine is set up (hosts, users, keys, lock or sleep
settings, remote access), home paths of real accounts, or internal
infrastructure. Test data uses invented people (Jean-François Martaing, Margot
Martin, Camille), `example.com` addresses and `/Users/me` paths. Machine notes
stay outside the repository. The self-tests and their data never ship: they
compile only with `SKILLI_SELFTEST`. `.github/workflows/hygiene.yml` checks
every pull request for the generic cases (keys, home paths, remote access).

## What this is

Native macOS launcher, a fast and light alternative to Raycast: app search,
Hyper key, chord and multi-key sequence bindings, text transforms on the
current selection (AI presets next), and deep app actions (CleanShot X URL
scheme, menu search, contacts). macOS only.

- **Bundle ID:** `com.nomdelasociete.Skilli` — display name `skil.li`
- **Repo:** https://github.com/nomdelasociete/skilli
- **Stack:** Swift 6 (strict concurrency), AppKit, XcodeGen, Liquid Glass
  (`NSGlassEffectView`). No SwiftUI on the hot path, no web views, no Node.
- **North star:** opens in under one frame, idles near 20 MB, never makes the
  user wait. Speed is the product.

## Build, test, run

```sh
./script/build_and_run.sh test        # swift test — SkilliCore unit tests
./script/build_and_run.sh build       # xcodegen + Debug build
./script/build_and_run.sh benchmark   # Release build + perf report + layout snapshots (dist/)
./script/build_and_run.sh selftest    # real app + event tap, driven end to end (dist/selftest.json)
./script/build_and_run.sh selftest ai # AI checks only: Keychain, Claude Code status, spare answers, sleep
./script/build_and_run.sh remote ai   # same self-tests on the Mac mini (SSH host `skilli-mini`): this Mac stays free
./script/build_and_run.sh remote models # writers only: Codex's and the OpenAI key's models, a real ChatGPT and OpenAI answer, the Model menus
./script/build_and_run.sh remote-app  # copy and open skil.li there, to grant its permissions once
./script/build_and_run.sh selftest clipboard # no keys: store, search, OCR (safe while the Mac is in use)
./script/build_and_run.sh run         # build + open
./script/build_and_run.sh restart     # quit gracefully, rebuild, reopen
./script/build_and_run.sh daily       # the developer's own skil.li: Release, dev traces kept (SKILLI_TRACE)
CONFIGURATION=Release ./script/build_and_run.sh remote speed # typing speed, key by key, as shipped
./script/build_and_run.sh --telemetry # open + stream os_log for the bundle
script/ai_bench.py                    # latency/tokens of the AI engines on the user's plans (spends tokens)
```

Persisted logs (hyper plan, tap state, transform timings) after the fact —
full path, because `log` is a zsh builtin:

```sh
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.nomdelasociete.Skilli"'
```

Compile-only check when you do not need the app running:

```sh
xcodegen generate --spec project.yml
xcodebuild -project Skilli.xcodeproj -scheme Skilli -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

- `project.yml` is the source of truth for `Skilli.xcodeproj`; regenerate after
  editing it, and commit both.
- `Package.swift` only covers `SkilliCore` + tests so `swift test` stays fast.
- `benchmark` needs no permissions: no event tap, no key remapping. Run it
  before and after any change to the launcher, search, or startup path, and
  report the numbers. It also writes `dist/launcher-light.png`,
  `launcher-settings-light.png`, `launcher-empty-light.png` and
  `leader-light.png`: layout previews with the glass approximated (off-screen
  captures cannot render Liquid Glass or the dark appearance). Plus
  `brand-menubar.png` (the menu bar S at 16/18/22 pt, light and dark) and
  `brand-appicon.png` (the icon as macOS masks it).
- `selftest` is the end-to-end check for anything keyboard-, selection- or
  launcher-related. It quits a running skil.li, launches the signed Debug build
  through `open` (so skil.li owns its Accessibility grant), drives it with
  hardware-like key events in a test window, a TextEdit document and a Safari
  textarea, then relaunches skil.li if it was running. It steals focus for
  ~25 s and aborts the moment focus is not where it expects, so synthetic keys
  never land in the user's apps. Needs Accessibility for the Debug build.
  It writes `dist/settings-<pane>.png`, captured from the window server
  (ScreenCaptureKit, own windows only: no Screen Recording permission).
- Do not launch the normal app from an agent unless asked: it installs a global
  event tap and may remap Caps Lock. The user launches from Xcode or `run`.

### Where tests run: the developer's Mac or the Mac mini

The keyboard self-tests take the keyboard, the focus and the screen for
minutes. **Never run them on the developer's Mac while the developer is using it**; run them on the
Mac mini, driven from here:

| Where | What | Command |
|---|---|---|
| This Mac, any time | Unit tests, builds | `./script/build_and_run.sh test` |
| This Mac, any time (no keys, no windows; restarts skil.li ~2 s) | Clipboard store, search, OCR; setup drawn off screen; live decisions (Ask, emoji, clipboard and files by meaning, nothing written) | `./script/build_and_run.sh selftest clipboard` / `selftest setup` / `selftest decide` |
| Mac mini | Everything with keys: launcher, shortcuts, Settings, Kill, clipboard paste, Ask, Commands, Claude, browser tabs, files seeded for Spotlight, sound output switched and put back | `./script/build_and_run.sh remote ai`, `remote settings`, `remote glass`, `remote browser`, `remote files`, `remote sound`, `remote projects`, `remote keyboard`, `remote scripts`, `remote history`, `remote brew`, `remote imports`, `remote roundtrip`, `remote card`, `remote control`, `remote sight`, `remote calc`, `remote handoff`, `remote mcpauth`, `remote toolrights`, `remote settingtools`, `remote windows`, `remote models`, `remote panes`, `remote catalog`, `remote rootsearch`, `remote dictation`, `remote snippets`, `remote shortcuts`, `remote settingsearch`, `remote meetingbar`, `remote previews`, `remote emoji`, `remote undo`, `remote chess`, `remote doit`, `remote apps`, `remote` (all) |

Nothing else that opens skil.li runs on the developer's Mac: `selftest` refuses other
scopes and `benchmark` refuses outright unless `SKILLI_LOCAL_UI=1` (a Mac
nobody is using); `remote-benchmark` runs the benchmark on the mini. Agents
started from a session are told so in their brief.

`remote <scope>` builds here, copies `Skilli.app` to `~/skilli-selftest` on
the SSH host `skilli-mini` (`SKILLI_REMOTE` for another), runs the
self-test there in the logged-in session (kept awake by `caffeinate`), and
brings `selftest.json` and the captures back to `dist/remote/`. About 5 min
for `ai`; this Mac stays free. Read the failures in `dist/remote/selftest.json`
and look at the PNGs there.

The test Mac is the SSH host in `SKILLI_REMOTE` (default `skilli-mini`,
an alias in your own `~/.ssh/config`). How it is set up stays out of this
repository. What the self-tests need from it:

- A logged-in session that stays awake: a locked screen swallows the
  synthetic keys and the self-test aborts; a sleeping Mac does not answer
  SSH. `remote …`, `remote-app` and `remote-benchmark` check this before
  building (`check_remote`) and stop at once (exit 2) when SSH does not
  answer, does not answer within 20 s, or the Mac is at the login window or
  locked: NSWorkspace's frontmost app is then `com.apple.loginwindow`
  (System Events' "frontmost process" names the app behind the lock: never
  use it). The check wakes the display first, since a sleeping display can
  show the login window too. `SKILLI_REMOTE_CHECK=0` skips it, for a host
  that cannot be asked this way.
- skil.li there (`./script/build_and_run.sh remote-app` copies and opens it
  normally, its setup window asks Accessibility; the rest from Settings →
  Privacy): Accessibility, Paste from Other Apps → Allow, Screen & System
  Audio Recording (+ → `~/skilli-selftest/Skilli.app`).
  Grants survive rebuilds (same signature). macOS asks again about once a
  month to "bypass the private window picker": Allow.
- For the live AI checks: the TypeSafe Jev and OpenAI Decisions keys in
  skil.li's Settings → SI Accounts on that Mac (its own Keychain; never in
  chat), and Claude Code signed in there (`claude`, then `/login`), kept up
  to date (`claude update`): an old Claude Code answers slower and may not
  call skil.li's MCP tools. Without them those checks are skipped, not
  failed.

Differences with the developer's Mac: no Raycast Hyper key in the way of the
self-test's own trigger (F19), macOS 26 menu titles ("Nouvelle fenêtre
Finder"), another Claude plan. A failure seen only on the mini is checked
for these before blaming the code.

### Signing and permissions

Debug builds sign with **Apple Development** (team `JSFMAD28GS`). Keep it that
way: macOS ties the Accessibility grant to the signature, and ad-hoc signing
makes every rebuild lose it. Permissions needed at runtime:

- **Accessibility** — event tap (`.defaultTap`), reading the selection via AX,
  posting synthetic ⌘C/⌘V/Escape. The only permission the first-launch
  setup asks for, with the user's SI (D7, 2026-10-17); every other one
  is asked where its feature first needs it, in place (`Permission.askedFrom`:
  macOS's own question there, or its list in System Settings once
  refused; Full Disk Access through Settings → Privacy). See Setup below.
- **Input Monitoring** — only if the tap still fails once Accessibility is
  granted.
- **Full Disk Access** (optional) — Safari's history. It cannot be asked
  for: Settings → Privacy opens its list, the user turns skil.li on.
  The pane then quits skil.li ("Quit & Reopen", a Quit AppleEvent from
  `SecurityPrivacyExtension`) and, on macOS 26, does not reopen it: in
  `applicationShouldTerminate`, a Quit whose sender is that pane or System
  Settings (`QuitSender`, by the sender's executable) leaves `Skilli
  relaunch <pid> <app>` behind (`Relaunch`), which waits for the process
  to end (a kqueue exit event) and opens the app. Any other Quit stays a
  quit. `selftest setup` drives the watcher on a scratch app.
- **Screen Recording** (optional, `Permission.screenRecording`; asked
  where do it here stops without it: its failure card's Allow Screen
  Recording ↩ when it would have read the screen, `ComputerControl.missedScreen`;
  Settings → Ask and Privacy too) — "do it here" reads the
  words a window shows where the app tells Accessibility little
  (`ScreenSight`: ScreenCaptureKit, then Vision's text recognition, on this
  Mac; the words go to the decision model, and pictures of that window
  to TypeSafe Jev when they say too little, to the writer (Claude) when a
  next step has to be worked out: see "do it here sees the window" and
  "clicks what it sees"; Settings → Privacy's "Thinking it through"). It
  takes effect after "Quit & Reopen", which `Relaunch` handles. `selftest` also captures the
  launcher and the leader overlay on screen. macOS asks twice: the Screen & System Audio
  Recording switch, then "bypass the system private window picker" → Allow.
  Without the second, windows are shareable but displays are not. If that
  prompt was dismissed, `tccutil reset ScreenCapture com.nomdelasociete.Skilli`
  (run by the user) brings both back.
- **Camera** (optional, `Permission.camera`, entitlement
  `com.apple.security.device.camera`, NSCameraUsageDescription) — asked
  only by the meeting card's Check Camera & Mic, the first time.
- **Bluetooth** (optional, `Permission.bluetooth`,
  NSBluetoothAlwaysUsageDescription; no Hardened Runtime entitlement
  exists for it) — read with `CBManager.authorization` (never a prompt);
  asked from the launcher's "Allow Bluetooth" row when typing about it
  ("bluetooth", "connecte…"; after the pane for "réglages bluetooth") or
  Ask, by starting a `CBCentralManager`.
  Nothing of IOBluetooth is called before it is granted.

The app is **not sandboxed** (event taps and AX are impossible in the App
Sandbox). Distribution is Developer ID + notarization + Sparkle, like `dsmn`,
never the Mac App Store.

### Releases

To release: the `release` skill (`.claude/skills/release`). What it runs,
`script/release/publish.sh` from a clean checkout of main (2026-10-18:
"distributed from our website and ideally from brew"). It runs on GitHub's
Macs (2026-10-19: not the developer's Mac, and the Mac mini is for other apps'
tests): `.github/workflows/release.yml`, started by hand (`gh workflow run
release.yml`), on the `xcode-27` runner (macOS 27, Xcode 27.1, free for a
public repository), in the `release` environment: the maintainer approves each run,
`main` only, and every credential is there (secrets `DEVELOPER_ID_P12` and
its password, `NOTARY_API_KEY`, `SPARKLE_ED_PRIVATE_KEY`,
`HOMEBREW_TAP_TOKEN`, `SKILLI_KLIPY_KEY`; variables `NOTARY_KEY_ID`,
`NOTARY_ISSUER_ID`, `SKILLI_SPARKLE_PUBLIC_ED_KEY`), put once by
`script/release/ci-secrets.sh`. The scripts read each credential from the
environment first, else from this Mac's login keychain as before (the
Klipy key aside: from the Mac's own `daily` skil.li, never the keychain),
so a release from a Mac still works. A pull request that touches the release
(the workflow, `script/release/`, `project.yml`, `Config/`) is built there
unsigned, its unit tests run.

1. `build.sh`: a Release archive signed with **Developer ID Application:
   NOM DE LA SOCIETE (JSFMAD28GS)** (manual signing, `Config/ExportOptions.plist`),
   universal, Hardened Runtime; the build number is the commit count + 900
   (`stamp_build.sh`); `SKILLI_UPDATE_FEED_URL` (https://skil.li/appcast.xml)
   and `SKILLI_SPARKLE_PUBLIC_ED_KEY` go in its Info.plist. Development
   builds leave both empty: no updater (`SoftwareUpdate.isConfigured`), no
   Check for Updates…, so they never replace themselves with a release.
2. `package.sh`: the app notarized (`notarytool`: an App Store Connect API
   key in GitHub Actions, else the keychain profile `dsmn-notary`: the same
   Apple team) and stapled; its zip (what Sparkle
   downloads) and a DMG with an Applications link, signed, notarized,
   stapled: `dist/release/files/skil.li-<version>-<build>.{zip,dmg}`.
3. `appcast.sh`: Sparkle's feed for the zip, signed with the EdDSA key
   (`SKILLI_SPARKLE_KEY_FILE` in GitHub Actions, else the login keychain's,
   account `nomdelasociete-skilli`, made once by `keys.sh`; public key
   `I+4nuoWKfHEjDRI6pOl/wO04kxCWkFSpzglqJMphf24=`).
4. A GitHub release `v<version>-<build>` of this repository (public,
   GPL-3.0, since 2026-10-18): the DMG and zip, plus `skil.li.dmg` and
   `appcast.xml` under stable names. The website's Caddy redirects `skil.li/download`
   and `skil.li/appcast.xml` to the latest release's, so the files can move
   without an app update.
5. The Homebrew cask `Casks/skilli.rb` in **nomdelasociete/homebrew-tap**
   (`script/release/skilli.rb.in`: version `<version>,<build>`, the DMG's
   sha256, `auto_updates`, macOS 26 or later, livecheck on the feed):
   `brew install --cask nomdelasociete/tap/skilli`. The official
   homebrew/cask list wants a notable project (around 75 stars): submit
   then.

A build number the feed already has is refused: commit, then release
again. Updates: Sparkle checks once a day and asks before installing
(`SoftwareUpdate`, status menu → Check for Updates…). A user moving from a
development build to the Developer ID one grants Accessibility again
(another signature).

This repository is public (GPL-3.0) and started over on 2026-10-18; the
work before it is in the private `nomdelasociete/skilli-history`. What
goes in stays public: test data uses invented people at invented
companies (Lumière, Horizon, Nimbus, Acme, `example` domains), and no
private endpoint, hostname or key ever lands in a commit.

## Architecture

```
SkilliMain (@main, accessory app)
  └── AppDelegate
        ├── HyperKeyRemapper      # Caps Lock → F-key plan (hidutil)
        ├── KeyRouter             # tap → Hyper state → chords → BindingEngine
        │     ├── EventTap        # CGEventTap on the main run loop
        │     ├── KeyboardLayout  # key code ⇄ character for the active layout
        │     └── LeaderOverlay   # which-key hints while a sequence is pending
        ├── ActionRunner          # SkilliAction → launcher / selection / URL
        │     └── SelectionService  # AX read, ⌘C fallback, ⌘V replace
        ├── LauncherController    # one glass block: search, then results; apps + commands
        ├── SettingsWindowController  # System Settings–style sidebar + panes
        ├── ShortcutStore         # shortcuts.json, validation, engine, recorder
        ├── LearningStore         # learning.json (QueryLearning)
        ├── Preferences           # @Observable, UserDefaults-backed, applied live
        └── AppIndex + UsageStore # app scan, fuzzy search, launch-count boost

SkilliCore (framework + SwiftPM library, no AppKit)
  ├── Chord / Key / Modifiers     # parsing "hyper+k u", Mac-style rendering
  ├── BindingEngine               # trie of chords, sequences, timeout
  ├── HyperKeyMachine             # hold = Hyper, tap = Escape
  ├── HyperKeyPlanner             # hidutil output → adopt / install / leave
  ├── FuzzyMatcher                # DP alignment, word-start + consecutive bonus
  ├── QueryLearning               # picks per typed text (+ prefixes), half-life
  └── TextTransform               # local transforms (AI presets later)
```

### Key files

| Path | Role |
|------|------|
| `Sources/Skilli/Input/KeyRouter.swift` | All key handling decisions; swallow/pass rules |
| `Sources/Skilli/Input/EventTap.swift` | Tap lifecycle, re-enable on timeout, synthetic-event bypass |
| `Sources/Skilli/Input/HyperKeyRemapper.swift` | Coexistence with other Hyper tools |
| `Sources/Skilli/Input/KeyBindings.swift` | `KeyBindings` (the command macOS's key bindings give a key), `LineEditor` (a line skil.li draws, edited as a text field) |
| `Sources/Skilli/Launcher/LauncherController.swift` | Launcher UI and show path |
| `Sources/Skilli/Design/Theme.swift` | Radii, type, semantic colors, brand images, `KeycapView`, `HintBar` |
| `Sources/Skilli/Resources/Assets.xcassets` | App icon, menu bar template, brand mark, glass S, accent color |
| `Sources/SkilliCore/LauncherCommand.swift` | Built-in launcher commands (Settings, Quit, Kill a Process, Clipboard History); the rows (`LauncherItem`) stay in `Sources/Skilli/Launcher/LauncherCommand.swift` |
| `Sources/SkilliCore/FeatureCatalog.swift`, `LauncherPrefix.swift` | The Catalog ("?"): everything skil.li does, one list; the modes' prefixes, read by the launcher and the Catalog |
| `Sources/Skilli/Settings/CatalogPane.swift`, `Sources/Skilli/Launcher/CatalogReach.swift` | Settings → Catalog on the same list (search, alias, shortcut, On); an entry's shortcut action, shared with the "?" |
| `Sources/Skilli/Snippets/*` | `SnippetLibrary` (Markdown files), `SnippetExpander` (keywords as you type, insert at the caret) |
| `Sources/Skilli/Clipboard/*` | `ClipboardStore` (SQLite FTS5 + images and link previews folders), `ClipboardHistory` (watch, keep, OCR, paste back), `ClipboardLinks` (link previews: the request, the cache) |
| `Sources/Skilli/Settings/*` | Settings window, SwiftUI panes, `Preferences`, login item |
| `Sources/Skilli/Shortcuts/*` | `ShortcutConfig` (defaults, JSON), `ShortcutStore` (edit, validate, record) |
| `Sources/Skilli/AI/*` | `AIStore` (status, engine choice, tests, spare, sleep), `ClaudeCLI` (find, status, sign-in), `ClaudeSubscriptionEngine` + `ClaudeSession` (spare process), `ClaudeAPIEngine` (SSE), `CodexEngine` (ChatGPT through `codex exec`), `OpenAIEngine` (Responses API), `Keychain`, `PromptLibrary` (commands as files, About You), `AIActionController` + `AIPopover` + `QuestionView` (commands on the selection, questions in the card, Act steps and approvals), `AgentRun` (Claude Code for Act commands), `DecisionClient` (OpenAI Decisions, TypeSafe Jev) |
| `Sources/Skilli/Tools/*` | `MCPSocketServer` + `MCPBridge` (`Skilli mcp`, `Skilli call`), `MCPService` (MCP, approvals), `SkilliTools` (tools, menus through Accessibility), `ToolSettings` (`tools.json`), `SettingTools` (skil.li's own settings for agents) |
| `Sources/Skilli/Settings/AICommandsViews.swift`, `PromptEditor.swift`, `ModelPicker.swift`, `ToolsViews.swift` | Commands pane, command editor (questions, output, tools, model), prompt field with variable completion, the Model menu (editor and Settings → SI Accounts), Tools pane |
| `Sources/Skilli/Apps/LearningStore.swift` | Persists what the launcher learned |
| `Sources/Skilli/Apps/AppIndex.swift` | Scan roots, icon cache, search |
| `Sources/Skilli/Selection/SelectionService.swift` | Selection read/replace, clipboard restore |
| `Sources/Skilli/Actions/DefaultBindings.swift` | Built-in bindings (until user config) |
| `Sources/Skilli/Support/Benchmark.swift` | `--benchmark` report |
| `Sources/Skilli/Support/SelfTest.swift` | `--selftest` end-to-end driver |
| `Sources/Skilli/App/UndoableDeletes.swift` | Every delete of the user's data: at once, Undo ⌘Z for 10 s in the card (`offerUndo`) |
| `Sources/SkilliCore/*` | Pure logic, unit-tested |

## Invariants (do not break)

### Speed

Budgets, checked with `./script/build_and_run.sh remote-benchmark` (Release,
on the Mac mini, its lock taken; the benchmark shows the launcher again and
again, so `benchmark` on this Mac refuses unless `SKILLI_LOCAL_UI=1` on a Mac
nobody is using — it flashed on a developer's screen, 2026-10-16):

| Path | Budget | Last measured |
|------|--------|---------------|
| Show launcher (warm) | < 10 ms median, < 16 ms p95 | 6.9–7.2 ms / 10–11 ms (mini) |
| Keystroke → list redrawn | < 2 ms median | 0.65–0.69 ms, p95 2.1–2.2 ms (mini) |
| Keystroke, real sources + 3200 contacts (`remote speed`, Release) | < 2 ms median, < 8 ms p95 | 1.1–1.2 ms / 3.0–3.3 ms; first key after opening 3.0 ms (mini) |
| Key typed in the card (inside the event tap) | < 2 ms p95 | 0.24 ms / 0.35 ms (mini) |
| Search, 171 apps | < 0.5 ms worst query | 0.003–0.41 ms (mini) |
| Selection replaced after trigger (AX read) | < 10 ms | 1–4 ms (selftest) |
| Memory idle / after use | < 25 MB / < 40 MB | 24.3–24.6 MB / 27.8–27.9 MB (mini) |

"(mini)": measured 2026-10-16 on the Mac mini, three runs each of
`remote-benchmark` and `remote speed`, interleaved with main (a4af3f8:
1.4–1.5 ms / 3.8–4.1 ms a key, 26.4–26.7 MB idle / 34 MB after). The
older numbers were the developer's Mac's (M-series), where the same build reads
about 1.2 MB more memory (main: 27.6 MB there); the mini's typing times
move with its load (same build: 1.7 ms / 4.9 ms a busy hour earlier):
compare like for like, a build against main in the same hour.

Most of "show" is the window server ordering the glass panel in (~7.5 ms);
the plain-vibrancy panel took ~2 ms. Keep the glass, but do not add more
per-show work.

- The launcher panel is built once and kept off screen; showing it is
  reposition + order front. Never rebuild views or allocate per show.
- Fixed frames in the launcher: no Auto Layout pass on show.
- Icons are downscaled into small bitmaps and cached; never keep the full
  `NSWorkspace` icon (it holds large representations).
- Heavy work (scans, network, AI) runs off the main thread. The event tap
  callback only decides and returns; actions are dispatched with `Task`.
  Exception: opening the launcher runs inline (`SkilliAction.runsInline`).
- While the launcher is visible, the router hands every unbound key straight
  to its search field editor (`LauncherController.deliver`). The launcher
  opens from a hotkey our tap consumed, so macOS may leave keyboard focus on
  the previous app; typing must never depend on window-server focus. A click
  in another app closes the launcher.
- Nothing on a keystroke reads a file, asks TCC or CoreAudio, or prepares
  names for matching: the launcher's other sources are read once per show
  (`LauncherController.Catalog`), sound devices are kept until CoreAudio
  says they changed, contacts are indexed once (`ContactSearch.Index`).
  The permissions shown first are read once per show, and only those the
  rows can show (`PermissionCenter.refreshAttention`); a mode's words
  ("rappelle-moi", "réunion") are checked before Reminders' or Calendar's
  access. The self-test does not set `missingPermissions` and keeps
  Calendar and Reminders off the Mac: `remote speed` cannot see a TCC call
  slipped onto a key, so read the code.
- Typed on, a key looks only at the catalog entries the key before let
  through (`SearchNarrowing`): a row that does not hold "saf" in order
  cannot match "safa". A source of many long phrases (System Settings'
  sections) scored whole on every key is what #137 cost (catalog step
  90 → 420–550 µs a key on the mini).
- Rows are filled in place (`showRows`); `reloadData` on a keystroke threw
  every row view away and built them again (most of a key's time).
- A key typed in the card is handled inside the event tap: it only updates
  the answer line (`AIPopover.ask` fast path), never lays the card out again.
  Its caret keys too (`LineEditor`, measured on the mini in Release: median
  0.6 ms a key, p95 0.7 ms, bound 2 ms).
- Extensions, when they come, run out of process and are started on demand.
  Their memory must never count against the core app.
- Idle memory: nothing that only shows later is made at launch (the
  meeting alert card, the display prompt: made the first time they show;
  Calendar's and Reminders' `EKEventStore`s: made when first used), and a
  permission is read only where it shows (setup, Settings): each is asked
  through its own framework (AVFoundation, EventKit, Contacts…), which
  stays in memory once asked (~0.5–1 MB each; Contacts' was the #73 step,
  +1.2 MB).

### Design

- Liquid Glass surfaces only through `Theme.glass(cornerRadius:content:)`.
- Every glass window keeps `Theme.glassMargin` of clear space around its
  glass: Liquid Glass draws a shadow past its shape, and a window cut to the
  shape clips it into square corners and dark bands. `selftest glass`
  captures both glass windows on screen over dark, light and photo backdrops
  in both appearances, fails on any edge step, and saves
  `dist/glass-*.png` to look at; `benchmark` reports `glassEdgeAlpha`.
- Bitmaps drawn by hand (`NSBitmapImageRep` + `NSGraphicsContext`): set the
  rep's `size` in points **before** creating the context, or drawing is 1:1
  in pixels and fills a quarter of a Retina bitmap (app icons once did;
  `selftest` checks "App icons fill their size").
- The launcher is one glass block (search on top, hairline, results). Two
  shapes with a gap showed the background and the shadow between them.
- The launcher opens where the user dragged it: a click on its glass that
  no control takes starts skil.li's own drag (`LauncherMargin` →
  `LauncherController.drag`, `trackEvents`; `performDrag` cannot be
  pulled); a click in the clear margin still closes it. Within 8 pt of the
  screen's middles or the standard height the glass is pulled onto them
  (`LauncherPlace.snap`): a one-point accent guide fades in on each, in a
  window the size of the line (`LauncherGuides`; never a full-screen
  window and its backing store), with the trackpad's alignment haptic.
  The place is kept as fractions of the free space around the glass
  (`LauncherPlace`, `Preferences.launcherPlace`): centered stays centered,
  a corner stays a corner on every screen (the screen is Settings →
  Launcher → Opens on's: the pointer's by default); dropped on both
  standard guides, no place is kept. "Reset Launcher Position" and Settings →
  Launcher put it back. The AI card's resting place follows it.
  `selftest settings` drags it with real mouse events.
- Concentric radii from `Theme.Radius`: launcher block and cards 26,
  selection 14, keycaps 6.
- Semantic colors only (`labelColor`, `secondaryLabelColor`, `Theme.*` tints
  derived from them): they stay vibrant on glass in light and dark.
- Selection is a soft capsule (`Theme.selectionFill`), never the classic
  blue highlight; text keeps its label color.
- Keyboard affordances are drawn as `KeycapView`s; no debug numbers in the UI
  (perf lives in logs and the benchmark).

### Brand

- **The name is skil.li**, lowercase with its dot, wherever a person reads
  it, a sentence's start included: the app's menus, Finder, the Dock,
  permission lists, the DMG and its window, downloaded files, release
  titles, the website, docs, commits' user-facing text (2026-10-18:
  "Skil.li, skilli, skil.li… c'est quoi ce laisser-aller ?"). `Skilli` /
  `skilli` only where a dot cannot go and nobody reads it: the bundle ID,
  the module, `Skilli.app`'s file and executable, the repository, the cask
  token. macOS shows `en.lproj/InfoPlist.strings`'s name; the generated
  CFBundleName and CFBundleDisplayName stay `Skilli`, the file's name,
  which Finder requires before it shows the localized one
  (`LSHasLocalizedDisplayName`).
- **SI is the word for AI** (2026-10-13, `docs/website-design.md`):
  every user-facing "AI" says SI ("SI Accounts", "SI Command", "SI · Fix
  Spelling & Grammar", "Sent to your SI"), and pointing at it reveals
  "AI" in place, as the website's `si-label.js` does. `Brand.intelligence`,
  `SIText` (SwiftUI) and `SIRevealLabel` (AppKit) in
  `Sources/Skilli/Design/SILabel.swift`. Never rename, remove or question
  it; pane names by job (Ask, Commands, Tools) are the maintainer's and stay.
- Source of truth: `assets/brand/` (Halo menthe, glass S) and its README.
  The app uses static exports in `Sources/Skilli/Resources/Assets.xcassets`;
  no WebView, shader or animated mark anywhere in the app. One exception,
  asked on 2026-10-13: the S at the top of Settings → General turns
  toward the pointer (below); a 3D transform on the static PNG, never a
  loop, a light sweep or a 3D engine.
- `AppIcon`: `Sources/Skilli/Resources/AppIcon.icon` (Icon Composer, 2026-10-18):
  the S and the dot from `menu-template.svg` as two glass layers on a petrol
  gradient, a mint S in dark mode. The system adds mask, shadow and glass; never
  bake them in. Check the Default, Dark, Tinted and Clear renders and 16/32 px
  with `ictool` (command in `assets/brand/README.md`) before changing it.
- `BrandMark`: sizes from `3d/skilli-logo-3d.png` (the 3D v4, retained
  2026-10-12) with `sips -z`.
- `MenuBarIcon`: `menu-template.svg`, vector, template rendering; load it via
  `Theme.brandTemplate(size:)` (18 pt in the menu bar). The system tints it;
  no color, gradient or glass in it. Check `brand-menubar.png` after any
  change: the dot and the fold openings must survive at 16 pt.
- `BrandMark` (the glass S on its halo, 256/512 px): About, the launcher's
  skil.li Settings row. Never put text over its luminous areas. Not below
  ~60 pt: at the sidebar's 30 pt the S could not be read (removed
  2026-10-13).
- `BrandGlassHalo`: `3d/skilli-mark-halo@2x.png` (the glass S with the halo
  refracted in it, transparent around) at 120 × 117 and 240 × 235 px with
  `sips -z`: the top of Settings → General, 96 pt (`BrandHeader`,
  `GlassMark`). Teal, so it reads on light and dark; the clear
  `skilli-mark.png` washes out there. It turns toward the pointer anywhere
  over the pane like the site's hero (±10° across, ±6° up and down, eased
  0.6 s), lies flat when the pointer leaves, and stays flat with Reduce
  Motion. `selftest settings` moves the pointer and checks it
  (`settings-general-tilt.png`).
- `BrandGlass`: `3d/skilli-mark.png` (the glass S and its sphere,
  transparent, no halo, no tile) at 28 × 27 and 56 × 55 px with `sips -z`:
  the launcher's search bar, in place of a magnifier (`Theme.brandGlass`).
  Never on a tile or a squircle there.
- `AccentColor` (mint) drives selection, toggles and focus. Keep white text on
  it at 3:1 or better in both appearances; a user-chosen accent overrides it.

### Settings

- Three entry points, all covered by `selftest` (also with another app in
  front): status menu “Settings…”, typing “settings” in the launcher, ⌘,
  while the launcher is open. `selftest settings` runs just these.
- Layout follows System Settings: glass sidebar of tinted `IconTile`s, one
  pane per row, each pane a grouped form under a centered `PaneHeader`.
- A pane reads the preferences it shows in its `body` (not only inside a
  `Binding`'s get): agents change settings through tools and the menu bar
  can too, while the pane is open; a value read only in a closure is not
  observed and the control stays stale (Skillies' "In the menu bar" did).
  General, the first pane, opens on skil.li's glass S and name instead
  (`BrandHeader`); nothing above the sidebar's rows.
- Panes are named by what they do for the user, never by engineering names
  (no "SI", "MCP" in a title; such words only in help text). Caps Lock held
  is the **Hyper Key** (✦), the name Mac users know (Raycast, Karabiner,
  Hyperkey), in the app, docs and site; never "Super Key", the Windows key
  on Linux and Windows (2026-10-17: "it's hyper key and not super key"). The
  sidebar is five blocks split by a gap, no headers (`SettingsPane.blocks`,
  2026-10-15): General, Keys, Privacy, Backup · Launcher, Clipboard,
  Snippets, Emoji, Windows · Calendar, Reminders, GitHub, Your Details · Ask,
  Commands, Tools, Skillies, SI Accounts · Catalog, About. Keys holds Caps Lock as
  the Hyper Key (✦) and every shortcut; General the launcher's keys, how
  skil.li looks (glass) and the launcher's place on the screen; Launcher its shortcuts, search
  by meaning with ⇥ (pages, files) and what that sends, then under
  Advanced the screen it opens on, when it starts again empty and Type in
  English while open; Skillies how one runs (its name, then ↩), its folder
  and what leaves the Mac, then the list; Ask its keys,
  approvals and the user's rules (When It Acts),
  Keep Claude ready, voice, Continue in, Skills, On a Schedule; SI Accounts the default model and
  every account and key; Your Details the forms' details and About You.
  Ask and SI Accounts follow the twelve rules: Ask's first rows are how it is reached (✦A, ✦V recorders, ⇥ in
  the launcher as a keycap), then When It Acts; Keep Claude ready, Voice
  language, Continue in, Terminal and Skills under Advanced, On a Schedule
  last (its list). SI Accounts: Writing
  (the default model, then the account that model needs, its key field
  included), Choosing (TypeSafe Jev's key, else the OpenAI key's), then
  under Advanced "Pay for Claude with" (`aiEngineMode`) and every other
  account. Tools: how its tools are reached (Ask's keys, Copy Command
  for other agents), Help Me Choose, When they ask (→ Ask), what leaves
  the Mac, then Connected Servers and skil.li Tools by group, Your Tools
  and the bridge's command under Advanced. Commands: how one is reached
  (✦K then its key, its name in the launcher), what leaves the Mac, Your
  Commands then Built In, Import and the files under Advanced. A missing
  permission (Microphone, Screen Recording) shows beside
  the feature that needs it, only while not granted (`PermissionRow`).
  General, Keys, Backup, GitHub and Your Details follow them too (the
  panes audit, 2026-10-15). A feature pane's first row is how it is
  reached, read-only keycaps lined up with the recorders (`ReachRow`,
  Ask's "⇥" pattern): GitHub "pr" and its alias, Back Up skil.li Now's
  alias, Ask's ✦A in Your Details; Keys draws ⇪ → ✦. The launcher's keys
  are the first row of General and of Launcher (2026-10-16: "the
  most important command … should not be buried"), and the first of Keys'
  shortcuts list, under its name (asked: "why put the open skil.li again in
  the keys section": never a second block above the Hyper Key): one entry
  of the store, `launcherEntry`, "Open skil.li", never a copy. General: Open skil.li, Set Up
  skil.li… only while Accessibility is off (D7), Open at
  login (macOS's OK beside it while it waits: Open Settings,
  `SMAppService.openSystemSettingsLoginItems`), Show in menu bar, Glass;
  Launcher position under Advanced. Keys: the Hyper Key and its state
  (Accessibility, else Input Monitoring, beside it while missing), Tap
  Caps Lock alone under Advanced, then every shortcut by how it is typed,
  Open skil.li first ("Shortcuts", "✦K, then a key", "Windows: ✦W, then a key"; the ✦K
  group's stored name, "Leader", is never shown). Backup: Back up to, How
  often, Keep, Back Up Now, where backups go, then the backups. GitHub:
  the account and Last read, the strip and its preview, what leaves, then
  Live updates from (the relay: "relay" only in Advanced's help) and its
  token under Advanced. Your Details: the card (Contacts in its place
  while missing), your other details, About You, what leaves, then the
  people and what forms get from the card.
  Clipboard and Snippets too: Clipboard's first rows are ✦C, Paste in
  Sequence's ✦K V and "cb" as a keycap, then Keep clipboard history (Paste
  from Other Apps only while missing), Keep screenshots too and its
  folder; Keep copies for with Clear History (a change never deletes on
  the spot: the line under it says what the hourly pass removes); what
  leaves this Mac; under Advanced search by meaning, Show link previews,
  Read text in images, the two "by what they show", the apps never kept.
  Snippets: "snip" as a keycap, Expand keywords
  as you type, Expand (when) and its preview, Find snippets by meaning;
  what leaves; the snippets; under Advanced the apps where keywords stay
  as typed.
  The selected pane is not saved: nothing maps old pane names.
- Each pane opens with one sentence in the user's words (its subtitle):
  what it does for them, not how it works.
- What most people never change goes last, under Advanced, closed each
  time the pane opens (`AdvancedSection`: a native `DisclosureGroup` whose
  label lists what is inside; open, the rows follow it in the same group,
  each with its separator: inside a `DisclosureGroup` a grouped form drops
  them and the rows run together). Never hide there what a chosen option
  needs to work (a provider's key stays beside the provider). Advanced
  closes the settings: a long list follows it (Keys' shortcuts). `selftest
  settings` opens it (`Advanced.startsOpen`) to capture it and check the
  pane still fits.
- A pane whose features send anything off the Mac says so in one line,
  with whom (`LeavesMacRow`, built by `PrivacyMap.line(for:)` from the
  same rows as Settings → Privacy), and links to Privacy (or to SI
  Accounts when nothing can write yet): Ask, SI Accounts, Commands,
  Tools, Windows (its "Nothing: …" line), GitHub (the
  sign-in with each read, the relay's token), Your Details (forms typed on
  this Mac, the chooser reads only what fields ask, else forms wait for a
  key: SI Accounts; who gets About You).
  Backup says where backups go and who syncs that folder
  (`BackupPlan.syncService`, else macOS's `isUbiquitousItem`): skil.li
  sends nothing itself. Nothing leaves from General or Keys: no line.
- In a pane, the settings first and long lists last (calendars, places,
  tools), grouped by their owner (account, server).
- An option that changes what the user sees has a live preview beside it,
  drawn by the same code as the real thing from sample data
  (`SettingsPreviews.swift`): the meeting in the menu bar at its moments
  (coming, started and not joined, joined, the next beside it), each in
  a `MenuBarMock` whose clock tells the moment (`MeetingBar.plan` +
  `MeetingWatch.appearance`), today's reminders
  (`ReminderWatch.appearance`), the GitHub strip (`GitHubStripView`).
  Never a hand-written copy of a format. `selftest settings` snapshots
  them.
  SwiftUI is allowed here (not on the launcher hot path). The window is built
  on open and released on close.
- Settings → About: the version (`MARKETING_VERSION`, by hand), the build
  (the commit count + 900: the public repository started over after the
  private history's build 660, and again after build 815), the commit and when it was built
  (`script/stamp_build.sh`, a post-build phase before signing; a "+" after
  the commit: changes not committed were built), then one health line per
  feature (`Health`) and Copy Diagnostics, which carries the same.
- skil.li windows come forward with `Foreground.bring`: cooperative
  activation lets the frontmost app refuse, so it falls back to
  Accessibility. Launcher commands run before the launcher hides, or the
  panel hands focus back to the previous app.
- Settings → Privacy (`PrivacyPane`): each permission (`Permission`;
  Input Monitoring only there) with what it turns on (`turnsOn`), its
  state live and its one button; the apps skil.li scripts
  (`AutomationAccess`: System Events, Finder, Calendar, Mail, and the
  default browser while Reuse an open tab is on, read with
  `AEDeterminePermissionToAutomateTarget`, never a prompt; macOS answers
  only while the app is open); then What Leaves This Mac: `PrivacyMap`
  (SkilliCore), one `Flow` per feature that sends anything off the Mac
  (what, when, the pane where its switch or account lives), placed by
  `sections(for:)` under where it goes today (Claude, ChatGPT, OpenAI API,
  TypeSafe Jev, GitHub, your servers and agents, Apple) from what is set
  up (`AIStore.writer(for:)` per command, the keys, the switches). A
  feature that sends anything off the Mac adds its flow there, written
  from the code that sends it. The pane repeats no setting: a row links to
  the pane where its switch lives.
- Only settings that do something. No placeholder controls for features that
  do not exist yet; say so in a section footer instead.
- Every preference applies live through `Preferences.onChange`.
- How a pane's feature is reached (rule 2): `PaneReach` under the header,
  each Catalog entry's prefix and alias as keycaps, as "?" shows them.
  Settings → Calendar and Reminders follow the rules (2026-10-15) with the
  shared `AdvancedSection`, `LeavesMacRow` (`PrivacyMap.line(for:)`:
  Calendar "nothing leaves", Reminders Apple Maps for places, Windows Auto
  Quit's deciding key) and `PermissionRow`: Calendar shows the menu bar,
  the alerts and When a meeting starts first, the rest under Advanced.
- Every setting has a tool (rule 11): anything a pane sets, an agent sets
  through skil.li's tools under the same name, after the user's OK in the
  card. `SettingsTable` (SkilliCore) is the one table: each setting a pane
  shows, by pane id, its key (the `Preferences` property when it is one),
  its name as the pane shows it, its type and values, and the tools that
  change it. `SettingTools` binds each key to what the pane changes (the
  same property or store, so `didSet` and `onChange` run and an open pane
  shows it). Tools (group `settings`, "skil.li Settings"): `get_settings`
  (JSON by pane, built by `SettingsReport`: settings readable; keys,
  tokens, Keychain fields and the user's own content (`personal`: About
  You "set (12 words)", Your Details' values and people, snippets' text,
  places' and quicklinks' addresses) only "set" / "not set"; a read, no
  card), `set_setting` (pane, setting, value; a list: `change` add or
  remove), `set_alias` / `remove_alias`, `create_` / `update_` /
  `delete_quicklink` and `_snippet`, `add_` / `change_` /
  `remove_shortcut` (keys as said: `hyper+y`, `✦K then Y`; the store's
  rules). A change is checked before the card (a refusal names what is
  valid), the card says it in the pane's words ("Backup: How often →
  Every week"), Esc changes nothing. Every change asks every time
  (`ToolSettings.asksEveryTime`, `ToolPolicy` `everyTime`): no Always in
  its card, no "always allow" right or Always Allow mode makes it silent
  (a setting can turn on something that sends data out); only Block
  applies. What the agent reads back never holds the user's own content
  (the card may, for the user). Never
  through tools: API keys and sign-ins, Keychain fields, permissions, tool
  rights, the approval mode, servers and the user's own tools, the relay
  address (it says where a token goes). A new preference without an entry
  fails `swift test` (`SettingsTableTests` reads `Preferences.swift`) and
  `selftest settingtools`. The skill that ships with the app
  (`SettingsSkill`) is a resource (`skilli://skills/set-up-skilli.md`) and
  a prompt (`set-up-skilli`) of skil.li's MCP server, named in its
  instructions; nothing is written in the agents' own folders.
- Search (2026-10-16: "it's becoming quite packed"): a native search
  field atop the sidebar, as System Settings has (`SettingsSidebar`,
  `SettingsSearchField`); ⌘F takes it and a letter typed while the
  sidebar's list has the keys goes into it (`SettingsWindow`).
  `SettingsSearch` (SkilliCore) finds each pane by its title, then its one
  line; each `SettingsTable` setting by its name as the pane shows it;
  `SettingsSearch.rows` (section headers no setting is named after, and
  Back Up Now, Clear History, Copy Diagnostics, Add Shortcut); each
  shortcut (Keys) and permission (Privacy) by its name; and every Catalog
  entry (`SettingsSearch.entries`: what skil.li does and what the user
  made — commands, snippets, skillies, quicklinks, layouts) by its title,
  then its one line and the words people type for it, opening Catalog at
  its row (2026-10-16: "emoji" found nothing). Case and accents
  ignored; the words typed start words of the name, in any order
  ("skil.li" is also "skilli", SI also "ai"), then the pane's line, then
  inside a word (3 letters or more); no synonyms. Built when a search
  starts (the Catalog as it is then) and again when the shortcuts change; a keystroke takes ~0.3 ms (budget 5 ms,
  `SettingsSearchTests`). While it holds text the sidebar lists the panes
  that match, best first, each with its rows indented under it; the best
  row is selected, ↑↓ (⌃P ⌃N) move, ↩ or a click opens, "No Results for
  “…”" when nothing matches, esc gives the panes back. Opening a row: its
  pane, Advanced opened when the row is under it, the row scrolled to the
  middle and glowing about a second in the accent color. A row shown only
  while another setting is on leads to that setting
  (`SettingsSearch.shownWith`). Every setting and row carries
  `.settingAnchor("<key>")` in its pane, the key written as a literal:
  `swift test` fails when one is missing; a row under Advanced is also in
  that section's `anchors:`. `selftest settingsearch` (also in `settings`)
  types with real keys and opens every setting, section, permission and
  shortcut, checking each lands in sight.

### Shortcuts

- Every global shortcut lives in `ShortcutConfig` and is editable; nothing is
  hard-coded in the router. Actions have readable ids (`launcher.toggle`,
  `text.uppercase`, `url:…`, `app:/path`) so `shortcuts.json` stays editable
  by hand. Defaults keep stable entry ids so “Reset to Default” works.
- Validation: the first chord needs ✦, ⌘, ⌃ or ⌥ (plain keys would eat
  normal typing); no shortcut may equal or prefix another. Hand-edited
  conflicts are skipped and reported in Settings, never crash.
- Recording takes keys from the event tap (`KeyRouter.recordHandler`), not
  from the window: other apps' global hotkeys (e.g. Raycast's ✦K) fire before
  window delivery and would never reach a recorder.
- Any command takes a direct shortcut (✦G) or a chain (✦K then G), and can
  have several (one entry each; Add Shortcut). Every shortcut field has a
  visible ⓧ (`ShortcutStore.clear`): an extra shortcut goes with its row, the
  last one is emptied. Recording waits
  `ShortcutStore.sequencePause` for the next key of a chain, shown as a
  countdown; Return saves at once.
- Keys → Restore Defaults asks first and names what goes
  (`RestoreDefaults` in SkilliCore, `ShortcutStore.changesFromDefaults`:
  "Your 3 custom shortcuts and 2 changed keys are removed.", destructive
  Restore Defaults, Cancel); off while nothing differs from the defaults
  (order alone is no change). `selftest settings`
  (`restoreDefaultShortcuts`) presses it, Cancel, then Restore Defaults;
  `settings-keys-restore-*.png` (the dialog).
- Inside a chain, what is still held from its first chord does not count,
  nor Hyper (`Chord.inChain`, `Chord.chain` in SkilliCore): ✦K then ✦Y
  (Caps Lock kept down) is `hyper+k y`, ⌘Space then ⌘Space (⌘ kept down)
  is `cmd+space space`, the same shortcut as with ⌘ let go (asked
  2026-10-16: the same key several times). The engine (`handle`, `bind`),
  the recorder and `ShortcutStore.validated` apply it; files saved before
  are repaired on load (`ShortcutConfig.normalizingChains`). So a modifier
  of the first chord cannot tell two later chords apart (`cmd+k cmd+u` is
  `cmd+k u`). A binding is never both an action and the start of a chain
  (no waiting to tell them apart: it would slow the launcher). Test chains
  the way people type them: Hyper held for every key.
- No two actions on one shortcut (2026-10-16). `ShortcutStore.validated`
  is the one check (recorder, Settings' fields, Catalog, ⌘K Set Shortcut…,
  the settings tools): refused when the keys equal or start another of
  skil.li's shortcuts, or when their first key belongs to a `KeyOwner`
  (SkilliCore): the launcher's own keys while open (`LauncherKeys`: ⌘K
  Actions, ⌘↩, ⌘C, ⇧⌘C, ⌘⌫, ⌃N, ⌃P, ⌘W, ⌘X/V/A/Z, and its Open Settings
  key), since the bindings run before the launcher; or macOS's shortcuts
  on now (`SystemShortcuts`: `com.apple.symbolichotkeys`
  `AppleSymbolicHotKeys` read afresh each time, named and defaulted from
  macOS's own `DefaultShortcutsTable.xml`, plus ⌘Tab, ⌥⌘Esc, ⌃⌘Q, ⇧⌘Q,
  ⌃⌘Space). One kept with a character is that character's key ("m" for
  Minimize, not key code 46, which types "," on French), else its key
  code on the layout; F-keys and 🌐 ones cannot be skil.li's. The refusal
  names the owner and where to turn it off ("Used by macOS: Show
  Spotlight search. Turn it off in System Settings → Keyboard → Keyboard
  Shortcuts… → Spotlight."), with Open Keyboard Settings under the row.
  skil.li changes no macOS setting but one (Spotlight's ⌘Space, below).
  Open Settings (launcher only) is
  refused on a key a shortcut starts with. Measured on the mini
  (2026-10-16): the session tap gets a macOS shortcut before macOS does;
  bound in skil.li, macOS's action never runs (⌥⌘Space: Finder's search
  window stays closed). So a shortcut read from a file that shares keys
  stays bound and Settings says it in orange (`ShortcutStore.warnings`,
  re-read as General, Keys and Launcher appear: freed in System Settings,
  it is no longer said). Other apps' global hotkeys cannot be read.
- Two exceptions, an action that does the same thing as macOS's
  (`KeyOwner.replacedBy`): ⌃⌘Space, each app's Edit → Emoji & Symbols,
  is Search Emoji's by default (`SkilliAction.searchEmoji`, entry
  "emoji", the launcher straight in the picker; again closes it), as
  Raycast takes it (2026-10-16); and Spotlight's ⌘Space may be the
  launcher's (`SystemShortcuts.launcher`, recommended by the welcome, asked
  2026-10-18/19: "Raycast was able to override Spotlight's ⌘Space during
  the setup… that is exactly what I asked"). Once the launcher has ⌘Space,
  from anywhere (welcome, Settings → Keys, a setting tool), skil.li turns
  Spotlight's own ⌘Space off in macOS (`SpotlightKey`: entry 64 of
  `com.apple.symbolichotkeys`, `activateSettings -u` so it applies at
  once; normal mode only), and on again when the launcher leaves ⌘Space,
  only if skil.li turned it off (`SpotlightKey.turnedOff`).
  Kept for those actions only, refused for any other; Settings says
  "Replaces macOS's Emoji & Symbols." / "… Show Spotlight search." in
  grey (`Warning.isNote`), not a warning. Search Emoji's Catalog row
  records it too (`CatalogEntry.shortcutAction`).
- The status menu's Open skil.li says the launcher's real keys on the
  right (✦, a chain as "⌘ Space › Space"), read when they change and as
  it opens, nothing without keys; Settings… and Quit draw theirs the same
  way so all line up (`StatusMenuKeys`: one right tab stop), a hidden twin
  keeps ⌘, and ⌘Q working while it is open.
- `selftest shortcuts` (keys): the chain tests, ⌥⌘Space against the tap,
  ⌃⌘Space opening skil.li's picker and typing ❤️ (refused for another
  action, `settings-keys-emoji-*`), ⌘Space Space held and let go, Spotlight's ⌘Space refused (its reader
  swapped: `readSystemHotKeys`), the launcher's keys refused, the launcher
  in General, Keys, Launcher and the status menu (real click, light, dark,
  highlighted, a chain); `settings-general-*`, `settings-keys-*`,
  `settings-keys-refused-by-macos-*`, `settings-general-shares-with-macos-*`,
  `settings-launcher-*`, `status-menu-*.png`.
- `selftest` and `benchmark` use scratch/in-memory stores: never touch the
  user's `shortcuts.json` or `learning.json`.

### Learning

- `QueryLearning` records the typed text and its prefixes (half weight) for
  the picked item; bonus is logarithmic and fades with a 30-day half-life.
  Learned picks surface even when the text does not fuzzy-match.
- Items are keyed `app:<path>` / `cmd:<id>`; learning stays on the Mac.

### Launcher actions (⌘K)

- ⌘K opens the selected row's actions over the results, bottom right
  (`ActionPanelView`); the catalogue for every kind of row is
  `LauncherController.actions(for:)` in `LauncherActions.swift`. Built from
  what the row holds, nothing fetched: it must open at once.
- Few actions, the likely ones first, in three groups split by a hairline:
  doing, copying, removing (red). A new kind of row gets its list there;
  never more than a contact's (about ten).
- One key, one meaning, everywhere (rule 5): ↩ the row's own action, ⌘↩
  and ⇧↩ what they already do in the list, ⌘C copies the main value (a
  name, the result, the file, the link): its `.copy` action, else its
  first copy, never the skil.li link (`LauncherAction.isLink`), else the
  row's own words (`copyTitleAction`: its title, what was asked, a
  skillie's inline line, an argument typed but never a password), silently
  and the launcher closes, on every row; ⇧⌘C the second (the mobile, the
  path, the meeting link), ⌘⌫ removes (in a mode only: outside, ⌘⌫ edits
  the field). These keys work without opening the list; ⌘C copies the
  field's text instead when some is selected. The list shows each
  action's key; the others have none.
- In the list: typing filters (each word starts a word of the title: "co
  ph"), arrows move, ↩ runs, an action's key runs it, esc or ⌘K go back to
  the results, a click beside it closes it. ⌃N and ⌃P move as ↓ and ↑,
  in the list and in the results. Copies close the launcher, nothing
  said. A key with no action there says so in the list's field ("Nothing
  on ⇧⌘C here: pick an action in the list.", `ActionPanelView.say`) until
  the next key; the contact card's list too, and a key the card has no
  action for opens its list saying so.
- Copy Link (no key, last of the copies; "Copy skil.li Link" on a
  quicklink, whose Copy Link is its web address) on every row the Catalog
  lists: commands, Mac commands and window places, the user's commands,
  snippets, skillies, quicklinks (with what is typed for them), layouts,
  and every "?" row (`skilliLink(for:)`, `SkilliLink.link(for:)`). See
  Links below.
- The footer (`updateFooter`, `LauncherFooter` and `LauncherTab` in
  SkilliCore) names the selected row's ↩ as ⌘K lists it first
  (`mainAction(for:)`, the one source of both: "Open", "Paste", "Paste
  Result", "Join", "Quit", "Done" / "Not Done", "Run" / "Next" on a
  skillie's arguments, the Catalog's "Open" / "Run"), then ⇥ only where it
  does something of its own (Ask outside the modes with words typed; By
  Meaning, By Feeling, Processes, Details when they apply), then "Actions
  ⌘K"; nothing else. No row: no ↩ nor ⌘K. It follows the selection
  (`tableViewSelectionDidChange`) and each key; on the keystroke path it is
  a switch on the selected row and the hint bar's cache of built hints
  (`HintBar`), nothing built or read.
- Contacts: Message (`sms:` for a number, `imessage:` for an address), Call
  (`tel:`, the Phone app), Email (mailto), Send Contact Card… (a .vcf in a
  new message via `NSSharingService.composeMessage`, nothing sent), then a
  copy per number and address with its label, the mobile first.
- Apps: Open, Show in Finder; when the app runs, Quit and Force Quit, both
  through Kill Process's card (it confirms, then goes: the app gone is
  the answer); Set Shortcut… (or Change Shortcut ✦S…: the card asks for
  the keys and the next ones pressed are its `openApp` shortcut, the Keys
  pane's recorder, esc cancels, then it says them; 2026-10-16); Copy
  Name, Copy Path. A running app's row says "· running": `AppIndex` keeps the
  running bundle paths (KVO on `runningApplications`, nothing read on a
  key) and matches the resolved path, since Safari runs from its cryptex.
  `selftest card` (`appRowQuitsARunningApp`) drives it on Chess.
- `selftest card` (`actionsForTheSelectedRow`): a contact's footer, list
  and keys, filtering, ↩, ⇥ in the Contacts mode opening the same list,
  ⌘⌫ there said in the list, ⌘C / ⇧⌘C without the list, esc back to the
  results, then to the empty launcher, then closed; ⌘C on Reset Launcher
  Position copying its title (not its link); links kept by
  `LauncherController.openURL`, never opened. The app row's footer
  (`appRowQuitsARunningApp`), the Agenda's "Open in Calendar ↩ · Details
  ⇥" and Reminders' "Not Done ↩" then "Done ↩" as ↓ moves
  (`remindersSaidAndDone`).

### Aliases

- One alias per launcher item (`LauncherAlias` in SkilliCore, stored in
  `Preferences.launcherAliases` by the item's `learningID`): an app, a
  command, one of the user's commands, a skillie, a quicklink, a layout, a snippet, a
  Mac command. Set with ⌘K → "Set Alias…" / "Change Alias “e”…" (the
  list becomes a field, ↩ saves, empty removes), or typed in place in
  Settings → Catalog (the entry's popover; the same normalizing and check);
  aliases no row holds (apps, a sound device, a pane) are listed and
  removed under Catalog → Aliases. An alias belongs to one item: given to
  another, it moves.
- Typed then a space (`LauncherAliases.split`): a command that turns the
  launcher into a mode opens it with the rest as its filter ("e smile",
  `LauncherController.mode(for:)`); a skillie with arguments asks its first
  one; a quicklink takes the rest as its query. Typed alone, or for what
  opens no mode: the item comes first, its alias as a keycap on the row.

### Root search ("our way": fewer knobs than Raycast)

- 2026-10-15: Jev and learning rank; ↑ brings back recent searches;
  nothing found = Ask (the last row is always Ask “…”); Pin from ⌘K; only
  two settings: which screen, and when it resets. Pure parts in SkilliCore
  (`RootSearch.swift`: `RecentSearches`, `LauncherPins`, `LauncherRank`,
  `LauncherScreen`, `LauncherReset`), unit-tested.
- A name typed whole comes first (`LauncherRank`; #137: "display" must
  find System Settings' Displays): a row the query names ranks before
  rows its words only describe. Names: an app's, a command's or Mac
  command's title, a pane's name in each of the user's languages
  ("Moniteurs", "Displays"), a skillie's, quicklink's, layout's,
  snippet's, project's name. Typed whole (`FuzzyMatcher.names`): the
  same letters and digits in order, case, accents, spaces and punctuation
  aside, the name's final "s" left out or not ("display" names Displays,
  "wifi" Wi‑Fi; never "display" in "Move to Next Display", never "disp").
  Keywords (Move to Next Display's "display", Turn Wi-Fi Off's "wifi",
  Search Contacts' "contact"), a pane's sections and its "… settings"
  only lead to a row. A row named gains `LauncherRank.namedBoost` (25):
  more than a keyword typed whole (the matcher's exact match, 20, as much
  as a pin), less than one pick learned (30), so a habit still wins (Move
  to Next Display picked once for "display" is first again). Rows named
  alike stay as even as before (Calendar, the app and the command). So
  "display" and "wifi" give the pane, then the window move or the switch;
  "contact" the Contacts app, then Search Contacts.
- A settings word before or after a pane's name asks for that pane
  (`SystemSettingsPane.asked`: "réglages bluetooth", "bluetooth
  settings"); a row offered for a word comes after it
  (`LauncherRank.offerPlace`): Allow Bluetooth second there, still first
  for "bluetooth" alone or "connecte mes AirPods". `asked` never looks for
  panes ("system settings" must not list those that hold "system");
  `paneQuery` (a settings word first) does. `selftest panes`
  (`launcherOpensSettingsPanes`): "displays", "display", "night shift",
  "wifi", "réglages bluetooth" and "bluetooth settings" first, Allow
  Bluetooth next on the mini; `launcher-settings-pane-asked.png`.
- ↑ recent searches (`RecentSearches`, `RecentSearchStore`:
  `recent-searches.json` in skil.li's folder, read once, kept in memory,
  writes coalesced; the self-test's and the benchmark's in memory): only
  what was typed outside the modes and acted on (↩ on a row, ⇥ Ask, a ⌘K
  action that closed the launcher), the last 20, the same words again move
  up. Never a mode's filter (clipboard, files, a skillie's argument). In
  the empty field with the first row selected (or none), ↑ puts back the
  newest, ↑ again the one before (it stays on the oldest), ↓ goes forward
  and past the newest empties the field, as in a shell; while the field
  holds a search ↑ put back (the header says "Recent search · 1 of 2"),
  ↑ and ↓ walk them; typing ends the walk, and
  ↑ with words typed or a lower row selected moves the selection as ever.
  No hint in the footer (its rule above); Settings → Launcher says it.
- Pin (`LauncherPins`, `Preferences.launcherPins`, by `learningID`, in the
  order pinned): ⌘K → "Pin" / "Unpin" on the rows an alias can hold (app,
  command, the user's command, skillie, quicklink, layout, snippet, Mac
  command, System Settings pane) and on a Catalog entry that is such a row.
  Pinned items come first in the empty field (after the meeting about to
  start), with a small pin after the title (`ResultCellView.setPinned`),
  and gain `LauncherPins.boost` (20: an exact word's bonus, less than one
  learned pick) when they fit what is typed. Read once per show; apps and
  built-in commands looked up at once, the rest as the last catalog read
  found them (`pinnedFound`, refreshed after each read off the show path).
  A pin whose item is gone for good is dropped silently (an app no longer
  on disk, a quicklink, layout, snippet, skillie or command deleted); one
  turned off in Settings → Catalog, a sound device away or a pane macOS no
  longer lists only hides. Not in get_settings (`SettingsTable.notInPanes`):
  the user's own list.
- Opens on (`Preferences.launcherScreen`): the screen with the pointer
  (default, as before), the one showing most of the window in front (the
  window server's list, front to back: no Accessibility call a busy app
  could hold, no permission for frames; none: the pointer's), or the main
  display. Where on it stays `LauncherPlace`. The AI card's resting place
  follows.
- Starts again empty (`Preferences.launcherReset`): right away (default,
  as before), after 1 or 5 minutes, never. Closing keeps the words, the
  mode (a skillie's arguments so far; esc first steps out of it, ⌘W or a
  click outside keep it) and the row (by id and title, else
  its index); opened again in time it comes back: the mode entered again
  (its rows read again), the row selected, the words selected so typing
  replaces them. Words kept are found again with the last catalog read
  (nothing read on the show path), then it is read anew. ✦C, the menu
  bar's reminders and next meeting and the GitHub strip take back only
  their own mode.
- `selftest rootsearch` (keys): ↑ walks two calculations acted on, a
  search only typed left out, ↓ and ↑ on rows; Pin on Chess and Calculator
  from ⌘K, both first with their pin, Unpin, the boost for "cal", a pin of
  an app gone dropped, Pin in the Catalog's ⌘K; Starts again empty with
  each choice (a test hook ages the close: `pretendClosed`); Opens on each
  choice (one display: telling them apart is skipped and said);
  `launcher-recent`, `launcher-pin-action`, `launcher-pinned`,
  `launcher-unpin-action`, `settings-launcher` -light/-dark.png. Then
  ⌃N/⌃P in the rows, in ⌘K's list and ⌃P recalling a search; a quicklink
  taking the test window's selection (Wikipedia by name searches it, words
  typed win, nothing selected types its keyword); Type in English while
  open (switched and back with the bindings held when an English layout
  is on; the mini has French only: nothing switches, never changed there),
  `launcher-quicklink-selection`, `settings-launcher-english`
  -light/-dark.png.

### Catalog ("?")

- One list of everything skil.li does (`CatalogEntry`, `FeatureCatalog` in
  SkilliCore; 2026-10-15): the launcher's "?" mode and Settings →
  Catalog read the same entries (`AppDelegate.catalogInput`), never a copy. Each entry: its name (the launcher row's own
  title), one line in the user's words (third person, no period, ≤ 80
  characters, "SI" never "AI"), its group (Find, Do, Write, Stay on Top,
  Yours, skil.li), its prefix and what Return does (`CatalogEntry.Run`).
  Apps are not listed; System Settings' panes and each sound direction are
  one row. What the user made (their commands, snippets, skillies,
  quicklinks, layouts) is listed item by item; none yet: one row that opens
  where to make the first.
- New Snippet, New Quicklink and New Command (`LauncherCommand`, issue
  #4) are there either way, each after what it makes: launcher rows of
  their own, as New Window Layout opens the layout editor.
  `AppDelegate.run` → `SettingsWindowController.showNew`: the pane, its
  editor on a new one. The request (`SettingsNavigation.new`, in the
  environment) is taken once by `SnippetsPane`, `QuicklinksSection` or
  `AICommandsPane` as it shows or while shown. An editor open already,
  on any pane, keeps its edits: the request waits until that sheet ends
  (`NSWindow.didEndSheetNotification`), then runs. The window closed
  drops a request and the commands' draft (`AICommandsModel.editing`
  outlives the window). Nothing is added before Save, so their links run
  at once, as a pane's do.
- Every `LauncherCommand.ID`, `SystemCommand` and `WindowLayout` is in it
  exactly once (unit tests): a new command needs its line there.
- Prefixes come from `LauncherPrefix`, the list the launcher's parsers
  read (`LauncherController.controlTextDidChange`, `ProcessListing.query`,
  the `modeFilter`s): the first of each is the Catalog's keycap. The words
  Return types ("timer ", "awake ", "event ", "remind me ") are the
  parsers' own constants; a test parses them with words after.
- An entry's id is its launcher row's `learningID` ("cmd:emoji"), so the
  alias is the row's; "catalog.…" when it has none (no alias then).
  `selftest catalog` checks they match.
- The mode: "?" first (or "What skil.li Can Do"), the accent chip
  "Catalog"; text after it filters (`FeatureCatalog.filter`: a group stays
  together, the best group first). Rows (`CatalogCellView`): icon, name,
  the line in the secondary color, and on the right the keycaps of each
  way to reach it: prefix, alias, shortcut. Group names are rows in the
  launcher's header style, 34 pt (`CatalogHeaderView`), never selected; the
  first group's name is the header above the list, which follows the group
  at the top as the rows scroll. ↩ does what the entry's launcher row does
  (`launch(_:row:flags:)`), or types the start of the words; ⌘K: Run, the
  alias, Set Shortcut… (Settings → Keys). Entries, shortcuts and keycaps
  are made once as it opens; a key only filters in memory.
- `selftest catalog` (keys): "?" typed with the layout's own keys, the six
  groups, the header following, "? kill" then ↩ into Kill, Clipboard
  History's prefix, alias and ✦C, ⌘K, an entry Off dimmed and still
  run; `launcher-catalog*-light/-dark.png`. Links (`linksRunWhatTheyName`):
  ⌘K → Copy Link in "?" (Clipboard History) and on launcher rows (Left
  Half, a quicklink with its query, Lock Screen), each opened through
  `LinkRunner.openNow`: the history opens, the test window moves, the
  address is recorded, Lock Screen asks in the card and esc runs nothing
  (dry run), an unknown link says so; `launcher-copy-link-*.png`,
  `link-asks-*.png`, `link-unknown.png`. `linksTrustedPerEntry`: Lock
  Screen's card offers Always, ⌘↩ trusts it, its next link runs with no
  card, Sleep's still asks, Paste in Sequence's offers no Always and keeps
  nothing, what asks anyway is refused, Settings → Catalog lists it
  (`settings-catalog-trusted-links-*.png`), − asks again (dry run).
  `newFromLauncherOpensEditors`: "new snippet", "new quicklink" (Settings
  open on General) and "nouvelle commande" typed with keys, each first;
  ↩ opens its pane with the editor holding the keys, esc cancels it,
  nothing added; `settings-new-snippet/-quicklink/-command-*.png`. New
  Command asked over a snippet's editor leaves it, then opens after esc;
  Settings closed with a command's editor open, the next one is blank.
- Settings → Catalog (`CatalogPane`, `CatalogPaneModel`; last sidebar
  block with About): first how it is reached (From the launcher: "?" as
  a keycap; From other apps: ⌘K as a keycap, where links are described),
  then the search field filters with `FeatureCatalog.filter`
  (as "?"), then the entries by group. Rows are read-only, like the "?":
  tinted icon, name, the prefix as a keycap, its line; on the right only
  what exists ("Off", the alias as a keycap, the shortcut's keycaps) and a
  chevron when there is something to change. No placeholders, no controls
  in the list. A click opens the row's popover (`CatalogEntryEditor`,
  attached to the edited row only): Alias (a text field, ⌘K → Set
  Alias…'s check; ↩ or Done keeps it, closing keeps a valid one), Shortcut
  (the Keys pane's own `ShortcutField` and `ShortcutNote`: conflicts
  refused the same way; one added for an action without any goes again if
  recording ends without keys; closing stops a recording), Show in search
  (a native switch, live). Then, while nothing is searched, Quicklinks
  (moved from Launcher, no Raycast import), the aliases no row holds and
  Trusted Links (what links run without asking, each with −).
  The "?"'s Quicklinks row opens it there (`.settings("catalog/quicklinks")`).
- Off (`Preferences.catalogOff`, entry ids): the entry's rows leave the
  launcher's results: its own row, or what its words make or its search
  finds (`FeatureCatalog.entryID(ofRow:)`: the calculation, timers,
  "awake 1 h", events and reminders said in a line, sound devices,
  System Settings panes, Ask "…", contacts, projects, the meeting). Read
  once per show and taken out of `LauncherController.Catalog` then (a key
  never looks; parsers check a set). Its prefix, alias and shortcut still
  work; the "?" lists it dimmed with "Off" and runs it. Only entries with
  rows have a switch (`CatalogEntry.canBeOff`: not Ask by Voice, Do It
  Here, the case changes, the "make your first" rows).
- Speed: a Form builds every row as it opens (no laziness on macOS): the
  pane draws its first group at once (~65 ms on the mini) and the rest on
  the next turn of the run loop (~210 ms whole; Keys ~120–140 ms). Rows
  hold no controls: 92 switches or fields would cost ~0.1 s each kind.
- `selftest settings`: the pane (fast, fits, search, a row's popover,
  recording there and ⎋ leaving no empty shortcut, rows with nothing to
  change read-only, opened at its quicklinks), alias typed with keys in a
  popover then "zk " opens Kill, ✦B recorded in Keep Awake's popover then
  pressed, Show in search off for Kill and the calculator (they leave the
  results, "kill " still opens Kill, "?" dims it, ↩ runs it);
  `settings-catalog*-light/-dark.png`, `launcher-catalog-off-*.png`.

### Quitting and uninstalling from Ask

- "kill creative cloud", "tue …", "quitte de force …": the command
  question's quit / force quit option, then the name as a phrase of the
  request's words (`AskValues.target`); `QuitRequest`: the processes
  whose name, app or path has a word of it, and every one
  under the same vendor folder ("Adobe": CCXProcess, Adobe Desktop
  Service). Those whose name or app says every word of it as a whole word
  are sure ("kill code": Visual Studio Code, never Xcode); the decision
  model judges the rest in one request, a yes or no each (names and app
  folders only): sure ones (≥ 80 %) quit at once, normally (an app asks
  itself to save); unsure ones (30–80 %) are asked in the card in one
  question naming them all (↩ is Leave Them); by force only when said,
  after Force Quit ↩. Nothing of
  it running: the card says so. Done, the card closes: the apps gone are the
  answer; it stays only to say which refused.
- Clean uninstall (`AppUninstaller`, `AppLeftovers` in SkilliCore), from
  ⌘K → "Uninstall…" on an app or Ask "désinstalle Slack" (the command
  question's uninstall option, the name read as for quitting, matched
  to an installed app by name; no name said, or no app of that name:
  "Which app?" asked in the card, saying so): the app and what
  it left under ~/Library only (Application Support, Caches, Preferences,
  Containers, Group Containers, Saved Application State, Logs,
  HTTPStorages, WebKit, Cookies, LaunchAgents… by bundle id; by name only
  for a distinctive one), listed with sizes; Move to Trash ↩ quits it if
  it runs (5 s at most) then moves everything to the Trash. Never macOS's
  own apps (/System, com.apple.*) nor skil.li.

### Backup

- Settings → Backup (`BackupCenter`, `BackupPlan` in SkilliCore): a plain
  zip ("skil.li Backup 2026-10-15 at 09.05.12.zip", made with `ditto` as
  the Finder does) of `~/Library/Application Support/skil.li` (never
  `mcp.sock`, never the clipboard history: 2026-10-15) and the
  `Preferences.*` defaults in `Settings.plist`, minus this Mac's own state
  (`Preferences.machineKeys`: setup done, screens, launcher place, backup
  folder). API keys and sensitive form fields stay in the Keychain: never
  in a backup.
- The folder is the user's choice (iCloud Drive offered first); how often
  (only when asked, every day, week, month) and how many stay (5, 10, 30,
  all). One timer waits for the next one due; a backup missed while the
  Mac was off runs a minute after skil.li starts or wakes. Free: Raycast
  keeps scheduled backups for Pro.
- Restore (Settings, a confirmation listing what comes back in the user's
  words): the backup is unpacked first, then what is there now is backed
  up, then files and settings are replaced and skil.li opens again
  (`Relaunch.afterExit`); the clipboard history on this Mac stays, an
  older backup's is left out (`BackupPlan.restore`). Two backups in the
  same second both stay.
- "Back Up skil.li Now" in the launcher: out of sight, so one line says
  where it went; without a folder it opens Settings → Backup.
- `selftest backup` works on scratch copies only (folder, defaults suite,
  destination): no keys, no windows.

### Interactions: the six rules

2026-10-17, validated the interactions review
(`docs/interactions-review.md`): every flow, new or changed, is checked
against these.

1. Ask only before sending, deleting for good, paying or overwriting.
   Nothing else asks.
2. Reversible things happen at once, with ⌘Z for 10 s instead of a
   question (`offerUndo`).
3. A choice the user just made is not confirmed or announced. skil.li
   speaks only when something failed or happened out of sight.
4. A card never takes keys from the app the user is typing in.
5. The same key means the same thing everywhere: ↩ main, ⌘↩ second, ⌘C
   copy, ⌘⌫ remove, ⌘Z undo, esc back.
6. A failure says what happened and what to do, in words: never a bare
   beep, never a dead end that makes the user retype. In Ask and the
   card: a missing value is asked in place (`AskValues.Missing`, see "Ask
   never acts on a regex reading"); a menu item refused, an answer that
   could not be pasted, a contact card sent nowhere, a gone command, an
   event with no one to mail say so in one line (`notify`); a key of the
   contact's card with nothing to do says so on its status line.

### Deletes come back with ⌘Z

Rule 2 for the user's data (decision D3, 2026-10-17): every delete goes at
once, nothing asked, and the undo card offers Undo ⌘Z for 10 s
(`AIActionController.offerUndo`, `UndoDelete.seconds`): Undo ⌘Z and
Close esc, nothing else; ↩, ⌘C and every other key reach the app. Its
title says what went in the "Layout Deleted" style, its line names it in
bold (`UndoDelete.details`: one short line, Markdown escaped). One place
holds them all, `UndoableDeletes` (`Sources/Skilli/App/UndoableDeletes.swift`),
which the panes (`SettingsContext.deletes`), the command editor
(`AICommandsModel.deletes`), the shortcut fields (`ShortcutStore.deletes`),
the launcher and the self-test call:

- Launcher: a copy forgotten (⌘⌫ or ⌘K → Forget in the history: "Copy
  Forgotten"; its row, image and link preview gone from disk at once, held
  in memory for the 10 s, `ClipboardStore.forget`/`restore`, back with its
  id); a file moved to the Trash (⌘K → Move to Trash: "Moved to Trash", ⌘Z
  moves it back where it was, under a free name if another took its place,
  `UndoDelete.freeName`, never over it); an alias removed (⌘K → Remove
  Alias, or the field left empty); a layout deleted ("Layout Deleted",
  with its shortcuts).
- Reminders and Calendar: a reminder deleted (⌘⌫ or ⌘K → Delete Reminder
  in the Reminders mode: "Reminder Deleted", made again with every field
  it had, `ReminderBook.remove`/`restore`: list, dates, alarms and
  places, how it repeats, done or not); an event nobody else is invited
  to ("Event Deleted", that occurrence made again as an event of its own:
  calendar, time zone, place, notes, link, alerts, availability,
  `CalendarBook.remove`/`restore`). An event with invitees still asks
  ("Delete Event?"): deleting it can tell them, and EventKit cannot
  invite them again.
- Settings: a snippet (its file as written), one of the user's commands
  (its file and its shortcuts), a quicklink (in its place), a field of
  Your Details or a person or company with theirs (a locked value such as
  an IBAN back in the Keychain), the Claude API key or a deciding key, a
  connected server (its config, token or OAuth sign-in, its tools' rights
  and list), one of the user's tools (its right and token), a rule, a
  scheduled ask, a reminder place, an alias, the emoji words learned
  (Forget no longer asks), the GitHub live updates token, a shortcut (its
  ⓧ, Remove Shortcut and Delete in Keys).
- Secrets (keys, tokens, locked values) wait in memory only for the 10 s,
  are never logged and never reach a backup.
- After ⌘Z the panes that keep their own copy read again
  (`SettingTools.changed`). A later undo card replaces an earlier one:
  only the latest delete can come back.
- Still asked first (rule 1, deleting for good or overwriting): Clear
  History, a backup restored, Keys → Restore Defaults, Uninstall… (it
  quits the app too), an event with invitees. Agents' deletes
  (`delete_snippet`, `delete_quicklink`, `delete_reminder`…) wait for the
  user's OK in the card and offer no undo.
- While the launcher is open (a copy forgotten), the card shows right
  under its glass, as wide (`AIActionController.openLauncherFrame`,
  `UndoDelete.spot`: above it when the screen has no room below), never
  over its rows; the `.selection` rule, which pins for the tallest card,
  put it over them on the mini's 1080p screen. It takes ⌘Z there
  (`AppDelegate`'s `interceptForAI` → `AIActionController.undoKey`);
  every other key stays the launcher's.
- `remote undo` runs every check below at once (keys, scratch stores);
  each also runs in its feature's scope (`undoCardPutsBack`: gone at once, the card with Undo ⌘Z
  · Close esc and the item's name, ↩ reaches the test window's recorder
  and undoes nothing, ⌘Z puts it back and closes the card):
  `clipboardForgetUndoes` (snippets; the card under the open launcher,
  `launcher-clipboard-forgotten.png`, `card-copy-forgotten.png`),
  `trashUndoes` (files), `layoutDeleteUndoes` (windows),
  `reminderDeleteUndoes`, `eventDeleteUndoes`, `placeForgetUndoes` (card),
  `snippetDeleteUndoes` (snippets), `commandDeleteUndoes` (settings),
  `quicklinkDeleteUndoes`, `aliasRemovalUndoes` (catalog), `formDetailsUndo`
  (control), `keyRemovalUndoes` (ai), `serverRemovalUndoes`,
  `ruleRemovalUndoes` (toolrights), `scheduledAskDeleteUndoes` (schedule),
  `emojiWordsForgetUndoes` (emoji), `relayTokenRemovalUndoes` (github),
  `shortcutRemovalUndoes` (shortcuts).

### What is seen done is not said

- 2026-10-15: "some actions need to be done without validation that it
  has been done… it's too much". A success the user sees on screen is not
  announced: a layout put back (a card only when a window could not be
  put back, `LayoutReport.hasFailures`), a window placed, an app quit or
  killed (Kill Process, ⌘K Quit, Ask "kill …"), a timer started (the menu
  bar counts), hidden files shown or hidden, disks ejected, do it here
  done, a skillie that printed nothing.
- 2026-10-17 (rule 3): a choice the user just made is not announced
  either. Nothing said for a copy they chose (⌘C, ⇧⌘C, ⌘K Copy…, Copy
  Link, the contact card, the calculator), a sound output or a microphone
  chosen, a volume set, a Bluetooth device connected (its "Connecting…"
  card goes; only a failure stays), Keep Awake on (its cup in the menu
  bar; said only when macOS refuses), a layout saved in the editor, esc in
  the color sampler, a reminder or an event added after the card showed it
  and ↩ said Add.
- Said in one line: what happened out of sight that the user did not
  pick (an answer copied because the app could not take a paste, saved
  elsewhere, added to a list or a calendar straight from a sentence, with
  ⌘Z; backed up), the readings (speed, color, system info), and every
  failure or partial result ("No disk to eject.", "Not ejected: …", the
  windows not put back, a file the Finder did not move to the Trash).
- A delete of the user's data is not said either: the undo card shows
  instead, for ⌘Z (Deletes come back with ⌘Z, above).

### Keyboard

- Every swallowed key-down also swallows its key-up and auto-repeats
  (`swallowedKeyCodes`). Apps must never see half a key press.
- Unbound keys pressed with Hyper reach apps as ⌘⌃⌥⇧+key so Hyper shortcuts
  of other apps keep working.
- Synthetic events carry `SyntheticKeys.marker` and come from a private event
  source; the tap lets them through untouched.
- Bindings name characters (`u`), resolved through the active layout, so they
  work on AZERTY. ⌘C/⌘V are also resolved through the layout.
- Other Hyper tools' taps may run before ours: with Raycast's Hyper Key, F20
  never reaches skil.li and Hyper arrives as ⌘⌃⌥⇧ flags. Both paths must work;
  `selftest` covers ours with a test-only F19 trigger.
- Never clobber the user's key mappings. `HyperKeyPlanner`: adopt an existing
  Caps Lock → F13–F24 mapping (Raycast uses F20); install Caps Lock → F18 only
  when no mapping exists at all; otherwise leave Caps Lock alone. Remove only
  a mapping skil.li installed, and do it on quit.
- The keys of any Mac text field work in every text input of skil.li
  (2026-10-20: ⌘← and ⌥← did nothing): ← → with ⌥ or ⌘, ⇧ to select,
  ⌘↑ ⌘↓, ⌃A ⌃E, ⌥⌫ ⌘⌫. What a key does is macOS's own key bindings'
  (`KeyBindings`: Cocoa's standard ones and the user's
  DefaultKeyBinding.dict), never a list written here. The launcher's
  field gets the tap's events in its editor's `keyDown`
  (`LauncherController.deliver`), which ran no ⌘ key: a ⌘ key the
  bindings name is run as the editor's command, through
  `control(_:textView:doCommandBy:)` as the others (↑↓ stay the rows',
  ⌘↑ ⌘↓ move the caret). The card's answer line, drawn by skil.li, has a
  caret and a selection: the command runs on a text view never shown
  (`LineEditor`), typing and ⌘V go in at the caret, ← and ⌫ held repeat
  (`KeyRouter.repeatForAI`); any other ⌘ or ⌃ key still closes the card
  and goes on. Settings' search field takes ⌘↓ to the end (an
  NSSearchField ignores it). ⌘K's filter stays type-to-filter, without a
  caret (2026-10-20). `rootsearch` presses them all as a keyboard does
  (`caretKeysEditEverywhere`): launcher over another app, Settings' search
  and a SwiftUI field, the card.
- ⌃N / ⌃P are ↓ / ↑ in every launcher list and in ⌘K's
  (`LauncherController.controlStep`: N and P by what they type, by their
  place on a layout without Latin letters; an input method composing keeps
  them).
- ⇥ in the launcher (`pressTab`, `LauncherTab` in SkilliCore): outside the
  modes, Ask on the words typed; in a mode, the mode's own where it applies
  (By Meaning in the clipboard, files, history and snippets, By Feeling in
  the emoji, Processes on an app of several in Kill, Details on an event),
  else the selected row's actions, as ⌘K. Never Ask inside a mode (asked
  2026-10-17: the filter may be a password or a skillie's argument): the
  Catalog's "nothing fits, ⇥ asks" went with it. The footer says ⇥ only
  where it does something of its own.
- esc steps back, one level each time (`escape`, `LauncherEscape` in
  SkilliCore): ⌘K's list closes; an app Kill unfolded folds; a mode goes
  back to the root search with the field as it was before it (`modeBack`:
  "kill" for "kill " typed, the alias for "zz ", what was typed before ↩ on
  the mode's row, empty from "@"), as ⌫ on an empty field leaves it; then
  the launcher closes. A mode opened straight (✦C, ⌃⌘Space, the menu bar's
  reminders and next meeting, the GitHub strip, a `skilli://` link) has
  nothing before it: esc closes at once. ⌘W, a click outside and the
  launcher's own key close from where it is (the mode kept for Starts
  again empty).
- A failure in the launcher says what happened and what to do in one line
  (rule 6, `say`): in the footer's place while it is open, until the next
  key; once it closed (a menu item refused, a Move to Trash or a paste
  that failed, an app already quit), in the card (`onFailure` →
  `AIActionController.notify`). Never a bare beep: no `NSSound.beep()` is
  left on a launcher path, nor in the card's, the contact card's or the
  shortcuts' (`ActionRunner`).
- Type in English while open (Settings → Launcher → Advanced,
  `Preferences.launcherEnglishInput`, off by default; `EnglishTyping`,
  `EnglishInput` in SkilliCore): once the launcher is up (off the show
  path), `TISSelectInputSource` with the user's own enabled English layout
  (ABC, else U.S., else another English keyboard layout of plain letters);
  as it closes, theirs again unless they chose another meanwhile. Never a
  source added or turned on; none English, or English already, or Secure
  Input on: nothing (the pane says when none is on). Shortcuts keep their
  keys: `KeyboardLayout.hold` keeps bindings on the user's layout until
  `release`, and the launcher reads its ⌘ and ⌃ keys through it
  (`EnglishTyping.chordEvent`): ⌘K, ⌘, ⌃N stay where the hands know them;
  only typed text is English.

### Selection

- Read via AX first; fall back to ⌘C only when AX has nothing or only
  blanks (`InputScope.isBlank`: Arc gave a lone no-break space, and Claude,
  sent nothing to fix, answered nothing). Blanks copied are no selection
  either: "Select some text first."
- Always restore the full clipboard (every item, every type) after borrowing
  it, and mark our writes transient for clipboard managers.
- Replace with ⌘V so the target app's own undo works.
- Nothing to change, nothing pasted: a rewrite equal to the selection (spaces
  around it and accent encoding aside) shows "Nothing to change: it already
  reads well." and Return only closes; ✦K → U on text already in capitals
  says so in a card instead of pasting the same text.
- Send ⌘C/⌘V straight to the frontmost app (`postToPid`). Posted to the HID
  tap they cross Raycast's tap, which turns ⌘V into ✦V while Caps Lock is
  held; with `postToPid` nothing has to wait for the user to release keys.
- Wait on state, not on time: the clipboard comes back once the focused
  field's text changed (Accessibility; 250 ms only where nothing can be
  watched), a snippet's keyword is erased once it is seen before the caret.

### No workarounds where macOS has an API

Never simulate a shortcut or drive another app's UI when macOS offers the
thing itself; never type or press Return blind in another app.

- Lock Screen: login.framework's `SACLockScreenImmediate` (what Raycast
  uses), looked up when needed; a real ⌃⌘Q (modifier keys down and up)
  only if it is gone.
- Eject: `NSWorkspace.unmountAndEjectDevice` for each ejectable, removable
  or network volume (no Finder script, no Automation prompt).
- Volume: CoreAudio's `VirtualMainVolume` on the default output.
- send_message (Slack, Discord): each step checked through Accessibility —
  the ⌘K search takes the focus away from where it was, the name is in it,
  the window's title changes to the conversation, the message is in the
  message box before Return. If skil.li cannot see the app, it refuses.
- Kept, because they are macOS's own way: media keys (`NSEvent`
  system-defined), `pmset`, appearance, Trash, restart, shut down and log
  out through their scripting (System Events, Finder), hidden files
  through Finder's default; ⌘C/⌘V for the selection (the app's own undo),
  Escape for a Hyper tap, `press_keys` for agents.

### Blocks macOS calls on its own queues

- A block written inside `@MainActor` code is main-actor isolated: when a
  framework calls it on its own queue, Swift 6 stops the app
  (`dispatch_assert_queue` in `swift_task_isCurrentExecutor`). Ask by
  Voice did so on every use (the microphone tap on AVFoundation's audio
  queue). Build such blocks in a `nonisolated static` function
  (`VoiceInput.tap`, `ReminderBook.collect`), or use the framework's async
  API (`requestFullAccessToEvents()`, `CNContactStore.requestAccess`).
  Blocks the SDK marks Sendable (`readabilityHandler`) are fine.
- Test them on the real queue (`microphoneHeardForReal`,
  `eventKitAnswersOffTheMainActor`): stand-ins (an audio file, reminders in
  memory) never reach it.

### Ask never acts on a regex reading of a sentence

2026-10-16: "garde mon ordi hors veille pendant une heure trente" kept
the Mac awake one hour; a regex had read "une heure" and dropped "trente".
Word lists patched one sentence at a time are the bug, not the fix:
"regex is dangerous and not the manifesto. jev will be doing it way
better".

- What Ask acts with (how long, until when, how loud, what for) is read
  by the decision model, Jev first, then OpenAI Decisions
  (`AskValues` in SkilliCore, `AskRouter.values`): each value picked
  among fixed options, all asked in one request, put together in code.
  The model never computes a number. A timer's length and name, a volume
  level and Keep Awake's length ride in the route's own request
  (`AskRouter.speculativeValues`, `Decision.values`; D8, 2026-10-17:
  one request instead of two, more tokens per ask); plans, contacts,
  schedules and apps keep their second request.
- A value that can be said several ways is one option, never parts: a
  length is one of ~160 lengths, each described every way ("1h30 = 90
  minutes = an hour and a half"). Asked as amount, unit and minutes
  after, Jev read "an hour and a half" as 90 hours and 30 minutes, at
  69 %: parallel questions cannot agree on one reading. Parts only where
  the split is unique (an end time: its hour and its minutes).
- How sure is the least sure part used; under `AskValues.sureFrom` (0.6)
  what is undone as easily as it is done (a timer, the volume, Keep
  Awake: D5, 2026-10-17) is done all the same and the card says what
  it understood with ⌘Z for 10 s (`offerUndo`: "Keep Awake On · For 1 h
  30, until 15:42"; ⌘Z cancels the timer, puts the level back, lets the
  Mac sleep or keeps it as it was); a reminder or an event says what it
  understood and waits for ↩ (Add), then goes without a word.
- Free text (a timer's name) is selected among the request's own words
  (`AskValues.spans`), never written by the model.
- Regex and word lists stay where the grammar is typed, not spoken: the
  launcher's rows ("timer 10 min", "awake 2h", "volume 30"), and to find
  candidates for a model to choose among. Media keys ("musique
  suivante", "coupe le son") are the command question's, no fast path.
  Calendar and Reminders are the `plans` route (`AskValues.plan`: what is
  asked and every value in one request), contacts the `contact` route.
  Quit, force quit and uninstall are options of the command question,
  the app's name a span (`AskValues.target`); a schedule is read by
  `AskValues.schedule`. Left on words, on purpose: Bluetooth's
  permission prompt ("connecte mes AirPods" before skil.li may use
  Bluetooth: macOS's question, nothing done), and the Settings "+" field
  and the agents' `add_scheduled_ask`, typed and shown back
  (`AskSchedule.read`).
- Words of the request are picked, never written: a name or a short
  phrase whole among its runs of words (`AskValues.phrases`: who a
  contact is, an app, a place, a timer's name, what a schedule does);
  asked as a first and a last word, both models often stopped at the
  first ("Paul" for "Paul Durand"). What a reminder or an event says,
  which can be long, is a first and a last word, the words saying when
  left out.
- Whether to act or ask first counts only the parts that make it happen
  at the wrong time or place (what is asked, when, how often, where), the
  least sure of them. What it says is not among them: the card shows it
  once done, ⌘Z takes it back. Extras (a list, a calendar, an alert, a
  priority) are kept only when sure.
- A value Ask needs and the request did not give (2026-10-17, rule 6:
  "never a dead end that makes the user retype") is asked in the card,
  never a failure card: `AskValues.Missing` (how long, which level, which
  app, who, what about them, what a reminder says, when, which day, how
  often, which days, which day of the month, what to do each time). A
  small fixed set comes as keycaps, the pick taken as is (what about
  them: who they are or a mail; how often); anything else is typed, and
  only that answer is read by the model with the questions the request
  was read with (`Missing.questions(reply:)`), over the answer's own
  words: picked words come back as said (`Answer.said`), choices only for
  that value's own questions, joined to what the request gave
  (`completing` in `AIActionController`). Still not there: asked again
  ("Not read in “bientôt”: say it another way."); found and wrong for
  what it is used for, the same question with what happened above it ("No
  app named “Slak” on this Mac.", "No contact matches “Paul”.", "A timer
  lasts a day at most."). esc cancels; ↩ with nothing typed keeps the
  question (Ask's own too). Nothing read at all (every provider failed):
  "No decision model answered, so nothing was done: ↩ asks again." What
  the answer gives then goes through the same thresholds (sure: done;
  unsure: ⌘Z or ↩ as above). Not asked: a quit whose app is not running
  (what was asked holds; said once), Keep Awake with no length (until
  stopped).
- `selftest decide` (`askReadsValues`, `askReadsAnswersInTheCard`,
  `askReadsPlans`, `askReadsContacts`, `askReadsSchedulesAndApps`) runs
  the sentences said for real, French and English, on both real models, and
  typed answers alone; `selftest card` drives the same paths with the
  model's answers given (`plansRead`, `askAsksForWhatIsMissing` with
  `replyValuesOverride` for the answer).

### AI engines

Design in `docs/ai-architecture.md`; measurements, exact command lines,
protocols and traps per engine in `docs/ai-engines.md`. Read the latter before
touching an engine, and re-measure with `script/ai_bench.py` rather than
re-investigating.

- Phase 1 is Write on Claude: the user's own unmodified `claude` binary, or a
  Claude API key from the Keychain. Since 2026-10-15 ChatGPT and the OpenAI
  API write too, chosen per command (below).
- Writers (`AIStore.writer(for:)`, `ModelChoice` in SkilliCore): Claude
  (Haiku, Sonnet, Opus: `claude --model haiku|sonnet|opus`,
  `claude-haiku-5-5` / `claude-sonnet-5-5` / `claude-opus-5-5`; Sonnet and
  Opus on the API key send `fallbacks: "default"`), ChatGPT through the
  user's own Codex (`CodexEngine`: one `codex exec --json --ephemeral
  --skip-git-repo-check --ignore-user-config --ignore-rules -s read-only` per
  request, approvals never, no web search, skil.li's instructions in place
  of Codex's (`model_instructions_file`), tools, apps, plugins and agents
  off as `-c features.<name>=false` (an unknown name is ignored there;
  `--disable` would stop Codex), an empty working folder, the answer the
  last agent message; OpenAI's variables left out so
  the ChatGPT sign-in is used; ~3 s, no spare yet), and the OpenAI API with
  the key kept for Decisions (`OpenAIEngine`, Responses API streamed,
  `store: false`). Models: Codex's `codex debug models` (listed ones, low /
  medium / high) and the key's `GET /v1/models` (text GPT models, no dated
  snapshots), each cut to the newest of each family of the newest
  generation (`ModelCatalog.current`: GPT-6.1 Sol, GPT-6 Astra, GPT-6 Luna);
  a checked list stands in before they answer. Status: `codex login status`
  (no network); skil.li never reads `~/.codex`. Sign In opens `codex login`
  in Terminal.
- Model per command (`model:` and `effort:` in the file: `haiku` as always,
  `chatgpt/gpt-6-luna` + `effort: low`, `openai/gpt-6.1-sol`): the editor's
  Model is one pop-up grouped by provider (Default (Claude · Haiku), Claude,
  ChatGPT, OpenAI API), its title naming the provider ("ChatGPT · GPT-6
  Luna"), then Thinking (Low · Medium · High) for OpenAI's models. The same
  pop-up, without Default, is Settings → SI Accounts → Writing's default for Ask and
  commands (`Preferences.writingModel`; the old `aiModel` read once). A
  provider that cannot write stays listed, its models off, its header saying
  why and how ("ChatGPT — Not signed in: run codex login in a terminal").
  A command whose provider cannot write runs on the default and the card
  says so ("Claude · Haiku · 1.1 s · ChatGPT: not signed in"); a file naming
  a model this build does not know keeps it as written, writes with the
  default, and the import sheet and the editor say so. Commands with tools
  run in Claude Code: Claude's models only. The card's status names the
  writer ("ChatGPT · GPT-6 Luna Low · 3.0 s"); failures are said in words
  (`WritingFailure`: signed out, the plan's limit, a model not offered,
  out of credit, unreachable). `selftest models` (Mac mini).
- Engines run as spare processes: started ahead, one request each (no
  history), killed after use and replaced. Never spawn one on Hyper alone.
- Strip CLI context (Claude: `--tools "" --setting-sources ""
  --strict-mcp-config --disable-slash-commands --no-session-persistence
  --system-prompt …`); otherwise the user's own config leaks into answers.
- Never read other apps' credentials (`~/.claude`, `~/.codex/auth.json`,
  `~/.grok`, their Keychain items) or reuse their OAuth tokens; never bundle or
  modify a vendor CLI.
- Connecting the subscription = asking the user's `claude` for
  `auth status --json` and, when signed out, opening its own
  `claude auth login --claudeai` in Terminal. skil.li never handles the login.
- Child `claude` processes get the app's full environment (`ClaudeCLI.environment`):
  without `USER` it reports signed out. Run them in `ClaudeCLI.scratchDirectory`
  (empty), never in a project folder.
- The API key lives in skil.li's own Keychain item (`AIStore.apiKeyAccount`);
  the self-test uses `selftest-anthropic-api-key` and only reads the user's key.
- Decision keys (OpenAI Decisions, TypeSafe Jev) live in `openai-api-key` and
  `typesafe-api-key` (self-test: `selftest-` prefix); `DecisionClient` speaks
  `/v1/decisions` (gpt-6-luna, answers as a list with `name`) and
  `/v1/systemone` (jev-latest, answers keyed by name).
- Every new AI behaviour gets a check in `selftest ai` (one real request on
  the user's plan, ~850 tokens; the API-key check is skipped without a key).
  Interaction checks use `FakeTextEngine` through `AIStore.testEngine`: no
  tokens, deterministic.
- AI actions (`SkilliAction.aiPrompt`) run in `AIActionController`: read the
  selection, stream into `AIPopover`, Return pastes with ⌘V (the app's own
  undo), Esc or any other key cancels and kills the request. The card never
  takes focus or mouse events; its keys come from the tap
  (`KeyRouter.interceptForAI`), so the selection stays live in the app.
  While the launcher is visible it gets the keys first: a card that shows
  up then (a late "copied" note) never takes Esc from it.
  A card takes keys only when the user opened it or is answering it
  (rule 4): a note (`notify`) takes esc only; the undo card (`offerUndo`)
  ⌘Z and esc only, so ↩ and ⌘C reach the app (under the open launcher it
  takes only ⌘Z: `undoKey`); an outside agent's question
  or approval (`approve`, `ask`) waits until no key for 2 s
  (`typingPause`) and ignores keys for 0.5 s once shown
  (`unpromptedGrace`). What the user started (Kill Process, Mac commands)
  shows at once (`fromUser`). ⌘↩ in a card's field answers it and never
  reaches the app behind. A panel of skil.li's that took the keyboard to
  ask something (a display plugged in, a meeting alert with the screens
  dark) keeps its keys, esc included: a card behind it takes only ⌘Z
  (`AppDelegate.ownWindowHasKeyboard`).
  Paste only if the app in front is still the one that was; else copy.
  Where the card goes (`AIPopover.Placement`): started from the launcher
  (Ask, Commands), in the launcher's place, same top, same width
  (700 pt), up to 400 pt of text; started on a selection, under it (460 pt)
  or above it when the tallest card would not fit below; when the app does
  not tell where the text is, beside the focused field when it is one (at
  most 320 pt tall, `CardAnchor`), else the launcher's place (never the
  mouse): a whole document or web area is no place (Codex's on a second
  screen sent the card anywhere, 2026-10-16). The
  place is pinned once per show: the card only grows (down under a
  selection or from the launcher, up above a selection), it never jumps.
- Follow-ups in the card (`CardConversation` in SkilliCore,
  `AIActionController.followUpTurn`): after an answer shown in the card
  (output card, from Ask or a command, written or by the agent), "Follow up
  ⇥" asks "Your follow-up" in the card, the answer dimmed above the field.
  The same AI answers: the writer again, or Claude Code with the same tools
  and servers when the answer came from the agent. Each follow-up sends the
  conversation so far ("User: … / You answered: …", the agent's steps, the
  oldest turns dropped past ~80k characters) then the new question. ⌘↩
  hands Claude Code or Codex the whole conversation. Return copies the
  latest answer; the conversation ends with the card. `selftest card`/`ai`.
  A changed text follows up too (2026-10-18: "when the LLM does not do
  what we ask"): after a rewrite, an insert or a copy (Fix Spelling, a
  translation…), and after "Nothing to change", "Follow up ⇥" asks what to
  change; the same writer changes it again with the exchange so far
  (`CardConversation.message(refining:)`: the text alone, ready to paste);
  the latest version shows (the rewrite's changes highlighted against the
  selection) and ↩ puts it in place of the selection, as the first would
  have (`AIActionController.refine`). `selftest ai` (`rewriteFollowsUp`).
- Continue a conversation (`HandoffLauncher`, `Handoff` in SkilliCore,
  Settings → Ask → Continue a Conversation): after an answer in the card
  (output card or copy, not a rewrite of the selection), "In Claude Code
  ⌘↩" (or Codex) opens Terminal or Ghostty on a new session of the user's
  own CLI, in their home folder. Claude Code gets the conversation (the
  request as sent, what an agent did, the answer) through
  `--append-system-prompt` and waits for the next message; Codex has no
  documented way to take context silently, so it gets it as its first
  message and answers one short line. The conversation and a `.command`
  script go in a private temporary folder (0700); the script reads the
  conversation into a variable, deletes both, then `exec`s the CLI (every
  path single-quoted; the text passed as one argument, nothing expanded).
  Ghostty: `open -na Ghostty.app --args -e <script>`. A request over
  60 000 characters or an answer over 30 000 is cut. The CLI chosen in
  Settings, else the other one found; Claude Code is the one skil.li uses
  (signed in). `selftest handoff` (on the Mac mini: a stand-in CLI checks
  both terminals).
- Prompts are files (`PromptLibrary`): built-ins are written to
  `~/Library/Application Support/skil.li/prompts/` once, a file with a
  built-in's id replaces it, any other `.md` adds an action. Re-read before
  each run. The self-test and benchmark use an in-memory library.
- Commands (Settings → Commands, `AICommandsModel`, `CommandEditor`):
  built-ins are edited or reset, never deleted; custom ones are created,
  duplicated, deleted (their shortcut entries go too; at once, Undo ⌘Z
  for 10 s puts back the file and its shortcuts: `UndoableDeletes.command`).
  The editor writes
  nothing until Save (2026-10-17): New Command opens a draft
  (`draft()`, no file), Duplicate a draft copy of what the editor holds
  (the original stays as saved), Reset to Default puts the built-in in
  the draft; its shortcuts are the store's staged ones
  (`ShortcutStore.stage`: recorded and checked like the others, neither
  saved nor bound) until Save (`commitStaged`); Cancel, esc or the window
  closed drop them (`discardStaged`, as soon as the pane's `editing`
  changes). `selftest settings` (`commandEditorChangesNothingUntilSave`)
  presses each button. About You lives in `prompts/about-you.md`, edited
  in Settings → Your Details. "SI" is gone
  from the app (2026-10-15): a launcher row is the command's own name,
  "Command" beside it.
- Prompts are `PromptTemplate`s (SkilliCore): unknown `{words}` stay as typed;
  `{selection}` and `{clipboard}` are sent between `"""` (`AIPrompt.quoted`).
  A command needs a selection only if its prompt uses `{selection}`.
  Modifiers after a bar (`{selection | trim | upper}`, `| lower`, `| raw` = no
  quotes); an unknown modifier leaves the token as typed.
- Command files (`PromptFile`) also hold `output:` (`OutputMode`: replace,
  insert, copy, card) and `ask:` (`PromptQuestion`: id, question, options,
  default). Questions are asked in the card before the prompt is sent, never
  in a form: options as numbered chips (digits by key code, with or without
  ⇧, so AZERTY works; → ← Tab move; a click picks one: the card takes
  clicks only while its options show and never becomes key, so the app
  keeps its focus; Return takes the selected one, the default first), or typed
  text read from the tap (`KeyboardLayout.typedText`, dead keys included).
  The prompt reads answers with `{ask.<id>}`; answers it does not name go
  after it.
- Paste fallback: when Accessibility gave the selection and says the element
  is not editable (`SelectionService.pasteTarget`), Return copies instead and
  the card says so. Without Accessibility (Electron, terminals) it pastes.
- Tools and Act (Phase 2). skil.li hosts an MCP server (`MCPService`) on a
  Unix socket in its own folder (`MCPSocketServer`: 0600, same user only via
  `getpeereid`, newline-delimited JSON-RPC). `Skilli mcp` (the app binary,
  `MCPBridge`, before any AppKit) bridges stdio to it for any agent and
  starts skil.li if needed; `Skilli call <tool> '<json>'` (or `name=value`
  words) calls one tool: exit 0 its answer, 1 its error, 2 written wrong.
  Both reach `SKILLI_SOCKET` when set (a skillie's skil.li, never started).
  Tools (`SkilliTools`) are grouped (`ToolGroup`); each has a `ToolRisk`.
  `ToolSettings` (`tools.json`): `ApprovalMode` (ask / auto = ask before
  changes / always), a choice per tool, connected MCP servers. Approvals,
  `ask_user` and `notify` show in the AI card (`ToolPresenter`, implemented
  by `AIActionController`): Allow ↩, Always ⌘↩, Deny esc. An agent outside a
  command gets the card next to the text being edited, never over a command.
  A question about what the user started, or a step a tool takes once
  allowed, says what it does and is answered with that verb
  (`AIPopover.approve(verb:)`): "Restart?" ↩ Restart, esc Cancel; "Send
  to #general in Slack?" ↩ Send. Always (⌘↩) only where it is kept and
  honored (`send_message`'s; never a skillie's own ask, a Mac command or
  Force Quit), never "Allow “Restart?”?".
- MCP sign-in (`MCPAuth`, `MCPOAuth` in SkilliCore, `LoopbackServer`;
  Settings → Tools → a server's Edit → Sign-In: None / Token / OAuth).
  Token: kept in skil.li's Keychain (`mcp-token-<name>`), sent as
  `Authorization: Bearer …` (or as is in the header the user names, e.g.
  `X-Api-Key`). OAuth, as the MCP authorization spec says: the server's
  401 points to its metadata (`WWW-Authenticate … resource_metadata`, else
  RFC 9728's well-known path), that names the authorization server, whose
  metadata (RFC 8414, then OpenID) gives the endpoints; skil.li registers
  itself (RFC 7591, public client, `token_endpoint_auth_method: none`),
  listens once on 127.0.0.1 for the return, opens the browser on
  /authorize with PKCE S256, `state` and `resource` (RFC 8707), then trades
  the code for tokens. The session (client, endpoint, resource, tokens,
  expiry) is JSON in the Keychain (`mcp-oauth-<name>`); a token within a
  minute of expiring is renewed with the refresh token before a run; a
  failed renewal signs out and says so. Each agent run gets the headers in
  its own MCP config file (0600, removed when the run ends). A server Ask
  would use but the user has not signed in to is left out of Ask; a
  command that names it fails with "Sign in to … first". https only (http
  to this Mac for tests), for the server and every address its metadata
  gives; a session goes only to the host it was signed in for (the
  address edited: signed out). `selftest mcpauth` (a stand-in OAuth server).
- Tool rights (`ToolSettings`, `ToolPolicy.decision`, `MCPClient`,
  `MCPToolList` in SkilliCore; Settings → Tools). Per tool: Default,
  Always Ask, Always Allow, Block (`ToolOverride.never`). skil.li's tools are
  grouped by `ToolGroup` (collapsible, "Set All" per group). A blocked
  skil.li tool is not in `tools/list` (Claude Code, Codex, any agent) and
  is refused if called. A connected server's Tools… sheet lists its tools:
  `MCPClient` sends `initialize` and `tools/list` (every page) with the
  user's sign-in headers over Streamable HTTP (JSON or SSE, `Mcp-Session-Id`,
  `MCP-Protocol-Version`) or starts its command (stdio, JSON lines); no tool
  is called. The lists are kept in `server-tools.json` next to `tools.json`
  and refreshed after Save, after Sign In, and with Refresh. Hints set the
  defaults: `readOnlyHint` asks like reading (runs in Ask Before Changes);
  the rest asks like a change; the sheet groups Read Only / Change Things /
  Can Delete or Overwrite (`destructiveHint`, or not read-only without
  `destructiveHint: false`, as the spec reads it) / No Hints. In a run,
  `approve` refuses a blocked tool without a card, and `AgentRun` passes
  blocked tools as `--disallowedTools`. `selftest toolrights` (a stand-in
  HTTP server with two pages, the second as SSE; the bridge over stdio;
  decisions through `Skilli call approve --run`).
- Your rules (`ApprovalRule`, `ApprovalRules`, `ToolPolicy.decision(…verdict:…)`,
  `ToolCallSummary` in SkilliCore; `RuleJudge`, `MCPService.gate`;
  Settings → Ask → Your Rules, under When It Acts): sentences in the
  user's words, each Allow, Ask First or Never, kept in `tools.json`,
  written only in the pane (agents read them: `get_settings`,
  `list_tool_rights`). Before a step, when a rule could change what it
  does (`shouldJudge`) and a decision key is set, one Choice over the
  rules and "none" goes to Jev, else Decisions (5 s at most; the same call
  and rules kept 5 min): the tool's name, title and description (a
  server's own, marked as its claims), its kind, who asks, and its
  arguments in short (`ToolCallSummary`: names and values that look
  secret hidden, a link's query dropped, each value 80 characters, all
  300). What wins, in order: Block (never judged); a settings change asks
  every time (#150, never judged, no Always); a Never rule refuses (≥ 50 %;
  25–50 % asks "it may fall under"); an Ask First rule asks, over Always
  Allow and an allow right (no Always in that card: the rule would ask
  again); a tool set to Always Ask asks (a rule in general words does not
  silence a tool set by name); an Allow rule runs it (chosen, ≥ 50 %);
  then the right and the mode. Rules that could not be checked make what
  would run ask when there are strict ones. The card says which rule
  decided ("Asked because of your rule: …"); a run's step says "Allowed
  by your rule: …" or "Refused by your rule: …"; an outside agent gets
  the refusal in words, nothing shown. Without a key the pane says they
  need one (SI Accounts ›). `selftest toolrights` (the user's key, read
  only), `selftest decide` (both providers).
- Import From Other Apps (`MCPImport` in SkilliCore, `MCPServerImporter`,
  `ImportServersSheet`; Settings → Tools → Connected Servers): reads
  only the server lists of Claude Code (`~/.claude.json`: user servers and
  each project's), Claude for Mac (`claude_desktop_config.json`), Codex
  (`$CODEX_HOME` or `~/.codex/config.toml`, a TOML subset: tables, strings,
  arrays on several lines, inline tables) and Cursor (`~/.cursor/mcp.json`).
  The same address or command found in several places is shown once ("Also
  in Cursor, Claude Code · app"). skil.li itself, SSE servers, servers
  turned off, http addresses and tokens taken from `${VARIABLES}` are left
  out with the reason. An Authorization header (or one key-like header)
  becomes a token in skil.li's Keychain, never in tools.json; Codex's
  `bearer_token_env_var` asks to paste the token with Edit. A name already
  taken gets its app's name ("-codex"). After the import each server's tools
  are listed; a web server that answers 401 becomes an OAuth server (Sign
  In… on its row). Other apps' sign-ins are never read. `selftest
  toolrights` (scratch copies of the four files and a stand-in server).
- Rights with the user's AI (`ToolRights` in SkilliCore, `ToolRightsTools`,
  `HandoffLauncher.launchRights`, `Handoff.skillScript`): Settings →
  Tools → Help Me Choose → "Set Rights With Claude Code…" (or Codex,
  whichever is installed), and "Ask Claude Code…" in a server's Tools…
  sheet. With both installed, a menu beside the button picks the AI ("[Codex
  ▾] Set Rights…") and the sheet's button splits (its arrow asks the other
  one); it is the same choice as Ask → Continue in (`handoffTarget`). A
  terminal opens the CLI on a session with only
  skil.li's MCP server, given on the command line (Claude Code:
  `--strict-mcp-config --mcp-config '{…"skilli"…}'`, the two tools in
  `--allowedTools`, the skill in `--append-system-prompt`, the request as
  the first message; Codex: `-c mcp_servers.skilli.command=…` and `.args`,
  `.enabled_tools` (the two only), `.default_tools_approval_mode="approve"`
  (else Codex asks in the terminal on top of the card) and
  `.tool_timeout_sec=600` (the card waits for the user), the skill then
  the request as the first message). The CLI's own settings
  are never written. `list_tool_rights` (overview, or a server's tools
  with their hints and rights, `search`) and `set_tool_rights` (`server`,
  `"tool=right"` entries: default/ask/allow/block) are offered outside runs
  only (never to Act commands). Every change waits in the card, by right
  ("Always allow (3): …"), with Allow ↩ and Deny esc only (no Always);
  unknown tools are left out. The skill treats servers' descriptions and
  hints as data. Checked for real: Claude Code (`-p`, Haiku, on the Mac
  mini) called both reads in 6 s; real interactive Codex 0.162 sessions on
  the mini (2026-10-12): it reads the rights, asks one or two questions in
  French, proposes by group, calls `set_tool_rights` without a prompt of
  its own, keeps waiting on the card (its code mode runs the call in the
  background: the skill says to wait, it did for 6 min), and reports
  applied (22 allow, 35 block) or declined. `list_tool_rights` labels
  `harmless` tools "light change" (they run in Ask Before Changes): with
  "changes" the AI reported them as gaps. A Homebrew Codex whose
  `codex-code-mode-host` was never opened sees no tool at all until macOS's
  Gatekeeper prompt for it is accepted ("timed out negotiating with the
  code-mode host").
- Act commands (`tools:` in the file) run `AgentRun`: the user's Claude Code
  with `--tools ""` (no shell, no files), `--strict-mcp-config` with skil.li's
  bridge (`--run <id>` ties the connection to the command's `AgentContext`:
  its tool groups, selection and app) plus the servers it names,
  `--allowedTools` for skil.li's tools (skil.li approves them itself) and
  `--permission-prompt-tool mcp__skilli__approve` so other servers' tools are
  approved in the card too. Steps come from stream-json (`AgentStream`).
  Measured: read + approve + replace on Haiku in ~5 s.
- Ask (built-in `ask`, ✦A, and Tab in the launcher with the typed text):
  the instruction is typed in the card (or comes from the launcher), then
  `AskRouter` picks answer / rewrite / act in one typed decision (Jev first,
  then OpenAI Decisions; only the instruction, "selection: yes/no", the
  app's name and, when the agent can run, the connected servers' names with
  up to 12 tool names each are sent, never the selection). Answer → card;
  rewrite → replace; act → the agent with every tool group and connected
  server. No key: the agent decides (or Claude answers without Claude
  Code). The launcher also lists the user's commands by name, and its last row is
  Ask “…”.
- Ask on a schedule (`AskSchedule`, `ScheduledAsk` in SkilliCore,
  `AskScheduler`, `AIActionController+Scheduled`; Settings → Ask → On a
  Schedule): "tous les lundis à 9h résume mes PR", "every weekday at 8:30
  tell me my day", "le 1er de chaque mois à 9h …": Ask's decision asks a
  question of its own, only when the request says "every", "chaque",
  "tous les"… (`AskRouter.scheduleQuestion`; as an option of the route
  question it moved OpenAI's routes of other requests): yes, the
  `schedule` route, whose values the decision model reads
  (`AskValues.schedule`: how often, the weekdays one by one, the day of
  the month, the time or a part of the day, 9:00 when none, and what to
  do as a phrase of the request without the words saying when); without
  the scheduler, the agent with `add_scheduled_ask`. A repeating reminder
  or event ("rappelle-moi tous les lundis de…") is Calendar and
  Reminders' (`plans`, which repeat on their own). The card says it back ("Every Monday at 9:00:
  résume mes PR", First: …), Keep ↩ keeps it silently, esc keeps nothing.
  Kept in `scheduled-asks.json`; one timer for the next time (never a poll),
  set again on wake, clock and time zone changes. Each time runs once, out
  of sight, as Ask would: the route from the request alone; an answer by
  the writer, a Mac command or an app at once, the rest by the agent
  without the selection, screen, menus or settings groups (its approvals
  take the card as an outside agent's). Missed while asleep or off: once,
  a minute after the wake or start. The answer is kept on the row and
  shown as Ask's card (⇥, ↩, ⌘↩) once the user is there: card free,
  launcher closed, screen on and unlocked (macOS's notifications), no key
  in the last 2 s; never a user notification (a permission more, a line
  without the card's keys; the card waits, the row keeps it). Rows: when,
  what, the last run's line (a click shows it again), a switch (off: its
  times are not caught up), −; + takes a sentence. Tools (settings group,
  every change asks every time): `list_scheduled_asks` (the last answer
  only as set), `add_scheduled_ask`, `pause_scheduled_ask`,
  `remove_scheduled_ask`. `selftest schedule` (the clock moved ahead to
  fire one early).
- Skills for Ask's agent (`AgentSkill` in SkilliCore; Settings → Ask →
  Skills): folders holding a SKILL.md in
  `~/Library/Application Support/skil.li/skills`, and `~/.claude/skills`
  when "Use Claude Code's skills too" is on (only SKILL.md files read
  there). `AgentRun` hands them to Claude Code as its own skills: a plugin
  folder made for the run (`--plugin-dir`, a link per skill, removed with
  the run), `--tools Skill` (no `--disable-slash-commands`: it turns skills
  off), `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1` and `skillOverrides` for
  the built-in plugins' few; `--setting-sources ""` loads none of the
  user's own (checked on the mini, 2.1.296). No skill: the old flags.
  Agents write one with `create_skill`.
- Contacts (`ContactSearch`, `ContactRecord` in SkilliCore, `ContactBook`;
  Permission `.contacts`, entitlement `personal-information.addressbook`,
  NSContactsUsageDescription): read through the Contacts framework once the
  user allowed it, asked where first needed (`ContactBook.allow`: Ask's
  contact route and `search_contacts` show macOS's question; the "@"
  mode's Allow Contacts row asks right there; Your Details and Privacy
  have its row; never in the self-test, `asksTheMac`), kept in memory
  and read again on CNContactStoreDidChange. Every field but the note: the
  note needs Apple's `com.apple.developer.contacts.notes`, granted on
  request (macOS 13+), not asked for yet, so the key is never fetched.
  Searched without a model, accents ignored: names (10), nickname (9),
  company (8), email (6), job (5), department (4), related people (3),
  address and web (2), phone digits ("06 12…" matches "+33 6 12…"); a
  whole word counts more than its start, a typo or a part; the words that
  only carry the sentence ("qui est le contact … chez") are dropped. The
  launcher's Contacts mode ("@" or "contact …", Search Contacts) lists them
  with where they matched; the best two (a name or a company) also show in
  any search. Return shows the contact's card, the same from Ask's "qui
  est …" (`ContactCardView`, a `CardContent` in the card; 2026-10-16:
  the Markdown one was "designed pretty badly and useless"): as Apple's
  Contacts shows one, the photo (`ContactBook.thumbnail`) or the monogram
  on Contacts' gray, the name, job · department · company, then each
  field with its label on the left in Contacts' order
  (`ContactRecord.cardRows`: the mobile first). Its keys: ↩ reaches them
  (a message with a number, else a mail; nothing sent), ⌘↩ opens
  Contacts, ⌘C copies the name, ⇧⌘C the first number, ⌘K the launcher's
  own list for the contact (`ContactActions`, one list for both, less
  Show Contact): typing filters, arrows move, ↩ runs, esc goes back to
  the card.
  Agents: `search_contacts`, `compose_email` (Contacts tool group).
- Ask and contacts (`AskValues.contact`, `MailDraft` in SkilliCore): the
  `contact` route ("qui est …", "le numéro de …", "who is …", "crée /
  écris / envoie un mail à …"), then the decision model reads who or a
  mail, the person as a phrase of the request's own words, and whether it
  says what the mail should say. The person is searched here, in
  Contacts (`ContactSearch`); the contacts never leave the Mac, only the
  request does, as for any Ask. Who someone is with no contact of that
  name ("qui est Emmanuel Macron"): answered in the card.
  One contact well ahead (score ≥ 7.5, 30 % above the next): its card (as
  from the launcher), or a new mail to their address; close ones: "Which one?" as keycaps. When
  the request says what the mail is about, the user's AI writes subject
  and body first, in the card, then the mail app has it (nothing sent).
- Agenda (`AgendaEvent`, `MeetingLink`, `AgendaRequest`, `Agenda` in
  SkilliCore, `CalendarBook`; Permission `.calendar`, entitlement
  `personal-information.calendars`, NSCalendarsFullAccessUsageDescription):
  every account the Calendar app has, through EventKit, asked for at first
  use (macOS's prompt: `CalendarBook.allow`, the agenda, Ask, the tools)
  or from Settings → Calendar or Privacy; the menu bar's meeting and its
  alerts show once it is allowed. Parity target: Raycast's
  Calendar and Tinycast's meetings, said rather than filled in. The next
  meeting is one that started up to 15 min ago, else the first to come
  (never all-day or declined); from 10 min before to 10 min after its start
  it is the first row of the empty launcher, and "join", "réunion",
  "prochaine réunion"… put it first while typing. Return joins the call
  (Zoom and Teams in their app when installed: `zoommtg:`, `msteams:`;
  the 15 services Raycast knows, found in the event's URL, location or
  notes), else shows the event in Calendar; ⌘Return shows it in Calendar
  (its scripting dictionary, day view: Calendar has no link to one event);
  ⇧Return writes to whoever is invited (mailto). Agenda mode ("cal …",
  "agenda …", Agenda): three months in Raycast's order (today, tomorrow,
  this week by day, next week, the rest of the month, then by month),
  filtered by title, calendar, place or invitee; ⇥ shows the event in the
  card. Copy Availability: free time in the next 5 working days (9–18 h,
  slots of 30 min or more), copied with Return. Ask, its `plans` route
  then what is asked read by the decision model (`AskValues.plan`, see
  "Ask never acts on a regex reading of a sentence"):
  "prochaine réunion" / "next meeting" (the card), "rejoins la réunion" /
  "join the call" (joined at once), "qu'est-ce que j'ai demain", "mon
  agenda jeudi", "what do I have today" (the day), "mes dispos", "my
  availability", "suis-je libre jeudi après-midi", "am I free tomorrow at
  3pm" (busy or free then, and the free time around). Events said in one
  sentence (`EventRequest`, `SpokenWhen` in SkilliCore, French and
  English): "rdv demain 14h point budget avec Paul", "ajoute à mon agenda
  dentiste jeudi 9h30 #perso", "réunion de 14h à 15h vendredi : notes",
  "schedule standup every weekday at 9:30 for 15 min", "… rappel 10 min
  avant", a link; a day alone is all day; "bloque 2h demain matin pour
  écrire" / "block 1 hour tomorrow at 4pm" keeps time. The launcher offers
  it first ("Add “…”", also "réunion budget demain 14h"), ↩ adds it (the
  launcher's typed grammar: `EventRequest`, `SpokenWhen`). Ask reads it
  with the decision model (`AskValues.plan`: the start's day and time as
  parts, how long or until when, the title as a span without the words
  saying when) and adds it at once when what times it is sure, else the
  card says what it understood and ↩ adds it. The card says where it went: ⌘Z takes it back, ⌘↩ shows it
  in Calendar. Agenda: ⌘⌫ deletes that occurrence at once, Undo ⌘Z for
  10 s (`offerUndo`) makes it again with its fields; an event with
  invitees asks first (`AIActionController.deleteEvent`).
  Agents: `list_events` (with ids and the calendars), `create_event`,
  `update_event`, `delete_event` (Calendar tool group; the changes wait
  for the user's OK in the card). Settings → Calendar (`AgendaPane`,
  `MeetingWatch`; the menu bar, the alerts and When a meeting starts
  first, the rest under Advanced, the long list last): the launcher's
  window (2–30 min, Advanced), the next meeting in its own menu bar item (never, as
  it starts, 5, 10 (default), 30 min or 1 h before, or always; only
  meetings with a call by default). Its moments look apart at a glance
  (2026-10-16: "i don't know if i'm very late or just still have
  time"; `MeetingBar` in SkilliCore: the state, words, glyph and the
  moments it changes; `MeetingWatch.appearance` draws it): coming, a
  template calendar and "Weekly sync · in 12 min" ("at 14:30" an hour or
  more away); a call started and not joined, the camera in the system's
  red (as the card's "STARTED … AGO") and "Weekly sync · started 3 min
  ago" ("starting now" its first minute), up to 15 min after its start
  (the next meeting's window); on, the template ring that empties and
  "Weekly sync · 20 min left". Joined is only what this Mac can tell:
  Join from skil.li (card, menu, launcher, Ask, as it starts;
  `CalendarBook.joined`, per occurrence, `onJoin` redraws at once), or
  another app taking a microphone from 10 min before its start
  (`MicrophoneUse`: CoreAudio's process objects, skil.li's own use left
  out, read again when CoreAudio's listeners say an input started or
  stopped, never polled; started only from 11 min before a call the menu
  bar, an alert or Join at once watches, so CoreAudio stays out of
  skil.li at launch; kept once seen). A call on the microphone since
  earlier is the meeting before running over: still red. So is one begun
  while another meeting with a call, begun before this one, was still on
  (`MeetingBar.joined` among the day's events; back to back, or the one
  before joined late: a 9:45–10:00 call joined at 9:51 does not join the
  10:00 one). Left in its last minute for the next one, it cannot be told
  from staying: only skil.li's Join says so then. A Mac without a
  microphone cannot tell: the camera without red, "started 3 min ago",
  and its help says so. The item's help (tooltip) says when it starts or
  ends and why it is red. "Count down to its end" (on by default): the
  ring and the time left until it ends, else (joined) "Weekly sync · now"
  and it leaves 5/10/15 min after its start or at its end; "The next one
  too, during a meeting" (on by default): once the next one is that close
  the bar stays short, "12 min left · then Standup 14:30" (never a bare
  "12 min" read as the time to the next one), and the menu adds "Next: …"
  with its own Join; the menu joins, shows it in Calendar, opens the
  agenda, dismisses);
  "Alerts" (`MeetingAlert`, `MeetingAlerts` in SkilliCore): each On
  time or 1, 2, 5, 10, 15, 30 min or 1 h before, as the card or the card
  with every screen dark around it; each once at its minute (the Mac
  asleep then: nothing late); none for a call the user is in already,
  joined as the menu bar tells it (`MeetingBar.inCall`, `MeetingAlerts.shows`:
  Join from skil.li, or the microphone since just before its start; one
  on the microphone from long before, or begun during the meeting before,
  still alerts, as it is still red);
  Try shows it now on a sample; the preview
  is the card's own view. The card (`MeetingCard`, `MeetingCardView`):
  one glass card in the middle of the screen the pointer is on, a
  non-activating panel at the screen saver's level that takes the keys
  only when the user is not typing; "STARTS IN 4:58" counting each second
  (mint dot), "STARTING NOW", "STARTED 2:05 AGO" (red); the span; the
  name on two lines at most (26 pt); the call or the place and the
  calendar; who is in it (faces of initials on a color of their own, the
  same name the same color); then Dismiss esc, Calendar ⌘↩, Join ↩ (the
  one filled control, mint). Without a call: Got It ↩, Calendar ⌘↩. It
  leaves at the meeting's end, or as soon as the user is in the call
  (Join from the menu bar, the launcher or Ask, or the microphone taken
  for it: `MeetingWatch.onInCall`, at each refresh), the screens dark
  around it coming back. With a call, "Camera & Mic ⇥" beside
  Dismiss (`MeetingCheck`, `MeetingCheckView`): ⇥ or a click opens, under
  who is in it, the camera live (macOS's preferred camera, mirrored, 16:9,
  radius 14) and one line: the camera's name, the default microphone's name
  and its level (a capsule in the accent color, from the audio channel's
  power); the card grows down, its top kept. No camera: the line alone
  ("No camera"); not allowed: said, a click opens Settings → Privacy.
  macOS's camera question is asked there only (the card steps down to the
  floating level while it shows). Nothing recorded; stopped as the card
  goes or ⇥ closes it, before a call is joined. `selftest card` captures it
  on a still image (the mini has no camera). Screens dark (`ScreenDimmer`): each screen
  blurred and darkened under the card, menu bar and Dock included; a
  click on the dark lets it go. The card takes the keyboard unless the
  user was typing in the last second; with the screens dark it takes it
  even then (2026-10-16: ↩ joins, esc dismisses, hands on the keys),
  the keys of its first half second swallowed and any other key doing
  nothing while it is dark. "When a meeting starts": nothing more, or
  joined at once (then no alert On time for it; not for a call the user
  is in already, `MeetingAlerts.joinsAtOnce`: it would open twice); the old "Ask to join"
  (and its screens dark) became an alert On time. "Events without a call
  too", off by default, for the alerts. Then the app ⌘↩ opens events in, the browser for
  Google Meet; then every calendar grouped by account (`EKSource`: iCloud,
  each Google account, Exchange, this Mac; subscribed and birthdays last)
  with its color. Hidden calendars are saved by `calendarIdentifier` (two
  accounts may each have a "Calendar"); names saved before turn into the
  identifiers of every calendar with that name once they can be read.
  Nothing polls: one timer for the next change (each minute while a
  number is said: in 12 min, started 3 min ago, 20 min left), set again
  on EKEventStoreChanged, wake, day, clock or time zone change, settings,
  a Join from skil.li and the microphone taken or let go. `selftest
  meetingbar` (also in `card`): each moment from stand-in events and a
  stand-in microphone (the real one's reading is said),
  the menu's Join; no alert and no Join at once for a call joined
  already (the menu's Join, the microphone since just before, the menu
  bar off too; one on it from long before, or the meeting before's back
  to back, still alerted, red), a card up gone
  as the menu's Join or the microphone joins it, the screens back
  (`meetingAlertsNotWhenJoined`); captured where the mini's menu bar shows it
  (`meetingbar-<moment>.png`, then `-bar-light` / `-bar-dark` with the
  item's appearance set) and drawn alone over a light and a dark menu bar
  (`-light`, `-dark`: a status item's window number is past
  `CGWindowID`'s range, out of a window capture's reach), and Settings →
  Calendar's preview light and dark (`settings-calendar-menubar-*.png`).
  EventKit
  cannot answer an invitation or invite anyone (attendees and their status
  are read-only): those stay in Calendar. Reads stay on the Mac; today's
  and tomorrow's events are kept in memory until EKEventStoreChanged.
- Reminders (`ReminderItem`, `ReminderRequest`, `RemindersRequest`,
  `Reminders` in SkilliCore, `ReminderBook`; Permission `.reminders`):
  every list the Reminders app has, through EventKit, asked for at first
  use. Parity target: Raycast's Apple Reminders, said rather than filled
  in. Quick add in one sentence (French and English, `SpokenWhen` for the
  date): "rappelle-moi d'appeler Paul demain 9h", "remind me to call Paul
  tomorrow at 9am !!", "todo acheter du pain #courses" (`#` a list, `!`
  `!!` `!!!` or "urgent" the priority), "rappel payer le loyer tous les mois
  le 5" (repeats), a link, notes after ": ", "lire cet article" / "this
  page" (the page in front goes with it: `BrowserTabs.frontPage`, its web
  area's AXURL). The launcher offers it first ("Remind Me: …", Return adds;
  `ReminderRequest`, its typed grammar). Ask reads it with the decision
  model (`AskValues.plan`: what it says and where as spans of the
  request's words, when as parts or a delay, how often, a list or a
  priority kept only when sure) and adds it at once when what times or
  places it is sure, else the card asks first. The
  card says which list: ⌘Z takes it back, ⌘↩ opens Reminders. Reminders
  mode ("todo …", "rappels …", Reminders): Raycast's order (overdue, today
  by morning, afternoon and tonight, tomorrow, later by day, no date, done
  this week); ↩ checks one off where it is (the row stays, its circle
  fills), ⌘↩ opens Reminders, ⇧↩ its link, ⌘K (or ⇥) its actions (done,
  tomorrow, next week, a date typed, another list, priority, make it an
  event, copy, delete). Tomorrow and Next Week (its Monday; the time kept:
  `Reminders.moved`) change the row where it is: the launcher stays, the
  row goes to its day and stays selected, nothing said; ⌘Z puts it back
  for 10 s. A date typed, a list or a priority are asked in the card,
  then done with ⌘Z for 10 s (`offerUndo`: "Reminder Moved", "Priority
  Set"). ⌘⌫ deletes at once, Undo ⌘Z for 10 s (`offerUndo`) makes it
  again with every field (`AIActionController.deleteReminder`); a
  reminder changed in place drops an undo card still up, so ⌘Z is
  always the latest change's. What is typed and fits nothing is
  offered to add. Ask (`plans`): "mes rappels", "qu'est-ce que j'ai à
  faire aujourd'hui", "my reminders" (today and overdue), "en retard",
  "tous mes rappels". Agents: `list_reminders`, `create_reminder` (list,
  priority, repeat, link), `update_reminder`, `delete_reminder` (changes
  wait for the user's OK). EventKit has no tags: Raycast's tags are not
  offered. Settings → Reminders (`RemindersPane`, `ReminderWatch`): where
  said reminders go (a list, or the Reminders app's default); today's in
  the menu bar (never by default, how many, or how many and the next;
  hidden when none; its menu checks one off, shows them in skil.li or
  opens Reminders; read again when reminders change, on wake, day or clock
  change, or when the next one falls due, never polled); places (a name
  and an address Apple Maps turns into a place, `MKGeocodingRequest`):
  "rappelle-moi d'acheter du pain en partant du bureau", "remind me when I
  get home" ring there (EKAlarm with a structured location, arriving or
  leaving; maison and home, bureau and work are the same place; with none
  saved under that name, home or work is the Home or Work address on the
  user's card in Contacts, found once on Apple Maps, as Apple's Reminders
  does, `ContactBook.myAddress`; an unknown place says where to add it). "répondre à ce mail" / "this
  email": the message selected in Mail (`MailSelection`, Mail's scripting
  dictionary, only when Mail is in front) goes with it, its subject in the
  notes and a message:// link back to it.
- GitHub (`GitHubInbox`, `GitHubNotifications` in SkilliCore; `GitHubBook`,
  `GitHubClient`, `GitHubStripView`, Settings → GitHub): the user's open pull
  requests and those waiting for their review, in four groups (ready,
  blocked, waiting, testing) decided by GitHub's own merge box
  (`mergeStateStatus`: CLEAN / HAS_HOOKS is ready only when the user can
  merge — write access or admin bypass —, else the maintainers' turn;
  BLOCKED says why from the review decision and the checks; BEHIND,
  DIRTY, UNSTABLE are never ready; UNKNOWN is "GitHub is checking"; the
  merge queue is testing). No heuristics of our own on top (asked
  2026-10-15: "there's an official way"), and their unread notifications.
  Pull requests come from one GraphQL request (`GitHubInbox.query`: commit
  statuses such as Woodpecker's and Vercel's included, the repository's
  default merge method; Merge offered only with write access,
  `viewerPermission`); notifications from `/notifications` with
  `If-Modified-Since` (304 costs nothing), at GitHub's `X-Poll-Interval`.
  Signing in: GitHub's device flow (a code, copied, typed on
  github.com/login/device; the token in the Keychain as `github-token`,
  `selftest-` for the self-test) with the OAuth app "skil.li" (owned by nomdelasociete, device flow on,
  tokens that do not expire: renewing them would need a client secret) and
  its public client id in `GitHubOAuth.publishedClientID`
  (`GITHUB_OAUTH_CLIENT_ID` overrides it);
  scopes `repo notifications read:user`. The strip under the search field
  (Settings → GitHub → Show under the search field, on by default, once
  signed in): the counts in Git Island's colors and the unread
  notifications; a click opens the GitHub mode on that group. Nothing asks
  GitHub unless the strip shows (or the mode, a tool): then one timer,
  every 15 s while checks run or 2 min after a change, else every minute;
  on wake and network return; on each launcher show when older than 15 s.
  With a relay origin (Settings → GitHub → Advanced → Live updates from, or
  `RELAY_PUBLIC_URL`) and a sealed
  stream token in the Keychain (`relay mint`, account `relay-token`), the
  strip or GitHub mode holds one `GET /stream`. A connect, reconnect, or
  wake refetches pull requests immediately; the inbox timer runs only while
  that stream is down. Notifications stay `GET /notifications` on GitHub's
  interval. No origin: the timer above, unchanged. The GitHub OAuth token
  is never sent to the relay.
  "pr " / "prs " or GitHub Inbox: the GitHub mode (grey chip; "gh " stays
  GitHub's search quicklink): Return opens (a notification is then read),
  ⌘Return copies the link, ⌘K (or ⇥) its actions (Open, the merge method,
  Update Branch, Checks, Copy Link; merging asks again in the card: Return
  twice), ⌘⌫ marks a notification read. Agents: `list_pull_requests`,
  `list_github_notifications`, `merge_pull_request` and
  `update_pull_request_branch` (changes: the card asks),
  `mark_github_notification_read`. `selftest github` (a stand-in GitHub:
  device flow, GraphQL, 304, merge, read).
- Keep Awake for a while (`AwakeRequest` in SkilliCore,
  `SystemCommands.keepAwake`): "awake 1 hour", "do not sleep 1", "garde le
  mac éveillé 2h", "caffeinate until 6pm", "pas de veille jusqu'à 18h30",
  "allow sleep" typed in the launcher (whole words, accents ignored; a
  bare number is hours up to 24, minutes above; "until/jusqu'à" a time,
  today or tomorrow) show "Keep Awake · 1 h (until 14:05)" first. The
  same power assertion as Keep
  Awake, released by a timer; the status menu says "Keeping the Mac Awake
  until 14:05 — Allow Sleep". Plain "keep awake" stays the toggle. That
  grammar is the launcher's only: in Ask, the route picks Keep Awake and
  the length or the end time is read by Jev (`AskValues`, see "Ask never
  acts on a regex reading of a sentence"); unsure, done with ⌘Z.
  Agents: `keep_awake` (minutes, until, sleep). While awake, a cup in the
  menu bar with the time left ("59 min", "1 h 20"; `AwakeIndicator`), its
  menu: until when, Allow Sleep.
- Ask and connected services (`ServiceMention` in SkilliCore): the act route
  reads "look something up in, or do something with, one of their connected
  services". A request that names a connected server ("nimbus deployment" or
  its distinctive first word "nimbus", accents, dashes and case ignored) is
  noticed without a model and told to the decision ("The request names the
  connected service …"); words that are a tool's subject ("deployments" in
  listDeployments) are told as a hint. If the decision still picks another
  route, the card puts it to the user: "Use nimbus-deployment" first (↩), the
  other routes as keycaps. `selftest decide` (real Jev and Decisions, a
  stand-in list of services), `selftest card`.
- Ask's *control* route, "do it here" (`ComputerControl`, the pure part
  in SkilliCore's `ScreenControl`): acts in the window in front toward a
  goal, step by step (12 at most). Each step reads the window
  (`UIReader.snapshot`: Accessibility elements with their frames; the app's
  menus; with fewer than six things to press, or when the model found
  nothing to act on among them (once a step), the words on screen), keeps
  the ≤ 150 items the goal names first (`ScreenControl.candidates`), and
  asks the decision model in one request: the next step (click, type, key,
  scroll, done, stuck), the item (a Choice over the items' ids), the key,
  whether the steps done already finish the goal (≥ 50 %: done; a dialog's
  last button after its choices finishes it), whether the goal cannot be
  taken back, and, with a profile, which detail goes in the field. Jev only picks among what was
  read; text to type comes from the goal's quotes (`« … »`, `"…"`), then
  the writer (Claude: "only the text, or ASK"), then the user in the card.
  It acts through Accessibility (press, focus, set the value; off the main
  thread, 2 s at most: an app opening a modal dialog may hold its reply),
  else the mouse at the item's middle (the card lets the click through); a
  ring shows the item first (`TargetHighlight`). Reading is bounded:
  0.5 s per Accessibility call, 2 s per window (`UIReader.snapshot`), 1.5 s
  for the menus (`MenuReader.items`), the first 25 rows of any list (a save
  dialog's file browser would fill the 200 kept). An open menu's items (a
  pop-up's list: "Format du fichier" → PDF) are read too. A goal that sends,
  shares or publishes nothing never gets an item that does
  (`ScreenControl.isOutbound`: "Envoyer au format PDF", "Partager › Mail";
  a menu item by its whole path). "Nothing" is the goal's own verbs
  (`ScreenControl.mayAct`, `asksToSend`), never Jev's "risky" alone: Jev
  ranked "Partie › Partager › Mail" first (60 %) for "joue le prochain
  coup" in Chess. A goal that asks to submit ("valide", "inscris-moi")
  may press a form's own "Envoyer" / "Send" button, never "Partager" or a
  menu item ("signale ce mail" is no submit). A save dialog's last button
  (`isFinalSave`) waits until the sidebar place the goal names ("dans mes
  documents" → Documents, "sur mon bureau" → Desktop: folder names in
  English and French, `ScreenControl.place`) is clicked first, before the
  model's pick, as soon as the dialog's final button shows. Choosing the
  same menu item twice ends the run. A label that sends, deletes,
  pays, buys, publishes (`ScreenControl.isRisky`, French and English), or
  Return in such a goal, or Replace (overwriting a file), is asked first
  ("Do It" ↩ / "Stop"). Under 40 %
  with others close, the user picks among the best three. Passwords are
  never typed. After each step it waits for the window to change (1.5 s at
  most), stops when the same step repeats three times. The card shows the
  steps live and goes once done (the log keeps "Done by Jev · 3 steps ·
  2.1 s"); it stays only to say why it stopped. The route stays
  "do it here" whatever the menus say: it sees them too, and a sure menu
  item is often only the first step ("Envoyer au format PDF" is not "export
  to Documents"). `selftest control` (Mac mini, the user's key):
  `Skilli testform <state.json>` opens a real AppKit form in a second
  process; a French goal fills it from quotes, ticks, saves; through Ask;
  from a card (the user's, then "pour Margot"; no value in what was sent);
  delete asked first; a drawn "Archive" read on screen and clicked; then
  "exporte en PDF dans mes documents" through Ask in TextEdit and in Word
  (skipped when Word is not activated: read-only).
- "Do it here" sees the window (`ScreenControl.pictureNeed` / `isUnsure`,
  `WindowPicture` in SkilliCore; 2026-10-15): where what was read says
  too little, Jev gets one picture of the window in front with the words,
  in the same request. Too little is measured: things to press with no
  words (`ScreenItem.isWordless`: an icon-only button; every one is
  offered then, named by its place, "3rd of 6 in a row · bottom left" —
  `wordless`),
  fewer than six things with words beside words read on screen
  (`drawn`: a canvas, a web view), or, read in words, under 50 % for the
  item to click or type into (`unsure`: asked once more, with the
  picture). A goal that names an item by all its words ("clique sur
  Snooze", read on screen) is asked in words first, the picture only if
  they are unsure (`ScreenControl.goalNames`: with the picture first, Jev
  once took Safari's Back button for a drawn “Snooze”); such a step offers
  only items with words. Items without words make the look read the
  screen's words too, in the capture the picture reuses. A JPEG of that window only (ScreenCaptureKit's
  desktop-independent window; the capture the words were read in when
  there is one), its longest side one pixel a point from 512 to 1024,
  padded on white to 280 a side like `JevImages.jpeg`; the state becomes
  `{step, window_picture}` (`DecisionClient.reply`). Jev still picks among
  what was read: the click is an Accessibility action or a click at a read
  item's frame, never at a place the model says. Never without Screen
  Recording or a TypeSafe key (OpenAI Decisions decides from the words),
  never with a password field read or Secure Input on. An item without
  words picked for a goal that cannot be taken back is ringed and asked
  first. No switch of its own: it happens only with Screen Recording on,
  granted for "do it here"; Settings → Privacy says it (`PrivacyMap`'s
  "Doing it here", the permission's line). The card says "Looking at the
  window…" while Jev looks. `selftest sight` (also in `control`, Mac mini,
  the user's TypeSafe key): `Skilli testform <state.json> photos` (six
  icon-only buttons Accessibility has no words for) and a Safari page
  (icon-only buttons, a canvas), each goal in words then with the picture;
  report and captures in `dist/remote/doit-vision-*`.
- "Do it here" clicks what it sees and thinks first
  (docs/click-what-you-see.md; 2026-10-18: "unleash skil.li
  capabilities in every app", Chess as the showcase). With a picture, the
  target question also offers `spot` (`ScreenControl.spotID`): something
  only drawn (a board, a map, a canvas). `pickSpot` finds it in two looks,
  the window then a close-up at the capture's own pixels
  (`WindowPicture.closeUp`): Jev's Box (TypeSafe's Box question, Jev 1.14,
  `JevImages.locate`, with a Noul "is it there"), back on screen with
  `WindowPicture.unplace`; ringed, clicked, settled on the picture
  (`PictureChange`: a canvas's Accessibility does not move). A numbered
  grid (`CanvasGrid`, `SpotWay.grid`) stays only to measure: Jev does not
  read its numbers back, and Claude pointing in one picked the wrong
  column. A next step to work out (a move, a puzzle: Jev's `thinks`) is
  planned by the writer, Claude Opus when the writer is Claude
  (`AIActionController.planSteps`; the window's picture to Claude only,
  `AIRequest.images` as image blocks): one standalone click or key a line,
  a drawn thing by its look and where it is next to things easy to see,
  or DONE / STUCK; Jev grounds each line (an item, a key, or `spot`, the
  line as the Box's words), asked which item the plan's next line acts
  on (`ComputerControl.planTargetQuestion`), never the goal's guide about
  sending and exporting: with it, Jev put "Partie › Partager › Mail"
  first and the planned square at 20–28 % (docs/click-what-you-see.md,
  "Grounding a plan's line"); without a plan the guide stays (Word's
  export needs it). A line that quotes one enabled item's exact words
  ("Click the button “pion blanc, e2”") is that item
  (`ScreenControl.named`), whatever Jev ranked; the outbound gate still
  applies. A line that clicks an item by its words that no item read is
  (`ScreenControl.unread`; a real Chess game answered 15 of 73 elements in the
  look's 2 s, “b5” not among them, and a pawn was clicked) reads the
  window again first: a look cut short (`UIReader.snapshot`'s
  `cutShort`) every 300 ms with 6 s each for 12 s, then stops; a whole
  one once after 0.8 s. Still not read, no other item is clicked unless
  Jev is 60 % sure of it for the line: the run stops (planned again,
  Opus described the square as drawn and Jev pressed its neighbours). A line is done only by a step that did what it says
  (`PlanProgress`, `ScreenControl.follows`: its item, a click in the
  picture for it, any step for a line naming no item; never a scroll).
  Every line done and the window changed: done
  (planning again played a second move); a line clicked in the picture
  may have missed, so the writer looks again first (DONE or what is left). `selftest chess` (Mac mini,
  TypeSafe key, Claude): squares found on Chess's board hidden from
  skil.li, scored against its Accessibility frames (upside down in Chess,
  flipped back); games against its computer per chooser and finder; the
  demo through Ask, recorded with the other apps hidden
  (`dist/remote/chess-*`, `/tmp/skilli-chess.json` picks what;
  `"grounding": N` replays each request "do it here" sent, N times each
  way of asking: `dist/remote/chess-grounding.json`; `"slowLooks": N`
  cuts the N looks after a move's first press to 15 elements, as a
  slow real Chess game; `"hideTarget": true` never reads a plan's second square;
  `"slowProbe": N` picks up the f1 bishop N times and reads
  the window every 500 ms: `dist/remote/chess-slow.json`).
- "Do it here" from anywhere (docs/do-it-here-from-anywhere.md; asked
  2026-10-19: what the Chess showcase unlocks, skillies first): not only
  Ask starts it. `AIActionController.doItHere` runs it for a link or a
  tool, in the app named (`ControlTarget.bringForward`: running by bundle
  id or name, else installed and opened; Accessibility's frontmost when
  activating is declined), else the app the caller came from, never
  skil.li; Ask's decision keys and writer (Opus plans), every guard of
  `ComputerControl` unchanged. Its steps show in a command's own card
  while its agent calls it, else in the card taken as an agent outside a
  command takes it (esc stops it: `outsideControl`). The link
  `skilli://do?goal=…&app=…` (see Links) and the tool `do_in_app` (see
  Screen tools). No `look_at_window` picture tool for agents: the picture,
  Box and planning already happen inside `do_in_app`, skil.li never clicks
  where a model points, and a picture would leave under a read right.
  `selftest doit`: the links dry (asked, esc, a chain dropped, Always per
  goal and app, no goal), a skillie's two `open` lines through macOS
  (TextEdit exports to Documents, then Finder opens Documents),
  `do_in_app` from `Skilli call` and from a real Act agent (Haiku), and
  two skillies waiting for their step (`"$SKILLI_CLI" call do_in_app`):
  allowed and done, then its next branch; declined, its other branch; one
  stopped at its limit with its call.
- Forms from a card (`FormProfile` in SkilliCore, Settings → Your Details): "do
  it here" types the details of whom the request is for ("remplis ça pour
  Margot": the one or two words after "pour"/"for"), else the user's own
  card (My Card, `ContactBook.me`) and their fields. Whom: a person or
  company kept in Settings → Your Details (`FormPerson`, `FormProfile.match`),
  their Contacts card by name and their fields; else a Contacts card
  (first name, then family name). Someone named and not found gets
  nobody's. Fields kept in skil.li beyond Contacts (`FormExtra`: SIRET, VAT
  number, IBAN…, suggested in "Add a Field", or any) are stored in
  `Preferences.formProfiles`; a locked (sensitive) one keeps its value in
  skil.li's Keychain item `form-<id>` (`FormSecrets`, `selftest-` in the
  self-test), never in the preferences, and is typed only after "Do It" ↩
  in the card. A form filled in one go (every field and its detail known
  together) asks its sensitive details once, in one question ("Type your
  SIRET and IBAN in Safari?", `FormProfile.typingQuestion`); Stop types
  the rest without them. A detail only known at its step ("type" chose
  it) is asked there; one allowed already in the run is not asked again.
  Steps that send, pay or delete keep their own ask (rule 1). The
  model reads each detail's kind ("Postal code (code postal, ZIP)"), never
  its value; a value typed from the card reads "(filled)" in the next
  state and the step reads "Typed Margot's email in …". Addresses come
  in parts (`ContactRecord.postal`), the birthday as this Mac writes dates.
  Passwords and payment details are never filled.
- Ask's *find* chooses its item at once at 80 % and up, or once picked
  among the keycaps, unless the item cannot be taken back or ends what is
  open (`MenuCandidates.isDestructive`: `ScreenControl.isRisky` and
  `isOutbound` on its whole path, plus quit, close, clear, sign or log
  out, restart, shut down, discard, revert, force): those wait for ↩ in
  the card. Chosen at once, a note teaches its shortcut ("File › Export as
  PDF… · next time: ⇧⌘E"; none without one). Under 80 %, the best three
  as keycaps ("Send PDF" at 66 % once ran for "export en pdf"). An item
  the app refuses is said in one line with its keys, never a beep (Search
  Menu Items too). A Mac
  command the route is sure of (≥ 80 %) and its list is not: its likeliest
  from 25 %, and under 50 % the likeliest three as keycaps.
- Ask's *find* route: while the user types, skil.li reads the app's menus
  off the main thread (`MenuReader.shareableItems`: enabled items only;
  never the Window, History, Bookmarks or Services menus or "Open Recent",
  `MenuCandidates`). The menu rides in the routing request as extra Choice
  questions (≤ 254 items each plus "none"; answered in parallel, so no extra
  time). A menu item at ≥ 85 % beats the agent; it is pressed through
  Accessibility once the key's handling is done (`pressMenu`). Finding
  needs no Claude: Ask checks the text engine only for
  answer and rewrite.
- Ask's *open* route: the installed apps (the launcher's index) ride in the
  same request, with the kind each declares (`LSApplicationCategoryType`,
  `AppCandidates`): "mon app de dessin vectoriel" → VectorCraft, no agent.
  The list with a sure candidate wins between find and open (≥ 85 % vs
  < 50 %); under 60 % the best three come as keycaps. A Mac command
  route with no command that fits ("ouvre les réglages système":
  Decisions says command 40 %, act 8 %) goes to the app or menu item
  that fits from 60 %, else to the agent. The agent gets
  `list_apps`, and `open_app` only opens the app's own name (case, accents,
  a trailing version) and answers with close names instead of guessing.
- Ask unsure of its route (decision confidence < 50 %, and no sure menu
  item or app decided it) offers the routes that can work as keycaps
  ("Answer here", "Rewrite the selection", "Find it in the menus", "Open an
  app", "Do it with tools"). The launcher shows the selection Tab will work
  on: the focused element is captured just before the panel takes the
  focus (one Accessibility call, 50 ms at most), its text read after.
- Recipes (tools that do a known job the fast, sure way):
  `update_app` tries the app's own "Check for Updates…" (never an
  "Automatically…" setting; the app is launched first if needed), then the
  App Store's Updates page (`_MASReceipt`), then `brew upgrade --cask`
  (token from `brew info --cask --installed --json=v2`); macOS's own apps
  open Software Update. `send_message` (Slack, Discord: ⌘K, the name, ↩)
  reads the conversation actually opened from the window title and asks
  "Send to <it> in Slack?" before pasting and sending (`SkilliTools.confirm`
  → the card). Sending is checked by hand: a test would open a real
  conversation.
- Snippets (`Snippet`, `SnippetMatcher`, `SnippetExpansionMode`,
  `SnippetMeaning` in SkilliCore; `Sources/Skilli/Snippets`; Settings →
  Snippets): one Markdown file each in
  `~/Library/Application Support/skil.li/snippets` (front matter `name`,
  `keyword`; the text with `{date}`, `{clipboard}`… and one `{cursor}`).
  Found in the launcher by name, keyword or words (↩ types it, ⌘↩ copies
  it), by agents (`list_snippets`, `insert_snippet`), and expanded where
  their keyword is typed: `KeyRouter.onTypedKey` hands `SnippetExpander`
  the keys going on to the app in front (not the launcher's, not with
  Hyper). Settings → Snippets → Expand (`Preferences.snippetExpansionMode`):
  as soon as it is typed (the default, as before): a keyword starting
  with a symbol (";addr") expands at once; one made of letters ("addr")
  waits for its word to end (space, punctuation) and the space comes back
  after the snippet; or after a space or ↩ only, kept or left out. A
  keyword starting with a letter needs a word start before it, so
  "address" never expands. A ↩ that ends a keyword is held back from the
  app (`onTypedKey` returns true: a chat would send the keyword), then
  pressed again after the snippet when it stays (before the caret goes
  back to `{cursor}`); ⇧↩ and ⌥↩ never count. The keyword is erased with
  ⌫, the text pasted (clipboard restored), the caret moved back to
  `{cursor}`. Only the last 48 characters stay in memory, dropped on a
  click, another app, ⌘/⌃, arrows, Return, 5 s idle; never in secure
  input or the apps of "Keywords stay as typed in"
  (`Preferences.snippetExcludedApps`; password managers out of the box,
  taken from the clipboard's list once); logs name the snippet, never what
  was typed. The pane's preview is `SnippetMatcher.result`, the same
  matcher on two samples. Held keys now repeat in the launcher, not in the
  app behind it. Search Snippets ("snip ", `LauncherController.Mode.snippets`,
  a pink chip): every snippet by name, keyword or first words; ⇥ by
  meaning (`SnippetLibrary.searchByMeaning`): "mon iban", "adresse du
  bureau" go to Jev or OpenAI Decisions in one Choice, each snippet told
  by its name, keyword and first 80 characters as written (placeholders
  unfilled, never the rest; a bank or card number or a key goes as what it
  is, "(an IBAN)", never itself: `ToolCallSummary.maskingSecrets`, also in
  every clipboard excerpt; `PrivacyMap.snippets`); the likely ones (≥ 4 %)
  best first. Only on ⇥ and with Settings → Snippets → Find snippets by
  meaning with ⇥ on (default). `selftest snippets` (keys; ⇥ on the user's
  key), `selftest decide` (both providers).
- Windows (`WindowLayout` in SkilliCore for the geometry, `WindowManager`
  for the moving): halves, quarters, thirds, two thirds, maximize, almost
  maximize, center, next and previous display, restore. ✦W then a key
  (arrows, F, A, C, U I J K, 1–5, N P, R; the overlay lists them, group
  "Windows"), the launcher ("left half", "moitié gauche"), Ask (route
  `command`: window places ride with the Mac commands as `MacAction`,
  "window.leftHalf") and agents (`run_mac_command`); all go through
  `WindowManager.apply`. The same place pressed again within 1.5 s takes
  its next size (`WindowCycle`, `WindowLayout.sizes`): the halves ½ → ⅔ →
  ⅓ (left, right, top, bottom), the middle third ⅓ → ½ → ⅔; after a pause
  it starts over at the first size, or the next one when the window is
  there already (a press never does nothing). Maximize on a filled window
  puts it back. Space between windows (Settings → Windows,
  `Preferences.windowGap`, 0 by default, 4–16 pt): every place
  (`WindowLayout.place`: the whole gap at the screen's edges, half of it
  on an edge inside, so two windows have one gap between them; none for
  Almost Maximize), the layout editor's places, free spots and snapping
  lines (`LayoutSnap`). Next and Previous Display: a place ✦W gives stays
  exactly that place there, gap included
  (`WindowLayout.moved(_:from:to:gap:)`); any other frame keeps its place
  in proportion. Always on Top is not offered: macOS has no public way to
  set another app's window level (Accessibility has no level attribute;
  `CGSSetWindowLevel` is private and only acts on the caller's own
  windows, or on all through code injected into the Dock with SIP off,
  as yabai does); a mirror of the window in a floating panel would be a
  workaround. Other apps'
  windows move through Accessibility (focused window, size → position →
  size, `AXEnhancedUserInterface` off while moving, 0.5 s messaging
  timeout); skil.li's own windows through `NSWindow` (Accessibility into
  skil.li from skil.li can deadlock). Frames are top-left, y down, like
  Accessibility's (`WindowManager.topLeft`). Restore goes back to where the
  window was before skil.li first moved it, unless the user moved it since.
  Full-screen windows are refused with a message.
- Browser tabs (`BrowserTabs`): Safari, Chrome, Arc, Brave, Edge,
  Chromium, Vivaldi, Opera, Firefox, Zen read through Accessibility, no
  Automation prompt. Safari 26 lists its tabs as AXRadioButton/AXTabButton
  in an AXOpaqueProviderList (its only AXTabGroup is the page); others
  under a tab group; never inside AXWebArea. A window with no tab buttons
  is one tab. "tab github" / "onglet …" or Search Tabs: the Tabs mode
  (indigo chip); Return activates the browser, raises the window, presses
  the tab. Agents: `list_tabs`, `focus_tab`. `selftest browser` runs only
  this check (Safari, two local pages; keys).
- Quicklinks (`Quicklink` in SkilliCore, `QuicklinkStore`, Settings →
  Catalog → Quicklinks): a keyword and `{query}` in an address, in
  `~/Library/Application Support/skil.li/quicklinks.json` once edited
  (Google g, YouTube yt, GitHub gh, Wikipedia wiki, Maps map, Translate tr
  shipped). "g skilli" is the first row; a quicklink picked by name puts
  its keyword in the field for the query; text that matches nothing on the
  Mac offers "Search Google for “…”" before Ask. Only http(s) addresses;
  the query is percent-encoded whole (&, =, #, / too). Opened through
  `ActionRunner` (the self-test records instead).
  Nothing typed for one that takes a query: the text selected where the
  launcher opened is the query (`quicklinkQuery`, `Quicklink.query(fromSelection:)`:
  one line, 1,000 characters at most), the row says it ("Wikipedia · Tour
  Eiffel", "selected text"), ↩ searches at once; nothing selected, its
  keyword goes in the field as before. Reuse an open tab (Catalog →
  Quicklinks, `Preferences.quicklinkReuseTab`, off by default: it replaces
  the page in that tab, a new tab never loses anything): the default
  browser, when its dictionary lists tabs with addresses and loads one
  (Safari, Chrome, Brave, Edge, Chromium, Vivaldi; not Arc, Firefox, Zen,
  Opera), with its Automation permission (asked as the switch turns on
  while it is open, else by macOS the first time): a tab on the same site
  (`Quicklink.tabToReuse`: the same page first, then the one in front of
  its window, front windows first) gets the address and comes forward
  (`BrowserTabReuse`, AppleScript, 3 s at most); anything else opens
  normally. Add from Library… (a menu by group): `QuicklinkLibrary`, 23
  ready ones (Google Maps gm, DeepL dl, WordReference, MDN, Apple
  Developer adev, npm, Amazon.fr amz, Leboncoin lbc…), added one by one,
  never by default; one already there (same address) shows checked; its
  keyword dropped when one of the user's has it.
- Timers (`TimerRequest` in SkilliCore, `TimerCenter`): "timer 10 min
  pâtes", "minuteur 1h30", "timer 1:30", "pomodoro" in the launcher (a
  Start Timer row). In Ask, a timer is a route of the decision ("Start a
  timer", never a reminder at a time or a day), its length read by Jev
  and its name picked among the request's words (`AskValues`); unsure,
  started with ⌘Z (which cancels it). The nearest counts down in the menu bar (its own
  item, "+2" for more; the menu cancels); at the end the Glass sound and
  a card. "timer", "minuteur" or "chrono" typed out lists the running ones
  (Return cancels), never first and never on "t" or "c": c↩ for Chrome
  must not cancel a timer. Saved in
  UserDefaults (the self-test's own suite), back after a relaunch; 24 h
  at most. Agents: `start_timer`, `list_timers`, `cancel_timer`.
- Window layouts and Switch Window (`WindowArranger`, `WindowLayoutPlan`
  and `DisplayFingerprint` in SkilliCore, `Displays`, `AXWait`): "save
  layout Coding" in the launcher saves every standard window of the Dock
  apps, minimized, full-screen and hidden apps' too (bundle, title, rank,
  frame, state, the file it shows from `AXDocument`, its display), the
  hidden apps, and the displays by who they are, as JSON in
  `~/Library/Application Support/skil.li/layouts` (`screens` still
  written for older builds; layouts without `displays` still work).
  A display's fingerprint: maker, model, EDID serial (CoreGraphics), the
  text serial and week of manufacture (I/O Registry `DisplayAttributes`
  on Apple silicon), and macOS's id for it
  (`CGDisplayCreateUUIDFromDisplayID`). Never its name alone: a
  Samsung display calls itself "SAMSUNG". A serial makes it sure (`unit`);
  without one, or with one that two connected displays share, only the
  model (`model`), told apart by macOS's id. Nothing is saved before it
  is looked over: "save layout Coding", the New Window Layout command,
  Settings → Windows and ⌘K → Update to the Windows Open take every
  window into the layout editor (`LayoutEditorController`, `LayoutDraft`,
  `LayoutEditorView`; SwiftUI, built on open, released on close); New
  Empty Window Layout (launcher, Settings → Windows) opens it with the
  displays only. A layout also opens files, folders and links
  (`Window.opens`, `LayoutOpening`; the editor's "Opens when applied", +
  File or Folder… / Link… (typed in its own popover, so Return never
  saves the layout), − on each): each is a window on the canvas of the
  app that opens it now (the default browser, the Finder), placed and
  dragged like the others. Applied, one is opened (in the background)
  only when no window of that app shows it yet (its file, the page's
  address from AXDocument or the web area's AXURL, a file's or folder's
  name as the title); an app not running starts with them; the window it
  shows in takes its place (the one that shows it, else the first new
  window, else for a link the window in front), woken by Accessibility,
  4 s at most. Taken anew (Update, "save layout" with its name,
  `save_window_layout`), a layout keeps what it opens. Add App (the apps open, or Other App… for any app
  installed) puts a window of it on the display in use, on its first free
  half or quarter (`LayoutSnap.freeSpot`); an app's ⋯ adds another window;
  Remove from the Layout or ⌫ takes a window out (unticking only leaves it
  out); Clear empties the layout. There,
  apps and windows are kept or left out (left-out apps are remembered in
  the layout's `ignoredApps` and stay out when it is taken anew; apps in
  Settings → Windows → Always leave out show unticked), each window's
  state is chosen (open, in the Dock, full screen), an app can be hidden
  once in place, and windows are dragged and resized on a picture of the
  displays (`LayoutCanvasMap`), sticking to edges, quarters, thirds and
  halves (`LayoutSnap`; ⌥ places freely) or put by the same places as ✦W.
  Displays not connected are dashed; a seal says whether a display is
  known by its serial. Try It puts the windows there without saving;
  Return saves (a name already used is replaced, said in orange), esc
  cancels. ⌘K on a layout: Apply, Edit Layout…, Update to the Windows
  Open…, Copy Name, Delete Layout (at once, its shortcuts with it; the
  card offers Undo ⌘Z for 10 s, `offerUndo`, which puts both back:
  `UndoableDeletes.layout`). Settings → Windows (`WindowsPane`), in the
  Settings rules' order: how to reach it (✦W from Left Half's shortcut as
  keycaps, "save layout"), Accessibility only while it is missing, Space
  between windows with its preview (`WindowGapPreview`, placed by
  `WindowLayout`'s own geometry), then the layouts, grouped by the
  displays they are made for when there are several groups, each with
  its shortcut (Add Shortcut), Apply, Edit…, Update, Delete (with Undo); what leaves
  the Mac (`LeavesMacRow`, `PrivacyMap.line(for: "windows")`: nothing);
  Always leave out and the monitors ignored under Advanced
  (`AdvancedSection`), closed. Agents
  save at once (`save_window_layout`), the always-left-out apps excepted.
  Displays plugged in (`DisplayWatch`: AppKit's screen changes, no
  polling; `DisplayArrival` in SkilliCore): a display that was there
  before the Mac or its screens slept and comes back asleep or within 30 s
  of waking is not plugged in; the built-in display never is. The layouts
  saved on a display plugged in (`LayoutTrigger`: by serial, or by model
  when it has none; not set to never; monitors ignored offer nothing; the
  one made for exactly the displays there first) are asked in the middle
  of the biggest one (`DisplayPrompt`, a non-activating glass panel, no
  time limit): ↑↓ picks, ↩ applies, esc ignores once, ⌘K lists Always
  Apply Without Asking (only for a display known by its serial), Edit
  Layout…, Record New Layout Here…, Ignore Once, Never Apply
  Automatically, Ignore <monitor>. It takes the keyboard only when no key
  was pressed in the last second (`CGEventSource.secondsSinceLastEventType`);
  a click does. A second display a dock plugs joins the question already
  asked; a display unplugged leaves it. A display no layout knows: nothing.
  A layout's `automatic` (ask, always, never) is set in the editor and in
  Settings → Windows (⋯), which also lists the monitors ignored, last. The
  self-test offers a display instead of plugging one (`offerDisplays`).
  Typing "coding" offers the layout, Return puts each window back: its app opened in the
  background if needed, its file opened again if it is not; the same
  file first, then the same title, then the same rank. Each saved display
  is paired with itself where it is now (same size: same place; another
  size: same place in proportion); one not connected hands its windows to
  the nearest of its kind (built-in or not). Windows come out of full
  screen or the Dock to move, are kept on their display when the app
  keeps them larger, then go back to the Dock or full screen; hidden apps
  are hidden again. Waits are Accessibility notifications (`AXWait`: a
  window created, moved, out of the Dock), never fixed sleeps. The card
  says what was adapted (`LayoutReport`: a display resized, one standing
  in, an app's minimum size, windows that did not open) and stays longer
  for each line. Layouts can get a shortcut (Add Shortcut → Window
  Layouts). Switch Window lists every window (app icon, title) and
  Return brings one forward (activate, AXMain, AXRaise). Agents:
  `list_windows`, `focus_window`, `save_window_layout`,
  `apply_window_layout`. `selftest windows` runs only these checks (✦W ←
  four times: ½ ⅔ ⅓ ½; a 12 pt gap read back at the edges and between
  two windows; ✦W N on a second display; a layout opening a TextEdit file
  and a page served on the Mac in Safari, applied twice) and writes
  `layout-editor.png`, `layout-editor-empty.png`,
  `layout-editor-opens-light/-dark.png`, `settings-windows.png`,
  `settings-windows-light/-dark(-bottom).png`, `display-prompt.png` and
  `display-prompt-actions.png`.
- File search (`FileSearch`, `FileMeaning` in SkilliCore): Search Files
  or "f " / "file " / "fichier " turns the launcher into Spotlight's files
  (a green chip). Typing searches names (every word, case and accents
  ignored) once typing pauses 100 ms, in the home folder without Library,
  hidden folders and app bundles, recently used first; Return opens,
  ⌘Return shows in Finder. ⇥ searches by meaning
  (`FileSearch.searchByMeaning`): up to 240 candidates (files named with
  the request's words, then opened in the last 90 days, then PDFs,
  office files, archives, videos, audio and screenshots changed this
  week), one line each (kind, readable name, folder, "yesterday 18:02") in
  one Choice to Jev or OpenAI Decisions; the likely ones (≥ 4 %) best
  first, ~0.3 s. Only on ⇥ and with Settings → Launcher → Search files by
  meaning on (default). Spotlight's C API (`MDQuery`), synchronous, one
  query at a time on its own queue, stopped when no longer wanted or after
  3 s: queries started together (one per key) were seen waiting forever,
  and NSMetadataQuery's main-run-loop notifications crashed the Swift
  runtime's executor check. `selftest files` (on the Mac mini) seeds a
  few files in `~/skilli-selftest-files-<pid>` (mdimport, which returns
  at once: Spotlight takes them seconds apart, each is waited for;
  removed after).
- Screen tools for agents (`UIReader`, tool group `screen`, "Screen
  Controls"): `list_ui` reads the front window's buttons, checkboxes,
  radios, fields, pop-ups, links and short texts through Accessibility
  (≤ 4 000 nodes visited, 200 kept, reading order), each with an id
  ("e12"); secure fields are named, never read. `find_ui` lets Jev or
  Decisions pick the element from a description (~0.3 s; names compared
  without a key). `press_ui` presses (AXPress, then Confirm, Pick) or
  focuses a field; `set_ui_value` sets AXValue (never a password field),
  else types it; `press_keys` sends "cmd+s", "return", arrows… (the
  `Chord` parser, the current layout). `do_in_app` (goal, app) hands a
  whole goal to "do it here" and waits: "Done in TextEdit in 14.2 s · 5
  steps: …", a stop an error with why and the steps done
  (`ControlReport`); an app not installed refused with list_apps; no app
  named, the one the command started in. Pressing, filling, keys and
  do_in_app ask in the card like any change. The agent prompt says: one
  menu item for one step, a goal of several steps whole to do_in_app,
  find_ui/list_ui and press_ui/set_ui_value for a single press, press_keys,
  read again after a change.
- Emoji (`EmojiSearch` in SkilliCore, `EmojiLibrary`): ":" or "emoji "
  in the launcher (or Search Emoji) is the picker, an orange chip. Names
  come from macOS itself (`CoreEmoji.framework/…/<language>.lproj/
  AppleName.strings`, ~1 900 emoji), in the user's language and English;
  recent ones first (the self-test keeps its own). By feeling: ⇥, or on
  its own after 350 ms when no name matches, the ~255 expressive emoji
  (faces, hearts, hands, celebrations; one skin tone) go to Jev or
  Decisions in one Choice, both names in each option, "read it as a
  native speaker would"; only what was typed is sent. ↩ types the emoji in
  the app in front, ⌘↩ copies it.
- Search Menu Items ("m ", "menus "; `MenuSearch` in SkilliCore, asked
  2026-10-16: "sometimes it's not useful to use AI"): the menu items of
  the app in front (the panel never activates skil.li, so it is still the
  one the user was in), read by `MenuReader` off the main thread when the
  mode opens (1.5 s at most), enabled ones only, found by name with the
  launcher's fuzzy matcher: an item's own name before its menus' names.
  Rows say where it is and its keys; ↩ hides the launcher and presses it
  through Accessibility after the key's handling, as Ask does: the row
  picked is the choice, nothing asks again, whatever the item. Refused by
  the app: one line says so with its keys (`onFailure`). Nothing leaves
  the Mac. Not "menu ": "menu bar" finds apps. Its shortcut can be
  recorded (`SkilliAction.searchMenus`, none by default).
- The picker is a grid (`EmojiGridView`, 2026-10-16 after Raycast's):
  eight across, one fixed size (no column setting). It draws the
  launcher's rows; the hidden table stays the selection every action
  reads (↩, ⌘↩, ⌘K, the self-tests), the grid shows it and ←→↑↓ move it
  (↑↓ to the nearest tile of the row above or below). Nothing typed:
  every emoji, Recently Used then Unicode's groups (`EmojiList.browsing`),
  the group at the top in the header as it scrolls, the selected name on
  its right; a search shows up to 96, ranked. The order is Unicode's
  `emoji-test.txt` turned into `EmojiOrder.swift` by
  `script/emoji_order.py` (macOS keeps its own only in undocumented binary
  files): run it again when Unicode adds emoji. macOS's names keyed
  "…@CH-SKU" (China's flags) are left out: never typed as is.
- Symbols in the picker (2026-10-19: "apple logo" found nothing; "do
  it better", never a copy of Raycast's list): macOS names emoji only,
  and the Apple logo (U+F8FF, private use) nowhere, neither in CoreEmoji
  nor in the Character Viewer's `CharacterDB.sqlite3`. So skil.li writes
  its own (`SymbolTable` in SkilliCore, ~190): each symbol with an English
  and a French name and the words people type ("cmd", "logo pomme", "au
  carré"), in six groups browsed after Unicode's (Mac Keys first: ⌘ ⌥ ⇧,
  ✦ the Hyper Key, the Apple logo). U+FE0E draws an emoji-capable one as
  text (↩︎ the Return key beside the ↩️ emoji); U+FE0F names an emoji
  macOS leaves unnamed (♀️ ♂️) until it names it. Then every other symbol
  Unicode names in its symbol blocks (`SymbolTable.blocks`, ~2 500), by
  its Unicode name, search only; one no font of this Mac draws is left
  out (`isDrawn`). Ranked as emoji are, a name written for people one
  step above Unicode's, an emoji before a symbol at the same score; the
  symbol typed or pasted finds itself. Never sent to the decision model
  (`expressive` keeps emoji). The header says the keys that type the
  selected symbol on the user's own layout (`KeyboardLayout.keys(typing:)`,
  ⇧ and ⌥ at most, `TypingKeys`): "Apple logo · ⌥⇧K". Names folded once
  (`EmojiSearch.Index`, one buffer), a key compares bytes: 0.34 ms over
  the 4 500 (worst 0.7 ms, release; the old emoji-only search, folding on
  every key, took ~6.5 ms); the first open reads and folds them, ~14 ms. `selftest emoji` (`emojiPickerFindsSymbols`):
  "apple logo" first, its keys beside it, ↩ types it,
  `launcher-emoji-symbols-light/-dark.png`.
- One feature, one pane (2026-10-16: "having emoji stuff in
  multiple places is not a good thing"): Settings → Emoji (`EmojiPane`)
  holds all of it, in the rules' order: Search Emoji's shortcut (⌃⌘Space)
  and the launcher's prefix, the skin tone; Find emoji by feeling with ⇥
  (`emojiMeaningSearch`, on by default; off, neither ⇥ nor the pause
  asks) and Words learned with Forget; what leaves the Mac (the
  `emoji` flow is the pane's, with that switch). Keys and Catalog still
  list it, as they list everything; no other pane holds an emoji setting.
- Emoji skin tone (Settings → Emoji, `emojiSkinTone`, asked
  2026-10-16 after Raycast's): `EmojiSkinTone.apply` puts the modifier
  after each person or hand (`isEmojiModifierBase`; ✌️ loses its U+FE0F)
  and keeps it only when Apple Color Emoji draws one glyph, so a family
  or people holding hands stay as they are. Rows and what is typed use
  it; recents keep the plain emoji. The picker's hands are drawn by the
  same code. No column count nor "primary action" setting: ↩ pastes, ⌘↩
  copies.
- Words learned (Raycast's "custom keywords"): picked from a by-feeling
  list, its words are kept for that emoji (`EmojiLibrary.said`, eight
  each, on this Mac only) and searched as names; the same words put it
  first, so it comes at once, without asking again. Settings → Emoji
  counts them and Forget empties them at once, nothing asked: Undo ⌘Z for
  10 s brings them back (`forgetSaid`, `restoreSaid`).
- Search GIFs (`GIF`, `Klipy`, `GIFRecents`, `GIFPaste` in SkilliCore;
  `GIFLibrary`, `GIFGridView`, `FileSearch.gifs`; 2026-10-19 after
  Raycast's GIF Search, docs/gif-search.md): "gif " / "gifs " or Search
  GIFs (a recordable shortcut, none by default: `SkilliAction.searchGIFs`)
  is a grid, four across, a mint chip. Klipy only (Tenor's API closed
  2026-06-30; GIPHY's production keys are paid), and Klipy's rules
  (docs.klipy.com, read 2026-10-19) bind the design: requests and media
  loads from the user's Mac, never through a server of ours; no copy of
  its media kept (no disk cache, Recently Used keeps slugs and reads them
  back with `gifs/items`; a search's slugs end with its mark,
  "hello-3--kULSAXj24", `gifs/items` answers "hello-3": Recently Used
  keeps `plainSlug`, a share sends the slug as given); Search and Trending shown in its order,
  nothing added, moved or filtered in the app (`content_filter` medium is
  its own parameter); its GIFs never mixed with another source in one
  section; "Search KLIPY" as the field's placeholder (required). Nothing
  typed: Recently Used, then Trending on Klipy (one request as the mode
  opens); typed, once typing pauses 250 ms: Klipy's GIFs, then On this
  Mac (Spotlight, `com.compuserve.gif` whose name holds every word), each
  its own section; each search's answer kept for the mode's life. Tiles
  show Klipy's `md.jpg` still (~20 KB, sharp at 2×), decoded off the main
  thread at the tile's pixels into an `NSCache` of 16 MB; only the
  selected tile plays (`md.webp`, a fifth of the GIF; 160 ms after it
  stays selected), frame by frame through ImageIO; everything released
  when the mode closes. ↩ pastes: the full GIF (`hd`, 15 MB at most)
  fetched, one temp file named after it (`skilli-gifs/`, the one before
  removed, the folder at launch) and its `com.compuserve.gif` data on the
  clipboard, then ⌘V; in a terminal or a code editor (`GIFPaste`:
  `EditorProjects.editors` and known terminals, read as the mode opens)
  ↩ types `![title](link)` instead and the footer says Paste Markdown.
  ⌘↩ copies, ⇧⌘C copies the link; ⌘K adds Open in Browser, Copy Markdown
  (a file of this Mac: Show in Finder, Copy Path). A paste or copy of
  Klipy's is counted by `gifs/share/{slug}` with the words (its rule),
  `customer_id` a random id made once on this Mac. The key: the user's own
  (Settings → GIFs → Advanced, Keychain account `klipy`, read once and
  kept in memory: never the Keychain on a key), else skil.li's, put in the
  Release build by `script/release/build.sh` (`SKILLI_KLIPY_KEY`: the
  `release` environment's secret on GitHub Actions; on a Mac, the key
  inside its own `daily` skil.li, which `daily` carries over; never in the
  repository nor the keychain, 2026-10-19; Info.plist `SkilliKlipyKey`);
  none: only the GIFs on this Mac, the grid says so.
  Settings → GIFs (`GIFsPane`): the shortcut, the prefix, where Klipy's
  GIFs come from, Advanced: Your Klipy key (Remove at once, ⌘Z saves it
  again); `PrivacyMap.gifs` under Klipy. `selftest gifs` (keys, on the
  mini): a stand-in Klipy on 127.0.0.1 and a GIF seeded in the home
  folder; `launcher-gifs-*`, `settings-gifs` -light/-dark.png. `remote
  gifslive` with `SKILLI_KLIPY_KEY` set (any build takes it from the
  environment, as a release does): the real Klipy, the build's own key,
  nothing set in Settings; `launcher-gifs-live-*`, `gifs-live-pasted.png`.
- Calculator (`Calculator` in SkilliCore, a hand-written parser: nothing
  evaluated but numbers): the first launcher row for "2 + 3 * 4",
  "12,5 × 4" (French decimal comma; "1,234" groups in English, "1 234"
  too), "20 % de 85", "85 + 20%", √, sin, log, pi; units through
  Foundation's Measurement with exact coefficients where it rounds
  ("10 km en miles", "32 °F to °C", "1,5 Go en Mo", "100 km/h in mph",
  "3 jours en heures"); the time elsewhere ("heure à Tokyo", "time in New
  York"). ↩ types the result (without grouping) in the app in front, like
  a clip, a snippet or an emoji (D4, 2026-10-17); ⌘↩ and ⌘C copy it,
  nothing said. ⌘K: Paste Result ↩, Copy Result ⌘↩. A lone number or a
  word is not a calculation. `selftest calc` (`launcherCalculates`): the
  footer, ⌘K, ↩ pasted in the test window, ⌘↩ and ⌘C copied silently.
- Mac controls (`SystemCommand`, run through `AIActionController.runMac`
  from the launcher, shortcuts and Ask): play/pause, next and previous
  track, volume up/down, mute — the keyboard's own media keys
  (`NSEvent` system-defined, subtype 8: whatever plays answers, macOS
  shows its HUD); Test Internet Speed — `/usr/bin/networkQuality -c`
  (~15 s, a card says it is working, then "↓ 330 Mbps · ↑ 41 Mbps ·
  Responsiveness: High…"); Pick a Color — `NSColorSampler`, the hex
  copied, with rgb() and hsl(); System Info — battery (IOPowerSources),
  free disk, memory used (active + wired + compressed), load, IP (en0/en1),
  uptime, macOS, and the Wi-Fi (`WiFi.summary`: on or off, signal in words
  from its dBm, rate; the network's name only when macOS gives it: CoreWLAN
  hides it without Location Services, which skil.li does not ask for).
  Agents also get `set_volume` (CoreAudio) and `system_info`. Ask: a Mac
  command Jev or Decisions is sure of (≥ 85 %) wins over the agent and a
  written answer ("il me reste combien de batterie").
- Volume at a level (`VolumeRequest` in SkilliCore, `MacAction.volume`):
  "volume 30", "mets le son à 30 %", "set the volume to 30 percent", "son
  au max" typed in the launcher (a sound word and one level; "monte le son
  de 10" is a step, "30 % de 85" a calculation, another app's sound not
  the Mac's). The launcher's first row "Set Volume to 30 %" (Catalog
  "volume "). In Ask, the command question has "set the volume to a
  level" and Jev reads the level (`AskValues.level`). CoreAudio's
  `VirtualMainVolume`; nothing said: the level chosen is heard.
- Wi-Fi on and off (`SystemCommand.wifiOn`/`wifiOff`, `WiFi`): CoreWLAN's
  `CWInterface.setPower`, what the Wi-Fi menu's switch does. The launcher
  lists only the way it can go (read off the main thread as it opens,
  `AppDelegate.refreshRadios`; a change redraws the rows); seen in the
  menu bar, so nothing said. Ask "coupe le wifi" (no confirmation: asked
  for); "open the wifi settings" opens the pane, never the switch, and
  the switch beats the pane when the settings are not named. The
  launcher ranks by names instead: "wifi" names the pane, first, the
  switch next (`LauncherRank`). From a
  skil.li link, Wi-Fi off and Show Desktop ask first (`asksFromALink`).
- Bluetooth devices (`BluetoothDevices` on IOBluetooth, `BluetoothRoute` in
  SkilliCore, `MacAction.bluetooth`): the accessories paired with this Mac
  (not computers, phones or watches), one row each the way it can go
  ("Connect AirPods Pro", "Disconnect Magic Keyboard"; Catalog "Bluetooth
  Devices"), Ask "connecte mes AirPods" / "déconnecte le clavier" (each
  device both ways in the command question, by position; already
  connected is said), agents `list_bluetooth_devices`,
  `connect_bluetooth_device`. `openConnection(target)` waits for
  `connectionComplete` (15 s at most; "is it on and nearby?"),
  `closeConnection`; "Connecting …" in the card while it tries, gone once
  connected, a failure said. Read off
  the main thread as the launcher opens; a key never asks IOBluetooth.
  Turning Bluetooth itself on or off is not offered: IOBluetooth only
  reads `IOBluetoothHostController.powerState`; the setter tools use
  (`IOBluetoothPreferenceSetControllerPowerState`) is private.
- Show Desktop (`SystemCommand.showDesktop`): macOS has no API for it, so
  it presses the user's own Show Desktop shortcut (`SymbolicHotKey`, entry
  36 of `com.apple.symbolichotkeys`: F11 unless changed, the fn bit added
  for F-keys as a keyboard sends them). Turned off in System Settings →
  Keyboard → Keyboard Shortcuts → Mission Control: said, not worked
  around. `selftest keyboard` checks the test window moves aside and back.
- Auto Quit (`AutoQuit` in SkilliCore, `AutoQuitter`; Settings → Windows →
  Quit apps you stopped using, off by default; Unused for 30 min, 1 h
  (default), 2 h, 4 h; Never quit, a list of apps): an app not in front
  for that long is quit without a word (`terminate`: it may save); one
  still open 10 s later is said. Never the app in front, skil.li, Finder
  or macOS's own faces; never one with unsaved work (`AXEdited` on a
  window's close button: AppKit says it there) or a modal window or sheet
  open (a dialog subrole alone says nothing: Calculator's main window is
  one), one CoreAudio says plays or records (its process
  objects, a browser's helper by bundle id), or one using 5 % of a core
  over 2 s. Without Accessibility nothing goes. With a deciding key, Jev
  (else Decisions) gets each one's name and windows' titles in one request
  and keeps it under 70 % "safe" (a call, a download, a command running);
  `PrivacyMap.autoQuit`. One timer for when the next app is due, set again
  on NSWorkspace's activate, deactivate, launch and terminate and on
  settings. `selftest calc` decides as a dry run (Chess "unused" 2 h; the
  test form with unsaved work: `Skilli testform <state> edited`).
- Raycast imports (`RaycastImport` in SkilliCore): **no button in the
  app since 2026-10-15** (not tried for real yet; bring them back
  only when the maintainer asks). The code stays, covered by `selftest imports`.
  Snippets: reads the JSON Raycast's Export Snippets saves
  (`[{name, text, keyword}]`): each one a snippet file; a keyword already
  used is left off; placeholders skil.li does not fill yet ({uuid},
  {date format=…}, {argument…}) are kept as typed and named. Quicklinks:
  reads Export Quicklinks'
  JSON (`[{name, link}]`): Raycast's one argument ({Query}, {argument
  name=…}) becomes {query}; a link already here (same address), with
  another placeholder ({clipboard}…) or not http(s) is left out, by name;
  imported ones have no keyword (Raycast has none). Script Commands:
  `ScriptLibrary.importRaycast` (above). `selftest imports` (no keys).
- Homebrew (`Homebrew`, `BrewPackage` and `BrewSearch` in SkilliCore):
  the Homebrew command or "brew " (yellow chip). Names from Homebrew's
  own lists (`~/Library/Caches/Homebrew/api/formula_names.txt`,
  `cask_names.txt`: no network, read again after a `brew update`),
  ranked exact, prefix, part ("ffmpeg@6"), contains; installed ones and
  their version from `Cellar` and `Caskroom`; updates from `brew outdated
  --json=v2` (when the mode opens, kept 10 min); the top rows'
  descriptions from `brew desc` once typing pauses. With no text: the
  installed ones, updates first, and Upgrade All (N). Return installs, or
  upgrades one with an update (an installed, current one opens its page);
  ⌘Return opens formulae.brew.sh; ⌘⌫ uninstalls. A formula installs at
  once (a command-line tool, removed as easily: D9); an app (a cask), an
  upgrade or an uninstall asks in the card first ("Install “Figma” with
  Homebrew?", ↩ Install, esc Cancel). Then the card says it is working and what brew printed last
  (output and errors, exit status; 30 min at most). The self-test's
  Homebrew only ever runs `--dry-run`. Agents: `brew_search`,
  `brew_install`, `brew_upgrade` (names checked against Homebrew's lists).
  Homebrew 7's own package payload is a private format: not read.
- Browser history (`BrowserHistory`, `HistoryVisit` and `HistoryMeaning`
  in SkilliCore): Chrome, Arc, Dia, Brave, Edge, Vivaldi, Chromium, Opera
  (`History`, table `urls`, every profile: Default and "Profile N") and
  Firefox, Zen (`Profiles/*/places.sqlite`, `moz_places`) and Safari
  (`~/Library/Safari/History.db`, `history_items` joined to
  `history_visits`, titles on the visits, seconds since 2001) of the
  browsers installed, opened `immutable=1` (a running browser keeps its
  lock; nothing written; Safari tries `mode=ro` first, its WAL holds the
  last visits); only http(s) pages; the same page once, its last visit.
  Safari's is behind Full Disk Access (`Permission.fullDiskAccess`,
  `BrowserHistory.safariNeedsAccess`: opening `~/Library/Safari` fails
  without it): the History mode then shows an "Allow Full Disk Access" row
  first, which opens Settings → Privacy (`Permission.askedFrom`
  `.privacyPane`: it cannot be asked, the pane says how). Search Browser History
  or "history " / "historique " / "hist ": the History mode (cyan chip);
  typing searches titles and addresses (every word, LIKE with `%`, `_`
  escaped) once typing pauses 100 ms; rows: title, site · "21:08" /
  "yesterday" / "Mon" / "12 Oct", the browser's icon. Return opens the page
  in the browser it came from, ⌘Return copies its address. ⇥ by meaning
  (`BrowserHistory.searchByMeaning`): the last 240 pages, one line each
  (title, site, "yesterday 18:02"), in one Choice to Jev or OpenAI
  Decisions, only on ⇥ and with Settings → Launcher → Search browser
  history by meaning on (default). Agents: `search_history`.
  `selftest history` (scratch Chrome, Zen and Safari histories).
- Skillies (`ScriptLibrary`, `ScriptCommand` in SkilliCore, Settings →
  Skillies, `MacAction.script`): skil.li's own commands, the
  scripts of `~/Library/Application Support/skil.li/skillies` (one level
  of subfolders; hidden and `.template.` files left out) whose first 60
  lines say `# @skilli.…` or `// @skilli.…`: Raycast's Script Command
  metadata under skil.li's name (title and mode required, schemaVersion 1;
  icon, packageName, description, argument1–3 text / password / dropdown
  with optional and percentEncoded, needsConfirmation, refreshTime,
  currentDirectoryPath). Raycast's own scripts are never read in place:
  `importRaycast` (no button for now, see Raycast imports) copies them in with `@raycast.`
  renamed `@skilli.` in the header comments only, executable; a name taken
  becomes "name-2". Agents write new ones with `create_skillie` (title,
  description, language bash / zsh / python / node / swift / ruby, code,
  mode, text arguments, needs_confirmation; a title taken refused); its
  description says a skillie acts in apps with one `open
  "skilli://do?app=…&goal=…"` line a step, or waits for one to branch on.
  Read again when the folder changed. The launcher lists them by title
  (emoji or image icon, "Skillie"); one with arguments turns the launcher
  into a Skillie chip asking each in turn (a dropdown's choices as rows;
  Return: Next, then Run; a password shows as dots in its row, not in the
  field). Run: the file itself, or its shebang without the executable bit;
  skil.li's PATH with Homebrew; output and errors together, ANSI colors
  out; 120 s at most (`ChildProcess.run`, with what it started: its
  process group, `stopsGroup`, SIGTERM then SIGKILL 3 s on, even once
  the script itself ended). Told `SKILLI_CLI` (skil.li's
  own binary), `SKILLI_SOCKET` (its tool server, which `Skilli call` and
  `Skilli mcp` then reach instead of the usual one) and `SKILLI_SKILLIE`
  (this run's id, sent in their first line), `SkillieEnvironment`: a step
  that waits, `"$SKILLI_CLI" call do_in_app app=TextEdit goal="…"`
  (`name=value` words, or one JSON object), exits 0 done, 1 not done (why
  on its first line), 2 written wrong (docs/do-it-here-from-anywhere.md,
  5). Its call is an outside agent's: the tool's right asks in the card,
  needsConfirmation still asks first; one run by an Act command's agent
  calls within that command's run (`ScriptLibrary.running`). The id lends
  the call the skillie's own card (`SkillieCall`, a task-local while
  `MCPService` handles it; `AIActionController.lentCard`): taken at once
  rather than waited for (the skillie waits for the call), one call at a
  time, then "Running…" again; esc answers that call alone; one still in
  the card when the skillie ends (its limit) is stopped as esc would. It
  grants no right. Nothing printed: the working
  card goes, nothing said. silent: the last line 2 s;
  compact: the last line; fullOutput: all of it in the card (scrolls,
  20 s); inline: the row shows the last line, read again when the launcher
  opens and it is older than refreshTime (10 s at least). Exit ≠ 0: the
  card says the last line. needsConfirmation asks in the card, even when
  `run_skillie` is always allowed. Ask: skillies that need no argument
  join the command question as `script0`…; one that fits (≥ 60 %) beats
  the agent, asked first under 85 %. Shortcuts: Add Shortcut → Skillies
  (`script:<path>`). Agents: `list_skillies`, `run_skillie` (arguments in
  order; a missing one refused), `create_skillie`. `selftest scripts`
  (scratch folder; a real Haiku agent writes one).
- Clean Keyboard (`KeyboardCleaner`, `SystemCommand.cleanKeyboard`):
  the launcher, Ask ("bloque le clavier, je vais le nettoyer"), a
  shortcut or an agent's `run_mac_command` turn every key, modifier and
  media key (NX_SYSDEFINED) off for a minute: its own session tap at the
  head, only while cleaning, re-enabled if macOS disables it. A glass card
  centered on each screen (dimmed, screen-saver level, key without taking
  the app in front) counts down; Done (the mouse still works) or the end
  turns the keys back on. Keys in a password field (Secure Input) reach no
  tap. `selftest keyboard` (on the Mac mini: keys off a few seconds).
- Apps in one key (`SystemCommand`): Quit All Apps and Quit Other Apps
  (all but the one in front) ask first in the card, naming them; each
  quits as Quit does (it asks to save); gone is the answer, one still open
  after 5 s is said. Hide Other Apps, Show All Apps. Never skil.li or
  Finder (`SystemCommands.openApps`). Mute / Unmute Microphone: the
  default input's own mute (CoreAudio `kAudioDevicePropertyMute`), else
  its level to 0 and back to where it was; said in one line (nothing on
  screen shows it). From the launcher, Ask ("coupe le micro", "ferme tout
  sauf Safari" picks Quit Other Apps), shortcuts and agents.
  `selftest calc`.
- Editor projects (`EditorProjects`, `EditorProject` and
  `EditorProjectParsing` in SkilliCore, `MacAction.project`): the recent
  folders and workspaces of the editors installed, read-only, again only
  when a file changed: VS Code, Cursor, Windsurf, VSCodium, Insiders
  (`history.recentlyOpenedPathsList` in `User/globalStorage/state.vscdb`;
  files and remote ones left out), Zed (`workspaces.paths` in
  `Zed/db/0-stable/db.sqlite`, by timestamp), Sublime Text
  (`folder_history` of `Session.sublime_session`), JetBrains IDEs and
  Android Studio (newest `recentProjects.xml`, by `projectOpenTimestamp`).
  SQLite opened `mode=ro`, else `immutable=1`; folders that are gone left
  out. The launcher shows the four that fit a name (editor icon, "Cursor ·
  ~/Documents/Github"); Search Projects lists them all (purple chip).
  Return opens the folder in its editor, ⌘Return shows it in Finder.
  Ask: the 40 last join the command question as `project0`…, "ouvre le
  projet skilli dans cursor"; a project that fits beats an unsure app or
  the agent (≥ 40 %; ≥ 25 % when asked to open something no app is:
  "ouvre mon portfolio", Decisions 32 %) and, with nothing selected, a
  written answer (≥ 75 %).
  Shortcuts: Add Shortcut → Projects (`project:<bundle id>:<path>`).
  Agents: `list_projects`, `open_project`. `selftest projects` (scratch
  Cursor and Zed lists; nothing of the Mac's editors read or opened).
- Sound devices (`AudioDevices` on CoreAudio, `AudioRoute` in
  SkilliCore, `MacAction.sound`): every visible output and microphone
  (not hidden, with streams, not an aggregate private to skil.li: Ask by
  Voice's AVAudioEngine leaves CoreAudio's "CADefaultDeviceAggregate-…"
  in the process until it quits), by UID. The launcher lists "Sound Output:
  AirPods Pro" and "Microphone: …" (typing the name, "son", "sortie",
  "casque", "écran", "micro"…; "(current)" on the one in use); Return
  makes it macOS's default (like Sound settings; alerts follow when set
  to the selected output), nothing said. Shortcuts: Add
  Shortcut → Sound, id `sound.output.<uid>` (kept when the device is
  away). Ask: the connected devices join the command question as
  `sound0`, `sound1`… (their UIDs read as words: "BuiltInSpeakerDevice"
  pulled every "son" to the speakers), described kind first ("the screen
  or TV plugged into the Mac…, named “SAMSUNG”: where it plays, not how
  loud"). Agents: `list_audio_devices`, `set_audio_device` (name or kind,
  `AudioRoute.match`; ambiguous names refused with the list). No
  permission. `selftest sound` (on the Mac mini: switches its output and
  puts it back).
- Mac commands (`Sources/Skilli/System`, `SystemCommand`): lock (⌃⌘Q),
  sleep and displays off (`pmset`), dark mode, eject disks, empty the Trash,
  restart, shut down, log out (Apple events to System Events or Finder:
  `com.apple.security.automation.apple-events` + `NSAppleEventsUsageDescription`,
  macOS asks once per app), hidden files (`defaults` + `killall Finder`),
  Keep Awake (an IOKit assertion until run again; the menu bar offers Allow
  Sleep). The Trash, restart, shut down and log out ask in the card first.
  In the launcher (titles and French keywords), in Ask (route `command`,
  the commands ride in the decision request) and for agents
  (`run_mac_command`).
- Kill Process (launcher): typing "kill " (or picking Kill a Process)
  turns "kill" into a red chip before the field, which then holds only a
  name or a port; ⌫ on the empty field leaves. Apps come as one row with
  all their processes (`ProcessListing.groups`: Gather and its helpers);
  Return quits the app, then helpers still there 2 s later; ⇧Return forces
  the whole group; Tab unfolds an app to stop one process. "kill" lists the
  busiest, a name filters, "3000" shows what listens on the port
  (`ps -axo pid=,pcpu=,rss=,comm=`, `lsof -nP -iTCP:<port> -sTCP:LISTEN
  -Fp`, parsed in `ProcessListing`). Return closes the launcher and the
  app quits at once (D2, 2026-10-17: it asks to save itself), without
  a word (only a refusal is said); apps quit through `terminate`, so they
  can save. ⇧Return force quits and asks ("Force Quit Gather and its 6
  other processes?", ↩ Force Quit, esc Cancel): what is not saved is
  lost. Return's modifiers are read in `LauncherController.deliver`
  (the event tap's keys never become `NSApp.currentEvent`). Never skil.li
  itself or pid ≤ 1. Agents: `list_processes`, `quit_process`.
- Clipboard history (`Sources/Skilli/Clipboard`, Settings → Clipboard):
  ✦C (`SkilliAction.clipboardHistory`), Clipboard History in the launcher or
  "clipboard " / "presse-papier " / "cb " turns the launcher into the
  history (a blue chip, like Kill). Paste in Sequence
  (`SkilliAction.pasteInSequence`, ✦K V by default, the launcher's row):
  each run pastes the next older copy, the newest first, from the history
  as it was when the sequence began (`PasteSequence`); 30 s apart, or a
  copy made after skil.li's paste, starts again from the newest; past the
  oldest, one line says so. Not on ✦C again (it closes the history) nor
  ✦V (Ask by Voice). Paste Latest Screenshot (`SystemCommand`: the
  launcher, Ask "colle ma dernière capture", shortcuts, agents): the
  newest image of macOS's screenshots folder and the one Settings watches
  that macOS marked as a screen capture (`kMDItemIsScreenCapture`, an
  extended attribute `screencapture` writes) or named as macOS or
  CleanShot X name theirs, put on the clipboard as an image (PNG, TIFF)
  and pasted; seen pasted, nothing said. Rows newest first; typing searches
  SQLite FTS5 (`unicode61 remove_diacritics 2`: "reunion" finds "Réunion")
  over the text and what Vision read in images. Return pastes in the app
  in front (every format it was copied with), ⇧Return plain text (an
  image's OCR text), ⌘Return only copies, ⌘⌫ forgets at once (Undo ⌘Z
  for 10 s, the card under the launcher). The list narrows to
  290 pt beside a preview (`ClipboardPreviewView`) made for each kind of
  copy (below), then Information (copied as a relative date, times copied:
  `copies` column, added to older files on open). ⇥ searches by meaning
  (`ClipboardHistory.searchByMeaning`, `ClipboardMeaning`): the last 240
  copies, one line each (kind, app, "yesterday 18:02", 200 characters of
  text or OCR), in one Choice to Jev or OpenAI Decisions with now's date;
  the likely ones (≥ 4 %) best first, ~0.25 s. Only on ⇥ and with Settings
  → Clipboard → Search by meaning on (default); typing never sends
  anything, and the trace logs the request and picked ids, not the copies. Kept in
  `~/Library/Application Support/skil.li/Clipboard` (0700): `history.sqlite`
  and `images/`. A copy of the same content moves up instead of adding a
  row (SHA-256). Retention: 1 day, 1 week, 1 month (default), unlimited or N
  days, pruned at launch and then hourly (`ClipboardHistory.poll`), never
  when the setting changes (2026-10-17: a shorter choice deleted
  older copies at once): the pane (and `set_setting`) only changes it,
  and a line under it says what the next pass removes ("812 copies are
  older than a week: they go within the hour.",
  `ClipboardRetention.removalLine`, counted from the store); Custom starts
  from the choice before it (a week: 7 days; Unlimited: a year).
  `selftest snippets` (`clipboardRetentionWaitsForTheHour`) picks with
  real clicks; `settings-clipboard-retention-*.png`. Never kept:
  nspasteboard.org concealed, transient and auto-generated types
  (password managers, skil.li's own writes), excluded
  apps (Passwords, Keychain Access, 1Password, Bitwarden… editable), and
  skil.li's own ⌘C/⌘V borrowing (`PasteboardSnapshot.isBorrowing`). Only
  the change count is polled (0.4 s); the content is read only when
  `NSPasteboard.accessBehavior == .alwaysAllow` (Privacy & Security →
  Paste from Other Apps), else macOS would ask on every copy. skil.li is
  listed there only after macOS asked once: Allow (✦C's "Allow Clipboard"
  row, Settings → Clipboard or Privacy) reads once, then opens the list. Vision's first OCR loads its models (~30 s once); then
  ~0.1 s. Logs never contain what was copied, only its kind and length.
  `selftest clipboard` runs the store, search, OCR and policy checks on a
  scratch store and a private pasteboard: no keys, safe while the Mac is in
  use.
- Previews by kind (2026-10-16: "social preview for websites, color
  preview for colors, jev details for screenshots"). What a text copy is
  comes from the whole copy (`CopiedValue` in SkilliCore), never from
  something inside a sentence: a color's grammar (`CopiedColor`: #RGB to
  #RRGGBBAA, six bare hex digits mixing figures and letters, 0x…, rgb()/
  rgba()/hsl()/hsla() with commas or spaces and "/ alpha", SwiftUI/NSColor/
  UIColor literals with "62 / 255"; Display P3 left out), one http(s) or
  "www." link, Apple's `NSDataDetector` covering the whole text for an
  email address, a phone number (7–15 digits) or a postal address (shaped
  like one first: a number, commas or lines), else code by a few rules on
  its first 40 lines (`CodeLanguage`: JSON when it parses; Swift, Python,
  JavaScript/TypeScript, Shell, SQL, CSS, Go, Rust, C, Java, HTML/XML by
  signs; prose with none of code's marks reads no rule), else text. ~0.3
  ms a copy, cached by id; the detectors are used once off the main thread
  as the history first opens (their first use costs ms; not at launch,
  where they would weigh on skil.li idle). The views (fixed frames, no layout
  pass): a link's social card (`LinkCardView`: the page's Open Graph or
  Twitter picture across the top, icon, site, title, description; without
  a picture the words with a 32 pt icon; before it is read, while off or
  when the page says nothing: the domain large on a globe and the link,
  no error, no spinner); a color as a swatch (checkerboard under
  transparency, hex and rgb written in black or white, white while it
  keeps 3:1) with Hex, RGB, HSL, Opacity; an image fitted, then "SI sees
  an invoice, a receipt or a bill." (`ImageTags.sentence`, from the kind
  and person Jev already picked: Jev answers choices and yes/no, never
  free text; an `SIRevealLabel`, sparkles in the accent, nothing for
  "other" without a person), then Text in Image (3 lines of the OCR), then
  Content, Dimensions, File size, From (the app, or "Screenshots
  (folder)"); one file: Quick Look's thumbnail (`QLThumbnailGenerator`,
  else its icon) and name, Kind, Size, Where, Modified; several: each
  one's icon, name and kind from its extension (nothing read from disk),
  "and N more"; an email address, a phone number or an address on a card
  (a tinted symbol, the value, what it is); code monospaced under its
  language's name; text with a fade at the bottom, Size, and Reading time
  from 400 words. A copied color's row shows its swatch. Showing a row
  costs 0.3–2 ms on the mini (`lastShowSteps`); pictures, file details,
  Quick Look and link previews are read off the main thread and fill in
  (a token drops what comes back for another row).
- Link previews (Settings → Clipboard → Advanced → Show link previews,
  `Preferences.clipboardLinkPreviews`, on): `ClipboardLinks` reads a page
  only when its copy is shown in the preview, 160 ms after it stays
  selected (arrows flying over links read none), never in the background
  for every copy. A plain GET from its own ephemeral session: no cookies
  sent or kept, no credential storage, no cache, a sign-in challenge
  refused, http(s) only (a link with a name or password in it is not
  read), at most 5 redirects and only to http(s), 6 s without an answer, the head
  read up to `</head>` or 512 KB, a picture up to 8 MB and an icon up to
  512 KB; a link to a picture is its own preview. The head's tags
  (`LinkPreviews.parse`: og:, twitter:, `<title>`, description, `<base>`,
  icons ranked Apple touch icon first, SVG last, /favicon.ico; scripts,
  styles and comments skipped; entities decoded; the charset the header or
  head names). Kept beside the history (`previews/<id>.json`,
  `<id>.image.jpg` ≤ 800 px, `<id>.icon.png` 64 px; `LinkPreviewCache`),
  removed with the copy (⌘⌫, pruning, Clear History; orphans swept at
  start); read again after a week, a failure after ten minutes (what an
  earlier read found stays meanwhile). Logs never name the link. No App
  Transport Security exception was added: a plain http page macOS refuses
  shows the plain card. `PrivacyMap.linkPreviews` under "Websites";
  Clipboard's line says it. `selftest previews` (keys, on the self-test's
  own store): every kind walked with ↓ and captured light and dark
  (`launcher-clipboard-preview-*`), the links from two pages it serves on
  127.0.0.1 (no real website): nothing read before a link is shown nor
  while previews are off, then the card with picture, icon and title, no
  cookie sent back although the page sets one, only GETs, the files gone
  with the copy, each row shown in under 8 ms.
- Images by what they show (Settings → Clipboard, both on by default; asked
  2026-10-15): Jev sees a 512 px JPEG of each image once (`ImageTagger`,
  `JevImages`, TypeSafe's image questions) and picks its kind
  (`ImageTags`: screenshot, code, chat, document, invoice, chart, diagram,
  photo, design, other; unsure under 50 %: other) and whether a person is
  in it. The kind's words, English and French ("invoice … facture"), go in
  the item's `tags`, searched by FTS5 with the text and OCR, and in the
  description ⇥ sends; the row says "Invoice “…”". About 1,000 input
  tokens, $0.00004 an image, ~0.25 s, in the background. Without a
  TypeSafe key nothing is sent; images kept meanwhile are tagged at the
  next launch (`tagUntagged`, the 60 newest). Screenshots join the
  history with Settings → Clipboard → Keep screenshots too
  (`Preferences.clipboardScreenshots`, on; `ImageFolderWatcher`: macOS's
  screenshots folder from `com.apple.screencapture`'s `location`, else the
  Desktop, or one chosen): a kernel watch of the folder, a new file taken
  once its size holds still, kept as if copied when it was made (from: the
  folder's name), the 20 newest the first time a folder is watched; their
  words read by Vision on this Mac (Read text in images), found by typing
  and by ⇥. Jev looks at them only with Advanced → "Screenshots, by what
  they show" (`imageTagsFolder`); "Images you copy, by what they show" for
  copies. `selftest clipboard` drops one in a scratch folder (found by its
  words, Jev not asked).
  Measured on the mini (`selftest vision`, the user's key): 8/8 kinds right
  at 512, 1024 and 1568 px; a copied invoice and a chart saved in a
  watched folder found as "facture" and "graphique".
- Debug builds log everything to the `dev` category (`Log.trace`: the
  request, candidates, decision, message, tool calls and answers, in
  clear); Release builds log none of it. `selftest decide` runs only the
  live decisions (route, Finder's menus, installed apps): no keys, no
  windows, safe while the Mac is in use.
- Ask by Voice (✦V, `SkilliAction.askByVoice`): `VoiceInput` runs macOS 26
  `SpeechAnalyzer` + `SpeechTranscriber` (progressive preset) on the Mac;
  the live text fills Ask's question (typing stops listening and keeps the
  text), Return stops, 0.4 s of silence settles the last word, Ask runs.
  Language: Settings → Ask, else the keyboard layout's language (people
  speak what they type, as with an English system and a French
  keyboard). macOS asks for the microphone once and downloads each
  language model once. The self-test speaks with `say` into a file
  (`voiceFileOverride`); French voices say English names the French way, so
  its sentences are all French.
- Dictate (✦D, `SkilliAction.dictate`, Catalog → Write; `Dictation.swift`
  in SkilliCore): what the user says is typed at the caret of the app in
  front. Ask by Voice's card and keys (title Dictate, "Insert ↩"; typing
  stops listening to edit; ✦D again works as ↩; esc drops it), Ask's
  language setting. Engine: `DictationTranscriber`
  (`.progressiveLongDictation`, punctuation), the model of macOS's own
  dictation, because it reads `AnalysisContext.contextualStrings` and
  `SpeechTranscriber` does not: the contacts' names and companies, only
  when Contacts is allowed already (`DictationVocabulary`: the user's
  company and name, the contacts picked in the launcher, companies several
  share, then the rest; legal forms dropped; 100 phrases at most, Apple's
  advice), given after the microphone starts. Nothing leaves the Mac.
  Typed with ⌘V (`SelectionService.replace`, the app's ⌘Z) after
  `DictationText.insertion` against the text before the caret: a space
  after a word, a capital at a sentence's start, lowercase mid-sentence
  unless a contact's name, "I" or an acronym. Never in a password field
  (Secure Input or `AXSecureTextField`) or an app the clipboard history
  stays out of; another app in front or nothing that takes text: on the
  clipboard, said in one line. Measured on the mini: "Martin" alone,
  "Martaing" told. `selftest dictation` (TextEdit, the test window, a
  stand-in Secure Input).
- Welcome (`Sources/Skilli/Setup`, spec `docs/onboarding.md`, asked
  2026-10-18: "at least on par with Raycast, Arc… VERY IMPORTANT"): seven
  steps of doing, not reading (`WelcomeModel`, `WelcomeView`,
  `WelcomeStages`): welcome; Accessibility; the Hyper Key held (live,
  `KeyRouter.onHyperChange`, or ⌘⌃⌥⇧ flags when another Hyper app's tap
  runs first); the launcher's keys chosen, ⌘Space instead of Spotlight
  (recommended), ✦Space, or the person's own recorded with the store's
  recorder and refused as Settings → Keys refuses them
  (`WelcomeModel.launcherChoices`, `recordLauncher`), then pressed and closed (`LauncherController.onOpened`/`onClosed`);
  your SI found live (Claude Code, Codex, a key with Verify; the first
  ready one writes, `chooseReadyWriter`; under Chooses, a TypeSafe Jev key
  pasted and verified, `verifyDecisionKey`, the OpenAI key counting too);
  a practice sentence fixed with ✦K G (✦U without SI) and taken back with
  ⌘Z ("Try it"); what was set up, line by line, missing ones saying where
  (`WelcomeModel.setUp`), and Open at login (on by default, applied on
  Start only). It says from its first step that it sets things up (asked
  2026-10-20: a colleague thought it was "just for show"). Steps needing the key tap
  are left out while Accessibility is off. A done live step moves on by
  itself. A Caps Lock tap sends Escape: the welcome ignores it as Back for
  400 ms. D7 holds: only Accessibility is asked (`Permission.showsInSetup`).
  Every other permission is asked where its feature first needs it, never
  here (`Permission.askedFrom`): the launcher's "Allow …" rows ask macOS
  right there (`PermissionCenter.grant`: its question when never asked,
  else its list in System Settings), Full Disk Access opens Settings →
  Privacy, and the features ask themselves (the microphone in
  `VoiceInput`, Calendar and Reminders in their `allow()`, Contacts in
  `ContactBook.allow`, Bluetooth in Ask and its tools, the camera in the
  meeting card's check, Screen Recording in do it here's failure card,
  Input Monitoring when the key tap fails, Automation by macOS at the
  first script). While Accessibility waits, `SettingsGuide` floats a
  never-key glass panel under System Settings' window ("Turn on skil.li",
  the app's icon to drag into the list), naming the list as the OS does
  ("Device Control and Data Access" from macOS 27); the welcome stays at
  its normal level behind, and comes back in front when the switch flips
  (`PermissionCenter.onChange`, `SetupWindowController.comeBack`). Shown
  by itself on the first launch only: Start, Later and ✕ set
  `Preferences.didCompleteSetup`; it never opens by itself again, nor when
  the key tap fails. Again on request: Welcome to skil.li (launcher,
  Catalog), and while Accessibility is off Set Up skil.li… (menu bar,
  Settings → General) and the launcher's Allow Accessibility row, both on
  the Accessibility step. Entitlements for the microphone and Reminders
  are in `Config/Skilli.entitlements` (Hardened Runtime denies silently
  without them). `selftest setup` captures every step and state, light and
  dark (`drawWelcome`), drives the live steps with the app's own welcome
  (`welcomeLiveSteps`) and the guide on a stand-in window
  (`settingsGuideFollowsTheWindow`); `selftest settings` clicks its ✕
  (`setupClosedMeansLater`).
- Your Tools (`CustomTool` in `tools.json`): name, when to use it, webhook
  (https, or http to this Mac only); token in the Keychain; POST
  `{text, note, tool, app}`, reply back to the agent; `.changes` risk.
- Reminders tool (`create_reminder`, EventKit): due as ISO 8601 parsed by
  `ReminderDate`; the agent's system prompt carries the date and time zone.
- With nothing selected, `{selection}` commands take the field being edited
  (`InputScope`: whole field ≤ 2,000 characters, else the paragraph at the
  cursor), selected through Accessibility; never in password fields or
  terminals; Electron apps get `AXManualAccessibility`.
- Self-test captures show only skil.li: no padding around windows, and a
  see-through card is captured only while the (large) test window is behind
  all of it. The user's own windows must never end up in `dist/`.
- Links (`SkilliLink` in SkilliCore, `LinkRunner`, `Config/Info.plist`'s
  scheme): `skilli://run/<entry id>` (any Catalog entry, "cmd:emoji",
  "system:window.leftHalf"), `skilli://quicklink/<keyword or id>?q=…` (no
  q: the selection, read as Ask reads it; neither: the launcher with its
  keyword), `skilli://layout/<id>`, `skilli://skillie/<path in the
  folder>?arg=…&arg=…` (missing arguments asked in the launcher),
  `skilli://do?goal=…&app=…` ("do it here" toward the goal in that app,
  else the one in front; see below). Opened
  from any app (macOS may bring skil.li forward: the app that was in front
  comes back first), each does what its row does in the "?"
  (`LauncherController.run(fromLink:)`). A link can come from a web page:
  `SkilliLink.asksFirst` asks in the card first (Allow ↩ / Deny esc,
  saying a link asked) for skillies (once: one that asks by itself is not
  asked twice), snippets, the user's commands, case changes, Ask by Voice,
  Dictate, Quit skil.li and the Mac commands that take the Mac away or can
  lose work (lock, sleep, displays off, eject, hidden files, clean
  keyboard, microphone); Empty Trash, Restart, Shut Down, Log Out, Quit
  All and Quit Other Apps ask anyway. The rest only opens or reads, or is
  seen at once and undone as easily: it runs at once. A link skil.li does
  not know, or whose target is gone, says so in the card.
  Trust (D6, 2026-10-17: "Always from links, per entry, after the
  first ↩"; `LinkTrust`, `TrustedLink` in SkilliCore): that card offers
  Always ⌘↩ and says what it does; Always trusts that entry only (its
  Catalog id; a skillie with the same arguments, others ask again), and
  its next link runs at once. Kept with the tools' rights in `tools.json`
  (`ToolSettings.linkTrust`, `trustLink`, `removeTrustedLink`), listed
  last in Settings → Catalog (Trusted Links, − asks again; read by
  `get_settings`, never changed through tools). Never trusted, their card
  offering no Always (`LinkTrust.neverTrusted`): what asks anyway (Empty
  Trash, Restart, Shut Down, Log Out, Quit All, Quit Other Apps: their own
  card, `once`), settings (a pane, Reset Launcher Position), and pastes of
  the user's copies (Paste in Sequence, Paste Latest Screenshot: a page
  that opened the link could read them in its field). A trust read from
  the file for one of those does nothing. A skillie that asks by itself is
  neither asked by the link nor skipped.
  `do` links (docs/do-it-here-from-anywhere.md) always ask first: Allow
  “<the goal>”? — skil.li does it in <app>, step by step… What sends,
  deletes or pays still asks; Always trusts that goal in that app only
  (`LinkTrust.askDo` / `trustDo`, entry `do`, arguments goal then app;
  Trusted Links "Do It Here · “goal”, “TextEdit”"). They run one at a time
  in the order they came (`LinkRunner.chainDo`), so a skillie chains steps
  with `open` lines; one that came while another waited or ran is dropped
  when that one did not finish (denied, stopped, cancelled), saying
  nothing more. A stop stays in the card to say why; no goal says so, and
  a goal over 300 characters (`SkilliLink.longestGoal`) is not run: its
  card must show it whole.
- Linked apps (docs/apps.md; `LinkedApp`, `AppLinkCommand`, `CleanShot` in
  SkilliCore, `LinkedApps`): apps skil.li drives through the links they
  document, only those. CleanShot X (`pl.maketheweb.cleanshotx`, read from
  cleanshot.com/docs-api): every command a `MacAction.appLink(command,
  variant:)` (raw value `link:cleanshot.capture-area`, `…/copy` for a
  variant), so one list serves the launcher's rows (CleanShot's icon,
  accessory "CleanShot X"), the Catalog (group In Your Apps, entry
  `system:link:…`, only when installed: `FeatureCatalog.Input.appLinks`),
  shortcuts (Add Shortcut → CleanShot X, a submenu per command with
  variants; the old `url:cleanshot://…` ids decode to these,
  `SkilliAction.appLink(url:)`), links (run at once: they open CleanShot,
  seen at once; never trusted), Ask (the command question's options) and
  agents and skillies (`run_action` `cleanshot.<command>`, `variant` one of
  its variants' ids; upload asks every time, whatever the rights). ⌘K on a row lists its
  variants (`action=copy|save|annotate|pin|upload`, `start`/`autoscroll`,
  `linebreaks`, `tab`), gated by CleanShot's version (`since`, 4.7 for
  parameters). skil.li's own: Capture / Record Front Window put the front
  window's frame in the link (`CleanShot.frame`: points from the
  display's bottom left, `display` 1 the main one in `NSScreen.screens`'
  order; checked with a real capture of a Finder window, one
  display), Annotate / Pin Latest Screenshot the newest screenshot's path
  (PNG or JPEG). `SystemCommands.openAppLink` is the self-test's dry run;
  `remote apps` (✦K C, "capture front", ⌘K, the frame) captures nothing.
- Import: `skilli://commands/import?command=<file>` (repeatable) or
  `?url=https://…` (`CommandLink`, `Config/Info.plist`). Settings →
  Commands shows every command in full before Add; nothing is added from a
  link alone. Import… reads `.md` files; Share copies a link or exports the
  file. Imports never replace a command (free id).
- The prompt editor (`PromptEditor`, AppKit) shows its own variable list under
  the cursor (`VariableCompletionList`): the system completion list does not
  filter as you type. Create the text view with `init(frame:)`: a nil text
  container shows nothing.
- Changes are highlighted only when the rewrite stays close to the original
  (`TextDiff.characterSimilarity` ≥ 0.75); translations show plainly. A word
  replaced by a close one shows only the letters that changed (enfant·s,
  mang·~~er~~·é); unrelated words are replaced whole; a case-only change shows
  just the new letter.

## What not to do

- Do not add SwiftUI, web views, or a JS runtime to the launcher hot path.
- Do not enable the App Sandbox or target the Mac App Store.
- Do not sign local builds ad hoc (Accessibility grant resets every build).
- Do not use `.skipsHiddenFiles` when scanning apps: `/Applications/Safari.app`
  is a hidden symlink into the Safari cryptex.
- Do not use Carbon `RegisterEventHotKey` for bindings: sequences need the
  tap, and macOS 15+ rejects Option-only hotkeys there.
- Do not add docs or drive-by refactors unless asked.

## Workflow

- `git fetch --all --prune` and `git status -sb` before changing code.
- Branches `<handle>/<topic>`; never push to `main`. Open a PR.
- Run `test` and `benchmark` before pushing; paste benchmark deltas in the PR
  when a hot path changed.
- If you only ran compile-only validation, say so. Event tap, Hyper,
  selection and launcher behaviour are covered by `selftest`; run it.

## Status

`docs/MANIFESTO.md` holds the principles every feature answers to (asked
2026-10-15; rewritten 2026-10-18: every claim true today, the interaction
rules folded in, "taught once, then quiet"). Its words are chosen one by
one: change them only with the maintainer. `docs/FEATURES.md` lists everything skil.li does, one section per Settings
pane in the sidebar's order (2026-10-16): how each feature is reached,
what it does, its settings. Add a feature there in the same change that
builds it; `FeaturesDocTests` fails when a Catalog entry, a setting or a
pane is missing from it.

See `docs/implementation-status.md` for built vs. not-yet-built and how
each was verified. Update it when shipping meaningful milestones.
