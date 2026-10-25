# Smart window layout

skil.li learns where the user puts each app's windows, with which other
apps and on which displays, and puts them there: all at once with one key
(**Arrange**), and a new window as it opens (**Usual places**). No layout
to save first: the saved layouts stay, for the arrangements someone wants
by name.

Status: spec, not built. Nothing below exists yet unless "What skil.li
already has" names it.

## Target

- The screen after a few apps were opened, a display plugged or the
  laptop taken off its stand: one key and every window is where the user
  would have put it by hand.
- A new window (an app launched, ⌘N) opens where the user always drags it,
  when skil.li is sure, and nowhere else.
- What skil.li learned is the user's own moves, kept on the Mac. Nothing
  leaves it.
- The same place for the same app in a different context: the editor on
  the left two thirds next to the browser on the big display, filling the
  laptop's screen when alone.

Not the target: tiling (windows forced into a grid, resized as others
open). A window the user placed never moves unless they press a key.

## Moment

The rule (AGENTS.md → A feature's moment): when the user reaches for it
comes before how it learns.

**1. When**

| The moment | What the user is doing | What skil.li does |
|---|---|---|
| A messy screen | opened several apps, wants to start working | **Arrange**, on their key |
| A display plugged or unplugged | sat at the desk, or left it with the laptop; macOS piled the windows on the displays left | **Arrange**, on their key; the display prompt keeps offering the saved layouts that match (unchanged) |
| An app launched | about to use it | its first window goes to its usual place, when sure (Usual places) |
| A new window in an app already open (⌘N, a new browser window) | about to use it | the same, when sure |
| A window moved or resized by hand | putting it where they want it | nothing shows; skil.li remembers the place once it settles |
| A window placed with ✦W | choosing a place on purpose | nothing shows; remembered, counted more than a drag |

**2. The path**

- **Arrange: ✦W W.** In the ✦W group already there (the overlay lists
  it), on a free key: arrows, F, A, C, U I J K, 1–5, N, P and R are taken
  (`ShortcutConfig.windowDefaults`), W is not, and "✦W W" reads as
  "windows, all of them". Also in the launcher (`arrange`, "ranger",
  "tidy", "organiser les fenêtres"), Ask ("range mes fenêtres"), ⌘K on the
  launcher's window rows, a link and a tool (Where it lives).
- **Arrange again** within 10 s puts every window back where it was before
  (as Maximize Window again puts it back): the undo is the same key.
- **Usual places** has no key: it acts as the window opens. Its switch is
  in Settings → Windows.

**3. Hint or push**

- Arrange is an action, never a push: no card offers to arrange. Windows
  in a mess are not lost if missed, and a card on every display change or
  app launch would be noise. The display prompt (already there when a
  display with a saved layout is plugged) does not gain an Arrange row in
  this spec: open point.
- Arrange shows nothing when it worked: the windows moving is the answer
  (MANIFESTO 8). A small card only when something went wrong or happened
  out of sight: a window that refused to move, windows left where they
  were because skil.li knows nothing about them yet (the count, once).
- Usual places moves a window the user did not ask to move: the one
  automatic part, so the strictest rules (Usual places, below). Taught
  once: the first time it places a window, a card for 4 s on that window's
  display, "skil.li put Xcode where you usually do. ✦W R puts it back;
  Settings → Windows turns this off." Never again after that.
- Nothing involving other people: windows only.

**4. Deterministic or AI**

Deterministic. Where a window goes is answered by the user's own history:
the place they gave that app, on these displays, with these other apps
open. Code counts and weighs it (Learning, below); a model would add a
delay and send app names off the Mac for an answer the history already
gives.

Jev only for what history cannot answer and only if it proves magic: an
arrangement of apps never seen together, where Arrange would otherwise
leave windows where they are. Phase 4, behind its own switch, listed in
Settings → Privacy (What leaves the Mac, below). Calendar, time of day
and window titles are not used (Not used, below).

**5. Wrong**

| Wrong guess | What it costs | How the user sees it and undoes it |
|---|---|---|
| Arrange puts a window in a place the user does not want | one window to move back | ✦W W again within 10 s: every window back; or ✦W R on that window; or drag it: the drag is learned and lowers the wrong place |
| Usual places moves a new window wrongly | a window jumping as it opens; the worst case is under the pointer or the caret | it acts only before the user touched the window (Usual places); ✦W R puts it back (the frame it opened at is kept in `WindowManager`'s memory, as for a ✦W move); moved away within 30 s, the place loses its weight and that app is not placed again until it has been confirmed again |
| Learned from a move that meant nothing (a window pushed aside for a second) | a wrong place counted once | a place needs several confirmations before Usual places uses it; a move that does not last a few seconds is not counted |
| Learned from skil.li's own moves | a loop: skil.li confirming itself | Arrange's and Usual places' moves are never counted as the user's; a window left where skil.li put it counts as a weak confirmation only |

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
  proportion (`WindowLayoutPlan.frame(_:from:to:)`), matching windows.
- **`DisplayFingerprint`, `Displays`, `DisplayWatch`, `DisplayArrival`**:
  who each display is, plugged and unplugged events without the false ones
  after sleep.
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

- **App**: its bundle id. Never the window's title or document.
- **Window kind**: its rank among the app's windows (the first window,
  another one) and whether it is the only one. Standard windows only
  (`AXStandardWindow`): no panels, dialogs, sheets, palettes, full screen.
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
- **How**: dragged by hand, placed with ✦W, or left where Arrange or
  Usual places put it (weak).
- **When**: the date, for the half-life.

### When it is read: no watcher on every window

skil.li reads a window's place at moments it already sees, not on every
move:

- **An app leaves the front** (`NSWorkspace` deactivate, as
  `AutoQuitter` already follows): its visible standard windows are read
  once (frame, display). A window whose frame changed since the last
  reading and that is not where skil.li put it was moved by the user:
  one placement. Reading a few windows of one app through Accessibility
  takes milliseconds, off the key path.
- **✦W places a window** (`WindowManager.apply`): one placement, "placed
  with ✦W", counted double.
- **Arrange is pressed**: before moving anything, the windows' places are
  read; any the user moved since they were last read are counted first.
- **skil.li quits or the Mac sleeps**: the front app's windows are read
  once.

No Accessibility observer stays on every app for learning (to measure:
whether Usual places' observers, below, are cheap enough to also tell
moves as they end).

A move counts only when the window stayed there: read again at the next
moment above, still in place (within 8 pt). A window moved and moved back
counts nothing.

### How a place is chosen

For a window of app A, in the displays connected now, with the apps
visible now:

1. The placements of A with the same set of displays, A's same window
   kind.
2. Each weighed: its age with a half-life of 30 days (as
   `QueryLearning`); ✦W ×2; weak ×0.25; times how alike its "with" is to
   the apps visible now (shared apps over all apps of both: 1 when the
   same apps, 0 when none in common, never below 0.2 so a habit still
   counts with other apps open).
3. Places within 24 pt of each other are one place; the place with the
   most weight wins, on its display.
4. No placement with this set of displays: the placements on a display
   of the same kind (the built-in one, an external one) carried in
   proportion, at half their weight.
5. Nothing: no place. Arrange leaves the window where it is.

**Sure** (what Usual places needs): the winning place holds at least 3
placements and at least 70 % of A's weight in this context, and none of
its last 3 placements in this context went elsewhere.

Kept small: for each app and set of displays, the 12 heaviest places,
each with its last 8 "with" sets. In
`~/Library/Application Support/skil.li/placements.json`, written after a
change, at most once every 10 s, and on quit; read once at launch. A
user with 60 apps and 3 display sets stays in a few hundred kilobytes.

## Arrange (✦W W)

1. The windows: every visible standard window of every visible app on
   every display connected. Minimized windows, hidden apps, full-screen
   windows and skil.li's own are left as they are.
2. **A saved layout first.** When a saved layout's displays are the ones
   connected and its apps are the apps open (or a subset covering all of
   them), Arrange applies that layout: the user's own words beat what
   skil.li learned. Several match: the one applied last.
3. Otherwise, each window's place (How a place is chosen), front windows
   first. Two windows wanting the same place on the same display: the one
   in front keeps it, the other takes its next place, or else stays where
   it is. Windows of one app (two browser windows) take their app's places
   in rank order.
4. Windows with no place stay where they are. When some do, and only the
   first few times, a small card says how many and that placing them once
   by hand teaches skil.li.
5. Each window is moved through `WindowManager.place` (the enhanced UI
   switch for Chrome and Electron, size, place, size again). Before
   moving, each window's frame is kept for Arrange again (10 s) and for
   ✦W R, as `WindowManager`'s memory keeps it today.
6. One line in the log with the windows, where they went, from which
   placements, and the time taken. Budget: under 150 ms for 20 windows,
   off the key path (the key only starts it).

## Usual places

A new window goes to its usual place, only when every condition holds:

- the switch is on (Settings → Windows, Place new windows where you
  usually put them);
- it is a standard window, not full screen, from an app not in Never
  place (Settings → Windows, at the bottom);
- the app's place in this context is sure (How a place is chosen);
- the window is not already there (an app that restores its own frame
  there costs nothing);
- the user has not touched it yet: it appeared less than 1.5 s ago, no
  click in it, no key typed since it appeared, the mouse button up;
- it is not an app's window restored at launch among several (an app
  reopening ten documents is placed by Arrange, not one by one).

