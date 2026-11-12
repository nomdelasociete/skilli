# Clipboard History: review (2026-11-10)

Read: `Sources/Skilli/Clipboard/*`, the launcher's clipboard mode, its
preview and actions, Settings → Clipboard, the spec of #123. Measured: a
real 30-day history on the test Mac (402 copies: 299 texts, 71 files, 32
images, 19 MB on disk). The other apps (Raycast, Paste, Maccy, Alfred,
Pastebot, macOS's own history in Spotlight) are compared from what I know
of them, not re-checked today.

## What #123 shipped, in plain words

Two things, both in the preview on the right:

1. **A part of a text copy.** Drag over the text in the preview with the
   pointer, press ⌘C: only that part is copied. Before, a copy was all or
   nothing.
2. **The words in an image.** On a screenshot whose text was read: ⌘K →
   *Show Text in Image* puts the text where the picture was (selectable
   the same way); *Copy Text in Image* (⇧⌘C) copies it all; ⇧↩ pastes it.

Why it is hard to "get": nothing on screen says it exists (the spec chose
"no hint, no badge"), the first needs the mouse in a keyboard tool, and
the second is behind ⌘K on a row that looks like every other image. It is
a correct small feature for a rare moment. It does not change what the
history feels like, and the things below matter far more.

Done since (same branch): #1 the whole history walks, #2 the clipboard
is read as the history opens, and a gap found right after: a picture
copied as its file had no text read and none of #123's actions (now read
when its row shows; reading it when copied made macOS ask for the folder).

Then (docs/clipboard-rows-and-search.md): #6 rows say when and the
header the day, #4 words are found inside words, by a piece of a link
and by the app, the found line shown and marked. Left of #4: typo
tolerance and ranking (the order stays newest first). Left of #6: day
separators inside the list, "+n lines".

