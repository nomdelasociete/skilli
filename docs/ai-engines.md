# AI engines — measured, and how to drive them

Lab notes behind [ai-architecture.md](ai-architecture.md): what each engine
costs in time, tokens and memory on JB's Mac, the exact command lines and
protocols, and the traps found on the way. Read this before touching an engine;
re-measure with `script/ai_bench.py` instead of redoing the investigation.

Measured 2026-10-10/11, M-series Mac, macOS 27, French text, one-sentence
spelling fix ("les enfant on manger des pome"), output only.

## Decision (2026-10-11)

Phase 1 ships **Write on Claude only**: the user's Claude subscription through
the unmodified `claude` binary, kept as a **spare process** (below), or a
Claude API key. ChatGPT comes later through `codex app-server`. Grok on the
SuperGrok plan is too slow for quick text and is kept for Act. Apple
Foundation Models are a bonus tier, never a dependency.

2026-10-15: each command picks its writer (AGENTS.md → AI engines):
ChatGPT through one `codex exec` per request (below; the `app-server` spare
stays for later), and the OpenAI API with the key kept for Decisions.

## Results

| Engine · model | How | First word | Complete text | Input tokens / request | Memory |
|---|---|---|---|---|---|
| **Claude · haiku** | **spare, lean flags** | **0.55–0.65 s** | **0.65–0.93 s** | ~850 | 225–230 MB |
| Claude · haiku | spare idle 5 min, then used | 0.74 s | 1.05 s | ~850 | same |
| Claude · haiku | spawned on request, lean flags | 0.96–1.18 s | 1.2–1.5 s | ~850 | — |
| Claude · haiku | long-lived session, default flags | 1.1–1.5 s (turn 1: 4.5 s) | — | ~55,000 (cached after turn 1) | — |
| Claude · default | `claude -p`, cold, default flags | 7.5–11.6 s | 8–12 s | ~55,000 | — |
| ChatGPT · gpt-6-luna | spare `codex app-server`, lean | 1.2–1.8 s | 1.3–2.0 s | ~9,900 | 118–126 MB |
| ChatGPT · gpt-6-luna | spare, default features | 1.8 s | 2.1 s | ~16,300 | ~250 MB |
| ChatGPT · gpt-6-luna | spawned on request | 3.0–3.3 s | 3.3–3.5 s | ~9,900 | — |
| ChatGPT · gpt-6-astra | `codex exec`, cold | 4.4–8.0 s | 4.5–8.1 s | — | — |
| ChatGPT · gpt-6-luna low | `codex exec`, lean (as shipped) | 2.3–4.2 s (= done) | 2.6–4.4 s | ~4,400 (2,800 cached) | — |
| ChatGPT · gpt-6.1-sol / gpt-6-astra low | `codex exec`, lean | 3.3–3.9 s | 3.6–4.2 s | — | — |
| OpenAI API · gpt-6-luna low | Responses API, streamed | 0.8–1.8 s (2.1–2.5 s in one run) | 1.0–2.1 s (2.3–2.7 s) | — | — |
| OpenAI API · gpt-6.1-sol low | Responses API, streamed | 0.9–1.6 s | 1.1–1.8 s | — | — |
| Grok · 4.5 (effort low) | spare `grok agent stdio` | 4.4–9.7 s | 4.6–9.8 s | not reported | 159–176 MB |
| Grok · 4.6 (low) | spare | ~10 s | ~10.5 s | — | ~167 MB |
| Grok · 4.7 (low) | spare | 10–14 s | 10–14 s | — | ~168 MB |
| Grok · 4.7 (low) | `grok -p`, cold | — | 12 s (3.3 s is CLI start) | — | — |
| Apple Foundation Models | — | unavailable: `modelNotReady` (Apple Intelligence off) | | | |

What the numbers say:

- **A spare process is the fast path.** Spawning per request costs ~0.5 s
  (Claude) to ~1.5 s (codex) of process start and TLS handshake. A spare is
  ready **~0.5 s after spawn**; requests sent sooner fall back to on-request
  latency.
- **Most of the default cost is context, not the model.** Claude Code sends
  ~55k tokens per request (its system prompt, tool schemas, the user's
  `CLAUDE.md` and hooks); the lean flags bring that to ~850. Codex keeps ~10k
  even when lean.
- **Grok's latency is server-side thinking.** A spare does not help; it only
  removes the 3.3 s CLI start.

## The spare-process pattern (validated by JB)

- Keep **one spare per engine and model** the user enabled: spawned and
  prepared, nothing sent.
- A request takes the spare, sends **one** message (instruction + text, no
  history), streams the answer, then **kills** the process. A new spare is
  spawned immediately.
