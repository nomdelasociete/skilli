# ⌘1–9 open a row; the calculator reads hex

Status: spec 2026-11-03, building on branch `claude/launcher-cmd-digits-hex`.

The last two ideas taken from Nanolight (github.com/justrach/nanolight),
after [launcher-app-in-front.md](launcher-app-in-front.md): its ⌘1–9 run a
row, its math reads hex. Peekalight's scopes on ⌘1–5 (search one kind
only) are not taken: they would need the same keys, and the modes (`f`,
`cb`, `@`…) already search one kind.

## ⌘1–9 open a row

### Moment

1. **When**: the launcher shows the row wanted, but not first: the third
   app for "s", the second file, a clipboard entry four rows down. Today
   it is ↓↓↩; the eyes already see it.
2. **The path**: ⌘ with the row's number, from the launcher already open.
   The number row's keys by their place, so AZERTY's ⌘& is ⌘1, as on
   every layout. The same as ↩ on that row: an app opens, a snippet
   pastes, a mode's row does what its ↩ does.
3. **Hint, not push**: nothing on screen until ⌘ is held alone; after
   0.3 s, each visible row shows its key (⌘1…⌘9) at its right edge, in
   place of what is there (a snippet's keyword), back on release. A
   quick ⌘C, ⌘K or ⌘↩ never shows them. No setting, no badge, no hint
   that comes back by itself (MANIFESTO 9).
4. **Deterministic**: the rows as drawn, counted from the first visible
   one. Nothing leaves the Mac.
5. **Wrong**: ⌘3 opens the third row when the user meant another: the
   same cost as ↓↓↩ one row off. An app opened is closed as any app; a
   paste is undone with ⌘Z in the app.

### Decided

- Rows that cannot be selected (a section's header) are not counted.
- ⌘K's list open: digits filter it as before (its own keys first).
- ⌘1–⌘9 join the launcher's own keys (`LauncherKeys`): a new shortcut on
  them is refused ("Used by the launcher: Open Row 3."); one given before
  still runs (the bindings see the key first) and Settings → Keys says it
  shares the key, as for ⌘K.
- One key, one meaning (MANIFESTO 7): no ⌘digit is used elsewhere in
  skil.li.

## The calculator reads hex

### Moment

1. **When**: a developer reads a color, a flag or an address in hex
   ("0x1F + 8", "0xff"), or needs one ("255 in hex", "4096 en binaire").
2. **The path**: typed in the launcher, no mode, as any calculation; ↩
   pastes, ⌘↩ or ⌘C copies.
3. **Hint, not push**: the answer row, as for any calculation.
4. **Deterministic**: the calculator's own parser.
5. **Wrong**: "0x10" was read 0 × 10 = 0 before; it now means 16 (no
   one writes 0 × 10 that way). A word after "in" that is not a base or a
   unit answers nothing, as before.

### Decided

- Literals `0x…`, `0b…`, `0o…` wherever a number goes. Alone ("0xff"), it
  is an answer: 255.
- "in hex / hexa / hexadecimal", "in bin / binary / binaire", "in oct /
  octal", "in dec / decimal / décimal" (also with "to", "en", "→"): the
  value in that base, "0xFF", "0b1010", "0o17". Integers only, within
  ±2^53; otherwise no answer.
- A calculation written with hex gives two answers: the decimal first,
  then hex ("0xff + 1": 256, then 0x100).
- No bitwise operators (`&`, `|`, `<<`): `&` is a key's place on AZERTY
  and an "and" in a sentence; to add only when asked.
