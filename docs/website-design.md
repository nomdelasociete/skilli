# skil.li website: approved design and content

Decision record consolidated on October 12, 2026. Read this before changing the
website's design, copy, demos, navigation, social assets or legal pages. These are
approved choices, not a request to redesign the site. Later explicit user decisions
supersede this record; update the relevant section when a choice changes.

## Sources of truth

- This document: approved website choices and rejected directions.
- [Manifesto](MANIFESTO.md): the principles the site's message follows.
- [Features](FEATURES.md): what the app does now, by area.
- [Brand kit](../assets/brand/README.md): ribbon geometry, material and native exports.
- [Website README](../website/README.md): preview, build, publishing and metric sources.
- [Skillies guide](../skillies/README.md): contributions and local installation.
- Native code and relevant tests: what the product actually supports. Check current
  implementations before adding claims; the demos are illustrations, not evidence.

## Message and page hierarchy

The site is entirely in English. Product name: `skil.li`; repository: `skilli`.
The website is the Cloudflare Worker `skilli-website`. The app is a fast, lightweight native macOS launcher with
customizable shortcuts, key sequences, contextual actions, voice and the user's AI.

The opening screen is an atmosphere and identity screen: logo, animated mint halo,
wordmark and these exact lines:

> Being skilled is your first nature.
>
> Your Mac must keep up.

“First nature” is intentional. Keep it. The concrete product explanation belongs
in the next section, not in the opening screen. The approved second-screen heading
is “Shortcuts, voice and your own AI.” Keep the opening logo and type restrained;
earlier oversized versions were rejected.

Feature sections should show useful work and explain differentiators: instant
access, fast sequences, context-aware actions, useful AI in the current app,
custom commands and an app that evolves with the user's agent. Open source,
free forever, no trackers or telemetry, and full BYOK are central messages.
External provider fees remain separate. Do not imply that AI inference is free.

## Visual identity

- Use the approved **Halo menthe** and folded glass S with its separate dot.
  Preserve its proportions, folds and dot. Follow the brand kit for geometry.
- `website/halo.js` is the site's original WebGL shader. “OpenShaders” was an
  exploratory reference, not a dependency or the source of the approved shader.
- Keep demo backgrounds dark, with mint/petrol accents derived from the halo.
- The Open source section uses the same shader, dimmed in the shader before its
  fine grain is applied. The old static radial gradient visibly banded and was
  rejected. Preserve dithering at the final color output.
- Glass in web demos uses translucent surfaces, subtle edges, blur and shadows.
  It approximates Apple Liquid Glass; the native app uses `NSGlassEffectView`.
- The S stays still. Its highlights stay attached to its folds. An independently
  moving shine across the S looked unnatural and was rejected.
- The app's menu-bar mark remains a simplified monochrome template; website
  shaders do not belong in the native app. The full app icon is mainly seen when
  Settings is open, not as a permanent Dock presence.

## Typography and writing

Use **Geist Pixel Line** for large headings and short catchy phrases. Use
**Trueno Light** for body copy and Trueno for the wordmark. Square and Circle
variants of Geist Pixel are used briefly in the approved heading animation.
Trial typeface comparisons are not the production direction. Fonts are
self-hosted with their licenses; do not add unlicensed or trial fonts to builds.

Copy should be direct, specific and brief. Use concrete examples instead of
vague promises about intelligence. No em dashes in site copy, titles or labels.

Hard guardrails from repeated feedback:

- No “Book a demo” CTA.
- No “Demo only”, “Confirm in demo”, “Run shortcut in demo”, or explanations of
  scripted results, microphone access or fake app activity in public copy.
  Use action labels such as Run, Send, Allow and Cancel. Internal docs may explain
  the simulation so future agents do not connect it to real external actions.
- No links to development tickets, PRs or internal design documents in product
  copy. The GitHub repository and Skillies contribution guide are intentional links.
- Do not present one person's launcher/voice shortcut as the default. Shortcuts
  are customizable, including Command-based and Hyper Key-based choices.

## Motion

Motion explains cause and effect. Keep a continuous sequence and a legible result.

| Surface | Approved behavior |
| --- | --- |
| Halo | Slow, visibly moving mint light; glass ribbon geometry remains fixed. |
| Headings | Brief character transitions between Geist Pixel Line, Square and Circle; large headings also animate on scroll entry. |
| “must” | A short restrained shake on entry and interaction, not perpetual vibration. |
| Voice to keyboard | A connected story from request to streamed result, then the saved key sequence. |
| Shortcut diagrams | A signal travels between keys; modifier stays held, next keys press in order, result follows. Loop while visible, at the faster approved pace. |
| BYOK connections | Several small segments travel quickly in both directions simultaneously, with randomized trips. |
| Speed section | Subtle fast particle trails and animated numeric counters using self-hosted Motion. |
| Demo progress | Thin progress line at the bottom of the scene, above the black controls; track the current step and reset at its boundary. |

Disconnected key flashes and arbitrary glitching were rejected: the viewer must
understand which key comes next. Keep the short pause/fade between shortcut loops;
the signal must not sweep backward during reset. Respect reduced motion, pause
controls, hidden tabs and offscreen states. Do not reintroduce a Stop button on
the opening screen. Existing demo playback controls are separate.

