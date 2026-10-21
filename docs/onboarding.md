# Welcome to skil.li: the first launch

2026-10-18: "the onboarding must be at least on par with Raycast, Arc
browser or the best of the best in class. It's VERY IMPORTANT because the
software is huge and has many capabilities."

This is the spec. It replaces the two-card setup window (D7: "First launch:
only Accessibility and your SI"), which stays true: the welcome asks for
no other permission.

## What the first minute must leave behind

In about a minute after the first launch, the person has:

1. turned on Accessibility, guided at the switch itself;
2. **felt** the Hyper Key: held Caps Lock and seen ✦ light up;
3. **opened** the launcher with ✦ Space and closed it with esc;
4. connected their SI, or chosen "later" knowingly;
5. **fixed real text** with ✦K G and taken it back with ⌘Z;
6. seen the three keys to remember, and where everything else lives (`?`).

Every step is something they do, not something they read. Then skil.li is
quiet (manifesto 9, "Taught once, then quiet"): no tips, no badges, no
checklist, no "did you know".

## What the best do, and what we take

Research of 2026-10-18 (Raycast, Linear, Superhuman, Things, Alfred,
Arc-era tools, Cursor, Warp, Claude, ChatGPT, Wispr Flow, Superwhisper,
Shortcat, Rectangle, Ice, Karabiner, PopClip, the HCI literature). The
points that decide this design:

- **Teach a key by having it pressed, in the flow.** Linear's ⌘K step
  ("Let's try it out"), Claude's "double-tap Option to test the shortcut".
  Superhuman taught E and H by pressing them: their use rose 50%, and
  activation went from 40% to 50%.
- **Full-screen steps beat checklists and tooltips.** Superhuman measured
  zero effect from checklists, tooltips and timed nudges. Steps with smart
  defaults took completion from 30% to 98%. Swipe-through "decks" of
  feature slides do not help (NN/g, 70 users).
- **Practice on safe content first.** Superhuman's fake inbox added 17% to
  activation. Wispr Flow's practice demos put your own dictation in a
  sandbox. Things ships a tutorial project you can recreate.
- **Permissions:**
  - one at a time;
  - say why in one line;
  - detect the grant live (Rectangle every 0.3 s, Ice every 1 s, Shortcat's
    window reacting);
  - guide at the switch: Codex, Permiso and PermissionFlow float a panel
    next to System Settings, with the app icon to drag into the list.

  Apple's HIG: the screen before macOS's prompt has one button, never
  labelled "Allow", and never shows a fake of the system alert. macOS 27
  renamed the list "Device Control and Data Access" (Rectangle follows the
  OS version); our words must too.
- **SI: find what the person already pays for.** Warp's "Sign in with
  ChatGPT", Claude-style detection. A key gets a **Verify** button
  (Raycast). "Set up later" keeps nobody stuck (Warp, after dropping its
  "I don't want AI" buttons). No account: Warp's forced login was its most
  hated step and was removed.
- **Nobody tests the Hyper Key live.** Raycast has a diagnostic panel;
  Karabiner has a separate EventViewer; Hyperkey and BetterTouchTool have
  nothing. A live "hold Caps Lock now" is ours alone.
- **After the welcome, the novice path is the expert path:**
  - Office's KeyTips and ExposeHK put the key where the click is;
  - Raycast's action bar shows each action's key;
  - marking menus appear only on hesitation (Kurtenbach).

  skil.li already does this (the launcher's footer, ⌘K with keys on the
  right, the Catalog's "?"); the welcome points at it once.
- **What people hate:**
  - forced login (Warp);
  - privacy hidden until sign-in (Cursor);
  - Clippy-style interruptions;
  - a tip at every launch (JetBrains);
  - permissions that silently break after an update (Wispr, PopClip,
    Shortcat);
  - a learned key taken over by a product change (ChatGPT's ⌥Space).

## The window

- One window, 720 × 520 pt, Liquid Glass (`Theme.glass`, card radius),
  centred on the screen with the pointer, no title bar. It stays above
  normal windows while it is in front. System Settings and macOS's prompts
  take the front when they open; the window comes back when their job is
  done (`PermissionCenter.onChange`).
- **Top, 300 pt: the stage.** Each step's own live picture: the switch,
  the keyboard, the launcher's keycaps, the providers, the practice text.
  **Below: the words.**
  - A title: SF Pro Display 28 pt bold.
  - At most two lines: 15 pt, secondary color.
  - One control row:
    - Back, bottom left, plain text with **esc**;
    - optional Skip, plain text;
    - the step's one filled button, bottom right, with **↩**.
- Progress: six small dots above the title. The current dot is long and
  mint, done dots are filled, the rest are hairline.
- Keys (manifesto 7, one key one meaning):
  - ↩ continues;
  - esc goes back, and on the first step closes (= later);
  - ⌘W closes (= later).

  The live steps take their own keys (Caps Lock, ✦Space, ✦K G, ⌘Z) and
  never steal anything else.
- Motion:
  - steps slide sideways (spring, 0.35 s);
  - a done step's check pops once;
  - the welcome's glass S rises and leans toward the pointer (the one 3D
    transform AGENTS.md → Brand allows), never a loop.

  With Reduce Motion: cross-fades, no tilt.
- Light and dark from semantic colors. Mint (`AccentColor`) only on the
  live elements and the current dot.
- VoiceOver: every stage has a label that says what is happening ("Caps
  Lock held: ✦ is on").

## The steps

### 1. Welcome

2026-10-20: a colleague who went through it "thought that it was
just for show and not for setup". So it says from the start that it sets
things up, and at the end what it set.

- **Stage:** the glass S on its halo (`BrandGlassHalo`), then four chips
  for what the next steps set up: Accessibility, Hyper Key, Launcher key,
  Your SI.
- **Title:** "Let’s set up skil.li."
- **Line:** "A minute: one switch, your keys and your SI. Then it works in
  every app. Free, open source, no account."
- **Button:** "Get Started ↩".

### 2. Accessibility

- **Stage:** a drawn System Settings row: the skil.li icon, "skil.li", and
  a switch that turns itself on, again and again (today's `SwitchHint`,
  larger). It is a drawing of what to do, never a copy of macOS's alert.
- **Title:** "One switch, and skil.li works in every app."
- **Line:** "It lets skil.li hear its keys, and read and replace the text
  you select. Nothing leaves your Mac for it."
- **Button:** "Continue ↩". It triggers macOS's own prompt
  (`PermissionCenter.grant(.accessibility)`), which opens the list.

**At the switch: the guide.**
- A small panel floats on System Settings' window, below its list:
  - the skil.li icon;
  - "Turn on skil.li", with an arrow to the list.

  If skil.li is not in the list, the icon can be dragged into it (the
  app's bundle URL is the drag item).
- It follows the window as it moves (`CGWindowListCopyWindowInfo`, a
  0.15 s timer while shown) and never takes the keyboard (a non-activating
  panel).
- It names the list as the OS does: "Accessibility" up to macOS 26,
  "Device Control and Data Access" from macOS 27.
- It closes when the switch is on, or when System Settings closes.

**Granted** (read live, every 0.5 s, as today):
- the welcome comes back in front;
- its stage's switch locks on;
- a check pops;
- 0.6 s later it moves on by itself.

**Later** (Skip, esc, ✕):
- the welcome goes on with steps 5 and 7 only (3, 4 and 6 need the key
  tap);
- the launcher's first row and the menu bar keep "Allow Accessibility" /
  "Set Up skil.li…" as today.

### 3. The Hyper Key

- **Stage:** a keyboard's left side, drawn: Tab, Caps Lock, Shift.
  - The Caps Lock cap reads "✦" over a small "caps lock".
  - While Caps Lock is held, the cap sinks and glows mint, and the keys
    A, C and Space light up with what they do (Ask, Clipboard, Launcher).
  - Released, it settles back.
- **Title:** "Caps Lock is your Hyper Key now."
- **Line:** "Hold it with a letter for skil.li's shortcuts: ✦A asks, ✦C
  opens your clipboard. Tapped alone, it's Escape."
- **Live:** "Hold Caps Lock." The first hold ticks the step:
  - "That's ✦.";
  - Continue fills.
- **Skip:** yes.
- **States** (`HyperKeyRemapper.plan`):
  - **shared with another app** (Raycast's F20): one more line, "Shared
    with your other Hyper Key app: both work.";
  - **custom mappings found** (`leaveAlone`): no live test. The stage
    shows Caps Lock untouched, and the line says: "Caps Lock already has
    a custom mapping, left as is. Choose your Hyper Key in Settings →
    Keys." The button reads "Continue ↩".

### 4. The launcher: its key, chosen, then pressed

2026-10-18: "the rights, then the primary shortcuts, then show around
with the chosen keys"; "Raycast was able to override Spotlight's ⌘Space
during the setup".

- **Stage:** three ways to open skil.li, side by side (2026-10-19:
  "recommend ⌘ Space, then Hyper Key Space or custom"):
  - **⌘ Space**, "Instead of Spotlight", marked Recommended;
  - **✦ Space**, "With your Hyper Key" (the default until a choice);
  - **Your own keys**: a click records the next keys pressed, with the
    store's recorder, refused as Settings → Keys refuses them (macOS's own
    shortcuts from its full Keyboard Shortcuts list, the launcher's keys,
    another skil.li shortcut), the reason said under the cards.

  The chosen one is teal with a check. A click chooses, saved as Settings
  → Keys saves it, so the rest of the welcome and the last step show it.
  ⌘Space is skil.li's by the same rule as Search Emoji's ⌃⌘Space
  (`KeyOwner.replacedBy`), and, as Raycast does, skil.li turns Spotlight's
  own ⌘Space off in macOS (`SpotlightKey`); it comes back on if the
  launcher later leaves ⌘Space.
- **Title:** "Open skil.li with one key."
- **Line:** "Choose its keys, then press them: the launcher opens. Type a
  few letters; ↩ opens, esc closes."
- **Live:**
  1. The launcher opens for real (`LauncherController.onOpened`). The
     chosen keys glow while it is open.
  2. Its line becomes "Type a few letters, then esc."
  3. When the launcher closes (`onClosed`), the step ticks and moves on.
- **Skip:** yes.

### 5. Your SI

- **Stage:** the providers found on this Mac, as rows, each with a state
  read live (`AIStore.claudeStatus`, `codexStatus`, the saved keys):
  - **Claude**:
    - "Your subscription, through Claude Code": Signed in ✓ / Run
      `claude` once to sign in (Copy) / Not installed (Get Claude Code ↗);
    - or "API key" (Paste, Verify).
  - **ChatGPT**: the same, through Codex, or an OpenAI key.
  - The first one ready is chosen: a mint radio, changeable.
  - These rows sit under **Writes** (answers and rewrites). Under
    **Chooses** (Ask in a blink, search by meaning, Do It Here) is
    **TypeSafe Jev**, marked Recommended, with a field and Verify (the
    same test as Settings → SI Accounts). An OpenAI key, when there is
    one, chooses too. Without one: Do It Here stops, nothing is found by
    meaning (clipboard, files, history, snippets, emoji by feeling), and
    Ask waits for Claude Code or Codex to choose. Said under the field.
- **Title:** "Bring your own SI."
- **Line:** "Your Claude or ChatGPT writes, TypeSafe Jev chooses in a blink.
  No credits, no account with us: only what a request needs leaves your
  Mac (Settings → Privacy)." This is manifesto 11 in the line itself.
- **Button:** "Continue ↩". With nothing connected, the button reads
  "Later ↩", and step 6 uses a command that needs no SI.
- **Verify:**
  - Paste a key in place (secure field, Keychain).
  - **Verify** runs the same test as Settings → SI Accounts → Test
    (`AIStore.tests`).
  - It shows "Works · 0.8 s" or the provider's own reason.

### 6. Try it on text

The one step that only shows: its title says so ("Try it: …").

- **Stage:** a note card with one sentence, already selected:
  "i has wrote this sentense to quick, it need fixing" (invented,
  public-repo rule). It is a real text field in the welcome window.
  Commands act on it as on any app's field (skil.li's own windows are
  read on the main thread, `FocusedElement.isOwn`).
- **Title:** "Fix any text, in any app."
- **Line:** "Select text, press ✦K then G. ↩ puts the fix in place; ⌘Z
  takes it back."
- **Live:**
  1. ✦K shows the chain panel (as anywhere).
  2. G runs Fix Spelling & Grammar. The card shows the change.
  3. ↩ replaces the text. The step reads "Fixed. ⌘Z brings the old one
     back."
  4. ⌘Z restores the text, and the step ticks: "That's the whole idea:
     it acts, ⌘Z undoes."
- **Without SI:** the line becomes "Select text, press ✦U: UPPERCASE." It
  runs the same way, with no card.
- **Skip:** yes.

### 7. Set up

- **Stage:** what the welcome set up, a line each, a check when it is on
  (`WelcomeModel.setUp`): Accessibility, Hyper Key, Open skil.li (its
  keys), the SI that writes, the SI that chooses. A missing one is
  orange and says where it is set later ("Settings → SI Accounts").
- **Title:** "skil.li is set up.", or "Almost set up." when a line is
  missing.
- **Line:** "Everything else: type ? in the launcher."
- **Toggle:** "Open skil.li at login" (on by default; the same setting as
  General).
- **Button:** "Start ↩". It closes the welcome. Nothing is opened for the
  person.
- **Small, at the bottom:** "This welcome stays in the launcher: type
  welcome."

## After the welcome

- It never opens by itself again (`Preferences.didCompleteSetup`, set on
  Start, Later or ✕).
- It reopens on request:
  - **Welcome to skil.li** in the launcher and the Catalog;
  - **Show Welcome…** in Settings → General, where today's "Set Up
    skil.li…" row is;
  - the menu bar's **Set Up skil.li…** while Accessibility is off, which
    opens on step 2.
- No other teaching surface is added. The ones that exist do the rest:
  - the launcher's footer (the selected row's ↩ named, ⌘K);
  - ⌘K's keys on the right;
  - the Catalog `?`;
  - the chain panel (✦K, ✦W);
  - each feature's in-place "Allow …" row.
- Updates: someone who already finished it never sees it again, even
  after a new version.

## What is not in it

- **No other permission:** D7. Microphone, Calendar, Contacts and the
  rest are asked where they are first used.
- **No import from Raycast:** hidden until the maintainer has tried it, 2026-10-15.
- **No account, no email, no newsletter, no telemetry.**
- **No use-case quiz:** the keys are the same for everyone.
- **No feature tour slides:** NN/g found they do not help. The Catalog is
  the tour.

## How it is tested

- `selftest welcome` (on the mini, under its lock) runs these checks:
  - draws every step off screen, light and dark, at every state:
    - waiting;
    - granted;
    - shared Hyper Key;
    - custom mapping;
    - no SI;
    - Claude signed in;
    - key verified;
    - fixed;
    - undone;
  - writes the captures;
  - fails when a step's content runs past the window.
- It drives the live steps with the self-test's own keys:
  - a held Hyper trigger ticks step 3;
  - ✦Space then esc ticks step 4;
  - ✦K G with the self-test's writer (no tokens), then ↩, then ⌘Z ticks
    step 6.
- It checks that the guide panel sits inside System Settings' window
  frame and follows it.
- Captures from the mini are judged by eye, two or three rounds, before
  the maintainer sees them (AGENTS.md → Design).
