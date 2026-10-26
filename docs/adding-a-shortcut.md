# Adding a shortcut

Asked 2026-10-26, after adding the Confetti Cannon and giving it a key:
"pour pouvoir ajouter un raccourci à un skillie c'est la croix et la
bannière… pourquoi ne pas le mettre depuis les settings des skillies ?"
and, about Keys → Add Shortcut: a menu with no way to type to narrow it,
the new row lands somewhere in the pane without showing where, and it is
already recording.

## Short answer

- **Where the thing is, its shortcut is.** Settings → Skillies shows a
  shortcut field on each skillie (one that needs an argument opens the
  launcher on it), as Apps and Catalog already do for their rows:
  "Record Shortcut" until it has keys. A click records there, under the
  pointer; ⎋ leaves nothing behind. Keys stays the index of every
  shortcut (one feature, one pane).
- **Keys → Add Shortcut… finds by typing.** A sheet with a search field,
  focused, over every command the menu listed (skil.li, SI commands,
  windows, Mac, sound, System Settings panes, launcher commands, layouts,
  projects, skillies, snippets, quicklinks, apps' commands, Shortcuts, an
  app). Typing narrows it; ↑↓ and ↩ pick, or a double-click (a click
  selects, as in any Mac list).
- **Picked, it is shown, not recorded.** The sheet closes, Keys scrolls to
  the new row and makes it glow, as Settings' search does; its field says
  "Record Shortcut". A click on it records. Nothing listens for keys the
  user did not ask to type.

## Moment

1. **When.**
   - *Just added or written a skillie* and wants it on a key: in Settings →
     Skillies, where it is listed (the import sheet closes onto that list).
   - *Wants a key for something skil.li does* (a launcher command, a pane,
     a shortcut of Apple's): Keys → Add Shortcut…, knowing its name, not
     which menu holds it.
   - *Not*: changing a shortcut that exists (its row, a click), the
     launcher's own key (General), a command's keys (its editor).
2. **The path.** Skillies: the row's field, one click, the keys. Keys: Add
   Shortcut…, a few letters, ↩, the glowing row's field, the keys.
3. **Hint or push.** Neither. The field reads "Record Shortcut" in the
   tertiary color on every skillie without one: what it does is written
   where it is. Recording shows as it always does (accent ring, "Type
   shortcut…").
4. **Deterministic or AI.** Code only: the sheet filters titles by every
   word typed (case and accents aside), the store adds and records as
   before.
5. **Wrong.**
   - *A click on the field by mistake*: it records; ⎋ or a click elsewhere
     ends it, and an entry added for it without keys goes again (as in Apps).
   - *The wrong command picked in the sheet*: its row glows with no keys
     and does nothing; left without keys, it goes when another is picked or
     Keys closes.
   - *A key another shortcut holds*: refused while recording, as everywhere;
     the reason stays on its row until the next try or the pane closes.

## Not in this change

The launcher's ⌘K has no Add Shortcut on a row yet; Catalog's rows and
Apps' commands already record in place.
