# Skillies

A skillie is one of skil.li's own commands: a script on your Mac whose
first comments give it a title. skil.li finds it, lists it in the launcher,
asks for its arguments, runs it and shows what it printed. Ask and your
agents can run it too, a key can run it, a link can run it, and an inline
one can sit in the menu bar.

Any language with a shebang works: shell, Python, JavaScript (Node or
JavaScript for Automation), Swift, Ruby, AppleScript… The header is
Raycast's Script Command metadata under skil.li's name (`@skilli.` instead
of `@raycast.`), so a Raycast script needs one word changed.

This folder is the reference. It is kept next to the code: change it in the
same pull request as the behaviour it describes.

| Page | What it answers |
| --- | --- |
| This page | What a skillie is, a first one in two minutes, where they live, every way to run one, safety |
| [Header reference](header.md) | Every `@skilli.` key: title, mode, arguments, icon, confirmation, refresh… |
| [How a skillie runs](running.md) | The process: interpreter, folder, environment, PATH, time limit, output, modes, errors |
| [Calling skil.li from a skillie](calling-skilli.md) | `"$SKILLI_CLI" call <tool>`, `skilli://` links, and every tool a skillie can call |
| [Community collection](../../skillies/README.md) | Contributing a skillie to the website, what runs on every Mac, recipes for skil.li's features |
| [Skillie files](../skillie-files.md) | The `.skilli` file format and import links (design notes) |

## A first skillie in two minutes

1. Open Settings → Skillies → Show in Finder. The folder is
   `~/Library/Application Support/skil.li/skillies`.
2. Save this as `hello.sh` in it:

   ```bash
   #!/bin/bash

   # @skilli.schemaVersion 1
   # @skilli.title Say Hello
   # @skilli.mode compact
   # @skilli.icon 👋
   # @skilli.description Greets someone by name
   # @skilli.argument1 { "type": "text", "placeholder": "Name" }

   echo "Hello, $1!"
   ```

3. Open the launcher, type `say hello`, press ↩, type a name, press ↩.
   The card says `Hello, Camille!`.

No restart, no build: skil.li reads the folder again when it changes. The
file does not even need to be executable; skil.li then runs it with the
interpreter its shebang names.

The fastest way to write one: ask your SI ("make me a skillie that flushes
the DNS cache"). Its agent writes the file with the `create_skillie` tool,
and the new skillie is in the launcher at once.

## Where skillies live

- `~/Library/Application Support/skil.li/skillies`, and one level of
  subfolders in it (`tools/deploy.sh`). Deeper folders are not read.
- Hidden files and Raycast's `*.template.*` files are left out.
- A file is a skillie when its first 60 non-blank lines (within the first 8 KB) give
  at least `@skilli.title` and `@skilli.mode`. Anything else in the folder
  (a README, a helper script, an image for an icon) is ignored.
- Settings → Skillies lists them, grouped by `@skilli.packageName`, with a
  magnifier that shows each file in the Finder. To remove one, delete its
  file.

## Every way to run one

| From | How | Notes |
| --- | --- | --- |
| The launcher | Type its title, ↩ | Arguments are asked one after the other in the launcher. An inline one shows its line right in its row. |
| A key | Settings → Keys → Add Shortcut → Skillies | Like any other command. One with a required argument opens the launcher to ask it; one without runs at once. |
| Ask | Say what it does | Skillies that need no argument are among the commands Ask can pick. |
| Your agents | `list_skillies`, `run_skillie`, `create_skillie` | Through skil.li's MCP server (Claude Code, Codex…). See [calling-skilli.md](calling-skilli.md). |
| A link | `skilli://skillie/<path in the folder>?arg=…` | From another app, Shortcuts, a Stream Deck, a web page. Asked first; see below. ⌘K → Copy Link on its row gives it. |
| The menu bar | Settings → Skillies → In the menu bar | Inline skillies without arguments only: their last line, refreshed on their own schedule. |

A link gives the arguments in order, one `arg=` each:

```bash
open "skilli://skillie/tools/deploy.sh?arg=staging&arg=fast"
```

With fewer values than required, the launcher asks for all of them. A
dropdown argument must be one of its values. A link to a skillie in a subfolder that was
moved still works when only one skillie has that file name.

## Safety

A skillie runs as you, with your files, your apps and your network. skil.li
does not sandbox it. What it does do:

- **Nothing runs on add.** A `.skilli` file or an import link opens
  Settings → Skillies on a sheet that shows the whole script, where it came
  from, and Add (or Replace). Exception to know: an inline skillie without
  arguments runs each time the launcher opens, to read its line; the sheet
  says so.
- **`@skilli.needsConfirmation true`** asks in the card before every run,
  even when an agent's `run_skillie` is allowed without asking (inline
  line reads excepted).
