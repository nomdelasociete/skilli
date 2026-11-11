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
- **The alias alone**: the command comes first, its Catalog row for
  those with no row of their own (Timer, Set Volume…); ↩ on it opens the
  chip.
- **Without an alias**: ↩ in the Catalog ("?") on a command that only
  reads a value (Keep Awake for a While, Timer, Set Volume, Add an Event,
  Remind Me) opens the same chip. Keep Awake and Record Meeting do
  something with no value: ↩ on them there does it, as on their row.
- **Off in Settings → Catalog**: the command's rows leave the search; its
  alias and the "?" still open its chip, as for any entry turned off.
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

- **When**, each case apart. All in the launcher, hands on the keys, the
  value the only thing left to say:
  - *Keep Awake*: before leaving a long task running (a build, a
    download), for a length or until an hour.
  - *Timer*: something started away from the Mac (tea, a break).
  - *Set Volume*: a call or a video about to start, a known level wanted.
  - *Record Meeting*: a meeting starting, a name worth giving it now.
  - *Add an Event*, *Remind Me*: a thought in the middle of other work,
    written before it is lost.
- **Path**: the alias, a space, the value, ↩. Or "?" → the command → ↩ →
  the value, ↩. The alias alone puts the command first.
- **Hint / push**: the chip names the command and the placeholder shows an
  example, so what to type is read, not learnt. No push: nobody is told to
  set an alias, none is given.
- **Deterministic or AI**: deterministic for all six, the parsers of the
  whole words (`LauncherArgument.text`). No model, and the chip sends
  nothing off the Mac: a length, a level and a recording's name stay
  here; an event or a reminder goes to the user's own Calendar or
  Reminders, which sync as the user set them.
- **Wrong**: nothing is done before ↩, and the row says what was read
  first ("Keep Awake · 2 h (until 16:05)"); not read, no row. After ↩:
  - *Keep Awake*: the cup in the menu bar says until when; the chip or
    "awake" shows it running, ↩ lets the Mac sleep.
  - *Timer*: it counts down in the menu bar; the Timer chip, empty, lists
    the timers running.
  - *Set Volume*: heard at once; set again.
  - *Record Meeting*: a recording is never automatic, and the chip shows
    the one running, ↩ stops it; a recording kept by mistake is deleted
    in Recordings (⌘Z brings it back).
  - *Add an Event*, *Remind Me*: the card says where it was added, ⌘Z
    takes it back.
  Giving up the words cut short costs those who typed them: they set an
  alias once.

## Where

- `LauncherArgument` (SkilliCore): the declarations, `of(_:)` by alias id,
  `text(_:)` the words the parser reads.
- `CatalogEntry.takesAlias`: true for an entry that declares an argument,
  even one with no launcher row of its own (`catalog.timer`).
- `LauncherController`: `Mode.argument`, `openAlias`, `argumentRows`,
  `argumentShown` (wired, not the Catalog's switch), `argumentEntry` (the
  alias alone), `runCatalog`.
- Self-tests: `calc` (the alias, alone and with a value, ⌫ out of the
  chip), `catalog` (Timer ↩ in the "?").

## Not done

- A field for the recording's name from the "?" without an alias: Record
  Meeting ↩ records at once there; "rec <name>" typed does it.
- More than one argument for a built-in command: none needs it yet.