- The system prompt is generic ("transform the text per the instruction,
  answer with the result only"); the preset's instruction travels in the
  message, so one spare serves every preset.
- Idle cost of a Claude spare: **0 tokens** (verified: nothing is billed until
  a message is sent), ~0.5 % CPU (0.3 s per minute), 2 TLS connections already
  open to Anthropic (why it is fast), 225–230 MB RSS, out of skil.li's
  process. Never spawn one on Hyper alone (pressed for every shortcut); ✦K or
  opening the launcher are the triggers when the always-on spare is off.
- Planned behaviour: a "Keep Claude ready" setting (on by default when Claude
  is the engine); kill the spare on sleep or screen lock, respawn on wake;
  respawn when it dies (CLI update, sign-out); time out a request after a few
  seconds and report the failure in place.

## Claude — `claude` binary on the user's subscription

Command line (Claude Code 2.1.295):

```bash
claude -p --input-format stream-json --output-format stream-json --verbose \
  --include-partial-messages --no-session-persistence --model haiku \
  --tools "" --setting-sources "" --strict-mcp-config --disable-slash-commands \
  --system-prompt "Tu transformes le texte fourni selon l'instruction. Réponds uniquement avec le résultat, sans commentaire."
```

| Flag | Why |
|---|---|
| `--input-format stream-json` | Process waits on stdin: this is what makes a spare possible |
| `--include-partial-messages` | `stream_event` lines with `text_delta`s, for streaming into place |
| `--no-session-persistence` | Otherwise every request is saved in `~/.claude/projects/<cwd>/` and shows up in the user's `claude --resume` |
| `--tools ""`, `--strict-mcp-config`, `--disable-slash-commands` | No tool schemas, no MCP servers, no skills in the context |
| `--setting-sources ""` | Skips the user's settings, hooks and `CLAUDE.md`. Without it the user's own instructions leak into answers (JB's global `CLAUDE.md` made the "corrected text" start with a `## Lang` section) |
| `--system-prompt` | Replaces Claude Code's ~50k-token system prompt |
| not `--bare` | `--bare` skips subscription auth: "Not logged in" |

Protocol: write one line
`{"type":"user","message":{"role":"user","content":"…"}}`, read NDJSON.
`stream_event` → `message_start` (carries `usage`), `content_block_delta` with
`delta.type == "text_delta"` (the text), `message_stop` (text complete). The
final `result` line arrives **~1.6 s later** because Claude Code writes a
`post_turn_summary` first: never wait for it.

In skil.li (2026-10-11, `selftest ai`): a spare started by the app answers
with its first word in **0.50–0.70 s** (complete 0.73–0.99 s) over four runs;
one earlier run took 4.5 s right after a fresh build, not reproduced.

Status and sign-in, no credentials involved: `claude auth status --json`
(~0.1 s, no network; `loggedIn`, `authMethod`, `subscriptionType` such as
`max`; exits 1 when signed out) and `claude auth login --claudeai` (Anthropic's
own browser flow), which Settings opens in Terminal through a `.command` file.

Process traps:

- Without `USER` in its environment `claude` cannot find its sign-in and
  reports `loggedIn: false`. Apps started from Finder have `USER`, but never
  build a child environment from scratch.
- Closing a spare's stdin makes it exit within ~0.75 s without sending
  anything, so a crashed skil.li leaves no orphan.

Rules: run the user's own unmodified binary; never read or reuse its OAuth
tokens, never offer a claude.ai login inside skil.li. Anthropic changed its
third-party rules several times in 2026: re-check before distributing.

## Claude — API key (not measured yet)

- Model `claude-haiku-5-5`: $0.10 / $0.50 per million input / output tokens
  (prompts ≤ 100K). A correction is a few hundred tokens: ~$0.0001.
- Swift has no official Anthropic SDK: raw HTTP. `POST
  https://api.anthropic.com/v1/messages`, headers `x-api-key`,
  `anthropic-version: 2023-06-01`, `content-type: application/json`, body with
  `"stream": true`. Server-sent events: `message_start`,
  `content_block_delta` (`text_delta`), `message_stop`.
- Haiku 5.5 thinks by default (adaptive, effort `medium`): set
  `output_config.effort` to `low` for transforms, and measure. Assistant
  prefill returns a 400. Prompt caching needs a 512-token prefix; our prompts
  are smaller, so no caching.
- Latency plan: one long-lived `URLSession`; warm the connection when ✦K is
  pressed (or keep it warm) with a request that bills nothing, so the TLS
  handshake is done before the real request. Key in the Keychain.
- To do: measure first word with a real key against the spare.

## ChatGPT — `codex exec` per request (shipped 2026-10-15)

`CodexEngine`, codex-cli 0.162.1. The prompt on stdin, from an empty folder
(`$TMPDIR/skilli-codex`):

```bash
codex exec --json --ephemeral --skip-git-repo-check --ignore-user-config --ignore-rules \
  -s read-only -c 'approval_policy="never"' -c 'web_search="disabled"' \
  -c 'model_instructions_file="$TMPDIR/skilli-codex-prompt/instructions.md"' \
  -c include_permissions_instructions=false -c include_apps_instructions=false \
  -c include_collaboration_mode_instructions=false -c include_environment_context=false \
  -c project_doc_max_bytes=0 -c skills.include_instructions=false \
  -c features.apps=false … -c features.realtime_conversation=false \
  -m gpt-6-luna -c 'model_reasoning_effort="low"' -C "$TMPDIR/skilli-codex" -
```

- Events: `thread.started` (~0.1 s), `turn.started`, one `item.completed`
  with the whole `agent_message` (no deltas: first word = done),
  `turn.completed` (usage). The lean flags bring ~11,000 input tokens to
  ~4,400 (2,800 cached). Most of the 2.3–4.7 s is the model and the
  connection; a spare like Claude's would need `app-server` (1.2–2.0 s
  above), not `exec`.
- `model_instructions_file` replaces Codex's own instructions (checked: a
  file saying "reply PINEAPPLE" wins). The user's global
  `~/.codex/AGENTS.md` still comes in (`codex debug prompt-input`): no option
  leaves it out, so the instructions say to ignore AGENTS.md.
