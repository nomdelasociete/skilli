# Clipboard History: a copy seen large (⌘Y)

Left of #7 in `docs/clipboard-review.md`: nothing in the history could
be looked at larger than the preview beside the list. A screenshot's
small print, a PDF's second page, which of two near-same pictures: the
user had to paste to find out.

## Moment

1. **When.** The user is in the history (✦C) on a picture or a copied
   file and the preview is too small to tell what it is or to read it.
2. **The path.** ⌘Y (Finder's Quick Look key), or ⌘K → Quick Look. The
   copy shows large over the launcher, which stays open and keeps the
   keys:
   - ↑ ↓ show the next copy large; on a copy with nothing to show large
     (a text, several files) the view closes.
   - esc or ⌘Y close the view; the history is as it was, same row.
   - ↩ pastes the copy, as always.
3. **Hint or push.** The line in ⌘K, with its key. Nothing shown
   unasked; the footer is unchanged.
4. **Deterministic or AI.** Code. Quick Look draws the file.
5. **Wrong.** A file moved or deleted since: one line says it is no
   longer where it was copied, nothing opens. A kind Quick Look cannot
   draw shows its icon, as in Finder.

## How

- `LookPanel`: a window of the launcher's (a child, never key), most of
  the screen, a `QLPreviewView` in it. The launcher is still the key
  window, so its keys, its field and its closing on a click elsewhere
  work as before. No app comes to the front, nothing is activated.
- What shows large is what ⌘K already opens in other apps
  (`clipFile`): a picture copy's own PNG, or the one file of a files
  copy. A text copy shows whole in the preview already
  (docs/clipboard-long-copies.md): no large view of it.
- The file is read when ⌘Y is pressed on it (or an arrow moves to it
  while the view is open), never while the list is drawn. A file in a
  folder macOS guards (Downloads, Desktop) is then asked for by the
  user's own key.
- `LauncherAction.Key.look` (⌘Y), only in the history.

## Checks

- Self-test (`previews`, keys): ⌘Y on a picture shows its file large,
  over the launcher, which stays open; ↓ shows the copied file;
  ↓ to a text closes the view, the launcher open; ⌘K on the file lists
  Quick Look ⌘Y; esc closes the view and leaves the history. Two
  captures.

Not done: several files one after the other in the view; a text seen
large; drag out of the history.