Then (docs/clipboard-pins-filter-actions.md): #3 pins (⌘K → Pin, first
under "Pinned", kept past the retention), and of #7 a link opens, an
address starts a mail, a file opens or shows in Finder. Left of #7:
Save as Snippet, Quick Look large, drag out. #5: ⌘K → Show Only Links
(the row's kind) or from its app, the chip says it, ⌫ shows all again.

Then the speed (AGENTS.md → Speed, three lines; `remote speed`): what
was measured on the main thread on 2026-11-11 and what it is now.

| Path | Before | Now |
|---|---|---|
| A 2560×1600 picture copied as TIFF, kept | 100 ms | 0.25 ms (in the history 103 ms later) |
| 1.6 MB of text copied, kept | 40 ms | 0.2 ms (64 ms later, its shape checked for a key since #129) |
| A kept picture put back for ⌘V | 32 ms | 1.3 ms (its TIFF made if asked) |
| ✦C on 412 copies, 12 such pictures first | 249 ms | 15 ms, the pictures 73 ms after |

Left of the speed: the 50 ms fixed wait before ⌘V (shared with emoji,
snippets and the calculator: the app in front taking its focus back);
a row's small picture is made again each run (not kept on disk), so a
first page of pictures shows the symbol for a few frames once a run.

Then (docs/clipboard-secrets-drops-hint.md): #13 a copy that is a key
or a token by its shape is not kept (Never keep keys and tokens, on);
#14 a copy not kept (a key, a text over 5 MB, a picture over 40 MB) is
said in one line when the history opens next; #16 the footer of an image
whose words were read says Paste Text ⇧↩. Left of #13: a key inside a
longer text, expiry, the file not encrypted.

Then (docs/clipboard-long-copies.md): #15 a long copy shows whole in
the preview, up to 200,000 characters, a word found far down marked and
in view, a part picked anywhere.

Then (docs/clipboard-paste-transforms.md): #10 ⌘K on a text copy
pastes it another way, only the ways that change it (a color's other
forms, a link without tracking, JSON pretty or minified, one line,
trimmed, its case).

Then (docs/clipboard-missing-files.md): #12 a file moved or deleted
since it was copied is said when pasted, the others pasted; the
several-files preview marks the ones gone. Left of #12: finding where a
moved file went.

Then (docs/clipboard-save-as-snippet.md): of #7, ⌘K → Save as
Snippet… on a text copy opens the snippet editor with its text. Left of
#7: Quick Look large, drag out.

Then (docs/clipboard-select-several.md): #9 several rows selected in
the history (⇧↓, ⇧↑, ⌘K → Select), pasted as one in the order copied.
Then #8: ⌘K → Paste in Sequence on a selection pastes the oldest now,
each Paste in Sequence after it the next (A, B, C, one key each). With
nothing selected it is unchanged, newest first.

Then (docs/clipboard-kept-formats.md): #11 a copy is kept with every
format its app gave it, in the app's order, up to 4 MB, and pastes back
with them. Left of #11: several items copied together; cells from
Numbers, an object from Keynote or Figma not tried in the real apps.

## Must (the history is behind the others here)

| # | Gap | Proof | Others |
|---|---|---|---|
| 1 | ~~Only the last 50 copies can be browsed.~~ **Fixed:** the next older copies join the list as it nears its end (`showOlderClips`). | `ClipboardStore.search(_:limit:before:)`. | All of them scroll the whole history. |
| 2 | ~~A copy made just before ✦C can be missing.~~ **Fixed:** opening the history reads the clipboard first (`onClipboardMode` → `poll`). | The 0.4 s timer stays for the rest. | Same timer everywhere (macOS has no notification); they read on open. |
| 3 | **No pins.** Nothing can be kept at the top or kept past the retention; `ClipboardRetention`'s own comment says "pinned items stay" and no pin exists. An address or an IBAN copied last month is gone. | No pin column, no action. | Raycast (⇧⌘P), Maccy (⌥P), Paste (pinboards), Alfred (via snippets). |
| 4 | **Search is words-from-their-start only, newest first.** "board" does not find "clipboard", "voice" does not find "invoice"; no typo tolerance; no ranking (a title match and a match at character 9,000 are equal). The app's name is not searched ("slack"). | `ClipboardSearch.ftsQuery`: `"word"*` joined by AND, `ORDER BY copied DESC`; FTS columns are text, ocr, tags. | Maccy: fuzzy; Raycast, Alfred: substring. The launcher itself is fuzzy; the history is the one place that is not. |
| 5 | **No filter by kind.** Images only, links only, files only, colors, from one app: not there without the AI key (⇥ "a link" asks Jev, ~0.25 s to seconds, and needs a key). The kinds are already known in code (`CopiedValue`). | No filter in `LauncherController`'s clipboard mode. | Raycast (⌘P menu), Paste, Pastebot. |
| 6 | **Rows say nothing but a first line.** No time, no day sections ("Today", "Yesterday"), no "+12 lines", no copy count, no size: 50 one-line rows that look alike; the eye must go to the preview for each. `extraLines` exists and is not drawn. | `cell.configure(title: item.title, accessory: "")`; one header, "Copied recently". | Raycast and Paste group by day; Maccy shows the key to press. |
| 7 | **A copied link cannot be opened, a copied file cannot be shown.** A link has a preview card and no "Open in Browser"; text has no "Save as Snippet", no edit; nothing is Quick-Looked large; nothing drags out. ⌘K on a text copy: Paste, Paste as Plain Text, Copy, Forget. | `LauncherActions`, `case .clip`. | Raycast: open, save as snippet/quicklink, edit, pin, share. |

Seen on the test Mac's captures today (`remote previews`, 3 checks of 3
passed): the footer says only "Paste ↩ · Actions ⌘K" on every row, so
neither half of #123 is visible anywhere; and the words searched are not
highlighted in the row or in the preview, so on a long copy found by a
word the eye has to hunt for where it matched.

## Should (where "way better" can be won)

8. **Paste in Sequence goes newest first.** Copy A, B, C then paste gives
   C, B, A. The use it is for (collect in one place, paste in another, in
   order) wants A, B, C: Paste's and Pastebot's queues do that. And
   nothing shows what comes next.
9. **Several at once.** Select a few copies and paste them joined (lines),
   or merge them into one. Alfred appends, Paste multi-selects.
10. **Transform on paste**, all code, no AI: trim, one line, UPPER/lower/
    Title, JSON pretty/minify, URL-decode, strip tracking parameters, the
    color as Hex/RGB/HSL (the preview shows the three, ↩ pastes only what
    was copied). Pastebot's filters are its reason to exist.
11. **Kept formats are RTF, RTFD, HTML only**, of the first pasteboard
    item. Cells from Numbers or Excel, a Figma or Keynote object, several
    items copied together come back as flat text or a picture. Paste and
    Pastebot keep every type. Bounded cost: keep all types under a size.
12. **Files are kept as paths.** A file moved or deleted since pastes
    nothing; the row does not say it is gone until the icon falls back.
13. **Secrets.** Only copies an app marks as concealed are skipped. A
    token or password copied from a terminal, a browser or a `.env` is
    kept in a plain SQLite file (folder 0700, not encrypted). A check by
    shape (`sk-…`, `ghp_…`, JWT, private key headers, high-entropy
    one-liners) would drop or expire them in minutes. Raycast encrypts
    its database.
14. **Silent drops.** A text over 5 MB or an image over 40 MB is not kept
    and nothing says so.
15. **The preview cuts at 4,000 characters** with no way to see the rest;
    #123's selection therefore reaches only the start of a long copy.
16. **Discoverability of #123.** One quiet line in the footer when the
    row is an image with text ("⇧↩ pastes its text") costs nothing and
    is what makes the feature exist for people.

## Speed (to measure before claiming "faster")

Measured today on the test Mac: a preview shows in 0.2 to 1.6 ms
depending on the kind (email, phone and address the slowest, their data
detector), search by meaning answered in 0.17 s. The word search is one
FTS query (the code says well under a millisecond; not timed today).
What is not measured anywhere (no line in AGENTS.md's speed
table for the history):

- **Capture on the main thread.** A copied image is converted to PNG and
  hashed inside the timer's tick, on the main actor
  (`pngData(from:)`, `hash`, then the file write under the store's lock).
  The largest image kept on the test Mac is 4.5 MB as PNG: its TIFF → PNG
  encode is tens to hundreds of ms during which the launcher cannot draw
  a key. Text copies up to 5 MB are hashed there too.
- **Paste of an image** reads the PNG and makes a TIFF from it on the main
  thread before ⌘V goes out, then waits a fixed 50 ms
  (`asyncAfter(0.05)`) for the app in front: a wait on time, which
  AGENTS.md forbids elsewhere ("Wait on state, not on time").
- **Opening on a long history**: first paint of ✦C with 50 rows and 32
  image thumbnails decoded on demand, on the main thread
  (`icon(for:)`, `CGImageSourceCreateThumbnailAtIndex`), cache dropped
  whole past 300.

Budget to set and hold, as the launcher has: ✦C to first paint, key to
list, ↩ to pasted, copy to kept.

## What is already better than the others (keep)

- Each copy previewed as what it is: color swatch with Hex/RGB/HSL, link
  card, address, phone, email, code. Nobody else does all of these.
- Words in images found by search, on the Mac (Vision), and image kinds
  tagged.
- Search by meaning over the whole history ("my train ticket from
  yesterday").
- Screenshots join the history without being copied.
- ⌘⌫ with a 10 s undo; secrets from password managers never kept; apps
  excluded.
- Reachable from skillies and agents (`get_clipboard`).

## Order I would take

1. ~~#2 (read on open) and #1 (scroll the whole history)~~: done, with
   the picture copied as its file.
2. #6 (rows: time at right, day sections, "+n lines") and #4 (substring
   and ranked search, app name): the history starts to feel fast.
3. #3 pins and #5 kind filter: one spec, they share the header.
4. #7 actions per kind (open link, show file, save as snippet).
5. ~~Speed budget lines + the three measurements~~: done.
6. ~~#13, #14, #16~~, ~~#15~~, ~~#10~~, ~~#12~~, ~~#8~~, ~~#9~~, ~~#11~~: done.
   Left: of #7, Quick Look large and drag out.
