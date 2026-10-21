# skil.li roadmap — Raycast parity, then past it

Status: decided 2026-10-11, updated 2026-10-12. Done: phase A (Ask with
voice, menus by meaning, app updates, messages, keycaps when unsure, the
selection's preview), B1, B2 except the next meeting, most of C (UI
control, skillies, browser tabs and history, editor projects, Homebrew, MCP
sign-in, tool rights, MCP import) and A2's follow-ups in the card and
handoff to Claude Code or Codex. Left: the next meeting and Reminders quick
add (permission prompts), floating notes, aliases, contacts, the gallery
(D), and distribution (Developer ID, notarization, Sparkle). See
[implementation-status.md](implementation-status.md).

Raycast facts below were researched on 2026-10-11 (manual, store, changelog,
HN, reviews; Reddit could not be read). Install counts are from
raycast.com/store/popular that day.

## What makes skil.li different

**Say it, it is done — at the speed of a shortcut.** Select anything (or
nothing), press ✦A or open skil.li and Tab, type or say what you want.
skil.li does it in the app you are in, with the cheapest step that works:

| Step | Time | What does the work |
|---|---|---|
| 0. Direct | instant | Shortcuts, chords, sequences, built-in actions |
| 1. Decide | ~0.25 s | Jev / OpenAI Decisions: pick the route, and **pick among candidates skil.li gathered itself** (menu items, apps, commands, contacts, tools) — select, do not generate |
| 2. Write | ~0.6 s to the first word | Claude on the user's subscription (spare process) |
| 3. Act | seconds | Claude Code with skil.li's tools, your webhooks and MCP servers; approvals in the card |

What Raycast does not do, and skil.li should own:

- **Acting in the current app.** Raycast's Screen Awareness only reads the
  screen; its agent acts through extensions or code it writes. skil.li acts
  through Accessibility: menus, buttons, fields — with Allow ↩ in the card.
- **Voice that runs things.** Raycast's Dictation is speech-to-text; its only
  voice command is an auto-submit word.
- **Menus by meaning.** Raycast's Search Menu Items is literal. skil.li gathers
  the app's menu (50 ms) and lets Jev choose the item for "where is export as
  PDF".
- **Keyboard model.** Raycast has hotkeys, taps and double-taps, but no
  chords or sequences; skil.li has ✦K → G.
- **Native and light.** Raycast 2 (Aug 2026) draws its UI in a web view,
  uses 350–450 MB by its own account, and needs macOS Tahoe on Apple silicon.
- **Your own AI, free.** Raycast has no AI on its free plan and moved bring
  your own key to Pro (Sept 2026). skil.li uses the user's Claude
  subscription or key, and their decision key, with no credits.

## The maintainer's examples, and how each will run

1. **"Où est le menu pour exporter en PDF ?"** — typed or spoken in any
   app. Decide routes it to *find in app*; skil.li reads the app's menu
   (`MenuReader`), keeps the ~30 closest items, and Jev picks one. The card
   shows "File › Export as PDF…": ↩ chooses it, ⌘↩ only shows it. Target
   under 0.5 s, no agent.
2. **"Mets à jour l'app en cours"** — a recipe:
   - the app's "Check for Updates…" menu item when it has one (Sparkle apps);
   - else its App Store page;
   - else `brew upgrade --cask <app>` after Allow ↩.
3. **"Dis à Thomas que j'arrive, j'ai 5 minutes de retard"** in Slack.
   - Decide routes it to *message* and fills the person ("Thomas") and the
     channel (Slack).
   - Claude rewrites the message in 0.6 s.
   - It is sent through Slack's MCP server when connected; otherwise through
     the Slack app: ⌘K, the name, ↩, paste, then ↩ after Allow.
   - The card shows "To Thomas: J'arrive, j'ai 5 minutes de retard." before
     sending. Target ~1.5 s plus the OK.
