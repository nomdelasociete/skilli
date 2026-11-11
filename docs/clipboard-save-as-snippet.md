# Clipboard History: a copy saved as a snippet

What was left of #7 in `docs/clipboard-review.md`: a text found in the
history that the user will want for good (a signature, an address, a
reply written once) could only be pinned. A pin stays in the history;
a snippet has a name, a keyword that types it anywhere, and its own
list.

## Moment

1. **When.** ✦C is on a text the user realizes they paste again and
   again, and want to type from a keyword from now on.
2. **The path.** ⌘K on the row → *Save as Snippet…*. Settings →
   Snippets opens with the snippet editor on a new snippet: the copy's
   text in it, its first line as a name to change, no keyword. Save
   keeps it; Cancel keeps nothing. No new key.
3. **Hint or push.** Neither: one more line in ⌘K on a text copy.
4. **Deterministic or AI.** Code.
5. **Wrong.** Nothing is saved until the user presses Save in the
   editor, where the name, the keyword and the text can all be changed.
   A copy that holds `{date}`, `{clipboard}`, `{name}`… would have
   them filled when the snippet is typed: the editor lists the
   placeholders it reads, as for any snippet. The copy stays in the
   history as it was.

## How

- `Snippet.draft(from:)` (SkilliCore): id empty (a new one), the name
  the first line that is not blank, 40 characters at most, the text
  whole.
- `SettingsAsk.text` carries it to Settings → Snippets
  (`SettingsWindowController.showNew(.snippet, text:)`), where the
  pane opens its editor on the draft, as New Snippet does on an empty
  one. An editor already open keeps its edits: this one waits, as any
  editor asked.
- Offered on text copies up to 20,000 characters (a snippet is typed).
  Not on images or files.
- No `skilli://` link and no tool: the action is on one row of the
  list, as Pin is.

Not done: a keyword proposed from the name; saving without the editor;
an image or a file as a snippet.

## Checks

- Unit: the draft's name, text and empty keyword; a first line cut at
  40; a blank copy.
- Self-test (`previews`): ⌘K on a text copy lists Save as Snippet…;
  ↩ on it opens Settings → Snippets with its editor, the copy's text
  and its first line in it; esc closes it and no snippet was saved.
