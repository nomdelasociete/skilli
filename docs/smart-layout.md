# Smart window layout

skil.li learns where the user puts each app's windows, with which other
apps and on which displays, and puts them there: all at once
(**Arrange Windows**), on a display plugged in (**Arrange as Usual** in
the display prompt), and, when the user turns it on, a new window as it
opens (**Usual places**). No layout to save first: the saved layouts
stay, for the arrangements someone wants by name.

Status: phases 1 (Learning, Arrange Windows), 2 (Arrange as Usual in the
display prompt), 3 (Usual places on launch, off by default) and 4 (Usual
places for new windows of apps already running) built; phase 5 not yet. "What skil.li already has" lists what came before it.

## Target

- The screen after a few apps were opened, a display plugged or the
  laptop taken off its stand: one action and every window is where the
  user would have put it by hand.
- For whoever turns it on, a new window (an app launched, ⌘N) opens where
  they always drag it, when skil.li is sure, and nowhere else.
- What skil.li learned is the user's own moves, kept on the Mac. Nothing
  leaves it.
- The same place for the same app in a different context: the editor on
  the left two thirds next to the browser on the big display, filling the
  laptop's screen when alone; the work browser window on the left, the
  personal one on the right.

Not the target: tiling (windows forced into a grid, resized as others
open). A window the user placed never moves unless they ask.

## Moment