4. **By voice.** Hold the trigger and speak; on-device speech (macOS 26
   SpeechAnalyzer) turns it into the same Ask instruction. Answers to the
   card's questions by voice too.

These need two new tool families: **UI control** (find an element by
Accessibility, press it, type into it), with Jev choosing among the
elements found, and **recipes**: small known paths (update an app, send a
Slack message) tried before the general agent.

## Raycast parity

### Built into Raycast

| Feature | Raycast | skil.li today | Plan |
|---|---|---|---|
| Root search, aliases, hotkeys, fallbacks | Free | Launcher, learning, SI Commands, Ask fallback | Add aliases; a fallback list |
| Hyper key | Free | Done, plus chords and sequences | — |
| Clipboard history (text, images, files, OCR, exclusions, paste plain) | Free for 3 months, more on Pro; v2 regressions reported | Done: ✦C, OCR, search without accents, retention up to unlimited, local | **B1** ✓ |
| Snippets with placeholders | Free | Done: keywords as you type, launcher, agents, `{cursor}` | **B1** ✓ |
| Window management (halves, thirds, center, displays, layouts) | Basic free | Done: ✦W chain, launcher, Ask, cycling ½ → ⅔ → ⅓ on repeat, gaps, displays, restore | **B1** ✓ (saved layouts later) |
| Search menu items | Free, literal | `MenuReader` (agent tool) | **A**, with meaning (Jev) and ↩ to choose |
| System commands (lock, sleep, empty trash, appearance, hidden files, eject…) | Free | — | **B1** |
| Applications: quit, force quit, restart, hide | Free | Launch only | **B1** |
| Calculator, units, currency, time zones, dates | Free | Done: arithmetic, units, time zones (currency and dates later) | **B2** ✓ |
| Quicklinks with arguments | Free | Done: keywords + {query}, web search fallback | **B2** ✓ |
| File search | Free, own index | Done: Spotlight by name, ⇥ by meaning with Jev, ⌘↩ shows in Finder | **B2** ✓ |
| Emoji and symbols, `:` picker in any field | Free | Done in the launcher: names in your language, by feeling with Jev | **B2** ✓ (a `:` picker in any field later) |
| Switch windows | Free | Done: Switch Window, and saved window layouts | **B2** ✓ |
| Calendar, next meeting, join | Free | — | **B2**, EventKit |
| Notes (floating) | 5 free | — | **C** |
| Focus (block apps and sites) | Free | — | Later |
| Translate | Pro | SI Commands | Done |
| AI chat, commands, extensions, MCP, agent | Pro | Ask, SI Commands, SI Tools, MCP | Done; free with the user's own AI |
| Dictation | Pro | — | **A**: voice to Ask |
| Script Commands | Free | Done as skillies: skil.li's own commands (Raycast's metadata as `@skilli.`), Raycast's imported and converted, agents write new ones | **C** ✓ |

### Top Store extensions (installs)

