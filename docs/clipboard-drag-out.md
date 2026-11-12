# Clipboard History: a copy dragged out

Last of #7 in `docs/clipboard-review.md`: a copy could only leave the
history through ⌘V. A picture wanted in a folder, a file wanted in a
mail's attachments, a text wanted at one place of a document: paste
goes where the cursor is, a drag goes where the pointer says.

## Moment

1. **When.** The user is in the history (✦C) with the pointer in hand
   and wants a copy at a place a paste does not reach: a folder, a
   drop zone, a spot in a canvas, another window than the one in front.
2. **The path.** Press on the row and drag. The launcher gets out of
   the way at once (what was under it is where the copy may go); let go
   over the place.
   - A text copy drops its text.
   - A picture copy drops a file, "Copied Image 2026-11-12 at 09.41.05
     (1280×720).png".
   - A copied file drops that file.
   - Dropped: the launcher closes, as after a paste. Let go over
     nothing: the launcher is back as it was.
3. **Hint or push.** None. Dragging a row is what a pointer tries
   first; nothing is added to the footer or to ⌘K.
4. **Deterministic or AI.** Code.
5. **Wrong.** A file moved or deleted since: the row does not drag and
   one line says it is no longer where it was copied. A place that
   takes nothing: the launcher comes back, nothing is lost.

## How

- The list is the drag's source (`pasteboardWriterForRow`), in the
  history only, towards other apps and skil.li's own windows (a field
  in Settings).
- `ClipboardDrag` (SkilliCore) says what a copy gives: its text, its
  picture, its one file, or nothing (several files copied together).
- A picture's own file is named by the history: a copy of it under a
  name a person reads is made in the temporary folder as the drag
  begins, in a folder named by the copy's id, and that one is dragged
  (`ClipboardDragExports`). It lives as long as the history keeps that
  picture: removed when that copy is forgotten or removed by Keep
  copies for, when its drag is let go over nothing, when the history is
  cleared, and when the app starts. Another copy dragged or removed
  leaves it, so an app that reads the dropped file a moment later
  still finds it. Dragged again while its file is there, the same
  file is given, and that drag let go over nothing leaves it.
- A copied file is looked for as the drag begins, never while the list
  is drawn.
- While the drag is on, the launcher is off the screen (ordered out,
  not closed: losing the keys then does not close it) and its frame is
  moved away. Ordered out only, a drop inside its old frame was entered
  then left by the window under it and never offered (3 runs of 4 on
  the test Mac); with the frame away it is taken (2 runs of 2). Dropped,
  it closes as after a paste; let go over nothing, it is back where it
  was, with the keys.

## Checks

- Unit: what each kind gives; the picture's name has no ":" or "/".
- Self-test (`previews`, pointer): a text copy pressed and dragged out
  of the history onto a view that takes drops, beside the launcher then
  under where it was: the drag begins, the launcher is off the screen,
  the text is there, the launcher is closed.

Not checked: a drop into another app (the self-test's target is a
window of skil.li's own); a picture or a file dragged for real (their
rule is unit-tested, their drag is not); the middle of the screen
(other apps' windows were over it on the test Mac).

Not done: several files copied together (the row does not drag);
several rows selected dragged as one; a text dragged with its formats
(the text alone); a drag from the preview.
