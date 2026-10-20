# Do it here from anywhere — links, skillies and agents

Status: built and measured on the mini, 2026-10-19. Asked by JB
the same day, after the Chess demo (PR #11): the demo was only a showcase
of skil.li acting in any app; what does it unlock, for skillies for a
start? Branch `claude/elastic-wu-f6a44e`, self-test scope `doit`.

## What was out of reach

"Do it here" (`ComputerControl`, docs/click-what-you-see.md) acts in the
window in front toward a goal: Accessibility and the menus, the words on
screen, the window's picture where they say too little (Jev's Box for what
is only drawn), Claude Opus planning the steps that need thinking, and the
guards (`ScreenControl.mayAct`: nothing that sends, shares or publishes
unless the goal's own verbs ask; what deletes, pays or overwrites asked
first; passwords never typed).

Only Ask could start it: `ComputerControl` is made in
`AIActionController.control` (and the self-test). What else acts in apps
had none of it:

- **Skillies** can only open `skilli://` links (`run`, `quicklink`,
  `layout`, `skillie`).
- **Agents' tools** (`list_ui`, `find_ui`, `press_ui`, `set_ui_value`,
  `press_keys`, `press_menu`) are Accessibility alone: no picture, no click
  in the picture, no planning, and the agent drives each press itself, a
  round trip of its model each time.

## Decided

### 1. A link: `skilli://do?goal=…&app=…`

    open "skilli://do?app=TextEdit&goal=exporte%20en%20PDF%20dans%20mes%20documents"

- **Name**: `do`, the verb of "do it here". `goal` (required) is the
  request as the user would type it in Ask, quotes for the exact text to
  type (`« … »`). `app` (optional) is the app to do it in, by name
  ("TextEdit", "Finder") or bundle id; it is brought forward, opened when
  it is not running. Without it, the app the user was in when the link
  came. A link with no goal says so in the card; a goal over 300
  characters is not run (its card must show it whole: a page could hide
  words past what fits).
- **Asked first, always** (`SkilliLink.asksFirst`'s rule: a link can come
  from a web page, and "do it here" acts out of the user's hands). The
  card: Allow “exporte en PDF dans mes documents”? — "skil.li does it in
  TextEdit, step by step: it reads the window and clicks for you. What
  sends, deletes or pays still asks." then the line every link card has (a
  link asks for it: another app or a web page). Allow ↩, Deny esc, Always
  ⌘↩.
