# Clipboard History: pins, one kind at a time, what a copy can do

Three of the gaps in `docs/clipboard-review.md` (#3, #5, #7):

- Nothing can be kept: an address or an IBAN copied last month is gone
  with the retention, and nothing stays at the top.
- Nothing narrows the list to one kind (images, links, files) without
  the AI key.
- A copied link cannot be opened, a copied file cannot be shown: ⌘K on
  a copy pastes, copies and forgets, whatever the copy is.

Built in two steps: pins and actions first (this document's first two
parts), the kind filter after (its third part, not built yet).

## Moment

1. **When.**
   - *Pin*: the user pastes the same thing again and again over weeks
     (an address, an IBAN, a signature picture, a link), or has just
     found an old copy and does not want to lose it.
   - *Actions*: ✦C is open on a copy and the user wants the thing
     itself, not a paste of it: the page, the file in Finder, a new
     mail to that address.
   - *Filter*: the user knows what kind it was ("that screenshot",
     "the link she sent") and not a word of it.
2. **The path.** ⌘K on the row, for all three. No new key: the keys
   are the user's to give.
   - ⌘K → *Pin*: the copy goes to the top of the list, under "Pinned",
     a pin after its title; ⌘K → *Unpin* puts it back at its date.
   - ⌘K → *Open in Browser* (a link), *New Email* (an address),
     *Show in Finder* and *Open* (files).
   - ⌘K → *Show Only Images* (the kind of the row), *Show All* to come
     back; ⌫ in the empty field leaves the filter before the mode.
3. **Hint or push.** Neither. The pin on the row and the "Pinned"
   header say what happened; nothing announces the actions.
4. **Deterministic or AI.** All code. The kind of a text copy is the
   one the preview already reads (`CopiedValue`).
5. **Wrong.** A pin is the user's own act and undone the same way. A
   pinned copy is never removed by Keep copies for; ⌘⌫ still forgets it
   (⌘Z brings it back, pinned), and Clear History in Settings removes
   everything, pins too: it is the one place that says "all". A file
   moved since: *Show in Finder* says it is no longer there. A kind read
   wrong (a text taken for code) only hides a row behind a filter the
   user can leave with one key.

## Pins

- `items.pinned`: when it was pinned, empty when it is not.
- The empty field: the pinned copies first, in the order pinned, under
  the header "Pinned"; then the history by date as before. The header
  follows the scroll ("Pinned", then "Copied today"…). Each row keeps
  its time.
- A search: one list, newest first; a pinned copy has its pin, nothing
  moves it.
- Copied again, a pinned copy stays pinned (its count and date move).
- The hourly pass and the line in Settings ("12 copies older than…")
  leave pinned copies out.
- Paste in Sequence goes by date, pinned or not.
- No `skilli://` link and no tool: a pin is on one row of the list,
  there is nothing to name from outside it.

## Actions by kind

After Paste and its variants, before the copies:

| The copy | ⌘K adds |
|---|---|
| A link | Open in Browser |
| An email address | New Email (`mailto:`) |
| One file | Open, Show in Finder |
| Several files | Show in Finder (all selected) |
| A picture copied as its file | Show in Finder, beside the image's actions |
| Any | Pin / Unpin |

The file is looked for only when the action runs (the user asked for
it): never while the list is drawn.

What leaves the Mac, and when:

- *Pin*, *Unpin*, *Open* and *Show in Finder*: nothing.
- *Open in Browser*: skil.li sends nothing itself; it hands the link to
  the default browser, which then loads the page, so the site is
  contacted as if the link were clicked. Only when the action is
  chosen; listing it in ⌘K contacts nothing.
- Apart from these actions, and unchanged by them: with link previews
  on (Settings → Privacy, on by default), showing a link's row already
  reads its page for the card in the preview, after a short pause on
  the row (`ClipboardLinks`). That request is the preview's, made by
  skil.li, without cookies; turning link previews off stops it. Open in
  Browser is a second, separate contact, by the browser.
- *New Email*: a new message opens in the mail app, addressed; nothing
  is sent until the user sends it.

Not done here: Save as Snippet (the snippet editor takes no text from
outside yet), Quick Look large, drag out, a phone number's call.

## One kind at a time (not built yet)

- `items.value`: what the copy is, as the preview reads it: image (a
  picture's file too), file, link, color, email, phone, address, code,
  text. Written when copied; older rows read once, off the main thread.
- ⌘K → *Show Only Links* on a link, *Show Only from Safari* on any
  copy with an app; the field's chip says it ("Clipboard · Links");
  ⌘K → *Show All*, or ⌫ in the empty field.
- The filter and the words typed apply together; ⇥ by meaning ignores
  the filter.

## Checks

- Self-test (`clipboard`): a pinned copy survives a prune that removes
  its neighbours, comes back pinned after ⌘⌫ ⌘Z, is first in an empty
  search and at its date in a search by words.
- Self-test (`previews`): ⌘K lists Pin on a copy and Unpin once pinned,
  the row shows under "Pinned" with its pin; Open in Browser on a link,
  Show in Finder on a file.
