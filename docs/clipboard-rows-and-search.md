# Clipboard History: rows that say when, a search that finds inside words

Two of the gaps in `docs/clipboard-review.md` (#4, #6):

- Rows were a first line and nothing else: 50 lines alike, no time, no
  day. Finding "the thing I copied this morning" meant walking the
  preview's Copied line row by row.
- Search matched words from their start only: "board" did not find
  "clipboard", "voice" did not find "invoice", "ithub.com/acme" found
  nothing; the app a copy came from was not searched; and a copy found
  by a word deep inside it showed its first line, so nothing said why it
  was there.

## Moment

1. **When.** ✦C is open and the user looks for one copy among many:
   - by when ("this morning", "yesterday's"): eyes go down the list;
   - by a piece of it they remember: a few letters typed, often the
     middle of a word, a bit of a URL, or where it came from ("slack").
2. **The path.** The list itself, and the field. No new key, no mode.
   - Each row says when at its right edge: the time today ("14:32"), the
     day within a week ("Mon"), the date before ("3 Nov").
   - The header over the list says the day of the row at its top, and
     follows the scroll: "Copied today", "Copied yesterday", "Copied
     Monday", "Copied 3 November".
   - Typed words are found anywhere inside the text, an image's words,
     and the app's name, accents and case ignored, all words required,
     newest first.
   - A copy found past its first line shows the line where the first
     word was found ("…the invoice for October"), and the preview marks
     the words and scrolls to the first.
3. **Hint or push.** Neither: nothing to learn.
4. **Deterministic or AI.** All code: SQLite on this Mac (an FTS5
   trigram index beside the word index). ⇥ by meaning is as it was.
5. **Wrong.** More is found than before (inside words), never less; the
   order stays newest first, so a wider match cannot bury the recent
   copy. A word under 3 letters cannot use the trigram index: a search
   with one keeps the old rule (words from their start).

## Rows

- Right edge, tertiary color, only as wide as it is: "14:32" (the
  user's own clock format) for a copy of today, "Mon" for the six days
  before, "3 Nov" before that, "3 Nov 2025" in another year. The title
  keeps the rest of the row.
- The header: the day of the top visible row, in words. A search by
  meaning keeps its own header ("By meaning · Jev · 0.42 s").
- Not done here: day separators inside the list, "+12 lines" on a row
  (the list is 290 pt wide; the preview says the size).

## Search

- Every word of 3 letters or more is looked for as it is typed, inside
  words too: `items_sub`, an FTS5 table with the `trigram` tokenizer
  (`remove_diacritics 1`, case ignored) over the text, an image's text,
  its tags and the app's name, kept by triggers as `items_fts` is, made
  and filled once when an older file opens. A word may hold punctuation
  ("ithub.com/acme", "a->b").
- Any word under 3 letters: the search is the old one (`items_fts`,
  words from their start; only symbols: plain substring).
- Order: newest first, as before. The pages of the list
  (`search(_:before:)`) work the same on both.
- The row's title: when the first line does not hold the first word
  typed, the line that does, cut to start a few words before it
  (`ClipboardSearch.found`), looked for in the first 100,000 characters.
- The preview: every word typed is marked in the text shown (temporary
  attributes, the copy is not changed) and the first is scrolled into
  view. Past the 4,000 characters the preview shows, the row's title is
  what says where.

## Mistyped

Since 2026-11-12 (was "Left of #4: typo tolerance").

- **When.** The user types a word they remember and one finger slips:
  "invocie", "facutration". The list is empty and nothing says why.
- **The path.** None: the same field. Only when the words as typed find
  nothing, the copies holding a close word are shown, newest first, one
  page, under the header "Close to “invocie”". The row's title and the
  preview mark the close word found.
- **Hint or push.** Neither.
- **Deterministic or AI.** Code. ⇥ by meaning is as it was.
- **Wrong.** A copy shown that was not meant: only where the list would
  have been empty, and the header says these are close ones. A slip not
  undone (the first letter wrong, three slips, a word under four
  letters): the empty list, as before.

How:

- A word of 4 to 7 letters may hold one slip, from 8 two: two letters
  swapped, another letter, one too many, one left out. Its first letter
  is right. The word typed may be the start of the kept word
  ("invocie" finds "invoices").
- Close to what: the words of the history itself, read from the word
  index (`items_words`, an `fts5vocab` over `items_fts`: nothing more
  on disk), those starting with the same letter. The six closest, then
  the ones in the most copies (`ClipboardSearch.close`).
- The search is then the word index's: each word as typed or one of
  its close ones, all words required (`closeQuery`). Not inside words,
  not the app's name: whole words of the text, an image's words, its
  tags.
- ⌘K → Show Only… narrows it as any search.

Not done: ranking (the order stays newest first on purpose: a wider
match cannot bury the recent copy); a slip in the first letter; a slip
inside a longer word ("clipbaord" is found, "pbaord" is not).

## Speed

One indexed query a key, as before; the trigram index costs about three
times the text on disk. Measured by `remote clipboard`: the search over
3,000 copies, a key. A mistyped word reads the index's words of one
letter and compares them: measured there too, among 3,000 copies.

## Checked by

Unit tests (`ClipboardSearch.substringQuery`, `found`, `ClipboardDay`).
`remote clipboard`: inside a word, a piece of a URL, the app's name,
accents, a 2-letter word falling back, an older file gaining the index,
the time of a search over 3,000 copies. `remote previews`: the row's
time, the header's day, the found line as title, the words marked in
the preview (`launcher-clipboard-found-*.png`).
