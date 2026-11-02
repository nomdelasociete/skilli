# The launcher and the app in front; names mistyped

Status: built 2026-11-02, branch `claude/peeklight-nanolight-inspiration-1cf772`.
Unit-tested; the self-test (`remote rootsearch`: `emptyFieldLearnsTheAppInFront`,
`namesFoundMistyped`) not yet run on the test Mac.

Asked after looking at two other launchers, Peekalight (peekalight.com) and
Nanolight (github.com/justrach/nanolight): "they seem better at giving
suggestions based on the selected app".

## What they do (checked, not guessed)

**Peekalight** (0.1.5, closed source): a ⌘Space launcher. Home shows recent
apps; search forgives missing letters, swapped letters, keyboard neighbours
and missing spaces; calculator, window and system actions, clipboard, app
aliases, quicklinks with `{query}`, scopes on ⌘1–5. Publishes its numbers
(download size, idle memory, search p95).

**Nanolight** (MIT, Zig): a 1 MB ⌘Space launcher. Apps by name, word starts,
initials, typos and how often each was opened; inline completion after the
caret; math with hex; Google completions; ⌘1–9 run a row.

Neither reads the app in front: Peekalight's site, docs and blog say nothing
of it; Nanolight's empty field lists the most-opened apps, one count for the
whole Mac (`results.zig`). skil.li already did more with context (the
selection where it opened, the meeting starting now, the menus of the app in
front) but its empty field and its learning ignored the app it opened over,
and its search needed the letters in order. The speed numbers are already on
skil.li (the Speed section).

## Moment

1. **When**: ✦Space from any app, nothing typed yet, about to run what is
   always run from there (Figma: the layout for designing, Export…; Mail: a
   snippet; Xcode: Simulator). And a name typed fast with a slip
   ("wahtsapp", "safaari"), where the launcher found nothing.
2. **The path**: the launcher's first rows, ↩ or ↓↩. Nothing new to find.
3. **Hint, not push**: rows in the list the user already looks at; nothing
   moves until three runs from that app make a habit. The row says why
   ("Application · in Figma"), once per row, no badge.
4. **Deterministic**: the user's own runs, counted per app on this Mac
   (bundle id → item, faded with the learning's 30-day half-life). No AI,
   nothing leaves the Mac. Typos: one edit undone by code.
5. **Wrong**: a habit row stands before the usual first app: one row lower,
   the accessory says where it comes from; it fades in a month unused, and
   Forget Learning clears it. A typo guess shows only when nothing matched
   as typed, under Ask's alternative; never on a key that finds something.

## Decided

- `QueryLearning` gains `places` (bundle id → item → hit), decoded as empty
  from older `learning.json` files. Recorded on every run from a launcher
  opened over an app that is not skil.li, whatever was typed, for the rows
  the empty field can show again: apps, commands, Mac commands, SI
  commands, skillies, quicklinks, layouts, snippets, menu items. Not
  contacts, files or events.
- The empty field: the meeting starting now, a selected price, the pins,
  then up to three items run at least three times (faded) from the app in
  front, then the apps by usage. The app in front itself is left out.
  Apps and commands found at once; skillies, quicklinks, layouts, snippets
  as the last catalog read found them (as pins); menu items read through
  Accessibility once the panel is up, off the main thread, only for an
  app with such a habit. Nothing added to the show path but
  `NSWorkspace.frontmostApplication`.
- Typed: an item run from that app gains a third of its learned points, at
  most 15: under a pin (20), a name typed whole (25) and one pick for the
  text (30).
- No setting (root search keeps two). Forget Learning clears it.
- Typos (`FuzzyTypos`): only when the query (4–12 letters) finds nothing as
  typed. One edit undone: two letters swapped, a QWERTY or AZERTY neighbour,
  a letter too many (a dropped letter already matches). A variant counts
  when the name's word starts carry it in runs and it fits strongly; scored
  12 under a match (4 more for a letter dropped). Apps, commands and
  their keywords, the catalog's names, SI commands.

## Not taken

- **Inline completion on ⇥** (Nanolight): ⇥ already shows actions and asks
  by meaning.
- **⌘1–9 to run rows**: to weigh against the keys modes use first.
- **Google completions, Grok and X rows**: they send what is typed away;
  Ask covers the need.
- **The size race** (1–3 MB): not winnable with the recorder and Whisper.

## Measures

- Typo corpus (`FuzzyTyposTests`): 95 names (Mac apps and skil.li's rows),
  three slips each (a swap in the middle, the second letter's neighbour,
  the third letter doubled), 269 slips that find nothing as typed: the name
  meant is first (alone, or tied with names sharing the corrected word, as
  every "Search …" row for "serach") 269 times.
- Worst key, 12 letters over 2,000 names, Debug build: 14 ms. Release on
  the test Mac (`remote speed`, the `typos` lap): not measured yet.
