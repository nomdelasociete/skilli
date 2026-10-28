# Launcher shorthand: a value after a word cut short or an alias

Asked 2026-10-28: typing `awa` fast, neither ⇥ (Ask) nor ↩ (the untimed
toggle) keeps the Mac awake **for 2 h**. Wanted: one way that fits the app
and works for every command that reads a value, not an Awake special.

## The rule

A command that reads a value takes it after **a space**, whether its word is
typed whole, cut short, or replaced by the user's alias:

| Typed | Read as | Row first |
|---|---|---|
| `awake 2h` | (as before) | Keep Awake · 2 h (until 16:05) |
| `awa 2h`, `aw 2` | `awake 2h`, `awake 2` | Keep Awake · 2 h (a bare number is hours) |
| `tim 10 tea` | `timer 10 tea` | Start Timer · Tea · 10 min |
| `ti 1:30` | `timer 1:30` | Start Timer · 1 min 30 s |
| `vo 30`, `volu 30` | `volume 30` | Set Volume to 30 % |
| `a 2h` (alias `a` on Keep Awake) | `awake 2h` | Keep Awake · 2 h |
| `r Weekly sync` (alias `r` on Record Meeting) | `rec Weekly sync` | Record “Weekly sync” |

- **Cut short**: two letters or more, the start of exactly one taught word
  (`AwakeRequest.word`, `TimerRequest.word`, `VolumeRequest.word`), and what
  follows must be read by that command's own parser. The value is strict (a
  duration, a time, a level), so a search like `visual st` never turns into
  a command. Words whose value is free text (`event`, `remind me`, `rec`) are
  not cut short: `re Weekly` would be anybody's guess.
- **Alias**: the user chose it, so it carries any value its row reads, free
  text included (`r Weekly sync`). Rows that read a value: Keep Awake
  (`awake`) and Record Meeting (`rec`). Aliases on modes and skillies keep
  working as before (`openAlias`).
- The user's alias wins: `aw` set on an app keeps `aw 2` for that app; a
  word is cut short only when the first word is no alias.
- Nothing read (`awa`, `awa `, `awa soon`): the launcher is as it was; the
  plain row stays (↩ toggles).
- ⇥ keeps its meaning (Ask outside the modes): no new key, no new mode.

## Moment

- **When**: in the launcher, in a hurry, the first letters of a command
  already selected its row, and the value is what is left to say.
- **Path**: keep typing — space, the value. No key to learn: the space is
  what one types after a word anyway.
- **Hint / push**: none needed; the row's title says what was read
  ("Keep Awake · 2 h (until 16:05)") before ↩. The Catalog's examples show
  one short form.
- **Deterministic or AI**: deterministic, the same parsers as the whole word
  (`LauncherShorthand` in SkilliCore, unit-tested). No model.
- **Cost of wrong**: low — a row offered first, nothing done before ↩; a
  timer or Keep Awake started by mistake is cancelled from its row, the menu
  bar or ⌘Z.

## Where

- `LauncherShorthand.expand(_:aliases:)` (SkilliCore): the text with the
  word whole, or nil.
- `LauncherController.updateResults`: the parsers of timer, Keep Awake,
  volume and Record read the expanded text; an alias whose value was read
  does not push its plain row above the read one.