**Seeing it open**

- **An app launched** (`NSWorkspace` launch): `AXWait` on that app for
  its first window created (4 s), as applying a layout does today. No
  standing observer.
- **A new window in a running app**: needs `kAXWindowCreatedNotification`
  on the apps that may open one. Observers only on the apps that have a
  sure place (usually a handful), added when their place becomes sure and
  removed when they quit. Phase 3, after measuring memory and CPU with
  20 apps observed (To check before building).

**Moved away within 30 s**: the place loses its sure state for that app
in this context (the user's move is learned as usual), and Usual places
leaves that app until the place is sure again.

## Where it lives

- **✦W W**, the launcher's **Arrange Windows** (and its words in English
  and French), Ask, ⌘K on window rows.
- **Settings → Windows**, in this order (settings first, long lists
  last):
  - Learn where you put windows (on). Off: nothing is read or written,
    Arrange uses only saved layouts.
  - Place new windows where you usually put them (on, after phase 2 was
    tried on a real Mac; off until then).
  - Forget what skil.li learned: deletes `placements.json`, at once, ⌘Z
    for 10 s (`UndoableDeletes`).
  - Never place (apps, at the bottom): Arrange and Usual places leave
    their windows, and nothing is learned from them.
- **The Catalog** ("?"): Arrange Windows, with its key and alias.
- **Skillies and agents**: a `skilli://run/system:…` link like the other
  built-in entries (`system:keepAwake`), and a tool `arrange_windows`
  (`display=front` for the display in front only) next to
  `save_window_layout` and `apply_window_layout` (`SkilliTools`);
  documented in `skillies/README.md`. Names proposed, set when built.