## Demonstrations

### Ask and writing

Lead with useful work: rough notes inside an email become a clear, friendly message
with the right tone. Preserve the recipient, subject and meaningful details.
Stream the answer visibly, review it, then Return applies it in the original app.
The keyboard demo also streams its result.

“Notes → email”, “Translate” and “Take action” form a playback sequence. Selecting
a tab starts that scenario; Watch demo starts the selected scenario's playback,
not an unconditional jump to Notes → email. Keep progression through the scenarios.

Do not imply that a straightforward rewrite request is ambiguous. The user can
review without pressing Return; a preview is not automatically applied.

### Ask, beyond writing

- A vector-app request may offer both VectorCraft and Adobe Illustrator. Show
  choice when several installed apps fit and Ask is unsure.
- Export demonstrates one intention across apps. The prominent claim is
  “One shortcut. One intention.” with the explanation “The action adapts to the
  app and the menus it exposes.” It must not become a tiny footnote.
- “Export the current document.” is visibly attributed to **You**, the user.
- Show real keycaps **⌘ ⇧ E**, the same in each app, with **“Your keys. Your choice.”**
  This is an illustrative configurable chord, not a product default. App changes
  animate the keys and update the result: Word / Save As…, Illustrator / Export…,
  InDesign / Export…, video editor / Render…. Do not substitute an empty key or
  “Your export shortcut” for the actual keys.
- These menu names illustrate context adaptation. Check current code and menu
  availability before claiming universal compatibility or unattended execution.
- “Also works with” includes core macOS functions and ends with the ability to
  build or connect more capabilities.

### Your shortcuts and launcher

Explain three equally valid paths to the same action: one keystroke, a sequence,
or a quick search. Forgetting a shortcut is fine: find the action in skil.li and
see its shortcut. Mid-sequence hints show the next keys; experienced users can type
straight through without waiting for the overlay or letting go of ✦.

Use a sufficiently large source for the launcher screenshot. The approved source
is 1560 px wide and is displayed at up to 760 CSS px; do not restore the blurred
low-resolution capture in “Know where you’re going.”

### Speed and BYOK

Speed and low memory are product benefits, not merely implementation details.
Use the metric definitions and recorded measurements in the website README.
Distinguish **AI time to first word** from completion time. Do not turn a warm-run
measurement into an “always under one second” guarantee.

Explain the user's own API keys or Claude Code subscription, local voice
transcription, Keychain storage, and provider costs separately. Provider support
and decision routing evolve: verify the native implementation before revising
provider names or behavior.

### Agent-created skillies

Show the user's request to their own agent, script creation, user approval and
the resulting launcher command. Subsequent script execution does not require a
new AI request. Keep the command useful (the current example is Project status).

The repository's `skillies/` folder is canonical for the public collection.
Merges rebuild the catalog automatically. This is website publication, not an
app subscription to the catalog: installation currently means inspecting and
placing a downloaded script in the local Skillies folder. SI command import
links are a different format and must not be presented as script installation.

### Everything else

After "The everyday stuff, too", one grid of cards ("Everything else": The
rest of your day. One key away.) shows what the sections above do not:
clipboard, snippets, emoji, windows, meetings, reminders, do it here,
dictate, search, GitHub, timers, what leaves the Mac. One sentence each,
from [Features](FEATURES.md); keys only where they are the app's defaults
(✦C, ⌃⌘Space, ✦W, ✦D). Add a card when a feature area ships.

The key is called the **Hyper Key** (✦), the name Mac users know from Raycast,
Karabiner and Hyperkey (2026-10-17: "everyone calls it hyper key"). Not
"Super Key": that is the Windows/logo key on Linux and Windows.
Privacy copy (FAQ, legal page) says what Settings → Privacy says:
Ask's request and the names it chooses among, extracts for searches by
meaning, images described by TypeSafe with a key, link previews.

## Navigation, footer and legal

The sticky header spans **the entire viewport**, with no capped dark rectangle
or cut-outs at either side. Keep it slim and translucent over the halo. Align
the persistent Trueno wordmark with the menu padding; it settles into the menu
on scroll rather than becoming a duplicate logo. Show the GitHub logo/link as
an OSS navigation element, with a public star count when GitHub's unauthenticated
API answers. Desktop links jump to real landing sections (launcher, speed, key
sequences, skillies, BYOK, FAQ). The primary CTA is **Get it**, which opens the
FAQ “How do I get it?”: Download skil.li (`/download`, the Worker's redirect to the
latest notarised DMG on GitHub) and the Homebrew command. On small screens
the same links open in a hamburger sheet (focus trap, Escape, `aria-expanded`).
Preserve responsive layout and keyboard focus states.

The shared footer on the landing page, catalog and legal page includes FAQ,
Legal & privacy, GitHub, the free/open-source/BYOK line and
“Made by Nom de la société”. A discreet independence/trademark disclaimer follows.

