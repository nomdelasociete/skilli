# Clipboard History: several copies at once, in the order copied

**Built, in two steps**: selecting, ↩ and ⌘↩ on a selection; then
Paste in Sequence on a selection. Two gaps of
`docs/clipboard-review.md`, taken together because one idea answers
both:

- **#8** Paste in Sequence goes newest first: copy A, B, C, then three
  keys paste C, B, A. Collecting in one place to paste in another wants
  A, B, C. Nothing shows what comes next.
- **#9** Several copies cannot be used at once: no way to paste three
  copies joined, or to make one copy of them.

The idea: **select several rows of the history**. What is selected is
pasted in the order it was copied, all at once (↩) or one key each
(Paste in Sequence).

## Moment

1. **When.**
   - The user has copied three or four things in one app (a name, an
     address, a number, from a page or a mail) and is now in the form,
     the sheet or the message where they go. They realize it now, not
     before copying.
   - Or they want one text made of several copies: lines gathered from
     different places.
2. **The path.** ✦C, as always, then:
   - ⇧↓ (or ⇧↑): the row is selected and the next one comes under the
     keys, as in a Finder list. ⌘K → *Select* / *Deselect* for a row
     that is not next to the others. A selected row shows a check and
     its place (1, 2, 3: the order copied, oldest first).
   - ↩: all the selected copies pasted as one, in that order, a line
     each.
   - ⌘↩: the same text copied instead, one new copy of the history
     ("merge").
   - ⌘K → *Paste in Sequence*: the first one (the oldest) pasted now;
     each Paste in Sequence after it (✦K V, or the key the user gave
     it) pastes the next. One per field.
   - esc: the selection goes first, the history stays open; esc again
     closes it.
   No new global key. ⇧↓ and ⇧↑ are keys of the list while it is open,
   as ⇧↩ and ⌘⌫ are: see the questions at the end.
3. **Hint or push.** A hint, where the eye already is: the chip reads
   "Clipboard · 3 selected", the footer "Paste 3 ↩ · Actions ⌘K", the
   rows their numbers. ⌘K lists *Select* on every copy, which is how
   the feature is found. Nothing is announced.
4. **Deterministic or AI.** All code.
5. **Wrong.** A selection is the user's own act and esc undoes it.
   Pasted in the wrong place: ⌘Z in that app, as any paste. Copies that
   cannot make one paste (see below): nothing is pasted and a line says
   what does instead. Paste in Sequence with nothing selected is
   exactly what it is today.

## What is selected, and how it reads

- Only in the history (✦C), and only while it is open: closing it
  without pasting forgets the selection. The one exception is a
  sequence started from it (below), which lives as today's does.
- Typing other words keeps the selection: rows selected and no longer
  shown stay selected, and the chip counts them. So the user can find
  "invoice", select it, find "address", select it.
- The order is the order copied, oldest first, whatever the order the
  rows were selected in. The numbers on the rows say it before
  anything is pasted: this is what "nothing shows what comes next"
  asked for.
- At most 50 (the length of a sequence today).
- ⌘1–⌘9 still paste that row alone.
- ⌘⌫, Pin and the other actions of ⌘K still act on the row under the
  keys, not on the selection (first version). ⌘K's first line, Paste,
  is ↩: with a selection it pastes the selection.

## ↩ on a selection: one paste

| Selected | ↩ pastes |
|---|---|
| Texts (links, colors, addresses, code: all text) | One text, a line each, in the order copied. Plain: the fonts and colors a copy came with are not kept. |
| Files | All the files, as one copy of several files (the ones still there: `docs/clipboard-missing-files.md`). |
| Texts and files together, or any image | Nothing: "These copies do not make one paste: only texts together, or files together. ⌘K → Paste in Sequence pastes them one key each." |

⇧↩ pastes the same as ↩ for texts, and the paths for files.

Not in the first version: another separator than a line (a space, a
comma); an image's text standing for the image.

## Paste in Sequence on a selection: one key each

- ⌘K → *Paste in Sequence* with a selection: the launcher closes, the
  oldest selected copy is pasted. Each Paste in Sequence after it
  pastes the next one, as copied: A, B, C.
