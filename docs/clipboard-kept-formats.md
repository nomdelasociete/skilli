# Clipboard History: a copy kept with every format it had

One gap in `docs/clipboard-review.md` (#11): a text copy was kept with
RTF, RTFD and HTML only, a picture with nothing but its PNG. What an app
puts there for itself (a table's cells, a shape, a web page's part) was
dropped, so the copy came back from the history as flat text or as a
picture.

## Moment

1. **When.** The user pastes from the history something copied from an
   app that has its own format: cells, a shape on a slide or a canvas, a
   part of a web page, back into that app or one that reads it.
2. **The path.** None to learn: ↩ pastes it as it was copied. ⇧↩ still
   pastes the text alone.
3. **Hint or push.** Nothing. It pastes as ⌘V would have, right after
   the copy.
4. **Deterministic or AI.** Code: the formats are kept as the app gave
   them and put back in the same order.
5. **Wrong.** A format left out (over the size, or the app too slow to
   give it): the copy pastes as before this, text or picture. A format
   kept that an app reads badly days later: ⇧↩ pastes the text alone.
   More of what was copied is on the disk (same folder, read by the user
   alone, removed by Keep copies for, Forget and Clear History as the
   rest of the copy).

## Measured (the test Mac, 2026-11-12)

What the first item of the clipboard holds after ⌘A ⌘C, and how long
each format takes to read:

| App | Formats | Bytes | Slowest read |
|---|---|---|---|
| TextEdit (styled text, a table) | RTF, text | 3 KB | 0.08 ms |
| Safari (a heading, a table) | web archive, RTF, HTML, text, WebKit's own | 6 KB | 0.3 ms |
| Chrome (a part of a page) | HTML, text, the page's address, a mark | 2 KB | not timed |

The text under its UTF-16 name took 3 to 4 ms to read in both: it is
not read (the text is kept once).

Not measured: Numbers, Pages and Keynote. On the test Mac each opens on
its first-launch window (Numbers' asks to accept its licence), which
nobody but the Mac's owner answers. Figma is not installed there. So the
size and the time of their own formats are not known; the two bounds
below are what holds them.

## How

- `ClipboardFormats` (SkilliCore) says what is kept: every format of the
  first item, but the text under its other names (kept once, as the
  text), pictures (a picture copy is kept once, as its PNG; the picture
  of cells beside their text is not kept, as before), marks an app or
  macOS leaves (`org.nspasteboard.…`, `com.apple.is-remote-clipboard`,
  Chrome's internal ones) and promised files.
- Bounds: 4 MB for all the formats of a copy (one that does not fit is
  left out, a smaller one after it kept); 50 ms in all to read them
  (each read asks the app copied from; past it the rest is left out).
  It was 2 MB and three formats.
- Kept in the app's order (`formats` column, a list; a copy kept before
  reads as RTF, RTFD, HTML) and put back in it, before the text or the
  PNG: the app pasted into takes the first it knows.
- A picture copy keeps its other formats too (a shape copied with its
  picture pastes back as a shape where the app reads it).
- The same content copied again moves up as before, and takes that
  copy's formats when it has some (a text copied plain, then from a
  table, pastes back as cells). A plain copy of it after keeps the
  formats it had: skil.li's own ⇧↩ is such a copy.

## Checks

- Unit: what is kept and what is not, by name; the stored list read back
  in order; a copy of before read as RTF first.
- Unit: several items' formats joined and read back apart; a copy of
  one unchanged.
- Self-test (`clipboard`): three objects copied together, the middle
  one plain, come back as three, each its own; ⇧↩ one text; two
  pictures come back as two.
- Self-test (`clipboard`): cells copied with their own format, RTF, text
  and a mark come back with the format first, without the mark; ⇧↩ the
  text alone; copied plain before and after, the cells keep their
  format; a shape copied with its picture comes back before its PNG.

## Several items

Since 2026-11-12. The moment: three shapes selected in a drawing and
copied, two pictures copied from a photo library, and pasted back
later from the history. Nothing to learn: ↩ pastes what was copied.
Code only. Before, the copy's text was every item's, joined, but only
the first item's formats were kept: a rich paste gave the first object
alone, and of several pictures only the first.

- A copy of several items keeps each item's formats apart, with the
  item's own text or picture among them (`ClipboardFormats.joined`: one
  list, a mark between two items; a copy of one item is as before, no
  mark). 24 items at most, the same 4 MB and 50 ms for all of them.
- ↩ puts back as many items, each with its formats. ⇧↩ pastes one
  text, every item's joined, as before.
- The row, the search and the preview are the copy's as before: its
  text is all items' joined; a copy of pictures shows the first.
- Wrong: when the items do not all fit or took too long to read, none
  is kept apart: a text pastes as its joined text (no format, rather
  than the first object alone), pictures as the first one, as before.

Not done: the preview and the row do not say "3 items"; the pictures
after the first are not read for their words; cells from Numbers, an
object from Keynote or Figma not tried in the real apps.
