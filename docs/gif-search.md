# GIF Search, skil.li's way

Proposal, 2026-10-19.

**Status**: phase 1 built the same day, Klipy and On this Mac (asked: "do
klipy and gifs on this mac"); AGENTS.md → Search GIFs says how it works.
Not built yet: Favorites, ⇥ by feeling, Ask opening the grid,
`search_gifs`, GIPHY, more than the first 48 of a search. Starting point: Raycast's
[GIF Search](https://www.raycast.com/josephschmitt/gif-search) (109 k
installs; [source](https://github.com/raycast/extensions/tree/main/extensions/gif-search)).

## Short answer

Not a skillie: a skillie prints text, it cannot show a grid of moving
pictures nor put a GIF file on the clipboard. GIFs become a **mode of the
launcher, built like Emoji** (`EmojiGridView`, "e smile", ↩ pastes, ⌘↩
copies): `gif ` or Search GIFs, a grid, the GIF pasted in the app in front.
What Raycast leaves as preferences (13 default actions, 3 grid sizes, max
results, 2 locale lists, download path, provider dropdown), skil.li decides.
One Jev moment where it is magic: ⇥ finds the GIF for a feeling or for the
message you are answering.

## How Raycast's works

Read in its source on 2026-10-19 (TypeScript, in Raycast's Node process):

1. **Search**: a plain `fetch` (no sign-in, 15 s timeout) to Raycast's own
   server: `gif-search.raycast.com/api/giphy?q=&limit=&offset=&lang=`,
   same for `/api/klipy`. That server adds the key and forwards to the
   provider. Raycast has used GIPHY Pro (GIPHY's paid tier) since 2024-04;
   Klipy went through the proxy on 2026-07-01, the day after Tenor shut
   down (before that, each user typed their own Klipy key). The Finer Gifs
   Club (The Office only) is called directly, no key.
2. **Results**: each provider's answer mapped to one shape (small preview,
   large preview, full GIF, page link, size, tags), shown in Raycast's
   `Grid` (8, 5 or 3 across, a preference), animated.
3. **↩**: one of 13 actions, picked in the preferences (Copy GIF by
   default). Copy and Paste download the full GIF to a temp file and put
   the file on the clipboard; Paste then pastes.
4. **Favorites and Recents**: ids in Raycast's LocalStorage, read back by
   id (`?ids=`). A favorite's file is kept in `cached-gifs/` once copied.
5. **Square**: writes a Swift script to disk and runs it with
   `/usr/bin/swift` (compiled on each run) to crop every frame.
6. **AI tool** `search-gifs`: 5 results' links for Raycast AI.

What makes it work is the server and Raycast's deals (GIPHY Pro, Klipy's
approval of the proxy). skil.li has neither. Calling Raycast's server from
skil.li would technically work (it asks for no sign-in), but it is
Raycast's service, under Raycast's agreements, and can be shut to us any
day: not an option.

## Every source, compared

Read 2026-10-19 ([Klipy docs](https://docs.klipy.com/getting-started),
[GIPHY docs](https://developers.giphy.com/docs/api),
[Tenor shutdown guide](https://agentdeals.dev/tenor-alternatives)).

| Source | What | Cost | Verdict |
|--------|------|------|---------|
| **Klipy** | Tenor's successor, 10 M+ GIFs (its figure), stickers, clips, memes; Bluesky and (reported) Discord use it | Free; Testing 100/h, Production unlimited on request | **First** |
| **GIPHY** | The biggest library | Beta 100/h free; Production needs an application and has a fee | **Second, with the user's own key**: 100/h is plenty for one person; never skil.li's shared key |
| Tenor | Was the default | API shut 2026-06-30 | Gone |
| Imgur | User uploads, not curated for reactions | Free for non-commercial use; not in the UK | No: weaker results, a country left out |
| The Finer Gifs Club | The Office only | Free, no key | No: a niche |
| GIFs on this Mac | GIFs on disk (Spotlight: `com.compuserve.gif`) and in Clipboard History | Nothing sent | **Yes, as its own section**: private, offline, skil.li's |
| Raycast's server | Raycast's keys | Raycast's | No: not ours |
| Scraping giphy.com / tenor.com | | Against their terms | No |
| Our own index | Curate and host GIFs | Licensing and hosting | No |

Klipy and GIPHY set the same rules (requests from the user's Mac, no
proxy, no saved media, results as given, never two providers mixed in one
grid), so the design below holds for both: a provider is a section of the
grid, never blended.

## The mode

- **Opens**: `gif ` / `gifs ` typed, Search GIFs in the launcher, its alias,
  a shortcut (none by default), Ask ("colle un gif bravo" opens the grid on
  "bravo": skil.li never pastes a GIF nobody saw). Its own chip. A Catalog
  entry (`FeatureCatalog`), its prefix in `LauncherPrefix`.
- **Grid**: `GIFGridView` on `EmojiGridView`'s pattern: it draws the
  launcher's rows, the hidden table stays the selection every action reads,
  ←→↑↓ move. Four across, one fixed tile size (no setting), each GIF
  cropped to fill its tile, its title under VoiceOver only. The selected
  tile's title and source in the header, as Emoji shows the name.
- **Moves only where you look**: every tile shows its first frame; only the
  selected one plays (and the one under the pointer). 24 GIFs playing at
  once would cost CPU and memory for nothing, and a calm grid reads better.
- **Field**: its placeholder says "Search KLIPY" (Klipy requires it).
- **Nothing typed**: Favorites, then Recently Used, then Trending, each its
  own section. skil.li keeps only their ids (slugs) and reads them back in
  one request (`gifs/items?slugs=`) when the mode opens: Klipy forbids
  keeping its media.
- **Typing**: one request after a 250 ms pause, the one before cancelled;
  the next 24 when the grid scrolls near its end. Klipy's results in
  Klipy's order, nothing added, removed or moved (its rule). Answers kept
  in memory for the mode's life: backspacing shows the earlier words' GIFs
  again, nothing asked.
- **On this Mac**: a section after Klipy's, the GIFs on disk that fit the
  words (Spotlight, by file name and folder) and those in Clipboard
  History. Read only on this Mac, pasted offline.
- **GIPHY**: with the user's own key (Advanced), its own section after
  Klipy's, in GIPHY's order; "Powered By GIPHY" under it, as GIPHY asks.
- **Language**: the Mac's (Klipy's `locale`); "chat qui danse" works.

## Keys and actions

One key, one meaning, as everywhere (AGENTS.md, Launcher actions):

| Key | Does |
|-----|------|
| ↩ | **Paste** the GIF in the app in front (see Paste below) |
| ⌘↩, ⌘C | Copy the GIF |
| ⇧⌘C | Copy its link |
| ⇥ | By feeling (below) |
| ⌘⌫ | Remove from Recently Used / Favorites, Undo ⌘Z 10 s (`offerUndo`) |
| ⌘K | Paste, Copy, Copy Link, Copy Markdown · Add to Favorites, Save to Downloads, Open Page · Remove |

Footer: "Paste ↩ · By Feeling ⇥ · Actions ⌘K", as `mainAction(for:)` says.
Dropped from Raycast's list: Copy/Paste Square (Slack emoji makers; back if
asked), View Details (the header says title and source), Download path
(Downloads, shown in Finder after).

## Paste

- The GIF is fetched (its full size from Klipy, 15 MB at most), written to a temp
  file named after its title, and put on the clipboard as **both** the
  file's URL and `com.compuserve.gif` data: Slack, Discord, Messages take
  the file; Mail, Notes, Pages take the data. An `NSImage` would lose the
  animation: never through `NSImage`.
- Then ⌘V, as Paste Latest Screenshot does
  (`SystemCommands.pasteLatestScreenshot`, `pressPaste`). Seen pasted:
  nothing said. Too slow to fetch (> 6 s) or refused: one line in the card.
- Where a file cannot go: a terminal or a code editor in front (the bundle
  ids `EditorProjects` already knows, plus Terminal, iTerm, Ghostty, Warp),
  ↩ pastes `![title](link)` instead and the footer says **Paste Markdown**,
  so it is never a surprise.
- Then the temp file goes, and Klipy is told the GIF was shared
  (`gifs/share/{slug}`: it counts shares, and its rules forbid getting in
  the way of that).
- Favorites and Recently Used keep ids only, never the GIF: no offline
  paste (Klipy's rule).
- To ask Klipy: whether a temp file made only to paste counts as a "copy"
  under its rules. If it does, ↩ pastes the GIF's link (whether Slack,
  Discord and Messages then show the GIF: to check on the mini).
- To check on the mini, app by app: Slack, Discord, Messages, Mail, Notes,
  WhatsApp, GitHub in Safari and Chrome. Animation must survive in each.

## By feeling (Jev, only on ⇥)

The magic moment, as Emoji's: GIF sites search words, people think in
situations.

- **A feeling or a situation typed**: "quand la CI passe enfin", "my PR got
  merged after 3 weeks". ⇥ sends only what was typed and a fixed list of
  ~150 reactions (en + fr: celebrate, finally, facepalm, mind blown, thank
  you, slow clap…) to Jev or OpenAI Decisions in one Choice; the two or three
  likely ones are searched and their GIFs shown, the reaction's name in the
  header. Jev picks among choices, never writes the query: what it can do,
  nothing more.
- **The message you answer**: text selected when the mode opens (read once
  with `SelectionService.read`, as SI commands do), ⇥ in the empty field
  sends that text (300 characters at most) the same way: "Reaction to
  “Server's down again…”". Select a Slack message, ✦ + the GIF shortcut,
  ⇥, ↩: answered.
- **Words learned**, as Emoji's (`EmojiLibrary.said`): a GIF picked after
  ⇥ keeps the typed words for its reaction, on this Mac; the same words
  next time skip Jev.
- Off with Settings → GIFs → Find GIFs by feeling with ⇥; then ⇥ does
  nothing and nothing is sent. Typing never sends anything to Jev.

## Provider and key

Read in [Klipy's docs](https://docs.klipy.com/getting-started) on
2026-10-19.

- **Klipy only, first.** Tenor's successor (same API shape: "replace
  tenor.googleapis.com with api.klipy.com"), free. A
  key from the Partner Panel: **Testing, 100 requests an hour** for the
  key; **Production, unlimited**, asked for in the panel once the app is
  ready. Endpoints: `api.klipy.com/api/v1/{key}/gifs/search?q=&page=&per_page=&customer_id=&locale=`,
  `trending`, `items?slugs=`, `share/{slug}`. The key is in the path of
  every request.
- **GIPHY not first**: a new key is a beta key, 100 calls an hour; going
  live means an application and a talk about pricing. Not for a free app
  shipping one key. Later, with the user's own key under Advanced, if asked.
- **Klipy's rules that shape the feature**:
  - Requests and media loads **from the user's Mac**, never through a
    server of ours without Klipy's written approval. (Raycast's server,
    `gif-search.raycast.com`, must have that approval.)
  - **No copies of the media** kept (no disk cache, no saved favorites)
    without approval: ids only.
  - Search and Trending **shown as given**: no reordering, inserting,
    removing or filtering in the app. Filtering (blocked words, an
    MPA-style rating) is set once in the Partner Panel.
  - "Search KLIPY" as the field's placeholder: **required**. "Powered by
    KLIPY": optional.
  - Ads come only if turned on for the key in the panel: left off, so
    none come.
- **The key: skil.li's own, in the Release build** (decided, from the
  rules above). Requests must come from the Mac, so the key has to be on
  the Mac: it is Klipy's standard integration, the one its SDKs and demo
  app use. `script/release/publish.sh` puts it in (never in the public
  repo); Debug builds and forks read Settings → GIFs → Advanced → Your
  Klipy key (Keychain, as SI keys are). The known risk: anyone can read a
  key out of an app or its requests. Production has no quota to burn, so
  the worst case is Klipy revoking a misused key: GIF search stops until an
  update ships a new one (Sparkle, the same day).
- **Not chosen**:
  - A server of ours: against Klipy's rules unless approved, one more
    service to run, and every search word passing through it. Its only
    gain, changing the key without an update, is not worth that.
  - Each user's own key as the only way: a sign-up at Klipy before the
    first GIF. Kept only as Advanced, for forks.
- **`customer_id`**: a random id made once on this Mac, never tied to the
  person (Klipy uses it for its own "recent" lists, which skil.li does not
  call).

## Speed and memory

- Nothing made at launch; the mode's objects made on first open, freed when
  the launcher closes (idle budget < 25 MB, after use < 40 MB, unchanged).
- A key in the field does what it does today: the request is scheduled,
  never made on the key (keystroke budget < 2 ms).
- Tiles: Klipy's smallest formats, decoded off the main thread with
  `CGImageSourceCreateThumbnailAtIndex` at the tile's pixel size (never the
  whole GIF), kept in a memory cache of 8 MB at most, gone when the mode
  closes (never on disk: Klipy's rule); the playing tile
  through `CGAnimateImageDataWithBlock` (ImageIO), stopped as the selection
  moves.
- Network as `ClipboardLinks` does: its own ephemeral session, no cookies,
  no cache, 6 s, http(s) only, sizes capped. Logs never contain the words
  searched.
- `PrivacyMap`: two flows under Websites. **GIF search**: sends the words
  typed in the GIF mode, the Mac's language and skil.li's random id to
  Klipy, after a pause; the id of each GIF pasted or copied.
  **GIFs by feeling**: sends what was typed, or the text selected, to Jev or
  OpenAI Decisions, only on ⇥.

## Settings → GIFs

One feature, one pane, settings first:

1. Search GIFs' shortcut and the launcher's prefix.
2. Find GIFs by feeling with ⇥ (on), what it sends, Words learned + Forget.
3. Favorites (count) and Recently Used (Forget, Undo ⌘Z).
4. Advanced: Your Klipy key; Your GIPHY key (adds GIPHY's section).

No grid size, no default action, no result count, no locale list, no
provider list, no safe search switch: what Klipy shows is filtered once,
for everyone, in its Partner Panel (its rule).

## Agents

`search_gifs` (words, count ≤ 10 → title, GIF link, page link), read-only,
always allowed, like Raycast's tool. An agent writing a PR description or a
Slack message can put a GIF in it. No `paste_gif`: an agent shows the link,
the user decides.

## Tests

- `selftest gifs` (keys, on the mini, with its lock): a fake Klipy on
  127.0.0.1 as `selftest previews` serves pages. Nothing sent before the
  pause nor for the words backspaced over; only the selected tile plays;
  ←→↑↓; ↩ into the test window gets GIF data and a file URL, animated
  (frame count > 1); ⌘↩ copies; Markdown in a terminal-like test window;
  Klipy's order kept; the GIF shared reported once; a favorite read back
  by its id; nothing of the media on disk after the mode closes; ⌘⌫ and
  Undo; ⇥ sends nothing
  with the switch off. Captures light and dark: empty, a search, long
  titles, nothing found, the network down. Judged by eye 2–3 rounds before
  the maintainer sees it.
- `remote-benchmark`: a key in the GIF mode, memory after 100 tiles shown
  and after closing.
- Paste into the real apps above, by hand on the mini, once.

## Phases

1. **Search and paste**: the mode, the grid, Klipy, ↩ / ⌘↩ / ⇧⌘C, Recently
   Used, the Markdown fallback, Settings → GIFs, PrivacyMap, `selftest gifs`.
   The one entry point tried first: `gif `.
2. **Keep**: Favorites (ids), ⌘K's full list, Ask opening the grid,
   `search_gifs`.
3. **By feeling**: ⇥ on words, on the selection, Words learned.

## What the maintainer does (only they can)

1. Create the account at partner.klipy.com, add the platform "skil.li
   for macOS", create its key; ads off, the content filter set.
2. Ask developers@klipy.com, in one mail: a temp file made only to paste,
   allowed? Production access for a free, open source Mac app (after
   phase 1 works on the Testing key).
