# skil.li Intelligence — architecture proposal

Status: proposal, 2026-10-10. Phase 1 decided 2026-10-11: Write on Claude
(subscription or API key), engines kept ready as spare processes. Built
2026-10-11: Settings → AI and the ✦K actions on the selection (step 1 and 2). Measurements,
command lines and protocols per engine: [ai-engines.md](ai-engines.md).
Next steps for commands (decide, act with tools, questions, voice, gallery):
[si-commands.md](si-commands.md).

## The idea in one paragraph

Most launcher work needs no AI, and most AI work needs no big model. skil.li
splits intelligence into three jobs — **Decide** (typed judgments in
milliseconds), **Write** (short text in about a second) and **Act** (multi-step
work in the user's own agent) — and gives each job the cheapest engine that does
it well. Engines run on the user's existing subscriptions through the vendors'
own sanctioned paths; API keys are used only where nothing else exists. Every
capability skil.li has (selection, apps, menus, CleanShot, shortcuts…) is a
**tool**, usable by skil.li's own brain *and* by any external agent through a
CLI and an MCP server. Prompts are plain files the user owns. Smart by default,
open by design.

## What we measured on the developer's Mac

One-sentence French spelling fix, output only. Details, ranges and how to
re-measure (`script/ai_bench.py`): [ai-engines.md](ai-engines.md).

| Path | First word | Input tokens / request |
|---|---|---|
| **Claude haiku, spare process, lean flags** (subscription) | **0.55–0.65 s** | ~850 |
| Claude haiku, spawned on request, lean flags | ~1.0–1.2 s | ~850 |
| Claude Code session with default flags | 1.1–1.5 s | ~55,000 |
| `claude -p`, cold, default flags | 7.5–11.6 s | ~55,000 |
| ChatGPT `gpt-6-luna`, spare `codex app-server`, lean | 1.2–1.8 s | ~9,900 |
| Grok 4.5–4.7 on SuperGrok, spare `grok agent stdio` | 4.4–14 s | not reported |
| Apple Foundation Models | unavailable (`modelNotReady`) | — |

Lessons: spawning a CLI per request costs 0.5–1.5 s; a **spare process**
(started ahead, used once, replaced) removes it. Most of a CLI's default cost
is its own context (system prompt, tools, the user's config), not the model:
strip it. Grok's subscription models always think first and stay slow. On-device
models are a bonus, never a dependency.

## Landscape (what the best do, what users hate)

Sources: research notes in the PR and links below.

- **Raycast 2.x**: Quick AI (Tab in root search, Return pastes into the previous
  app), AI Commands with `{selection}`/`{clipboard}`/`{browser-tab}`/`{argument}`
  placeholders and replace-with-highlighted-diff, Screen Awareness on request,
  Agent with Skills read from `~/.claude/skills`, MCP client, "connect your
  Claude/ChatGPT subscription" (2.3). Hated: BYOK and AI behind paywalls, web-view
  memory, endless retries.
- **Tuna**: prompts are Markdown files with `{{input}}`; Talk mode with local
  Parakeet/Whisper that never steals focus; a **Shelf** collecting background
  results; many providers incl. Apple on-device. No MCP.
- **Wispr Flow / Superwhisper**: select text, hold a key, *say* the instruction,
  the selection is replaced; per-app modes. Hated: cloud-only audio, heavy RAM.
- **Kerlig / BoltAI**: ⌥Space on any text, palette of workflows, MCP with
  per-tool toggles, headless background actions.
- **Apple (macOS 27)**: Foundation Models now take third-party models through a
  `LanguageModel` protocol (Anthropic and Google packages, `MLXLanguageModel`),
  Private Cloud Compute model (32K context, free under 2M downloads), Dynamic
  Profiles per mode, built-in `OCRTool`. On-device context ≈4K (8K hinted).
  `SpeechTranscriber` gives fast on-device dictation.

## Engines

### Decide — typed judgments, target < 300 ms

Route an intent, pick a preset for a selection, choose a menu item or contact,
fill an argument from candidates, guard an action. Output is a typed answer
with probabilities, never text to parse.

Ladder, first available wins:

1. **Local System One** via Ollama ≥ 0.35 (`/v1/systemone`, models `tev1` 0.8B/4B,
   `nimble` 9B; ~91 ms vendor figure on M5 Max). Free, offline, no key.
2. **Hosted Jev** (`POST https://api.typesafe.ai/v1/systemone`, `jev-latest`,
   $0.042 / M input tokens, output free; 70–500 ms vendor figure). Needs an API
   key — the one place an API is the best tool.
3. **Apple Foundation Models** with `@Generable` enums (on-device, free) when
   Apple Intelligence is on.
4. **Heuristics** (fuzzy score, regex, learned picks) — always there.

The same `/v1/systemone` contract serves 1 and 2, so one client covers both.
Questions follow TypeSafe's patterns: one request carries the routing Choice
and every branch's argument questions (speculative fan-out); code acts only
above a confidence threshold and otherwise shows the top options.

### Write — short generation, target < 1.5 s to first token

Rewrite, translate, summarize, answer a quick question. Streams into place.

Ladder, chosen per preset or automatically:

1. **Apple on-device model** (when available) for short inputs under its
   context limit.
2. **User's subscription, kept ready as a spare process** (one per engine and
   model, nothing sent until used, killed after one request, replaced at once):
   - Claude (**phase 1**): the unmodified `claude` binary, lean flags, `haiku`
     by default. 0.6 s to first word.
   - ChatGPT (later): `codex app-server` with `gpt-6-luna` (the successor of
     the nano models), ~1.5 s; or **Sign in with ChatGPT** → Responses API on
     the user's plan (interest form before shipping; not measured).
   - Grok: SuperGrok models always reason (4.4–14 s): Act only, not Write.
   - Copilot: Copilot SDK with the user's GitHub sign-in (not measured).
3. **API keys** (optional): **Claude `claude-haiku-5-5`** (phase 1, the
   alternative to the subscription; $0.10/$0.50 per M), GPT-6 Luna, xAI
   `grok-4.3` with effort `none` (the only fast Grok), Groq, Gemini (funded by
   Pro/Ultra Cloud credits), any OpenAI-compatible endpoint, Ollama/LM Studio
   local models.

### Act — multi-step work, seconds to minutes

"Find the PDF Paul sent last week and summarize it into a Notes page."
skil.li does not build its own agent loop: it **drives the user's agent** —
Claude Code, Codex, Grok Build, Copilot — over **ACP** (Agent Client Protocol;
native in Grok and Copilot, adapters for Claude and Codex), with skil.li's MCP
server attached so the agent can see the selection, operate apps and ask the
user. Progress and results land in a **Shelf**; approvals show what an action
will do before it runs.

### Router

One `Brain` abstraction:

```swift
protocol Brain {
    var id: String { get }                     // "claude.cli", "claude.api", "chatgpt.codex", "jev.local", "apple.ondevice"…
    var jobs: Set<Job> { get }                 // .decide, .write, .act
    var latencyClass: LatencyClass { get }     // instant, fast, deep
    func availability() async -> Availability  // signed in? installed? model ready?
}
```

Each preset says what it needs (`job`, latency budget, context size, tools) or
pins an engine; the router picks the first available engine that fits, keeps
a spare process of it ready, and shows a small badge with the engine and
measured latency.
Failures fall through to the next engine within the budget and are reported in
place — never silent, never endless retries.

## Rules for subscriptions (what is allowed, Oct 2026)

| Provider | Path skil.li uses | Never |
|---|---|---|
| OpenAI | Sign in with ChatGPT (apply before shipping); `codex` binary | — |
| Anthropic | user's own unmodified `claude` binary; Max/Team API credits | reuse OAuth tokens, offer claude.ai login |
| xAI | `grok agent stdio` | borrow Grok CLI's OAuth client id |
| Google | API key funded by Pro/Ultra Cloud credits | reuse Gemini/Antigravity login |
| GitHub | Copilot SDK | — |

skil.li never reads `~/.codex/auth.json`, `~/.grok/auth.json`, `~/.claude`
credentials or the Keychain items of other apps, never bundles or modifies a
vendor binary. Anthropic's rules changed four times in 2026: re-check before
each release.

## Everything is a tool

A single Swift tool registry, each tool with a JSON schema and a side-effect
level (read, write, external):

- `selection.read`, `selection.replace`, `clipboard.read/write`
- `app.list`, `app.open`, `app.frontmost`, `window.context` (on request only)
- `menu.search`, `menu.press` (Accessibility)
- `screen.ocr` (Vision / `OCRTool`), `cleanshot.*`
- `shortcut.run(id)` — any skil.li action, `launcher.show(query)`
- `ask_user(question, options)` — inline confirm in skil.li's UI
- `contacts.search`, `url.open`, `notify`

Exposed three ways:

1. **Inside skil.li** to its brains (Apple FM `Tool` protocol, LLM tool calls).
2. **`skilli` CLI** — `skilli selection read`, `skilli menu press "File > Export…"`,
   `skilli run text.uppercase` — talking to the running app over XPC (same
   pattern as `dsmn`/`dsmnctl`).
3. **`skilli mcp`** — stdio MCP server wrapping the same tools. Settings has
   one-click **Connect to Claude Code / Codex / Grok / Claude desktop (.mcpb)**,
   with a confirmation showing exactly which config file changes.

So the user can run the AI part inside skil.li, or in any agent they like,
with the same capabilities.

## Prompts are files (built: SI Commands)

`~/Library/Application Support/skil.li/prompts/*.md` — Markdown with front
matter, readable by humans and by agents, edited in Settings → SI Commands or
any editor:

```markdown
---
title: Improve Writing
profile: true             # add About You (about-you.md, same folder)
model: sonnet             # optional; default is Settings → SI
                          # chatgpt/gpt-6-luna or openai/gpt-6.1-sol, with effort: low | medium | high
---
Rewrite this to be clearer and more fluent. Keep the meaning, language and
formatting, and sound like me.

{selection}
```

Built today: `title`, `profile`, `model`; variables `{selection}`,
`{clipboard}`, `{date}`, `{time}`, `{datetime}`, `{day}`, `{app}`,
`{window}`, `{profile}`, `{name}`, `{language}` (typing `{` in the editor
lists them). Like Raycast, `{selection}` and `{clipboard}` reach the model
between `"""`; without the quotes a correction prompt got worse answers
("on mangé" left unfixed). Like Tuna, `{selection}` decides whether a command
needs a selection; without it the selection, if any, follows the prompt, and
with nothing selected the answer is inserted at the cursor. Unlike Raycast,
whose Profile does not apply to AI Commands, each command chooses whether to
include About You.

Later: `{browser-tab}`, `{argument name="…"}`, modifiers (`| trim`), per-app
defaults, output modes beyond the card (Shelf, chat). Act mode will read Agent
Skills folders (`~/.claude/skills`), loading a skill only when relevant.

## Entry points (best of the market, fast by default)

1. **✦K leader → prompt** on the selection, streamed in a popover by the text
   with a highlighted diff; Return replaces (app's ⌘Z undoes), Esc cancels.
2. **Launcher → Tab → Ask**: answer streams in the card; Return pastes into the
   previous app; ⌘Return continues in Act mode.
3. **Smart action ✦Return on a selection**: Decide picks the most likely prompt
   for this text and app; runs it above the confidence threshold, otherwise
   shows the top three as keycaps.
4. **Typed intent in the launcher**: when fuzzy search has no strong hit,
   Decide routes "traduis en anglais", "remind me tomorrow 9am" or "export as
   PDF" to a prompt, a command with filled arguments, or a menu item.
5. **Voice command** (later): hold a key, speak the instruction; on-device
   `SpeechTranscriber`; applies to the selection or inserts at the cursor.
6. **Shelf**: background and Act results, failures with the provider's error.

## Speed rules

- Keep a spare process per enabled engine: started ahead, one request each
  (instruction + text, no history), killed after use and replaced at once.
  Idle it bills nothing; it costs ~120–230 MB outside skil.li, so it is a
  setting (on by default), dropped on sleep and restarted on wake.
- Strip CLI context: no tools, no MCP, no user settings or `CLAUDE.md`, no
  session files, a short system prompt (Claude: ~55k → ~850 tokens).
- Prewarm Apple FM sessions; keep prompts tiny; cap Write inputs per engine.
- Ask Decide questions speculatively in one request; act on the first
  confident answer.
- Stream everything; first token on screen is the metric. Esc cancels.
- Verify the target app (pid) is unchanged before pasting a result.
- Agents and models run out of process: skil.li's own memory budget holds.

## Phases

1. **Write on Claude** — `Brain` + router, Claude spare process on the
   subscription or a Claude API key (Keychain); prompt files; ✦K popover with
   diff; Settings → AI (detect `claude` and its sign-in, "Keep Claude ready").
   Self-test with a fake brain plus a live latency report. ChatGPT
   (`codex app-server`) and other engines follow.
2. **skil.li as tools** — tool registry, `skilli` CLI over XPC, `skilli mcp`,
   one-click connect to agents; Act mode over ACP with the Shelf.
3. **Decide** — `/v1/systemone` client (local Ollama → hosted Jev → Apple FM →
   heuristics); launcher intent routing; Smart action; argument filling.
4. **Voice and context** — SpeechTranscriber command mode, screen context on
   request, per-app modes, Skills folders.

## Decisions

Taken (2026-10-11):

- Phase 1 is Write on **Claude**: subscription through the `claude` binary, or
  a Claude API key.
- Engines are kept ready as **spare processes** (pattern in
  [ai-engines.md](ai-engines.md)).
- Grok on SuperGrok is not used for Write (always reasons, 4–14 s);
  `grok-4.7-build-fast` is excluded (code model, expensive).
- Apple Foundation Models are not counted on (Apple Intelligence off on the
  developer's Mac).

Open:

- Phase order after phase 1 (proposal: 2 → 3 → 4).
- Decide engine: Ollama ≥ 0.35 for local Jev (global install — the maintainer's call) or a
  TypeSafe API key for hosted Jev. Needed for phase 3 only.
- Fill OpenAI's Sign in with ChatGPT interest form before skil.li ships with
  ChatGPT.

## Sources

- TypeSafe: [System One](https://docs.typesafe.ai/concepts/system-one.md),
  [API](https://docs.typesafe.ai/api.md), [models](https://docs.typesafe.ai/models.md),
  [intent routing](https://docs.typesafe.ai/patterns/intent-routing.md),
  [function calling](https://docs.typesafe.ai/cookbooks/function_calling.md),
  [Ollama decision models](https://ollama.com/blog/ollama-now-supports-jev-style-decision-models)
- OpenAI: [Sign in with ChatGPT](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt),
  [SIWC for open source/local](https://developers.openai.com/siwc/token-sharing-open-source),
  [codex app-server](https://learn.chatgpt.com/docs/app-server),
  [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna)
- Anthropic: [legal and compliance](https://code.claude.com/docs/en/legal-and-compliance),
  [headless](https://code.claude.com/docs/en/headless),
  [Agent SDK with your plan](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan),
  [Max/Team API credits](https://support.claude.com/en/articles/17154008-monthly-api-credits-for-max-and-team-plans)
- xAI: [Grok Build](https://docs.x.ai/build/overview), [OpenCode post](https://x.ai/news/grok-opencode)
- Google: [Gemini CLI FAQ](https://geminicli.com/docs/resources/faq/),
  [AI Pro/Ultra Cloud credits](https://blog.google/innovation-and-ai/technology/developers-tools/gdp-premium-ai-pro-ultra/)
- GitHub: [Copilot SDK GA](https://github.blog/changelog/2026-06-02-copilot-sdk-is-now-generally-available/)
- ACP: [agents](https://agentclientprotocol.com/overview/agents), [Zed external agents](https://zed.dev/docs/ai/external-agents)
- Apple: [Foundation Models 2026](https://www.apple.com/newsroom/2026/06/apple-aids-app-development-with-new-intelligence-frameworks-and-advanced-tools/),
  [context window TN3193](https://developer.apple.com/tutorials/data/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window.md),
  [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber.md)
- Competitors: [Raycast AI Commands](https://manual.raycast.com/ai/ai-commands),
  [Quick AI](https://manual.raycast.com/ai/quick-ai.md), [Raycast MCP](https://manual.raycast.com/ai/model-context-protocol.md),
  [Raycast 2.3](https://www.raycast.com/changelog/macos/2-3), [Tuna AI prompts](https://tunaformac.com/docs/ai-prompts),
  [Tuna Talk](https://tunaformac.com/docs/talk-mode), [Wispr Flow command mode](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode),
  [Kerlig](https://www.kerlig.com), [BoltAI](https://boltai.com/changelog/page/2)
