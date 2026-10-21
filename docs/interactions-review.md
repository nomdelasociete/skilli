# skil.li interactions review

2026-10-17. The maintainer validated the whole plan the same day: the six rules are in
AGENTS.md (Interactions: the six rules) and every decision below took the
recommendation.

skil.li asks and announces too much, and its cards take keys from the app you are typing in. Four code reviews of every flow (launcher, card, Mac and windows, Settings and agents) found six patterns behind about a hundred frictions; the proposal fixes the patterns, not each case.

## The rules

Six checks turn the manifesto's "No surprises" and "What you see done is not announced" into something every flow can be measured against. The maintainer's example (a "Copied" card after choosing Copy Phone Number) breaks rule 3.

1. **Ask only before sending, deleting for good, paying or overwriting.** Nothing else asks.
2. **Reversible things happen at once**, with ⌘Z for a few seconds instead of a question.
3. **A choice you just made is not confirmed or announced.** skil.li speaks only when something failed or happened out of sight.
4. **A card never takes keys from the app you are typing in.**
5. **The same key means the same thing everywhere:** ↩ main, ⌘↩ second, ⌘C copy, ⌘⌫ remove, ⌘Z undo, esc back.
6. **A failure says what happened and what to do**, in words: never a bare beep, never a dead end that makes you retype.

## What is wrong

Six patterns explain almost every friction found. The first is a safety problem, not just a nuisance.

| Pattern | What happens | Examples | Rule |
| --- | --- | --- | --- |
| **A. Cards take your keys** | While any skil.li card is on screen, even a 1.5 s "Copied" note, the ↩ and ⌘C you type in your own app go to the card. | A stray ↩ approves an agent's tool, undoes a layout delete or closes a note. ⌘↩ typed in Ask's field closes the card and reaches the app behind: Send in Mail or Slack. | 4 |
| **B. Announcing what you chose** | A card confirms what you just did, or what the screen already shows. | "Copied …" after every copy (⌘C, ⇧⌘C, ⌘K Copy…, the contact card, the calculator); Sound on X; Volume at 30 %; Connected X; a Keep Awake card next to its cup; Saved layout; Moved to…; Taken back; No color picked. Said twice after an unsure confirm (Keep Awake, volume, a reminder). | 3 |
| **C. Asking for reversible things** | A question before something you can take back. | Quit asks by default, though the app asks to save itself and Ask's own quit doesn't ask. Homebrew install. Ask unsure about a timer, the volume or Keep Awake. Deleting a reminder, or an event nobody else is invited to. A menu item found for sure still needs ↩. Quit helpers asked one by one. Do It Here asks detail by detail. Links ask every time, so a Stream Deck Lock needs ↩. | 1, 2 |
| **D. Destroying without asking or undo** | Data or secrets gone in one move. | Clipboard "Keep copies for" deletes old copies the moment you pick. Keys → Restore Defaults erases every custom shortcut. No undo for: forgetting a copy, Move to Trash, deleting a snippet, command, quicklink or IBAN, removing an API key or a server. A running timer shows first on "c", "t" or "m", so c↩ for Chrome cancels it. The command editor saves New Command before you type, Duplicate overwrites the original, Reset applies before Save. An agent's Always skips a skillie's own "ask first". | 1, 2 |
| **E. Keys that change meaning, dead ends** | The same key does different things; failures leave you stuck. | Undo is ↩ for a layout, ⌘Z elsewhere. ⌘C copies, announces, copies a skilli:// link or does nothing, by row. ⌘↩ is second action, Always, Continue in, or paste (inverted on the calculator). ⇥ in a mode runs Ask on the filter and closes the launcher, even on a password argument. esc in a mode closes everything. The footer always says Open ↩. Always ⌘↩ is shown on cards that never store it, worded "Allow “Restart?”?". Missing values (When? How long? Which app?) come as failure cards, so you retype it all. Bare beeps: menu item refused, argument missing, paste failed. Setup shows 7 permission cards; closing it with ✕ brings it back. | 5, 6 |
| **F. Meetings that ignore you joined** | Alerts don't check that you are already in the call. | The on-time alert, or screens dark, fires over a call you joined; the alert card stays on top until the meeting ends; auto-join opens the call again. | 1, 3 |

