# Clipboard History: files moved or deleted since they were copied

One gap in `docs/clipboard-review.md` (#12): the history keeps a file
copy's paths, not the files. A file moved or deleted since pasted
nothing, and nothing said why; with several files, the preview did not
say which were gone.

## Moment

1. **When.** The user picks a file copied days ago (↩, ⌘↩, Paste in
   Sequence) and the file has been moved, renamed or deleted since.
2. **The path.** None to learn. The paste says it; the preview shows
   it.
   - One file gone: nothing is pasted, a line says “report.pdf” is no
     longer where it was copied, and that ⇧↩ pastes its path.
   - Some of several gone: the ones still there are pasted, a line says
     which are not ("2 of 5 files are no longer there: the 3 others
     were pasted.").
   - The preview of several files marks each one gone ("No longer
     there", its name dimmed) and its first line counts them ("5 Files
     · 2 no longer there"). One file gone was already said (Kind: No
     longer there).
3. **Hint or push.** A line when the paste cannot do all that was
   asked (rule 6: what happened and what to do). Nothing otherwise.
4. **Deterministic or AI.** Code: the file is there or it is not.
5. **Wrong.** A file on a disk not plugged in reads as gone: the line
   says "no longer where it was copied", which is true, and the copy
   stays in the history for when the disk is back. Nothing is removed
   from the history because a file is gone.

## How

- `ClipboardHistory.files(of:)`: the paths still there, the names
  gone. Looked for only when the copy is used (pasted, copied, Paste in
  Sequence) or shown in the preview, never while the list is drawn: no
  row reads the disk, and macOS is not asked for a folder nobody opened.
- `write(_:plain:)` puts only the files still there on the clipboard;
  none there, it refuses and the caller says the line
  (`ClipboardFiles.line`, SkilliCore).
- ⇧↩ (the paths as text) is unchanged: a path can be pasted whether
  the file is there or not.
- The several-files preview looks off the main thread once shown
  (`FileListView.mark(gone:)`).

Not done: finding where a moved file went (Spotlight by name, a
bookmark kept when copied); the row in the list saying it is gone
(it would read the disk for every row drawn); keeping the file itself.

## Checks

- Unit: the lines for one gone, all gone, some gone, pasted or copied;
  the preview's count.
- Self-test (`previews`): a copy of three files, two never there: the
  preview marks two and counts them; a paste puts the one there on the
  clipboard; a copy of one file not there puts nothing.