- **Always** trusts that goal in that app only (`LinkTrust`, D6: per
  entry, here the entry is the goal and its app, as a skillie is trusted
  with its arguments). Another goal, or the same goal in another app,
  asks again. Listed in Settings → Catalog → Trusted Links ("Do It Here ·
  “exporte en PDF…”, “TextEdit”"), − asks again. A page cannot widen a
  trusted goal: it can only open the very words the user trusted.
- **One at a time, in order**, so a skillie chains steps by opening links
  one after another: a `do` link that comes while another waits or runs
  follows it. When the one before did not finish (denied, stopped,
  cancelled), the rest of that chain is dropped: its next step makes no
  sense then (a page opening ten links stops at the first Deny). Dropped
  links say nothing more: the card that stopped already says why. A link
  that comes when none waits starts afresh.
- **The card** is Ask's: the steps live while it works, gone once done;
  it stays only to say why it stopped (Allow Screen Recording ↩ where the
  words on screen were needed). Esc or a click away stops it.
- **Every guard stays** where it was, inside `ComputerControl`: the
  outbound gate reads the link's goal like a typed one, risky labels are
  asked in the card, passwords never typed, nothing with Secure Input on.
  The link adds the ask before it and removes nothing.
- **Who thinks**: the decision keys and writer Ask uses (the Ask
  command's model); thinking steps planned by Claude Opus when the writer
  is Claude, as in Ask.

### 2. An agent tool: `do_in_app(goal, app)`

- **What**: hands a whole goal to "do it here" and waits for it: the
  steps done and whether it finished ("Done in TextEdit in 14 s · 5
  steps: …", or "Stopped in TextEdit: <why>. Steps done: …", an error for
  the agent then). The agent no longer drives list_ui / press_ui press by
  press: one call, and the picture, the Box and the planning come with it.
- **Rights**: group Screen Controls, risk "changes" like `press_ui`: asked
  in the card by the tool's right ("Do it in an app" — goal, app), Always
  per tool. `ScreenControl`'s own guards then ask what each step needs.
- **Where**: `app` named → brought forward (opened if needed); else the
  app the command started in (Ask's agent, an Act command), else the app
  in front if it is not skil.li. An agent outside skil.li (Claude Code in
  a terminal) should name the app: the description says so.
- **The card**: inside a command's run, its own card shows the steps,
  then the agent's again; outside one (Claude Code, Codex, `Skilli call`)
  the card is taken as for an agent's question, and goes at the end either
  way (the agent says the outcome).
- **The agent's prompt** (`AgentRun.basePrompt`): one menu item for one
  step; a goal of several steps in an app goes whole to `do_in_app`;
  find_ui / press_ui for a single press.
- **`create_skillie`**'s description tells the agent how a skillie acts
  in apps: `open "skilli://do?app=…&goal=…"` lines, one per step, run in
  order.

### 3. No `look_at_window` tool, for now

Considered: a tool that hands the agent a JPEG of the window in front.
Not built:

- What an agent would do with the picture already happens inside
  `do_in_app`: Opus plans from it, Jev's Box finds what is drawn, the
  writer checks a click made in the picture.
- skil.li never clicks where a model points, only on an item read or a
  spot its Box found (click-what-you-see.md: Claude pointing in a grid
  missed by a column every time). A picture without a click in it invites
  agents to reason about coordinates they cannot use.
- It would send whatever window is in front to the agent's model under a
  read right (no ask in Ask Before Changes): more than `list_ui`'s words
  (photos, documents, other people's messages).
- About 1,500 input tokens a look, in the agent's context, each time.

Revisit when a measured agent run needs to check what only the picture
shows after `do_in_app` said done.

### 4. Skillies

A skillie that chains two apps:

```bash
#!/bin/bash
# @skilli.schemaVersion 1
# @skilli.title Export to Documents
# @skilli.mode silent
open "skilli://do?app=TextEdit&goal=exporte%20en%20PDF%20dans%20mes%20documents"
open "skilli://do?app=Finder&goal=ouvre%20le%20dossier%20Documents"
```

It ends at once (nothing printed: no card of its own); skil.li runs the
two steps one after the other, each asked first until trusted with
Always. A skillie that needs the outcome to branch on is not served by
this step (see Not now).

## Not now

- **No button** anywhere (no "Copy Link" for an Ask, no Catalog row): JB
  has not tried it yet (no untested entry points). Links and the tool are
  reached by those who write them.
- **A blocking call for skillies**: `Skilli call do_in_app '{…}'` already
  waits and exits non-zero on a stop, but skillies are not told where the
  `Skilli` binary is. An environment variable in `ScriptLibrary.run`
  would do it, once a skillie needs to branch on a step.
- **Several goals in one link** (`goal=…&goal=…`): one link a step keeps
  each step asked and trusted on its own.
- **Drags, canvas scrolling**: as in click-what-you-see.md.

## Measures (mini, 2026-10-19)

`remote doit`, 3 of 3 passing (06:42): macOS 27 in French, TextEdit with
a scratch RTF document, the mini's TypeSafe key (Jev) and Claude Code.
Each step's own decisions in parentheses; times of the earlier run 1
(06:15) were within 0.4 s of these.

| What | Result | Time |
|---|---|---|
| Links, dry: asked (the goal, the app, "link"; Allow / Always / Deny), esc declines | as specified | — |
| Two links back to back, the first denied | the second dropped, never asked | — |
| Always ⌘↩ | that goal in TextEdit runs at once next; in Pages it asks; listed in Trusted Links | — |
| No goal | "This link says nothing to do…" | — |
| **Skillie, two `open` lines through macOS** | skillie done in 143 ms (nothing printed) | |
| → TextEdit: "exporte en PDF dans mes documents" | PDF in Documents: Fichier › Exporter au format PDF…, Enregistrer (Jev, once with the picture) | 5.4 s from the skillie's start |
| → Finder: "ouvre le dossier Documents" | Aller › Documents: Finder on "Documents — Local", the new PDF in it (Jev, 267 ms) | 7.3 s from the skillie's start |
| `do_in_app`, an app not installed | refused, "Call list_apps…" | — |
| **`Skilli call do_in_app` from a terminal** (an agent outside skil.li) | one approval (↩), "Done in TextEdit in 3.5 s · 2 steps", exit 0, card free after | 3.6 s |
| **Act agent, Claude Code Haiku, Screen Controls**: "Exporte le document ouvert dans TextEdit en PDF dans mes documents" | one call, `do_in_app`, no list_ui / press_ui; one approval; PDF in Documents; answered "Fait." | 7 s from the request (6 s in run 1) |

Run 1 counted the chain as failed while it had worked: the check wanted
Finder's window title to be "Documents", and macOS 27 says "⁨Documents⁩ —
Local", the name between direction isolates (U+2068, U+2069). Two runs in
between aborted before any key: the mini's screen saver locks it after
300 s idle.

What the rows say:

- **Opening a `skilli://` link brings skil.li forward**: twice in the
  chain, once per `open` line. The runner hands the focus back to the app
  the user was in (`handFocusBack`) and brings the named app forward
  before each step: both steps acted in the right app.
- **One call instead of a press loop.** Given `do_in_app`, Haiku handed
  the whole export over at once, its only step in the card.
- **Nothing more was asked than the caller's own approval** (the tool's
  ↩, the links' trust): both goals went through `ScreenControl`'s guards
  like a typed one, and exporting to Documents trips none of them.