- **Links ask first.** A `skilli://skillie/…` link can come from any app or
  web page, so it asks before running, with the arguments it gives. Always,
  in that card, lets links run that skillie with those arguments at once
  (Settings → Catalog lists what you trusted). A skillie with
  `needsConfirmation` asks in its own card instead, every time.
- **Tool calls follow your rights.** When a skillie calls one of skil.li's
  tools (`"$SKILLI_CLI" call …`), the call is treated like any outside
  agent's: your approval mode and each tool's right decide whether it asks
  in the card. A skillie gets no extra rights.
- **A time limit.** A run is stopped after 120 seconds, with every process
  it started.

## Sharing a skillie

- **A `.skilli` file** is the script itself, renamed. Double-click it (or
  drop it on skil.li) and Settings → Skillies shows it whole before Add. One
  with the same title as yours replaces it, after you press Replace; its
  key and menu bar place follow.
- **An import link**: `skilli://skillies/import?url=https://example.com/the-script.sh`
  (up to 10 `url=`, https only, 256 KB each). Same sheet.
- **The community collection** on the website comes from this repository's
  [`skillies/`](../../skillies/README.md) folder: open a pull request there.

## Coming from Raycast

skil.li reads Raycast's Script Command header. `@raycast.` keys are
accepted as they are; renaming them `@skilli.` is the convention. What
differs:

- `@skilli.showsRunning` exists only in skil.li.
- Raycast's own script folders are never read in place: copy the scripts
  into skil.li's folder.
- `$SKILLI_CLI` and `skilli://` links reach skil.li's features from the
  script ([calling-skilli.md](calling-skilli.md)).

## When something does not work

| Symptom | Cause |
| --- | --- |
| Not in the launcher | Its title or mode is missing, the mode is not one of `silent`, `compact`, `fullOutput`, `inline`, the header is after the 60th non-blank line, `schemaVersion` is not 1, or the file is two folders deep. |
| "… is not executable: chmod +x …" | The file is not executable and its first line is not a `#!` naming an absolute path. |
| A command is "not found" | skil.li's PATH is not your shell's: it has Homebrew's folders and the system's, not what your `.zshrc` adds. Use full paths or set PATH in the script. |
| It stops after two minutes | The 120-second limit, which also stops what the script started in the background. Hand long work to macOS (`open` an app or a URL). See [running.md](running.md#the-time-limit). |
| It runs until the limit though it is done | A background process still holds its output: redirect it (`job >/dev/null 2>&1 &`). |
| A header change is not seen | skil.li reads the list again when the folder changes. See [running.md](running.md#when-the-folder-changes). |
| Colours or odd characters vanish | Terminal colour codes are taken out of the output. |
| An inline line shows only the title | It printed nothing within 10 seconds, the limit for an inline line. |
| The menu bar says "… did not answer" | The script could not be started (see "not executable" above). |
| `$SKILLI_CLI` is empty | Only skillies run by skil.li get it; a script run from Terminal does not. See [calling-skilli.md](calling-skilli.md). |
