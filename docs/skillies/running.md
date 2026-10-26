# How a skillie runs

What skil.li does when a skillie runs, whoever started it (the launcher, a
key, Ask, an agent, a link, the menu bar). The code: `ScriptLibrary.run`
(`Sources/Skilli/Scripts/ScriptLibrary.swift`), `ChildProcess.run`
(`Sources/Skilli/AI/ClaudeCLI.swift`), `SkillieEnvironment`
(`Sources/SkilliCore/SkillieEnvironment.swift`). Change this page with them.

## Before it starts

1. **Confirmation.** With `@skilli.needsConfirmation true`, the card asks
   "Run “…”?" first, every time (inline line reads excepted). Without it, a
   link asks first, unless you chose Always for that skillie with those
   arguments; a skillie that asks by itself is not asked twice, and offers
   no Always.
2. **Arguments.**
   - From the launcher, each is asked in turn.
   - From a link with fewer values than required, the launcher asks for
     all of them (the link's values are not kept). `arg=` with nothing
     after it passes an empty value.
   - From a key: a skillie with a required argument opens the launcher on
     its first one, as from the launcher; one whose arguments are all
     optional (or that has none) runs at once, with empty strings.
   - An agent calling `run_skillie` without a required one gets an error
     naming it.

## The process

| What | Value |
| --- | --- |
| Program | The file itself when it is executable. Otherwise the interpreter its first line names (`#!/usr/bin/env python3` → `/usr/bin/env python3 <file>`); the `#!` must name an absolute path. |
| Arguments | One per declared argument, in order (`$1`, `$2`, `$3` / `sys.argv[1:]` / `process.argv.slice(2)`), empty strings for optional ones left empty, percent-encoded where asked. |
| Folder | `@skilli.currentDirectoryPath` (with `~` expanded), else the script's own folder. |
| Standard input | Empty (`/dev/null`): a script that reads stdin gets end of file at once. |
| Output | Standard output and standard error together, as one text. Terminal colour codes are taken out. |
| Environment | skil.li's own environment, with the changes below. |
| Time limit | **120 seconds**; **10 seconds** for an inline line read by itself (launcher row, menu bar). |
| Exit status | 0: success. Anything else: the card shows it as a failure. |

### Environment

- **PATH**: the folder of the program started (the script's own folder
  when it is executable, else the interpreter's), then `/opt/homebrew/bin`,
  `/usr/local/bin`, `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`, then the PATH
  skil.li itself got from macOS. Your shell's startup files (`.zshrc`,
  `.zprofile`) are **not** read: a tool installed in `~/.local/bin`, by
  `nvm`, `pyenv` or `asdf` is not found unless the script adds it or calls
  it by its full path.
- `USER` is always set.
- Removed: `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `HTTPS_PROXY`,
  `HTTP_PROXY`, `ALL_PROXY`. A skillie that needs one sets it itself.
- Added, so the script can call skil.li back
  ([calling-skilli.md](calling-skilli.md)):

  | Variable | Value |
  | --- | --- |
  | `SKILLI_CLI` | The path of the skil.li binary running it. `"$SKILLI_CLI" call <tool> …` waits for a tool's answer. |
  | `SKILLI_SOCKET` | Where that skil.li's tools listen. `Skilli call` and `Skilli mcp` use it instead of the usual address. |
  | `SKILLI_SKILLIE` | This run's id. skil.li uses it to show the skillie's tool calls in its own card, under its name. |

  The three are set together, or not at all when skil.li's tool server is
  not running. Test for `SKILLI_CLI` before relying on it:

  ```bash
  if [ -z "$SKILLI_CLI" ]; then echo "Run me from skil.li."; exit 1; fi
  ```

### The time limit

At the limit, skil.li sends SIGTERM to the skillie **and every process
still in its process group** (what it started, unless one moved to a group
of its own, as `setsid` does), then SIGKILL three seconds later. A
`"$SKILLI_CLI" call` the skillie was waiting for stops with it, and a
question still open in the card for it goes away.

Background processes stay in that group:

- One that keeps the output open (`long-job &` without redirecting its
  output) keeps the run going until the limit: the card waits for it.
- At the limit (120 s after the start, even when the script itself has
  ended), whatever is still in the group is stopped, `nohup` or not.

To start something that must outlive the skillie, hand it to macOS: `open`
an app, a file or a URL.

## While it runs

- The card says "Running “Title”…", unless `@skilli.showsRunning false`.
- When the skillie calls one of skil.li's tools and that call has to ask
  you (the approval mode, the tool's right), the question takes the
  skillie's own card, one call at a time; esc declines that call alone:
  the `call` exits 1 and the skillie goes on. With
  `showsRunning false`, its calls take the card as any agent's do.
- Skillies that show the "Running…" card run one after the other: the
  next one starts once the card has closed. `showsRunning false` ones, an
  agent's `run_skillie` and inline reads can run alongside.
- An inline skillie is never read twice at once by the launcher, nor twice
  by the menu bar (the two can overlap).

## After it runs

| Mode | Success (exit 0) | Failure (exit ≠ 0) |
| --- | --- | --- |
| `silent` | Last non-empty line, 2 s | Last line, as an error |
| `compact` | Last non-empty line | Last line, as an error |
| `fullOutput` | All of the output, scrollable | All of the output, as an error |
| `inline` (run with ↩) | Last non-empty line | Last line, as an error |
| `inline` (read by itself) | Last non-empty line beside its title in its row; in the menu bar | The same: the exit status is ignored. Nothing printed: an empty spot in the row, the title in the menu bar |

Printed nothing and exit 0: the card closes, nothing said. Printed nothing
and failed: "“Title” failed (exit N)."

To an agent, `run_skillie` returns the whole output (its last 8,000
characters), or "Done." for none; a failure returns an error with the exit
status and the last 2,000 characters.

## Inline skillies

An inline skillie with no arguments is read without anyone running it:

- **In the launcher**: when the launcher opens and its line is older than
  `@skilli.refreshTime` (10 s by default and at least), it runs in the
  background and its row updates.
- **In the menu bar** (Settings → Skillies → In the menu bar): at once,
  then every `refreshTime` (1 minute by default, 10 s at least). The menu
  bar shows its icon and its line: an emoji before the line (32
  characters at most in all), an image file as a small picture; a click
  shows the whole line, Refresh Now, and Remove from Menu Bar.

Neither asks first, even with `needsConfirmation`, and the exit status is
ignored: the line is whatever it printed last.

So keep an inline skillie quick (well under 10 s), read-only and cheap: it
may run every time you open the launcher.

```bash
#!/bin/bash

# @skilli.schemaVersion 1
# @skilli.title Battery
# @skilli.mode inline
# @skilli.icon 🔋
# @skilli.refreshTime 5m

pmset -g batt | grep -Eo '[0-9]+%' | head -1
```

## When the folder changes

skil.li keeps the list in memory and reads it again only when the skillies
folder itself changed (its modification date): a file added, removed or
renamed in it. Most editors save by replacing the file, which counts.

- A change to a script's code is always picked up: the file is read at
  each run.
- A header change in a subfolder, or one written in place (`>>`, some
  editors), is not seen until the folder changes. Touch it:

  ```bash
  touch ~/Library/Application\ Support/skil.li/skillies
  ```