## Worst 15

Ranked by how often you hit it times how much it hurts. Size: S is under half a day, M a day or two.

| # | Friction | Where | Fix | Size |
| --- | --- | --- | --- | --- |
| 1 | Cards eat ↩ and ⌘C typed in your app | every card | A card takes keys only when you opened it or it asks you something you're answering; notes take esc only; agent cards wait until you stop typing (2 s), as scheduled asks already do | M |
| 2 | "Copied …" after every copy you chose | launcher, contact card, calculator | Copy silently | S |
| 3 | ⌘↩ in Ask's field reaches Mail or Slack (Send) | Ask, follow-ups | The card's fields keep ⌘↩ | S |
| 4 | "Keep copies for" deletes old copies at once | Settings → Clipboard | Say "Deletes 812 copies" and apply on the hourly pass | S |
| 5 | c↩, t↩, m↩ cancel a running timer | launcher | Running timers only for "timer" typed out, never first | S |
| 6 | Quit asks every time | Kill, ⌘K Quit | Quit at once; Force Quit still asks | S |
| 7 | An agent's Always skips a skillie's "ask first"; a stray ↩ approves an agent | agents | Never skip a skillie's own ask; typing guard on agent cards | S |
| 8 | Restore Defaults erases every custom shortcut in one click | Settings → Keys | Confirm, naming how many go | S |
| 9 | No undo when forgetting a copy, trashing a file, deleting a snippet, command, quicklink, IBAN, key or server | launcher, Settings | One undo: ⌘Z for 10 s, the layout delete's card for all | M |
| 10 | A missing value ends in a failure card; you retype everything | Ask | Ask that one value in the card, keep the rest | M |
| 11 | Meeting alerts over a call you already joined | meetings | Skip when joined or the mic is in use; close the card on join | S |
| 12 | Calculator: ↩ copies with a card, ⌘↩ pastes, ⌘C does nothing | launcher | See decision D4 | S |
| 13 | Each reminder change closes the launcher and leaves a card | todo | Change the row in place, ⌘Z to undo | M |
| 14 | ⇥ in a mode sends the filter to Ask, even a password | launcher | ⇥ shows the row's actions; never Ask inside a mode | S |
| 15 | "Allow “Restart?”?" with an Always that is never kept | Mac commands, Homebrew, skillies | "Restart? ↩ Restart · esc Cancel"; Always only where it is stored | S |

## Decisions

Nine choices change how skil.li behaves; everything else in the fix plan follows the rules. The maintainer took the recommendation for each (2026-10-17).

| # | Decision | Options | Decided |
| --- | --- | --- | --- |
| D1 | Make the six rules the standard | Yes: written into AGENTS.md as the test for every new flow · No | Yes |
| D2 | Quitting an app | Quit at once (the app asks to save itself) · Keep asking | Quit at once; Force Quit keeps asking |
| D3 | One way to undo | ⌘Z everywhere, in a 10 s card that never takes ↩ · Keep ↩ for layouts | ⌘Z everywhere |
| D4 | Calculator ↩ | Pastes the result in your app, like clips, snippets and emoji (⌘↩ and ⌘C copy) · Copies, silently | Pastes, for the same key everywhere |
| D5 | Ask unsure about something reversible (timer, volume, Keep Awake) | Do it on the best reading, ⌘Z to undo · Keep asking first | Do it, ⌘Z |
| D6 | skilli:// links (Stream Deck, Shortcuts) | Always from links, per entry, after the first ↩ · Trust Shortcuts and Stream Deck by name · Ask every time | Always per entry |
| D7 | First launch | Only Accessibility and your SI; every other permission asked where it is first needed, in place · Keep the 7 cards | Only the two |
| D8 | Ask's speed | Read the values (how long, which level) in the same request as the route: one call instead of two, more tokens per ask · Keep two calls | One call for timer, volume, Keep Awake; plans keep two |
| D9 | Homebrew install | No ask for formulae, ask for apps (casks) · Always ask | No ask for formulae |

