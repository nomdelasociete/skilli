# Skillie header reference

The header is a block of comments near the top of the script. skil.li reads
it with `ScriptCommand.parse` (`Sources/SkilliCore/ScriptCommand.swift`):
change this page when that function changes.

```python
#!/usr/bin/env python3

# @skilli.schemaVersion 1
# @skilli.title Convert Currency
# @skilli.mode compact
# @skilli.packageName Money
# @skilli.icon 💱
# @skilli.description Converts an amount with today's rate
# @skilli.argument1 { "type": "text", "placeholder": "Amount" }
# @skilli.argument2 { "type": "dropdown", "placeholder": "To", "data": [{ "title": "Dollars", "value": "USD" }, { "title": "Pounds", "value": "GBP" }] }
# @skilli.needsConfirmation false
```

## How it is read

- Only the first **60 non-blank lines**, and only the first **8 KB** of
  the file.
- A header line starts with `#` or `//` (spaces before it are fine), then
  `@skilli.<key>`, at least one space, then the value to the end of the
  line. Block comments (`/* */`, AppleScript's `--`) are not read: use `//`
  in JavaScript and Swift, `#` everywhere else.
- `@raycast.<key>` is read the same way.
- A key given twice: the last one wins.
- Unknown keys are ignored, so a Raycast header with keys skil.li does not
  use (`author`, `authorURL`) still works.
- The file is a skillie only when it has a non-empty **title**, a valid
  **mode**, and a `schemaVersion` that is `1` or absent. Otherwise it is
  silently left out.

## Keys

| Key | Required | Value | What it does |
| --- | --- | --- | --- |
| `schemaVersion` | no (write it) | `1` | Any other value: not a skillie. |
| `title` | **yes** | text | The name in the launcher, Settings and the card. Ask and `run_skillie` find it by title; keys and links by its file path. Keep it unique: `create_skillie` refuses a title taken, and a `.skilli` file with the same title replaces yours. |
| `mode` | **yes** | `silent`, `compact`, `fullOutput`, `inline` | What a run shows. See [Modes](#modes). |
| `description` | no | one line | Under the title in Settings, in the card a link asks with, in `list_skillies`, and what Ask matches against. |
| `packageName` | no | text | Groups skillies in Settings → Skillies ("Developer Utils"). |
| `icon` | no | emoji, or an image file | An emoji, or a path to a PNG/JPEG: absolute, or relative to the script's folder. Web addresses are not loaded. Without one: a terminal icon. |
| `argument1`, `argument2`, `argument3` | no | JSON object | Up to three arguments, passed as `$1`, `$2`, `$3`. See [Arguments](#arguments). |
| `needsConfirmation` | no | `true` / `false` (default) | `true`: asks in the card before every run, from anywhere, even when `run_skillie` is allowed without asking, and Always is never offered. An inline skillie's automatic line reads do not ask. For what changes or deletes things. It asks; it does not sandbox. |
| `showsRunning` | no | `true` (default) / `false` | `false`: no "Running…" card while it runs. For a skillie that draws something of its own (a confetti cannon). Its final line or its error still shows. skil.li only. |
| `refreshTime` | no | `10s`, `5m`, `1h`, `1d` | Inline only: how old its line may get before it is read again. 10 seconds at least. Without it: 10 s in the launcher, 1 min in the menu bar. |
| `currentDirectoryPath` | no | a path, `~` allowed | The folder it runs in. Default: the script's own folder. |

## Modes

| Mode | While it runs | After it runs |
| --- | --- | --- |
| `silent` | "Running…" card | Its last non-empty line, for 2 seconds. |
| `compact` | "Running…" card | Its last non-empty line, about 4 seconds. |
| `fullOutput` | "Running…" card | All of its output in the card (scrolls), about 20 seconds. |
| `inline` | — | Its last non-empty line is shown in its launcher row, and in the menu bar if you put it there. Run with ↩ it behaves like `compact`. |

In every mode: a run that prints nothing closes the card with nothing said;
a run that exits with a non-zero status shows its last line (all of it in
`fullOutput`) as a failure, or "… failed (exit N)" when it printed nothing.

An **inline** skillie with no arguments runs by itself: each time the
launcher opens and its line is older than `refreshTime`, and on its own
timer when it is in the menu bar. Keep it fast (10 seconds at most) and
free of side effects. An inline skillie with arguments only runs when you
run it.

## Arguments

Each argument is one JSON object on one line:

```bash
# @skilli.argument1 { "type": "text", "placeholder": "Query" }
# @skilli.argument2 { "type": "password", "placeholder": "Token", "optional": true }
# @skilli.argument3 { "type": "dropdown", "placeholder": "Size", "data": [{ "title": "Small", "value": "s" }, { "title": "Large", "value": "l" }] }
```

| Field | Value | Meaning |
| --- | --- | --- |
| `type` | `text`, `password`, `dropdown` | Required. Anything else: the argument is ignored. |
| `placeholder` | text | What the launcher asks for. Default: "Argument" ("Choose" for a dropdown). |
| `optional` | `true` / `false` (default) | An optional argument can be left empty; the script still gets it, as an empty string. |
| `percentEncoded` | `true` / `false` (default) | The value is percent-encoded before the script gets it (for a URL). |
| `data` | `[{ "title": …, "value": … }]` | Dropdown only, required: the choices. `value` defaults to `title`. A dropdown without choices is ignored. |

- Only `argument1` to `argument3` are read, in that order; a gap is closed
  (`argument1` and `argument3` give `$1` and `$2`).
- The script always gets one value per declared argument, empty for an
  optional one left empty.
- In the launcher, arguments are asked one after the other (↩: next, then
  run). A dropdown shows its choices as rows. A password shows as dots in
  its row.
- From a link, a dropdown value must be one of its `value`s.

## Comment style by language

| Language | Shebang | Comment |
| --- | --- | --- |
| Shell | `#!/bin/bash`, `#!/bin/zsh`, `#!/bin/sh` | `#` |
| Python | `#!/usr/bin/env python3` | `#` |
| Ruby | `#!/usr/bin/env ruby` | `#` |
| Perl | `#!/usr/bin/perl` | `#` |
| Node | `#!/usr/bin/env node` | `//` |
| JavaScript for Automation | `#!/usr/bin/osascript -l JavaScript` | `//` |
| Swift | `#!/usr/bin/swift` | `//` |

What each interpreter needs installed (nothing, Xcode's Command Line Tools,
Homebrew) is in the collection's guide:
[What runs on every Mac](../../skillies/README.md#what-runs-on-every-mac).

## Website-only keys

The community collection's build (`website/build.py`) also reads
`@skilli.requires` (`xcode-tools`, `homebrew:<formula>`), to say on the
website what a skillie needs. The app ignores it. See
[`skillies/README.md`](../../skillies/README.md).