- The rules of today's sequence hold: 30 s without a key, or a copy of
  the user's own, and it is over. Past the last: "That was the last of
  the 3 selected." The next Paste in Sequence is today's again (the
  newest copy, then older).
- The app in front changed before the first paste, or the launcher is
  still up: nothing is pasted, a line says the first copy is on the
  clipboard (⌘V pastes it, Paste in Sequence the next).
- A copy whose files are all gone is said and skipped: the next key
  goes on with the next selected one, the first as any other. Files
  gone among others: the others pasted, the gone ones named.
- Something else put on the clipboard before the first ⌘V is sent:
  nothing is pasted, and said.
- `PasteSequence.begin(with:now:)` in SkilliCore;
  `ClipboardHistory.putFirstInSequence(of:)`.
- Images and mixed kinds are fine here: each is its own paste.
- With nothing selected, Paste in Sequence does not change: newest
  first. Nobody's habit breaks.

## Why this and not a queue started before copying

The other apps with ordered pasting (Paste, Pastebot; from what I know
of them, not checked again today) have a mode: start collecting, copy,
then paste in order.

| | Select in the history (proposed) | Collect mode |
|---|---|---|
| When the user must think of it | After copying, when the need shows | Before copying |
| State nobody sees | None: it lives in the open list | A mode on while the launcher is closed: needs a mark in the menu bar and a way out |
| New entry points | ⇧↓/⇧↑ in the list, two lines in ⌘K | A command to start, one to stop, an indicator |
| Cost | ✦C has to be opened between copying and pasting | Forgotten on: the next copies pile up unseen |
| Also gives #9 | Yes | No |

A collect mode can still come later on top of this (it would only
select the copies as they are made). It is not proposed now.

Also set aside: guessing the run ("the copies made since the last
paste"). skil.li does not see the user's own ⌘V, and a guess that is
wrong one time in five is worse than no feature.

## What it costs to build

- `LauncherController`: a set of selected ids in clipboard mode; the
  row's check and number (`ResultCellView`); chip and footer; ⇧↓/⇧↑;
  esc one step earlier.
- `LauncherActions`: *Select* / *Deselect*, *Paste in Sequence* when
  something is selected; ↩ and ⌘↩ on a selection.
- SkilliCore: `PasteSequence` started from given ids, going forward;
  the rule of what makes one paste (texts, files, neither), unit
  tested.
- `ClipboardHistory`: one write of several copies (joined text, or
  files).
- Docs: `FEATURES.md`, the Catalog's line for Paste in Sequence.
- No setting, no store change, nothing leaves the Mac.

Speed: selecting a row is a set insert and one row redrawn; the bound
is the launcher's key bound (8 ms). To measure, not assumed.

Two pull requests: (1) select, ↩ and ⌘↩; (2) Paste in Sequence on a
selection.

## Checks

- Unit: the order copied whatever the order selected; what makes one
  paste (texts, files, neither); the chip; the sequence forward from
  given ids, its end, its 30 s, a copy of the user's own in between.
- Self-test (`previews`): ⇧↓ twice selects two rows, their places, the
  chip and the footer say so; ⌘K → Select adds the third; ↩ pastes the
  three in the app in front, a line each, oldest first; opened again,
  nothing is selected; esc lets a selection go before it closes the
  history; ⌘K → Paste in Sequence on three selected, then ✦K V twice,
  pastes one, two, three. Without keys (`clipboard`): two selected
  paste in the order copied, then "the last of the 2 selected", then
  the newest again.
- Captures of the selected rows, light and dark, looked at.

## Questions (my answer first; built with these answers, 2026-11-11)

1. **⇧↓ / ⇧↑ select.** Yes: they are keys of the open list, like ⇧↩
   and ⌘⌫, not shortcuts given to a command. If these count as the
   user's keys too, the feature ships with ⌘K → *Select* only, and is
   much slower to use.
2. **Order copied, or order selected?** Order copied: it is what #8
   asked, and the numbers show it. Order selected would let the user
   reorder, at the price of a rule to explain.
3. **⌘⌫ on a selection** (forget them all, one undo). Not in the first
   version: a destructive key that changes meaning with a state.
4. **A link or a tool for it.** None: a selection is rows of an open
   list, as a pin is. `get_clipboard` already gives a skillie the
   copies to join as it likes.