- `--disable <feature>` with a name this Codex does not know stops it
  ("Unknown feature flag"); `-c features.<name>=false` does the same and
  ignores an unknown name (checked: same ~4,300 input tokens), so the lean
  features are always passed that way.
- Models: `codex debug models` (~0.5 s) prints the plan's catalog: `slug`,
  `visibility` (`list` / `hide`), `supported_reasoning_levels` (low to
  ultra; luna to max), `supported_in_api`. On JB's plan: gpt-6.1-sol,
  gpt-6-astra, gpt-6-sol, gpt-6-luna, gpt-5.6-sol, gpt-5.6-terra,
  gpt-5.6-luna (listed). Measured answering: gpt-6-luna at low, medium and
  high; gpt-6.1-sol and gpt-6-astra at low and medium.
- Failures, as `--json` says them: a model the plan lacks ends in ~2 s with
  `turn.failed` holding the API's body ("The 'gpt-nope-1' model is not
  supported when using Codex with a ChatGPT account."); signed out, Codex
  retries ten times over 16 s ("Reconnecting... 2/5 (unexpected status 401
  Unauthorized…)") before `turn.failed`: skil.li stops at the first.
  `codex login status` prints on standard error ("Logged in using
  ChatGPT", exit 0; "Not logged in", exit 1), no network.

## OpenAI API — Responses API with the user's key (shipped 2026-10-15)

`OpenAIEngine`: `POST /v1/responses` with `instructions` (skil.li's system
prompt), `input`, `reasoning.effort`, `stream: true`, `store: false`;
`response.output_text.delta` streams, `response.completed` ends. Measured
on the Mac mini (`selftest models`, seven runs): GPT-6 Luna Low 0.8–1.8 s
to the first word, done 1.0–2.1 s, in ~8 chunks (one run took 2.1–2.5 s);
GPT-6.1 Sol Low 0.9–1.6 s. `GET
/v1/models` listed 27 text GPT models for the key (after dropping audio,
image, search, codex, dated snapshots…); the menus keep the newest of each
family of the newest generation.

## Claude — Opus

`claude --model opus` is `claude-opus-5-5` in Claude Code 2.1.296 (checked
with the lean flags: ~4.8 s cold). On the API key, Sonnet and Opus send
`fallbacks: "default"` (beta `server-side-fallback-2026-07-01`): a declined
request is answered by Anthropic's recommended model on the same stream.

## ChatGPT — `codex app-server` on the ChatGPT plan

Models on JB's plan (`model/list`): `gpt-6.1-sol` (default), `gpt-6-astra`,
`gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, plus
hidden ones. **There is no nano anymore**: OpenAI lists `gpt-6-luna` as the
replacement for `gpt-5.4-nano` (API deprecations page, 2026-10-01). Effort
starts at `low` (no `none` or `minimal`); luna used 0 reasoning tokens at
`low`.

Command line (codex-cli 0.161.0), lean:

```bash
codex app-server -c 'web_search="disabled"' \
  --disable apps --disable browser_use --disable browser_use_external \
  --disable browser_use_full_cdp_access --disable browser_annotation_api \
  --disable computer_use --disable goals --disable image_generation \
  --disable multi_agent --disable plugins --disable remote_plugin \
  --disable shell_tool --disable skill_search --disable sleep_tool \
  --disable tool_suggest --disable unified_exec --disable view_image \
  --disable hooks --disable in_app_browser --disable realtime_conversation
```

Lean cuts input from ~16.3k to ~9.9k tokens and memory from ~250 to ~120 MB.
`serviceTier: "fast"` on the thread made no measurable difference.

Protocol: JSON-RPC lines **without** a `jsonrpc` field. Full schema:
`codex app-server generate-json-schema --out <dir>`.

1. `initialize` `{clientInfo: {name, version}}`, then notification `initialized`.
2. `thread/start` `{cwd, model: "gpt-6-luna", ephemeral: true,
   baseInstructions: <system prompt>, sandbox: "read-only", approvalPolicy:
   "never"}` → `result.thread.id`. Takes ~0.15 s; part of preparing the spare.
3. `turn/start` `{threadId, effort: "low", input: [{type: "text", text}]}`.
4. Notifications: `item/agentMessage/delta` (`params.delta`),
   `thread/tokenUsage/updated` (`tokenUsage.last.inputTokens`),
   `turn/completed`.

Traps: one request in ~12 never completed within 60 s (needs a timeout and a
fallback); `app-server` is marked experimental; ~10k tokens per request count
against the user's ChatGPT/Codex limits. Never read `~/.codex/auth.json`. Not
explored yet: Sign in with ChatGPT (Responses API on the plan; interest form
before shipping).

## Grok — `grok` CLI on the SuperGrok plan

Models on JB's plan (`grok models`): `grok-4.7` (default), `grok-4.7-build-fast`,
`grok-4.6`, `grok-4.5`. `grok-4.7-build-fast` is built for code and expensive:
excluded. `grok-4.3` is refused ("unknown model id"). Effort starts at `low`
(`none` refused), and every model thinks before answering
(`agent_thought_chunk` updates).

Spare: `grok agent -m grok-4.5 --reasoning-effort low --no-leader stdio`
speaks ACP (JSON-RPC 2.0):

1. `initialize` `{protocolVersion: 1, clientCapabilities: {fs: {readTextFile:
   false, writeTextFile: false}, terminal: false}}`
2. `session/new` `{cwd, mcpServers: []}` → `sessionId`
3. `session/prompt` `{sessionId, prompt: [{type: "text", text}]}`; the
   response arrives when the turn ends.
4. Notifications `session/update` with `update.sessionUpdate ==
   "agent_message_chunk"` (`content.text`). The agent may send requests
   (`session/request_permission`): answer them (`{outcome: {outcome:
   "cancelled"}}`) or it waits. No token usage is reported.

One-shot: `grok -p "…" -m <model> --reasoning-effort low --tools ""
--disable-web-search --no-subagents --no-plan --output-format plain`.

The fast Grok is API-only: xAI routes non-reasoning traffic to `grok-4.3` with
effort `none` ($1.25 / $2.50 per million tokens), which needs an xAI API key.
Not measured.

## Apple Foundation Models

`modelNotReady` on JB's Mac: Apple Intelligence is off. Treat as a bonus tier
that lights up when available; never a dependency.

## Benchmarking traps

- A Claude Code session exports `HTTPS_PROXY`, `HTTP_PROXY` and
  `ANTHROPIC_BASE_URL` to its tools; child CLIs inherit them and go through
  the session's proxy. skil.li starts CLIs without them, so benchmarks must
  strip them (`script/ai_bench.py` does).
- Run CLIs from an empty directory: project files (`CLAUDE.md`, `AGENTS.md`)
  otherwise enter the context.
- Measure first word and `message_stop`/`turn/completed`, not process exit or
  the final `result` line.
- Latency varies run to run by ±30 % (provider load): compare medians of
  several runs.

## Re-measuring

```bash
script/ai_bench.py                          # Claude + ChatGPT, 3 runs each
script/ai_bench.py --engine grok --runs 1   # slow: ~1 min
script/ai_bench.py --engine claude --model sonnet
```

Each run spends real tokens from the user's plans (Claude ~850 per request,
codex ~10k) and kills every process it starts.

## Open questions

- Claude API key latency vs the spare (needs a key).
- Sonnet in a spare, for presets that need a stronger model.
- Sign in with ChatGPT vs `codex app-server` on latency and tokens.
- Decide engine (Jev hosted vs local Ollama) — phase 3, not needed for Write.

Sources: [OpenAI deprecations](https://developers.openai.com/api/docs/deprecations),
[xAI model retirement, May 2026](https://docs.x.ai/developers/migration/may-15-retirement),
[xAI pricing](https://docs.x.ai/developers/pricing).