- **Settings for agents** (`SettingTools`): both switches by the same
  names.

## What leaves the Mac

Phases 1 to 3: nothing. Placements hold bundle ids, frames and display
fingerprints, never window titles, documents or the screen.

Phase 4 (Jev for arrangements never seen), if built: the names of the
apps visible, the displays' sizes, the places the user already gave other
apps; never titles, documents or pictures. On Arrange only, never on a
new window. Listed in Settings → Privacy (`PrivacyMap`) with its switch.

## Not used

- **Window titles and documents**: they would tell a project apart (two
  Xcode projects, two placements), but they are the user's content, and
  the app and the context already tell most cases. Open point if the
  first tries show apps that need it (a browser's work and personal
  windows).
- **The calendar and the time of day**: a meeting changes which apps are
  open (the call's app), and that is already in "with". A rule on the
  hour would learn the wrong thing from a few days.
- **Spaces**: no public API; windows on another Space are not seen and
  not moved (as saved layouts today).

## Phases

1. **Learn and Arrange**: placements (reading at deactivate, ✦W, Arrange),
   `placements.json`, How a place is chosen in SkilliCore with its unit
   tests, Arrange (saved layout first, conflicts, Arrange again), ✦W W,
   launcher row, link, tool, Settings switches (learn, forget, never
   place). Self-test: three apps placed by hand, moved away, ✦W W puts
   them back; Arrange again restores.
2. **Usual places on launch**: `AXWait` on app launch, the conditions,
   moved-away rule, taught-once card. Off by default until tried on a
   real Mac.
3. **Usual places for new windows**: observers on the apps with a sure
   place, after measuring.
4. **Jev for arrangements never seen**: only if phases 1–3 leave windows
   unplaced often enough to matter, measured on placements (how many
   Arrange presses left windows without a place).

## To check before building

- Reading a deactivated app's windows: time on the main actor with a busy
  app (Accessibility's messaging timeout is 0.5 s in `WindowManager`;
  learning must never wait that long on the main thread: off it, or a
  shorter timeout).
- Which apps report `AXStandardWindow` for their main windows (Electron
  apps, Chrome's tabs dragged out, Java apps), and which windows are
  restored at launch (Xcode, Finder, Safari).
- Memory and CPU of `kAXWindowCreatedNotification` observers on 20 apps
  (phase 3), against the idle budget (< 25 MB).
- The 1.5 s, 24 pt, 70 % and 3-placement thresholds on a real week of
  use: placements logged with the guess Arrange would have made, before
  Usual places is turned on.

## Decided

- Learning local only, no observer for learning (moments already seen).
- Arrange on ✦W W; Arrange again within 10 s restores.
- A saved layout that matches beats what was learned.
- Usual places only for untouched new windows, only when sure.
- Deterministic first; Jev only in phase 4, if measured worth it.

## Open

- An "Arrange as usual" row in the display prompt when a display is
  plugged and no saved layout matches (the decided rule today: unknown
  display, nothing shown).
- Window titles to tell a browser's or an editor's windows apart.
- Usual places on by default after phase 2.