## Fix plan

Four batches, one pull request each (or a few), every one tested on the Mac mini and deployed before the next. Batch 1 needs no decision: it fixes bugs that lose data, take your keys or bypass an ask.

1. **Safety (now).** Cards stop taking your keys (#1, #3, #7). Clipboard retention says what it deletes (#4). Running timers stop catching c, t and m (#5). Restore Defaults confirms (#8). A skillie's own "ask first" always holds (#7). Meeting alerts skip a call you joined (#11). The command editor's Cancel really cancels.
2. **Silence (rule 3).** No "Copied", "Saved", "Connected", "Volume at" or "Moved to" cards for what you chose; nothing said twice. AGENTS.md currently requires some of these notes; it changes with them.
3. **Ask or undo (rules 1 and 2, D2 to D5, D9).** One undo for every delete: ⌘Z for 10 s. Quit without asking. Reversible Ask results done at once. Approval cards say the action plainly, with Always only where it is kept.
4. **Keys and dead ends (rules 5 and 6, D6 to D8).** The footer shows the selected row's keys. ⌘C copies on every row. ⇥ in a mode shows actions. esc goes back before it closes. Missing values are asked in the card. Beeps become one line. Setup asks for two things. Links can be trusted per entry.

Open question: a few behaviours were read in code only and need a live check on the mini during batch 1 (whether a failed reading turns Keep Awake off; whether macOS shows its own AirPods banner).

## Done

All four batches shipped (2026-10-17): #195, #196 and #197, then the rest in one pull request.

- **Batch 1, safety.** Cards leave the app its keys: notes take esc only, the undo card ⌘Z and esc only, an agent's question waits for a pause in typing, ⌘↩ in a card's field stays there, a panel that took the keyboard (a display plugged in, a dark meeting alert) keeps its keys. A skillie's own "ask first" holds over Always. Running timers only for "timer" typed out. Clipboard retention says what goes and prunes on the hourly pass; Restore Defaults confirms; the command editor writes nothing before Save. Meeting alerts and auto-join skip a call already joined (a call begun during the meeting before is that one's).
- **Batch 2, silence.** Nothing said for a copy, a sound output, a volume, a Bluetooth device connected, Keep Awake on, a layout saved, esc in the color sampler; a reminder or event confirmed is not said twice.
- **Batch 3, ask or undo.** Quit at once, Force Quit asks; unsure timer, volume or Keep Awake done with ⌘Z; a Homebrew formula installs at once; questions say the verb ("Restart? ↩ Restart · esc Cancel"), Always only where it is kept; every delete of the user's data comes back with ⌘Z for 10 s (copies, files, reminders, events without invitees, snippets, commands, quicklinks, keys, servers, Your Details fields…).
- **Batch 4, keys and dead ends.** The footer shows the selected row's own ↩; ⌘C copies on every row; ⇥ in a mode shows actions (or its own By Meaning…), never Ask; esc goes back a step; the calculator's ↩ pastes; beeps became one line; a missing value is asked in the card; a sure menu item is chosen at once; Do It Here asks sensitive details together; reminders change in place (Tomorrow, Next Week, ⌘Z); setup asks for Accessibility and the SI only, ✕ means later; links can be trusted per entry; a timer's, the volume's and Keep Awake's values are read in the route's own request.

Chosen without asking (say if one should change): pastes from links never trusted (a page could read the copies); a skillie's trust covers its arguments; modes opened straight (✦C, ⌃⌘Space) close on the first esc; a menu item chosen at once says its shortcut ("· next time: ⇧⌘E"); "Close" menu items still wait for ↩; Do It Here asks only for sensitive details (IBAN, SIRET), not name or email; the undo card's titles ("Copy Forgotten", "Moved to Trash", "Key Removed"…).
