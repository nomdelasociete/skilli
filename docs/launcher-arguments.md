# Launcher arguments: a command says what it reads

Asked 2026-11-11. Before: the value of Keep Awake, Timer or Set Volume was
read after their word cut short (`awa 2h`, `tim 10`, `vo 30`), a second
system beside the aliases that nobody saw, chose or could turn off, kept in
two hand-written lists. Wanted: one system, the user's aliases, and commands
that take an argument the way a skillie does (seen in Raycast: the command
declares its fields, alias then space puts the cursor in the first one).

## The rule

A command that reads a value **declares its argument** (`LauncherArgument`,
SkilliCore): the word its parser reads, the chip's name, an example.

| Command (alias id) | Chip | Example shown in the field |
|---|---|---|
| Keep Awake (`system:keepAwake`), Keep Awake for a While (`catalog.awake`) | Keep Awake | 2h, 90 min, until 6pm |
| Timer (`catalog.timer`) | Timer | 10 min tea, 1:30 |
| Set Volume (`catalog.volume`) | Volume | 30 |
| Record Meeting (`cmd:recordMeeting`) | Record | A name for the recording |
| Add an Event (`catalog.event`) | Event | lunch with Paul tomorrow 1pm |
| Remind Me (`catalog.remind`) | Remind Me | call Paul at 9am |

- **The alias, then a space**: the launcher becomes that command's chip, the
  field holds only the argument, its example as the placeholder. The row
  says what was read ("Keep Awake · 2 h (until 16:05)"); ↩ does it. Inside
  the chip the words are an argument, never a search: nothing overlaps.
- **Without an alias**: ↩ on the command in the Catalog ("?") opens the
  same chip.
- **One field**, read by the command's own parser (`2h`, `90 min`,
  `until 6pm`): no field per unit, no command per way of saying it.
- **Nothing typed**: the command's plain row where it has one (Keep Awake:
  ↩ toggles; Record Meeting: ↩ records; Timer: the timers running), else
  the example. Typed but not read: no row, the example again.
- **No alias is given by skil.li**: the user sets them (⌘K → Set Alias…,
  Settings → Catalog). The words cut short are gone; `awa 2h` is a search
  again unless `awa` is the user's alias.
- Whole phrases typed in the root search keep working as before
  (`awake 2h`, "pas de veille 2h", `timer 10 tea`, `volume 30`).
- esc leaves the chip for what was typed before it, like any mode.

## Moment

- **When**: in the launcher, in a hurry, for a command used often enough to
  have been given an alias, when the value is what is left to say.
- **Path**: the alias, a space, the value, ↩. Or "?" → the command → ↩ →
  the value, ↩.
- **Hint / push**: the chip names the command and the placeholder shows an
  example, so what to type is read, not learnt. No push: nobody is told to
  set an alias.
- **Deterministic or AI**: deterministic, the parsers of the whole words
  (`LauncherArgument.text`). No model.
- **Cost of wrong**: low. Nothing is done before ↩, and the row says what
  was read. Giving up the words cut short costs those who typed them: they
  set an alias once.

## Where

- `LauncherArgument` (SkilliCore): the declarations, `of(_:)` by alias id,
  `text(_:)` the words the parser reads.
- `CatalogEntry.takesAlias`: true for an entry that declares an argument,
  even one with no launcher row of its own (`catalog.timer`).
- `LauncherController`: `Mode.argument`, `openAlias`, `argumentRows`,
  `runCatalog`.

## Not done

- These commands' alias typed alone (no space) puts nothing first for the
  five that have no row of their own in the root search.
- More than one argument for a built-in command: none needs it yet.