| Rank | Extension | Installs | skil.li plan |
|---|---|---|---|
| 1 | Kill Process | 778k | **B1** built in: list by CPU or memory, kill, force kill |
| 2 | Color Picker | 618k | Done: Pick a Color (`NSColorSampler`), hex copied, rgb/hsl |
| 3 | Google Chrome (tabs, history) | 572k | Done: tabs (Safari, Chrome, Arc, Brave, Edge… through Accessibility) and history (Safari, Chrome family, Firefox, Zen; by meaning with ⇥) |
| 4 | Google Translate | 499k | Done through SI Commands |
| 5 | Spotify Player | 492k | Done for play/pause/next/previous/volume (media keys, any player); more through MCP |
| 6 | Visual Studio Code projects | 414k | Done: Cursor, VS Code, Windsurf, Zed, Sublime, JetBrains; launcher, Ask, shortcuts, agents |
| 7 | Linear | 404k | MCP (Linear's server) |
| 8 | Slack | 336k | MCP, plus the message recipe (A) |
| 9 | Brew | 296k | Done: search offline, installed and updates, install / upgrade / uninstall after a yes, agents |
| 10 | Notion | 281k | MCP |
| 13 | 1Password | 253k | `op` CLI tool, later |
| 15 | Speedtest | 187k | Done: macOS's `networkQuality` |
| 18 | Coffee (caffeinate) | 153k | **B1** built in (`IOPMAssertion`, no shell) |
| 21 | Timers | 124k | Done: launcher, Ask without a model, menu bar countdown |
| 22 | Apple Reminders | 123k | Tool done; quick add in the launcher (B2) |
| 23 | System Monitor | 122k | Done: System Info card and `system_info` tool |
| 24 | CleanShot X | 121k | Done: every command its API documents, in the launcher, ⌘K, keys, links, Ask, agents; front window and latest screenshot (docs/apps.md) |
| 38 | Clean Keyboard | 80k | Done: its own tap while cleaning, a glass card, Done or a minute |
| 39 | Set Audio Device | 77k | Done: launcher, shortcuts, Ask, agents (CoreAudio) |
| 48 | Port Manager (kill port) | 63k | **B1** with Kill Process (`lsof`) |
| 54 | Toothpick (Bluetooth) | 59k | Later |
| 59 | Docker | 53k | MCP |

Extension model: **no Node runtime.** Native built-ins for the daily
utilities above; MCP servers and your webhooks for services; Raycast Script
Commands run as is (C). Every one of them is reachable from Ask and the
agent, not only from a list.

## Phases

- **A. Ask, finished** (next):
  - voice to Ask;
  - menus by meaning, with ↩ to choose;
  - "update the app";
  - Slack message recipe;
  - when Decide is unsure, the top three routes as keycaps;
  - a preview of the selection in the launcher, so Tab says what it will
    work on.
- **A2. Ask, then go on** (wanted, 2026-10-12): a conversation started
  with Ask continues in the user's own AI:
  - done: follow-ups in the card itself (⇥ after an answer, the same
    conversation, its context kept);
  - done: "In Claude Code ⌘↩" / "In Codex ⌘↩" opens Terminal or Ghostty
    on a new session seeded with the conversation so far (nothing kept);
    `claude --resume <id>` would need sessions kept (`--no-session-persistence`
    today; an opt-in, the transcript lands in `~/.claude/projects`);
  - "Continue in the Claude app": only by handing over the text (no way
    to inject a conversation into it; a prefilled new chat link, to check).
- **B1. Daily essentials**: clipboard history, snippets, window management,
  system commands, quit / force quit / kill process / kill port, keep awake.
- **B2. Launcher depth**: calculator and conversions, quicklinks with
  arguments, file search, emoji, color picker, switch windows, next
  meeting, timers, audio device, clean keyboard.
- **C. Integrations**: UI control tools (done: list_ui, find_ui with Jev,
  press_ui, set_ui_value, press_keys), Script Commands, browser tabs (done),
  editor projects (done), brew, MCP sign-in with a token or OAuth (done),
  MCP servers imported from Claude Code, Claude for Mac, Codex and Cursor
  (done), tool rights with hints, Block and help from the user's AI (done),
  floating notes.
- **D. Gallery**: the website's command templates, one-click install
  (`skilli://` links already work).

Budgets to hold, measured by the self-test and benchmark:

| Path | Budget |
|---|---|
| Launcher shown | ~6 ms (current) |
| Decide | ≤ 0.35 s |
| Ask answer, first word | ≤ 1 s |
| Menu found | ≤ 0.5 s |
| Slack message ready to send | ≤ 2 s |

## Decisions (2026-10-11)

1. Order: A, then B1, then B2.
2. Raycast Script Commands are not read in place: an import turns them
   into skil.li's own commands, skillies (`@skilli.` metadata), and the
   user's agents write new ones (`create_skillie`).
3. Free and open source, always, with the user's own AI: no credits, no
   paid tier.
