# Clipboard History: a long copy shows whole

One gap in `docs/clipboard-review.md` (#15): the preview cut a text or
code copy at 4,000 characters with "…". A word found further down was
not shown or marked, and a part picked with the pointer
(`docs/clipboard-text-selection.md`) could only be in the start.

## Moment

1. **When.** ✦C is on a long copy (a log, a file's content, an
   article): the user searched a word that is far down it, or wants a
   part of it that is not at its start.
2. **The path.** None to learn: the preview scrolls through the whole
   copy; the word searched is marked and in view wherever it is; drag
   and ⌘C copy a part from anywhere.
3. **Hint or push.** Neither.
4. **Deterministic or AI.** Code.
5. **Wrong.** Nothing is decided. Past 200,000 characters the preview
   still ends with "…" (↩ pastes the whole copy as before).

## How

- `PreviewText.show(…, whole:)`: the first 4,000 characters at once, as
  before (a preview shows in under a millisecond whatever the copy).
  The rest joins them in place, 8,000 characters on each next turn of
  the main thread, each piece laid out as it comes, up to 200,000
  characters. Nothing in view moves, what is picked stays picked.
- The words searched are marked in each piece that comes; the first is
  scrolled to when nothing before it held one.
- Another row shown meanwhile: the pieces stop.
- Only the history's text and code copies. The words read in an image
  stay as they were (50,000 characters at once).

Measured on the test Mac, Release, 2026-11-11, a 142,233-character
copy with the word searched 117,000 characters down:

| Way | The main thread held | Whole after |
|---|---|---|
| The rest joined at once | 36 ms | 36 ms |
| 16,000 characters a turn, laid out when scrolled to | 31.5 ms (the turn that scrolled) | 57 ms |
| 8,000 characters a turn, each laid out as it comes | 3.2 ms at most | 134 ms |

The third is the one kept: no key waits more than a piece.

## Checks

- Self-test (`previews`): the long copy found by a word far down shows
  all its characters, the word marked and in view, no piece holding the
  main thread over 8 ms, ⌘C with the word picked there copies it.
