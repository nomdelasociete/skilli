# Pick from a list: `Skilli pick`

Status: spec 2026-11-05, not built. Idea taken from vicinae
(github.com/vicinaehq/vicinae, GPL-3.0), whose `vicinae dmenu` reads a
list on standard input, shows it in its launcher and prints the row picked.
The name and the Unix habit come from dmenu.

## Short answer

A script pipes lines into `Skilli pick`. The launcher opens on those lines,
searched as the launcher searches. ↩ prints the row picked on standard
output and exits 0. esc exits 1. Any skillie, any Terminal script and any
agent can then let the user pick from a hundred branches, hosts or files
without building a view. Today the only way is `ask_user`, which shows at
most 9 options in the card and has no search.

```bash
branch=$(git branch --format='%(refname:short)' | "$SKILLI_CLI" pick --prompt Branch) &&
  git switch "$branch"
```

## Moment

1. **When.**
   - *A skillie needs one of many*: a git branch, an SSH host from
     `~/.ssh/config`, a Kubernetes context, a folder under `~/Projects`,
     a line of a log. Today it asks for a typed argument (the user must
     know the exact name) or calls `ask_user` (9 options at most, no
     search).
   - *A Terminal script*: the same need outside skil.li, where people
     reach for `fzf` in the terminal. `Skilli pick` gives them the
     launcher instead, over whatever app is in front.
   - *An agent* (Ask, Claude Code through `Skilli mcp`) that has a long
     list to put in front of the user: `pick_from_list`.
   - *Not*: a choice among 2–6 answers (`ask_user` stays the right card),
     a typed answer (`ask_user` without options), a form.
2. **The path.** The script runs; the launcher comes forward in a mode
   whose chip is the prompt, with the rows in it. The user types to narrow
   the list, ↑↓ or ⌘1–⌘9 to choose, ↩ to pick. The launcher closes, and
   focus goes back to the app that was in front (Terminal, for a Terminal
   script). The script goes on with the answer.
3. **Hint or push.** Neither. The list opens because the user ran the
   script. Nothing is announced when it closes.
4. **Deterministic or AI.** Code only. Rows are matched with
   `FuzzyMatcher` (`Sources/SkilliCore/FuzzyMatcher.swift`), as the
   launcher's own rows are. No ⇥ Ask, no meaning search: the list is the
   script's, and a model has nothing to add to "which of these". The
   picker sends the rows nowhere, stores none, and never feeds them to
   the launcher's learning. The row picked goes back to the caller only.
   When the caller is an agent (Ask, Claude Code through `Skilli mcp`),
   that row is a tool result, and it reaches the agent's provider like
   any other tool result.
5. **Wrong.**
   - *The wrong row picked*: the script acts on it, as it would on a
     mistyped argument. A script that does something it cannot undo asks
     with `ask_user` after the pick, as it would after a typed argument.
   - *Closed by mistake* (esc, a click elsewhere): exit 1, the script
     stops or asks again. Nothing is half done by skil.li.
   - *The launcher was in use*: the pick replaces what it showed (the user
     started the script from it, or from a key). What was typed before is
     not brought back after the pick.

## Calling it

Three ways, one code path: the CLI's `pick` is `call pick_from_list` with
the items read from standard input, so approvals, exits and limits are the
same everywhere.

### `Skilli pick`

```bash
<lines> | Skilli pick [--prompt <text>] [--query <text>] [--index] [--custom] [--keep-order] [--socket <path>]
<lines> | "$SKILLI_CLI" pick …          # from a skillie
```

| Option | What it does | Default |
| --- | --- | --- |
| `--prompt <text>` | The mode's chip and the search field's placeholder. | `Pick` |
| `--query <text>` | Text already typed when the list opens. | empty |
| `--index` | Prints the picked row's line number in the input (1 first; skipped empty lines still count, so `sed -n "${n}p"` finds it) instead of its text. Useful when lines repeat. Not with `--custom`: typed text has no line number, so both together are written wrong (exit 2). | off |
| `--custom` | ↩ with no row matching prints what was typed. The last row reads `Use “…”`. | off |
| `--keep-order` | Matches keep the input's order instead of being ranked. Use it for lists already sorted by the script (recent first). | off |
| `--socket <path>` | Another skil.li, as for `call`. | |

Standard input is read to its end before anything shows, with three
bounds:

- If a limit is crossed while reading (see [The list](#the-list)),
  reading stops at once and the command exits 1. Nothing opens.
- If no new byte arrives for 30 s, reading stops and the command exits 1
  (`Nothing came on standard input for 30 s`). Nothing opens. A slow
  producer that keeps writing, such as `find` over a big folder, is not
  cut off.
- If standard input is a terminal (`Skilli pick` typed with no pipe), the
  command exits 2 at once (`Pipe lines into pick`).

A skillie's own
standard input is `/dev/null` (`running.md`), so a skillie always pipes
its own lines into `pick`. It never forwards its standard input.

### `pick_from_list`

| Tool | What it does | Arguments |
| --- | --- | --- |
| `pick_from_list` | Shows a list in the launcher and returns the row the user picked. | `items` (list), `prompt?`, `query?`, `output?` (`text` or `index`), `custom?`, `keep_order?` |

The right is the same as `ask_user`'s (risk none). It only shows text the
caller gave and returns what the user chose. Listed in
[calling-skilli.md](../skillies/docs/calling-skilli.md) under "Talking to
you", next to `ask_user` (`SkillieDocsTests` checks that it is there).

### No `skilli://` link

Decided 2026-11-05. A link returns nothing to whoever opened it, and a
pick whose answer goes nowhere serves no one. This is the one feature
without a link. If one is ever needed, it is a link that runs a skillie,
and that skillie calls `pick`.

## The list

- One row per line, UTF-8. `\r\n` and `\n` both end a line. Empty lines
  are skipped. Repeated lines are kept, since `--index` tells them apart.
- A line is shown on one row, cut with "…" past the row's width, and
  returned whole.
- A line that is an absolute path to an existing file or folder gets that
  file's icon, its name as the title and its folder as the subtitle.
  Picking it still prints the line as given.
- **Limits**: 10,000 lines and 1 MB at most. Past either limit nothing
  opens: exit 1, `More than 10,000 lines` or `More than 1 MB`. Nothing is
  cut silently, because a missing row would look like a row that does
  not exist.
- No lines at all: exit 1, `Nothing to pick from`. Nothing opens.

## In the launcher

- The launcher's own window, in a mode whose chip is the prompt. The empty
  query shows every row in input order. Typing ranks the matches by
  `FuzzyMatcher` score (ties keep input order), or keeps the input order
  with `--keep-order`.
- ↩ picks. ⌘1–⌘9 pick a visible row
  ([launcher-row-numbers-hex.md](launcher-row-numbers-hex.md)). ⌘C copies
  the row's text, and the list stays open. ⌘K shows Pick and Copy, nothing
  else: the row is text the script owns, so there is nothing more to do
  with it here.
- esc, a click outside the launcher, or another app coming forward
  dismisses the list. All three exit 1 with `Dismissed`.
- ⇥ does nothing in this mode: no Ask, no actions panel.
- A second pick while one is open waits its turn, and opens when the first
  one closes. At most 4 can wait. A fifth exits 1 with
  `Too many lists waiting`.
- A caller that goes away (Ctrl-C in Terminal, a skillie stopped, an
  agent ended) takes its list with it: an open list closes, and a waiting
  one is dropped before it opens and stops counting toward the 4. skil.li
  sees it on the socket. The connection's read loop ends when the caller's
  end closes, and `MCPSocketServer` calls its `onClose`
  (`Sources/Skilli/Tools/MCPSocketServer.swift`). The picks for that
  connection go at that point.

## Output and exits

| Exit | When | Standard output | Standard error |
| --- | --- | --- | --- |
| 0 | A row picked (or typed text with `--custom`) | The row's text, or its line number with `--index`, then `\n` | |
| 1 | Dismissed, nothing to pick from, over a limit, standard input silent for 30 s, too many waiting, skil.li not running and not startable | | Why, one line |
| 2 | Written wrong (unknown option, `--prompt` with no value, `--index` with `--custom`, standard input a terminal, not UTF-8) | | Usage |

These are the same codes as `Skilli call`. A shell `&&` after `pick` runs
only on a pick.

## Time

A skillie is stopped after 120 s (`ScriptLibrary.timeout`, a wall-clock
limit). Time spent while a list is open, or waiting its turn behind
another, must not count against it. Neither should time spent while
`ask_user`'s card waits: check how `ChildProcess.run` counts it today,
and fix both the same way. Without the limit, nothing else would end an
unanswered list or card. So a list left open, and an `ask_user` card left
unanswered, are dismissed after 10 minutes (exit 1, `Dismissed`), and a
forgotten script does not wait forever. Time spent waiting in the queue
counts toward those 10 minutes only once the list is open.

## Speed

North star: the list shows in the frame after its data arrives.

- `benchmark` gains a pick of 10,000 lines: time from the request on the
  socket to the first frame drawn, and time per keystroke while filtering.
  Both stay inside the launcher's current budget. Candidates
  (`FuzzyCandidate`) are built once, off the main thread, before the list
  shows.
- Nothing is loaded or kept when no pick is open.

## Tests

- `SkilliCore`: parsing the input (line endings, empty lines, repeats,
  limits, UTF-8), the CLI's options and exit codes, `--index` (line
  numbers counting the empty lines skipped) and `--custom` answers. Also
  a pipe held open with no data (exit 1 after 30 s), and input stopped as
  soon as it crosses a limit.
- `selftest scripts` (on the test Mac, with its lock): a skillie pipes
  three lines into `pick`, types a query, picks with ↩ and checks its
  output. Then esc for exit 1, `--index`, `--custom` with no match,
  `--index --custom` refused, a second pick waiting for the first, and a
  waiting pick whose caller is killed (it never opens).
- `SkillieDocsTests`: `pick_from_list` listed in calling-skilli.md.

## Docs to update when built

- [calling-skilli.md](../skillies/docs/calling-skilli.md): the tool, and a
  `Skilli pick` section next to "Outside a skillie".
- [skillies/README.md](../skillies/README.md): one recipe (switch git
  branch).
- [FEATURES.md](FEATURES.md) under Skillies, and the skillies guide
  (`website/guides/skillies.md`).

## Phase 2 (not built)

- `--multi`: several rows picked (⌘↩ marks one, ↩ returns every marked
  row, one per line).
- Rows with a subtitle or an icon: tab-separated fields, or JSON lines
  with `--json`.
- Space or ⌘Y previews a file row with Quick Look, as vicinae does for
  paths.