The rule (AGENTS.md → A feature's moment): when the user reaches for it
comes before how it learns.

**1. When**

| The moment | What the user is doing | What skil.li does |
|---|---|---|
| A messy screen | opened several apps, wants to start working | **Arrange Windows**, on their action |
| A display plugged in | sat at the desk; macOS put the windows where it wanted | the display prompt, centered on that display, offers **Arrange as Usual** (Display plugged in, below) |
| A display unplugged | left the desk with the laptop; macOS piled the windows on the screens left | **Arrange Windows**, on their action |
| An app launched | about to use it | with Usual places on: its first window goes to its usual place, when sure |
| A new window in an app already open (⌘N, a new browser window) | about to use it | with Usual places on: the same, when sure |
| A window moved or resized by hand | putting it where they want it | nothing shows; skil.li remembers the place once it settles |
| A window placed with ✦W | choosing a place on purpose | nothing shows; remembered, counted more than a drag |

**2. The path**

- **Arrange Windows**: a launcher row (`arrange`, "tidy", "ranger",
  "organiser les fenêtres"), the Catalog ("?"), Ask ("range mes
  fenêtres"), ⌘K on the launcher's window rows (Switch Window), a link
  and a tool (Where it lives). **No shortcut by default**: the user gives it the key they
  want, from its Catalog row or Settings → Shortcuts, as any other entry.
  skil.li never picks a key for it.
- **Arrange Windows again** within 10 s, by whichever path, puts every
  window back where it was before (as Maximize Window again puts it
  back): the undo is the same action.
- **Arrange as Usual**: a row of the display prompt that already shows
  when a display is plugged in (↩, ↑↓, esc, ⌘K as today).
- **Usual places** has no key: it acts as the window opens. Off until the
  user turns it on in Settings → Windows.

**3. Hint or push**

- Arrange Windows is an action, never a push: no card offers to arrange
  on an app launch or an unplug. Windows in a mess are not lost if
  missed, and a card each time would be noise.
- The display plugged in is the one moment that already has its prompt
  (`DisplayPrompt`): Arrange as Usual is a row in it, not a new card.
  The prompt shows for it only when skil.li has places for that set of
  displays (Display plugged in, below); otherwise nothing shows, as
  today.
- Arrange shows nothing when it worked: the windows moving is the answer
  (MANIFESTO 8). A small card only when something went wrong or happened
  out of sight: a window that refused to move, windows left where they
  were because skil.li knows nothing about them yet (the count, the first
  few times).
- Usual places moves a window the user did not ask to move: the one
  automatic part, so off by default and the strictest rules (Usual
  places, below). Its switch's line in Settings says what it does and
  that ✦W R (Restore Window) puts a window back; no card when it acts.
- Nothing involving other people: windows only.

**4. Deterministic or AI**

Deterministic. Where a window goes is answered by the user's own history:
the place they gave that app, and that window by its title, on these
displays, with these other apps open. Code counts and weighs it
(Learning, below); a model would add a delay and send app names off the
Mac for an answer the history already gives.

Jev only for what history cannot answer and only if it proves magic: an
arrangement of apps never seen together, where Arrange would otherwise
leave windows where they are. Phase 5, behind its own switch, listed in
Settings → Privacy (What leaves the Mac, below). Calendar and time of
day are not used (Not used, below).

**5. Wrong**

| Wrong guess | What it costs | How the user sees it and undoes it |
|---|---|---|
| Arrange puts a window in a place the user does not want | one window to move back | Arrange Windows again within 10 s: every window back; or ✦W R on that window; or drag it: the drag is learned and lowers the wrong place |
| Arrange as Usual offered when the user did not want it | one prompt to dismiss | esc ignores it once; ⌘K → Never Arrange on These Displays, or Ignore This Monitor (as today) |
| Usual places (when on) moves a new window wrongly | a window jumping as it opens; the worst case is under the pointer or the caret | it acts only before the user touched the window (Usual places); ✦W R puts it back (the frame it opened at is kept in `WindowManager`'s memory, as for a ✦W move); moved away within 30 s, the place loses its sure state and that app is not placed again until it has been confirmed again |
| Two windows of one app told apart wrongly by their titles | the work and personal windows swapped | Arrange again restores; dragging them back teaches the right ones |
| Learned from a move that meant nothing (a window pushed aside for a second) | a wrong place counted once | a place needs several confirmations before Usual places uses it; a move that does not last is not counted |
| Learned from skil.li's own moves | a loop: skil.li confirming itself | every window skil.li moves (Arrange, a layout, Usual places) is marked where it put it and never counted as the user's |

## What skil.li already has

- **`WindowManager`**: moves the front window through Accessibility (its
  own windows directly), keeps where each window was before (Restore,
  Maximize twice), the gap between windows (Settings → Windows), and the
  sizes cycled by pressing a place again (`WindowCycle`).
- **`WindowLayout`**: the named places (halves, thirds, two thirds,
  quarters, fill, almost fill, center) and their frames from a display's
  visible area and the gap.
- **`WindowArranger`**: every window open (`windows(all:)`), saved
  layouts in `~/Library/Application Support/skil.li/layouts`, applying a
  layout (apps opened, windows matched by title and rank, the report
  card `LayoutReport`).
- **`SavedWindowLayout` / `WindowLayoutPlan`**: a saved arrangement with
  each window's display by who it is, frames carried to other displays in
  proportion (`WindowLayoutPlan.frame(_:from:to:)`), windows matched by
  title and document (`WindowLayoutPlan.match`).
- **`DisplayFingerprint`, `Displays`, `DisplayWatch`, `DisplayArrival`**:
  who each display is, plugged and unplugged events without the false ones
  after sleep.
- **`DisplayPrompt`**: the glass prompt centered on a plugged display,
  listing the saved layouts that match (↩, ↑↓, esc, ⌘K options), with the
  ignored monitors in Settings.
- **`AXWait`**: waits on Accessibility notifications (window created,
  moved, resized) for one app, for a time, without sleeping.
- **`LayoutSnap.freeSpot`**: a free place for a window among others (the
  layout editor's Add App).
- **`QueryLearning`**: what the launcher learned, weighed with a
  half-life (30 days) so habits can change; the pattern to follow for
  weighing places.
- **`AutoQuitter`**: already follows when each app comes to the front and
  leaves it (`NSWorkspace` activate, deactivate, launch, terminate).

What is missing: nothing remembers where the user puts windows by hand,
and nothing places a window without a saved layout.

## Learning

### What is remembered: a placement

When a window settles where the user put it, skil.li writes one
placement:

- **App**: its bundle id.
- **Window**: its title and its document (Accessibility's `AXDocument`,
  when it has one), to tell one window of an app from another: the work
  browser window from the personal one, one project's editor from
  another's. The title is kept as its words (at most 80 characters),
  on the Mac only (What leaves the Mac, below).
- **Window kind**: its rank among the app's windows and whether it is the
  only one. Standard windows only (`AXStandardWindow`): no panels,
  dialogs, sheets, palettes, full screen.
- **Place**: the frame as fractions of its display's visible area, so it
  carries to another resolution. Within 24 pt of a named place
  (`WindowLayout`, with the gap), it is kept as that place, so "the left
  two thirds" stays the left two thirds on every display.
- **Display**: which display it is on, by fingerprint.
- **Displays**: the set of displays connected (fingerprints), the
  context that matters most: the laptop alone, the laptop and the big
  display, the desk's two displays.
- **With**: the other apps with a standard window visible on the same
  display at that time.
- **How**: dragged by hand, or placed with ✦W (or a place from the
  launcher, Ask).
- **When**: the date, for the half-life.

### When it is read: no watcher on every window

skil.li reads a window's place at moments it already sees, not on every
move (`WindowLearner`):

- **At launch**: every app's windows, where they are; an app launched
  later, once it finished launching.
- **An app comes to the front** (`NSWorkspace` activate): its visible
  standard windows are read (frame, display, title, document): where
  they are before the user works in it.
- **An app leaves the front** (`NSWorkspace` deactivate, as
  `AutoQuitter` already follows): read again. A window whose frame
  changed by more than 8 pt since and that is not where skil.li put it
  was moved by the user: one placement. The place it has as the user
  leaves the app is the one they settled on; a window moved and moved
  back meanwhile counts nothing.
- **✦W places a window** (`WindowManager.apply`, and a place from the
  launcher or Ask): one placement, "placed with ✦W", counted double.
- **Arrange is run**: the app in front is read first, so a move made in
  it since it came to the front counts.
- **The Mac goes to sleep**: the app in front is read.

Readings run off the main thread (Accessibility with a 0.2 s timeout per
app, CoreGraphics' window list for the apps beside it: no permission).
One Accessibility observer, on the app in front only (window created):
a window it opens during the visit is read where it opened, so moving it
before leaving the app counts too. An app just launched is read once it
finished launching. No observer on the other apps.

Every window skil.li moves itself (Arrange, a layout, ✦W) is marked
where it put it: found there (as the app rounded it, 24 pt), it is not
the user's move.

### How a place is chosen

For a window W of app A, in the displays connected now, with the apps
visible now:

1. The placements of A with the same set of displays.
2. Each weighed: its age with a half-life of 30 days (as
   `QueryLearning`); ✦W ×2; times how alike its "with" is to
   the apps visible now (shared apps over all apps of both: 1 when the
   same apps, 0 when none in common, never below 0.2 so a habit still
   counts with other apps open); times how alike the window is:
   - the same document: ×3;
   - else the title's words shared (over all words of both, numbers and
     words under 3 letters left out): from ×1 when none in common to ×3
     when the same; the words that are in every one of A's titles (the
     app's name, "— Google Chrome") do not count;
   - an app whose windows all have the same title (or none): the window's
     rank instead, ×2 for the same rank.
3. Places within 24 pt of each other are one place; the place with the
   most weight wins, on its display.
4. No placement with this set of displays: the placements on a display
   of the same kind (the built-in one, an external one) carried in
   proportion, at half their weight: the same display when it is
   connected, else an external one for an external one; never an
   external display's place on the Mac's own screen.
5. Nothing: no place. Arrange leaves the window where it is.

**Sure** (what Usual places needs): the winning place holds at least 3
placements and at least 70 % of the weight for W in this context, and
none of the last 3 placements in this context for a window like W went
elsewhere.

Kept small: for each app and set of displays, its last 48 placements.
In `~/Library/Application Support/skil.li/placements.json`, written
after a change, at most once every 10 s, at sleep and on quit; read once
at launch. A user with 60 apps and 3 display sets stays under a
megabyte.

## Arrange Windows

1. The windows: every visible standard window of every visible app on
   every display connected. Minimized windows, hidden apps, full-screen
   windows and skil.li's own are left as they are.
2. **A saved layout first.** When a saved layout's displays are the ones
   connected (each surely itself), its apps are exactly the apps with a
   window open, and it would open nothing (no file, folder or link it
   opens, every file it shows already open), Arrange applies that
   layout: the user's own words beat what skil.li learned. Several
   match: the one saved last. A layout that would open windows is put
   back by its name, not by Arrange: Arrange again could not take back
   what it opened.
3. Otherwise, each window's place (How a place is chosen). Two windows
   of one app never get the same place: the one whose title or file fits
   it better keeps it (two browser windows), the other takes its next
   place, or else stays where it is. Windows of different apps may share
   a place: the user stacks them (everything filled on the laptop).
4. Windows with no place stay where they are. When none got one, a small
   card says skil.li does not know where they go yet and learns once they
   are put where the user wants.
5. Each window is moved through `WindowManager.place` (the enhanced UI
   switch for Chrome and Electron, size, place, size again); one already
   there (4 pt) is left alone. Before moving, each window's frame is kept
   for Arrange again (10 s) and for ✦W R (`WindowManager.remember`).
   Arrange again puts every window back; one that refuses is named in a
   card and stays kept, so Arrange again once more tries it again.
6. One line in the log with the windows, where they went, from which
   placements, and the time taken (no titles in the log). Budget: under
   150 ms for 20 windows, off the key path (the action only starts it).

## Display plugged in: Arrange as Usual

The display prompt (`DisplayPrompt`) gains one row, **Arrange as Usual**,
when the displays connected now (the one plugged with the others) have
places learned: at least half of the visible windows would get a place.

- **Saved layouts match too**: they are listed first, as today; Arrange
  as Usual is the last row. ↩ applies the selected row.
- **No saved layout matches**: the prompt shows with Arrange as Usual
  alone, where it showed nothing until now. ↩ arranges.
- **Nothing learned for these displays**: no prompt, as today.
- ⌘K on the row: Arrange as Usual (↩), Record New Layout Here…, Ignore
  Once (esc), Never Arrange on These Displays (the displays connected
  then no longer get the row; listed in Settings → Windows → Advanced,
  Displays never arranged when plugged in), Ignore the monitors (as
  today). Learning off: no row.
- Same rules as the prompt today: a real plug, not a wake from sleep
  (`DisplayArrival`); one prompt on the biggest new display; the keyboard
  only if no key was typed in the last second; no timeout.
- Arrange as Usual is Arrange Windows run then: Arrange again within 10 s
  restores, from any path.

## Usual places (off by default)

Off until the user turns it on (Settings → Windows, Place new windows
where you usually put them). On, a new window goes to its usual place
only when every condition holds:

- it is a standard window, not full screen, from an app not in Never
  place (Settings → Windows, at the bottom);
- its place in this context is sure (How a place is chosen), its title
  and document included: a browser's personal window does not take the
  work window's place;
- the window is not already there (an app that restores its own frame
  there costs nothing);
- the user has not touched it yet: it appeared less than 1.5 s ago, no
  click in it, no key typed since it appeared, the mouse button up;
- it is not an app's window restored at launch among several (an app
  reopening ten documents is left to Arrange, not placed one by one).

A window often shows before its title is final (a browser's new window,
then its page's title): the title read when the window is created, and
again once if it changes within the 1.5 s; no place is sure from an empty
title alone unless the app's windows are told apart by rank.

**Seeing it open**

- **An app launched** (`NSWorkspace` launch): `AXWait` on that app for
  its first window created (4 s), as applying a layout does today. No
  standing observer.
- **A new window in a running app**: a `kAXWindowCreatedNotification`
  observer only on the running apps with at least 3 placements on these
  very displays (`WindowPlacements.mayBeSure`: the ones that may ever be
  sure), kept up to date as the setting, Never place, what was learned,
  the apps and the displays change; removed when they quit. The window
  then goes through the same rules (sure, untouched), its rank among the
  app's windows counted. Measured before building (Measured, below): no
  cost seen.

**Moved away within 30 s**: the place loses its sure state for that
window in this context (the user's move is learned as usual), and Usual
places leaves that app until the place is sure again.

## Where it lives

- **Arrange Windows**: the launcher (and its words in English and
  French), the Catalog with its alias and the shortcut the user gives it
  (none by default), Ask, ⌘K on window rows.
- **The display prompt**: Arrange as Usual (Display plugged in, above).
- **Settings → Windows**, in this order (settings first, long lists
  last):
  - Learn where you put windows (on). Off: nothing new is read or
    learned (what was learned stays until Forget);
    Arrange uses only saved layouts and the display prompt no longer
    offers Arrange as Usual.
  - Place new windows where you usually put them (off).
  - Forget what skil.li learned: deletes `placements.json`, at once, ⌘Z
    for 10 s (`UndoableDeletes`).
  - Displays never arranged when plugged in (list).
  - Never place (apps, at the bottom): Arrange and Usual places leave
    their windows, and nothing more is learned from them; what was
    learned before stays (Forget erases it) and counts again if the app
    leaves the list.
- **Skillies and agents**: `open "skilli://run/system:arrangeWindows"`
  (asks first, as Show Desktop does: every window moves) and
  `"$SKILLI_CLI" call run_mac_command command=arrangeWindows`, as every
  Mac command; documented in `skillies/README.md`.
- **Settings for agents** (`SettingTools`): both switches by the same
  names.

## What leaves the Mac

Phases 1 to 4: nothing. Placements hold bundle ids, frames, display
fingerprints, and the windows' titles and documents; all of it stays in
`placements.json` on the Mac, is never in the logs, and goes with Forget
what skil.li learned.

Phase 5 (Jev for arrangements never seen), if built: the names of the
apps visible, the displays' sizes, the places the user already gave other
apps; never titles, documents or pictures. On Arrange only, never on a
new window. Listed in Settings → Privacy (`PrivacyMap`) with its switch.

## Not used

- **The calendar and the time of day**: a meeting changes which apps are
  open (the call's app), and that is already in "with". A rule on the
  hour would learn the wrong thing from a few days.
- **Spaces**: no public API; windows on another Space are not seen and
  not moved (as saved layouts today).

## Phases

1. **Learn and Arrange Windows**: placements (reading at deactivate, ✦W,
   Arrange; titles and documents), `placements.json`, How a place is
   chosen in SkilliCore with its unit tests (titles told apart, the words
   every title has left out), Arrange (saved layout first, conflicts,
   Arrange again), launcher row, Catalog entry with no shortcut, link,
   tool, Settings (learn, forget, never place). Self-test: three apps and
   two windows of one browser placed by hand, moved away, Arrange puts
   them back; Arrange again restores.
2. **Arrange as Usual in the display prompt**: the row, the prompt shown
   with no saved layout, Never Arrange on These Displays. Self-test with a
   display offered as plugged, as `selftest windows` does today.
3. **Usual places on launch** (off by default): `AXWait` on app launch,
   the conditions, the title settling, moved-away rule.
4. **Usual places for new windows in running apps**: observers on the
   apps with a sure place, after measuring.
5. **Jev for arrangements never seen**: only if phases 1–4 leave windows
   unplaced often enough to matter, measured on placements (how many
   Arrange runs left windows without a place).

## To check before building

- Reading a deactivated app's windows: time on the main actor with a busy
  app (Accessibility's messaging timeout is 0.5 s in `WindowManager`;
  learning must never wait that long on the main thread: off it, or a
  shorter timeout).
- Which apps report `AXStandardWindow` for their main windows (Electron
  apps, Chrome's tabs dragged out, Java apps), and which windows are
  restored at launch (Xcode, Finder, Safari).
- Titles: which apps change their window's title as the user works (the
  browser with each page, the editor with each file) and whether the
  words left after removing the ones every title has still tell windows
  apart (a browser's profile name, a project's name); with a real week of
  titles, on the Mac.
- ~~Memory and CPU of `kAXWindowCreatedNotification` observers on 20 apps
  (phase 4)~~: measured, below.
- The 1.5 s, 24 pt, 70 % and 3-placement thresholds on a real week of
  use: placements logged with the guess Arrange would have made, before
  Usual places is built.

## Measured

**Window-created observers at rest** (2026-10-26, the test Mac, `selftest
windows` → `usualPlacesObserversCost`): 17 apps running, one observer on
each, skil.li at rest 15 s without then 15 s with: footprint 111.81 →
111.80 MB (no change), CPU 11.0 → 9.1 ms per 15 s (noise), wakeups 57 →
63 per 15 s (about 0.4 a second more). Far under the budget (1 MB, 1 %
CPU); and Usual places observes only the apps with enough placements,
usually a handful.

## Decided

- Learning local only, no observer for learning (moments already seen).
- Shortcuts are the user's: Arrange Windows has none by default; the user
  gives it one.
- Arrange Windows again within 10 s restores.
- A saved layout that matches beats what was learned.
- The display prompt offers Arrange as Usual, also when no saved layout
  matches, only when places are learned for those displays.
- Window titles and documents tell an app's windows apart; kept on the
  Mac, never sent.
- Usual places off by default, on only when the user turns it on; only
  for untouched new windows, only when sure.
- Deterministic first; Jev only in phase 5, if measured worth it.
