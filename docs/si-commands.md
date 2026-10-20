# SI Commands — from rewriting text to acting

Status: 2026-10-11. Built: transform commands (prompt with variables, About
You, model, shortcuts, card with highlighted changes, files), **Phase 1,
Transform+** (output modes, questions in the card, modifiers, import/export
and the `skilli://commands/import` link), **Phase 2, Tools and Act** (skil.li's
MCP server and `Skilli mcp`, approvals in the card, Act commands on Claude
Code); decision keys and live tests in Settings → SI. This document is the
plan for the rest: commands that decide, run by voice, and a gallery of
templates. Engine background:
[ai-architecture.md](ai-architecture.md), [ai-engines.md](ai-engines.md).

## What the best do (researched 2026-10-11)

**Raycast** (v2.7), the reference:

- An AI Command has: prompt (`{` inserts a placeholder, `@` an AI extension or
  MCP server), name and icon, model, creativity, reasoning effort, output
  behavior (open in Raycast, or replace selection; v2.7 falls back to the
  clipboard when the paste fails), "Highlight Editing Changes", tags.
  Built-ins can be edited and duplicated, not deleted.
  [manual](https://manual.raycast.com/ai/ai-commands)
- Placeholders: `{selection}`, `{clipboard offset=1}`, `{date format offset
  locale}`, `{browser-tab selector}`, `{snippet}`, `{calculator}`,
  `{argument name default options}` (up to 3, asked before the run), modifiers
  `| trim | raw`; in AI commands values are wrapped in `"""`.
  [manual](https://manual.raycast.com/dynamic-placeholders)
- Templates: **Prompt Explorer** (ray.so/prompts), categories, model and
  author per card, multi-select, "Add to Raycast" opens
  `raycast://prompts/import?prompts=<JSON>` — but the payload only carries
  title, prompt, creativity, icon and model (output behavior is lost).
  [source](https://github.com/raycast/ray-so/blob/main/app/(navigation)/prompts/utils/actions.ts)
- Tools: `@extension` or `@mcpserver` in a prompt; MCP servers installed from a
  form (stdio or HTTP, OAuth), with status. Permissions: **Ask / Auto (read-only
  allowed, destructive always asked) / Always Allow**, per-chat override,
  editable rules; approval card **Allow ↵ · Always ⌘↵ · Deny Esc**.
  [manual](https://manual.raycast.com/ai/ai-extensions),
  [MCP](https://manual.raycast.com/ai/model-context-protocol)
- Agents (instructions, model, allowed extensions) and Skills (`SKILL.md`,
  read from `~/.claude/skills`), but **not in AI Commands**; v2.5 turned off
  automatic tool and skill loading there.
  [skills](https://manual.raycast.com/ai/skills.md),
  [2.5](https://www.raycast.com/changelog/macos/2-5)
- Questions: AI Chat has an "Ask User Question" tool; **v2.7: "AI Commands and
  automations no longer stop to show a question form"** — questions go into
  the reply. [2.7](https://www.raycast.com/changelog/macos/2-7)
- Users love the UX speed; they dislike the grammar fix being "too
  aggressive" and answers wrapped in quotes, AI pushed everywhere, BYOK behind
  Pro, credits pricing, v2 heavier and slower.
  ([blog](https://pawelgrzybek.com/from-grammarly-to-raycast-ai/),
  [HN](https://news.ycombinator.com/item?id=46025505),
  [pricing](https://www.raycast.com/blog/changing-how-raycast-ai-is-priced))

**Others, one idea each:** BoltAI — five output modes (new window, insert
before, insert after, replace, copy). Superwhisper — modes switch per app or
website, voice instruction on the selection. Apple Shortcuts "Use Model" —
typed output (bool, list, dictionary) feeding the next step, "Follow Up" to
refine. Alter — actions adapt to the app in front. Tuna — prompts as Markdown
files, key-sequence combos. Kerlig — BYOK, 350+ models, one-time price.

**Decision models:** OpenAI **Decisions API** (`POST /v1/decisions`,
`gpt-6-luna` only, public beta): `predicate` → probability, `choice` →
choice + probabilities + confidence, `score` → ordered levels; several
independent questions per request; "about 10x faster than the Responses API";
$0.10 per 1M input tokens, output free; add an "other" option and tune
thresholds on labeled examples.
[guide](https://developers.openai.com/api/docs/guides/decisions). TypeSafe
**Jev**: Choice, Score and Noul primitives with probabilities, questions in
parallel over one state. [docs](https://docs.typesafe.ai/llms.txt)

## What stays ours

✦K chords and sequences; answers in ~0.6 s (spare process); commands are
files; About You chosen per command (Raycast's Profile skips AI Commands);
letter-level highlighting; the user's own subscription first, no credits, no
paywall on bringing a key; the cost of a run shown, never hidden.

## One command format, three kinds

Every command stays a Markdown file. New front matter keys are optional; the
kind follows from them:

```markdown
---
title: Reply to This Email
profile: true
model: sonnet
output: replace           # replace | insert | copy | card   (default: replace, insert with no selection)
ask:                      # questions, filled before the prompt is sent
  - id: tone
    question: Which tone?
    options: [Friendly, Formal, Short]
    default: Friendly
tools: [selection, apps, menus, mcp:linear]   # only for acting commands
approve: ask              # ask | auto | always, for tools that change things
---
Answer this email in a {ask.tone} tone, as me.

{selection}
```

| Kind | When | Engine | Speed |
|---|---|---|---|
| **Transform** | no `tools`, no `decide` | Write: Claude spare (subscription) or API key | first word ~0.6 s |
| **Decide** | `decide:` block (choices, parameters) | Decisions API (`gpt-6-luna`) or Jev; heuristics fallback | ~0.1–0.5 s |
| **Act** | `tools:` | Claude Code headless with skil.li's MCP server and the allowed MCP servers, on the user's plan | seconds |

### Transform+ (built)

As designed below, with these choices: `{ask.<id>}` names an answer (answers
the prompt does not name go after it); Insert After pastes the selection back
followed by a blank line and the answer, so ⌘Z undoes it in one step; Copy
writes the clipboard as soon as the answer is complete; Card output shows the
answer plainly and Return copies it. A link's command is shown in full
before Add (Raycast installs at once).

- **Output modes** (BoltAI, Raycast): replace, insert after, copy, card only;
  a failed paste falls back to the clipboard with a notice.
- **Questions without forms** (Raycast v2.7's lesson): `ask:` questions show
  in the card as keycaps (`1 Friendly · 2 Formal · 3 Short`), the default
  pre-selected so Return runs at once; free text when there are no options.
  Never a modal form in front of a quick command.
- **Modifiers** `| trim | upper | raw`; `{clipboard offset=1}` once clipboard
  history exists; `{browser-tab}` later (needs a browser bridge).
- **Conservative built-ins**: change only what is wrong (already done for Fix;
  keep the same rule for every built-in).

### Decide

A command that picks what to do: "Do It" on a selection classifies the intent
(translate, reply, add to calendar, open in an app…), fills the parameters
(language, date, app) with typed questions in **one** request, then runs the
chosen command or skil.li action. Above a confidence threshold it runs;
below, the card shows the top three as keycaps. Always an "other" choice.
Typed answers can feed the next step, like Shortcuts' Use Model.

Engine: `/v1/decisions` (OpenAI key) or Jev (TypeSafe key, or local through
Ollama later). Both are API-only: the user brings a key, the cost per run is
shown (fractions of a cent).

### Act

Multi-step work with tools, in the user's own agent:

- skil.li starts **Claude Code** headless (same lean, isolated way as the
  spare, subscription first) with `--mcp-config` pointing at **skil.li's MCP
  server** and at the MCP servers this command may use (`--strict-mcp-config`,
  allowed tools only: Raycast learned that loading every tool slows commands).
- The card shows the steps as they happen ("Reading the selection… Opening
  Linear…"), **questions** from the agent's `ask_user` tool (options as
  keycaps, or a text field; later by voice), and **approvals** for tools that
  change things: Allow ↵ · Always ⌘↵ · Deny Esc.
- Permission modes per tool: Ask, Auto (read-only allowed), Always; the list
  is editable in Settings → SI → Tools.

### Tools

- **skil.li's MCP server** (`skilli mcp`, also a CLI): `selection.read`,
  `selection.replace`, `clipboard.read/write`, `app.frontmost`, `app.open`,
  `window.context`, `menu.search`, `menu.press`, `url.open`, `cleanshot.*`,
  `commands.run(id)`, `notify`, `ask_user`. The same server lets any outside
  agent (Claude Code, Codex, Grok) drive skil.li.
- **Connected MCP servers**: Settings → SI → Tools: add (stdio or HTTP),
  import from Claude Code or Claude desktop configs after showing what will be
  read, status per server, a switch per tool.

### Tools and Act (built)

- Transport: a Unix socket in skil.li's folder (0600, same user only), and
  `Skilli mcp` (the app binary) as the stdio bridge any MCP client can run;
  `Skilli call <tool> '<json>'` for scripts. Tool names use underscores
  (`get_selection`): Claude's tool names allow no dots.
- Approvals: Claude Code's `--permission-prompt-tool` (verified: it calls
  the tool with `tool_name`, `input`, `tool_use_id` and hides it from the
  model) routes other servers' tools to skil.li's `approve`; skil.li's own
  tools are allowed up front and approved inside the server, with the
  user's choice per tool. Ask Before Changes is the default.
- Act runs: `--tools ""` keeps only MCP tools (verified); a run id on the
  bridge ties a connection to the command (its tool groups, its selection
  and app). Haiku reads, asks to replace, replaces and answers in ~5 s,
  ~2.7k tokens for a minimal tool round.
- Not yet: importing servers from Claude Code / Claude for Mac configs
  (servers are added by hand in Settings → SI Tools), a live status per
  server, the API-key engine for Act (Claude Code only for now).

### Voice (later)

Hold a key, speak the instruction or answer the card's question;
`SpeechTranscriber` on device. Per-app variants (Superwhisper, Alter): a
command can name apps where it is the default (`apps: [Mail, Slack]`).

### Templates gallery (website, later)

- A page of templates in the same file format, by category, with author and
  model; preview of the prompt, its questions and its tools.
- **Install in one click:** `skilli://commands/import?url=…` (or the file
  inline), several at once, the **full** command kept (output, questions,
  tools, model, suggested shortcut) — Raycast's import drops all but title,
  prompt, creativity, icon and model.
- Installing a command with tools shows them and their approval mode first.
- In the app: Share (link), Export (`.md`), Import.

## Phases (proposal)

1. **Transform+** — output modes, `ask:` questions in the card, modifiers,
   import/export and the `skilli://commands/import` deeplink (the gallery's
   foundation).
2. **Tools and Act** — `skilli mcp` server and CLI, permission model, Act
   commands on Claude Code with steps, questions and approvals in the card.
3. **Decide** — Decisions API / Jev engine, "Do It" command, typed steps.
4. **Voice and per-app** — spoken instructions and answers, app variants.
5. **Gallery** — website page with one-click install.

## Decisions for JB

- Order of the phases (proposal above: 1 → 2 → 3 → 4 → 5).
- Decide engine: an OpenAI API key for the Decisions API, a TypeSafe key for
  Jev, or both (the router takes the first available).
- Act runs in the user's Claude Code (subscription) by default; API key
  fallback.
