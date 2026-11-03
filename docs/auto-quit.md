# Auto Quit: only the apps you list, each its own delay

Status: built 2026-11-03. Unit tests: `AutoQuitTests`, `PrivacyMapTests`,
`SettingsTableTests`, `FeaturesDocTests`. Self-tests in the app: `remote
calc` (`autoQuitKeepsWhatIsInUse`) and `remote settings` (the pane drawn,
every pane fits) pass on the test Mac.

## What went wrong

Auto Quit was off by default, yet it ran on the test Mac and quit a VPN
client (three times in a day, each after an hour), Docker Desktop and a
browser. Its log there (`subsystem == "com.nomdelasociete.Skilli"`,
"Auto Quit:") names each quit.

- **How it got on.** Self-tests change the real settings and put them
  back in a `defer`. The Settings capture test turned Auto Quit on (with
  TextEdit as the app never quit) to draw it; a run killed before its end
  (a watchdog, another run) never put it back. The test build shares the
  app's bundle id, so its settings are the app's, and `remote` reopens that
  build as the test Mac's own skil.li afterwards. The test Mac's settings
  held exactly the test's values: on, TextEdit never quit.
- **Why it hurt.** On, it quit every app with a Dock icon but a few kept
  ones, after one delay for all. A VPN client or Docker shows a Dock icon
  there; to the rules and to Jev ("no window open") they looked unused.
- **Why it was hard to fix.** The settings sat in Windows, under the
  window gap and Arrange Windows, the list shown only once on; four delays
  to pick from, the same for every app.

## Moment

1. **When**: an app the user leaves open for nothing (a heavy editor, a
   chat app, a game launcher) holds memory all day; they decide once which
   ones go, and after how long.
2. **The path**: Settings → Auto Quit, its own pane in the sidebar
   (Catalog's Auto Quit opens it, as does the settings search). Turn it
   on, Add an App…, pick its delay. Agents: `set_setting` `autoQuitApps`
   "Arc: 2 hours".
3. **Push, but only what was asked**: the app is quit without a word, as
   the user set it; one that does not quit is said.
4. **Deterministic first**: when the user last had it in front, its
   delay, then what the Mac says (unsaved work, sound, CPU). Jev reads the
   titles only of an app already due, with a deciding key.
5. **Wrong**: an app quit the user still needed: only an app they listed
   can be, never one they did not name. Unsaved work, a call or a running
   task keep it.

## Decided

- Off by default. The pane shows the toggle, then the list, always (off,
  the list stays as set, nothing hidden behind the toggle).
- Only the apps listed are ever quit (`autoQuitApps`: bundle id and
  minutes). An app not listed stays open however long it goes unused.
- Each app its own delay: 15 min, 30 min, 1 h, 2 h, 4 h, 8 h, 1 day, or
  Custom…, any time typed from 5 minutes to 7 days ("90 min", "3 h",
  "1h30", "2 jours"; `AutoQuit.minutes(from:)`). A new app gets 1 hour.
- The settings from before (one delay for every app, Never quit) say
  nothing of which apps to quit: they are dropped and Auto Quit starts
  again off.
- The self-test's settings are a copy of the user's in a suite of its own
  (`skilli-selftest-preferences-<pid>`), dropped when it ends; a run killed
  before its end leaves the real settings untouched, and the next run drops
  its copy. No check can leave a setting on in the app the user runs.
