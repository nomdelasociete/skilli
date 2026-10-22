# Live checks, 2026-10-21

Features merged but never run for real, tried on the test Mac (the Mac
mini of "Where tests run", AGENTS.md) with main's build. What ran, what it
showed, and what could not run there and why.

| Feature | Result |
|---|---|
| "relance le wifi" with a Restart Wi-Fi skillie | **Failed, fixed** (this PR) |
| Type in English while open | **Worked** |
| Bluetooth connect | **Could not run here**: skil.li is not allowed to use Bluetooth there yet |
| Quicklinks: Reuse an open tab | **Could not run here**: the default browser there is one the feature does not script |
| Wi-Fi off, Restart Wi-Fi | **Could not run here**: no wired connection, Wi-Fi off cuts the session running the test |
| Meeting card: the live camera | **Could not run here**: no camera |
| Spotlight's ⌘Space handed to the launcher | **Could not run here**: needs a setting change |

## "relance le wifi" picked Turn Wi-Fi On over the Restart Wi-Fi skillie

`remote scripts` (`askRunsScripts`: a fixed list of skillies, Restart Wi-Fi
"Turns Wi-Fi off and on again", decided only), three runs on main:
TypeSafe Jev chose Turn Wi-Fi On once (90 %), the skillie twice (88 %,
75 %). OpenAI Decisions chose the skillie each time (95 %). The traces
(`Ask command “relance le wifi”`) show why: Jev's command question gave
`wifiOn` 56–90 % although its description says "not restart it", and
OpenAI 13 %. The description's French example, "(rallume le wifi)",
reads close to "relance le wifi".

Measured, the command question alone with three wordings of Turn Wi-Fi
On: `wifiOn`'s probability in %, Jev's range over 4 tries, then OpenAI's
(2 tries, the same answer each time):

| Wording | relance le wifi | rallume le wi-fi | active le wifi | turn the wifi back on |
|---|---|---|---|---|
| main: "(rallume le wifi); not restart it" | Jev 60–65, OpenAI 21 | 98, 98 | 91–94, 62 | 93–95, 97 |
| no French example | Jev 25–28, OpenAI 3 | 90–94, 69 | 89–93, 59 | 92–93, 95 |
| **"(allume le wifi); not restart it (off then on again)"** | **Jev 27–34, OpenAI 3** | **94–95, 98** | **88–92, 76** | **88–93, 98** |

Naming "relance le wifi" in the negative ("not restart it (relance le
wifi…)") helped Jev (23–33 %) but made OpenAI worse (54 %).
The fix keeps a French example that is not "relance": `SystemCommand`'s
decision description for `wifiOn`. After it, `remote scripts` twice and
`remote decide` once: "relance le wifi" → Restart Wi-Fi each time (Jev
89 %, 82 %, 85 %; OpenAI 95 %), and `askRunsNewMacCommands` still picks
Turn Wi-Fi On for "rallume le wi-fi" and Turn Wi-Fi Off for "coupe le
wifi" on both providers.

## Type in English while open

The test Mac has French only, where the check proves nothing switches. For
this run, ABC was turned on there (`TISEnableInputSource`) and turned off
right after (`TISDisableInputSource`: French only again, French selected).
`remote rootsearch`, all checks passed; `typesInEnglishWhileOpen`: "French
→ ABC while open (English: ABC), bindings held: true, “a” on the same key:
true, ⌘K: true, back to French". skil.li's trace: `Type in English:
com.apple.keylayout.French → com.apple.keylayout.ABC`. Settings →
Launcher → Advanced says "While the launcher is open your keyboard types
as ABC…" (`settings-launcher-english-light.png`).

## Bluetooth connect

`Skilli call list_bluetooth_devices` on the test Mac answered "macOS is
asking the user to let skil.li use Bluetooth: try again once they allowed
it.", and macOS's Bluetooth question for skil.li came up on its screen.
Answering it is a person's click. Once allowed there, the next run is:
`list_bluetooth_devices`, then `connect_bluetooth_device` on a paired
accessory nobody is using at that moment (a connected keyboard or
headphones move to that Mac), then the same tool to disconnect it.

## Quicklinks: Reuse an open tab

Only Safari and Chrome's family are scripted (`BrowserTabReuse`); the test
Mac's default browser is one `BrowserTabReuse` does not script, so a
quicklink opens a new tab there by design. Running it needs Safari or Chrome made the default browser there,
which macOS confirms with a click, and the browser's Automation permission
for skil.li. Not run.

## Wi-Fi off, Restart Wi-Fi

The test Mac has no wired link: turning
Wi-Fi off would cut the session that runs the test, and a Restart Wi-Fi
skillie turns it off first. Not run: needs the test Mac on a cable. What
runs without switching anything is already covered: the launcher's one
row the way Wi-Fi can go, the other way as a dry run (`selftest calc`),
and the decisions above.

## Meeting card: the live camera

The test Mac has no camera (`system_profiler SPCameraDataType` lists
none); `selftest card` already captures the check on a still image with
"No camera". Needs a Mac with a camera.

## Spotlight's ⌘Space handed to the launcher

`SpotlightKey` turns Spotlight's ⌘Space off only when it is on, and back on
only when skil.li was the one that turned it off. On the test Mac,
Spotlight's ⌘Space is already off (entry 64 of
`com.apple.symbolichotkeys`: `enabled = false`), so nothing would change.
Running it needs Spotlight's ⌘Space turned on there first: not done.

## Seen along the way (not fixed here)

`remote decide` fails two checks on main, the same with and without the
fix, both with OpenAI Decisions: "rappelle-moi dans une heure trente de
sortir le linge" is routed to a timer instead of a reminder
(`askReadsPlans`, 12/13), and "ouvre mon portfolio" goes to the
open-an-app route instead of the portfolio project (`askOpensProjects`).
