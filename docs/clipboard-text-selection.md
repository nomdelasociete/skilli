# Clipboard History: a part of a copy, and an image's whole text

Two gaps in the history's preview (✦C, `cb`):

- A text or code copy shows in the preview, but only the whole copy can be
  pasted or copied. Half a paragraph, one line of a log, one value in a
  JSON: back to the app it came from.
- An image's words are read (Settings → Clipboard → Read text in images)
  and found by search, but the preview shows three lines of them, cut, and
  nothing copies them. ⇧↩ pasted them under the name "Paste as Plain
  Text", which nobody tried on a picture.

## Moment

1. **When.** The history is open on a copy and the user wants a piece of
   it, not all of it:
   - a long text or code copy: one sentence, one line, one value;
   - a screenshot or a copied picture: the words in it (an error message,
     an address on an invoice, a code on a slide), whole or in part.

   Their eyes are on the preview already and the pointer is the tool that
   picks a part of a text; the keyboard picks rows.
2. **The path.** Where the text already shows.
   - Text and code: drag over the preview, ⌘C. No mode, no action first.
   - An image: ⌘K on its row → **Show Text in Image**: the picture's
     place shows its whole text, selectable the same way. **Copy Text in
     Image** (⇧⌘C, the row's second copy, as everywhere) copies all of it
     in one key, **Paste Text in Image** (⇧↩) pastes it.
3. **Hint or push.** Neither. The pointer turns to an I-beam over the
   text; the actions are in ⌘K, where a row's actions are looked for.
   Nothing new is said on screen, no badge.
4. **Deterministic or AI.** All code. The text is the copy's own; an
   image's text was read by Vision on this Mac when it was copied.
   Nothing leaves the Mac.
5. **Wrong.** Nothing is guessed. What can go wrong is the keyboard:
   a click in the preview must not take typing away from the search
   field, nor change what the row's keys do. So: the next key typed goes
   to the field as before, with its text kept (not selected, not
   replaced); arrows move the rows; ↩, ⌘↩, ⇧↩ act on the row. Only ⌘C
   changes, and only while a part is selected: it copies that part. Esc
   drops the selection first, then does what it did.

## Selecting in the preview

- Text and code copies (`PreviewText` with `isSelectable`): drag, double
  click (a word), triple click (a line), ⇧ click, as in any text.
- ⌘C with a part selected copies that part as plain text and closes the
  launcher (copies close it, nothing said). With nothing selected, ⌘C is
  the row's copy as before. Text selected in the search field still wins
  when the field has the keys: a click in the preview takes them, so the
  two never show together.
- A right click offers Copy, nothing else (no Look Up, no Services: the
  launcher closes when another window takes the keys).
- The selection goes when another row shows, and on esc. The same row
  shown again (a new copy arrived, the list refreshed) keeps it.
- Past 4,000 characters the preview shows the start of a copy, as before:
  ⌘↩ copies it whole.
- Links, colors, addresses, phone numbers, email addresses and files keep
  their cards: one short value, ⌘↩ copies it.
- Search Snippets' preview is not selectable (its placeholders are drawn
  parts, not text).

## An image's text

On an image whose text was read, ⌘K lists:

| Action | Key | Does |
|---|---|---|
| Paste | ↩ | the image, as before |
| Paste Text in Image | ⇧↩ | its text (was "Paste as Plain Text") |
| Show Text in Image / Show Image | | swaps the picture and the whole text in the preview; the launcher stays open |
| (CleanShot's, when installed) | | as before |
| Copy | ⌘↩ | the image, as before |
| Copy Text in Image | ⇧⌘C | its whole text |
| Forget | ⌘⌫ | as before |

- An image with no text read lists none of the three, and no "Paste as
  Plain Text" (it pasted nothing).
- The text view takes the picture's place under the heading "Text in
  Image"; the three-line extract below hides while it shows; Information
  gains "Text" (its words and characters). Up to 50,000 characters.
- Showing another row puts the picture back: the choice is for that row,
  that time.
- **The same picture copied as its file** (one file copied in Finder,
  or by a capture app that puts its file on the clipboard) is an image
  to the user, who cannot tell which way it was copied: its text is
  read the same (when copied; the ones already kept, at the next
  launch), search finds it, and ⌘K lists the same three, plus Copy Path.
  ⇧↩ pastes its text; a picture's file with no text read keeps Paste as
  Plain Text (its path).
- From a skillie or an agent: `get_clipboard` gives the text read in the
  image on the clipboard when the clipboard holds no text
  (`"$SKILLI_CLI" call get_clipboard`). No `skilli://` link: these act on
  one row of the history, which has no Catalog entry, and links never
  paste or read the user's copies (AGENTS.md, Links).

## Speed

Nothing added to showing a row: the same views, one flag. The whole text
is laid out only on Show Text in Image.

## Checked by

`remote previews` (`clipboardPreviews`): a real drag over the text copy,
⌘C copies the part and closes; a click then a typed key filters with the
field's words kept; esc drops the selection first; the image's ⌘K list,
Show Text in Image (whole text shown, picture hidden, then back), Copy
Text in Image.