`website/legal.html` follows dsmn.app's publisher/hosting structure, with English
copy adapted to skil.li. Do not copy dsmn's download analytics, feedback forms or
retention schedules: this site has none of those systems. Distinguish no app
telemetry from technical data processed by hosting providers. Update legal copy
when actual data processing changes. Publisher details came from dsmn.app's legal
page on October 12, 2026; they are not independently reverified registration data.

## Social previews and future edits

The approved social image uses the halo, glass S, baseline, “Your Mac must keep
up.” and the OSS/free/BYOK line. Keep practical product explanations in metadata.
Use page-specific descriptions and absolute production URLs. The README covers
image export and indexable pages.

Before completing a website change, check the affected interaction and layout
in the browser, including relevant narrow-width or reduced-motion states. Run
only checks relevant to the change. Documentation-only edits need link/path and
diff checks, not native tests or a full browser suite. Fetch the current branch
before coding, preserve unrelated app work, and follow the repository PR workflow.
No GitHub Actions for the website. The user allows a repository workflow only
if it becomes strictly necessary for the native macOS build. A merge to `main`
that changes `website/`, `skillies/` or `assets/brand/` publishes the site
(2026-10-22): Workers Builds on the Worker `skilli-website` runs
`python3 website/build.py`, then
`npx wrangler@4.151.3 deploy --config website/wrangler.jsonc`, from the
repository root. Other paths on `main` do not publish. Preview branches do not
publish. The same deploy command publishes by hand before that merge, or when
Builds is down.

For publishing, verify the live result after the build finishes. A merge starts
the publish; the live site is the proof it succeeded. Keep this record and
operational README consistent.

## Approved v4 glass hero (October 12)

The approved hero uses the v4 GLB directly in the landing
page, using `website/brand-glass/`. Frost is 0.1. The logo responds subtly to the
pointer. Geist Pixel Line starts below it, rises behind the glass with real
refraction, then the logo rises with a restrained rotation. Scroll reverses the
sequence. This treatment supersedes the static-S rule for the website hero. The user
approved publication on October 12. Highlights remain attached to the folds.

Follow-up correction: keep the original baseline wording, font size, tracking and
line spacing. Keep “Your Mac must keep up.” visible and moving with the baseline.
Keep the opening pinned long enough for both title lines to cross the glass
before the logo rises. The navigation and Ask section overlap the end of that
sequence from below, so there is no empty scroll corridor. Preserve the real
DOM title and its original character animations on arrival and hover; hand off
to the matching texture only during the glass crossing.

Both the headline and “Your Mac must keep up.” pass behind the glass, with
matching Geist and Trueno textures during the crossing. Keep the DOM animations
before that handoff; never layer the follow-up sentence in front of the logo.

The desktop hero recipe is unchanged: 170svh pin, -65svh nav overlap, logo
scale 0.78, rise `y = 1.18 + leave * 0.85`, pointer ±10° / ±6°, antialias on.
Do not special-case that path for width or pointer type.

On a phone the same mark and rise run in the hero iframe
(`allow="accelerometer; gyroscope"`). The desktop rest and rise
(`y = 1.18 + leave * 0.85`) are kept, mapped through the taller portrait
frustum (`innerHeight / innerWidth`) so the S stays in the top of the pin as
the nav overlaps; a landscape view is the identity, so desktop is unchanged.
Device orientation (beta / gamma, same ±10° / ±6° range) is used only when
the browser already sends it, with no prompt. Never call
`DeviceOrientationEvent.requestPermission`. Android and other browsers that
expose orientation without a prompt keep tilt. iOS Safari (where
`requestPermission` exists) stays on a slow idle drift unless motion is
already available and events arrive on their own. Reduced motion turns tilt
off. GitHub and the hamburger stay in the sticky nav that arrives while the
logo rises, not on the first screen.

## Public URL layout (October 13)

Serve the landing page directly at https://skil.li/, with `/skillies/` and
`/legal.html` alongside it. `website/` is a repository directory, not a public
URL prefix. Redirect legacy `/website/…` links to their root equivalents.
Canonical URLs, social metadata and the sitemap all use root paths.

## Navigation glass logo (approved October 13)

A separate 28 px glass mark fades in left of skil.li
when the sticky navigation reaches the wordmark. It must not be the large hero
shrinking or travelling into the menu: the hero keeps its approved text crossing,
then rises and tilts as before. Keep the small mark transparent and restrained,
without a bright mint fill. Use the static transparent v4 PNG for the small mark,
with restrained neutral toning; no iframe, WebGL scene or pointer tilt in the menu.
The large hero keeps its 3D rendering. Reduced motion disables the menu fade.
This supersedes the initial interactive menu mark (October 13).

## SI labels (October 13)

Use SI wherever public copy previously said AI, including metadata. Preserve
provider names such as OpenAI. Visible SI labels reveal AI on hover or keyboard
focus (tap on touch). In Geist Pixel text, the reveal follows the baseline's
500 ms Line / Square / Circle / Line rhythm. Body copy keeps its own typeface.
Keep label width stable and suppress the font animation for reduced motion.
The shared si-label script also handles text inserted by the demos.
