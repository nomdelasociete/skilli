# Search Snippets: list and preview

Spec, 2026-10-21. Asked: Search Snippets ("snip ") should look like
Clipboard History, a list beside a preview, with the snippet's own
details. AGENTS.md → Snippets says how it works once built.

## Layout

The launcher card as Clipboard History has it: the list narrows to 290 pt
on the left, the preview takes the other 410 pt, a hairline between them.
One split for both modes (`LauncherController.setSplit`), never two copies
of it. Fixed frames: a row change fills views in place, no Auto Layout.

```
┌ Snippets ▸ adresse ──────────────────────────────────────────────┐
│ 4 snippets            │ ╭──────────────────────────────────────╮ │
│ ▌Adresse bureau [;bur]│ │ 14 avenue de l'Opéra, 75001 Paris     │ │
│  IBAN perso    [;iban]│ │ Le 21 octobre 2026|                   │ │
│  Lien Calendly  [;cal]│ │                                       │ │
│  Refus poli     [;non]│ ╰──────────────────────────────────────╯ │
│                       │ INFORMATION                              │
│                       │ ───────────────────────────────────────  │
│                       │ Keyword                            ;bur  │
│                       │ Expands                As soon as typed  │
│                       │ Placeholders            {date}, {cursor} │
│                       │ Shortcut                         ⌥⇧⌘9   │
│                       │ Size                 9 words · 52 chars  │
│                       │ Modified                    2 hours ago  │
└──────────────────────────────── Type Snippet ↩  Copy ⌘↩  … ──────┘
```

## The rows

The snippet's name, its keyword as a keycap at the right edge (where the
full list put "first words · keyword"; the preview says the rest). No
keyword, nothing on the right. Its launcher alias, when it has one, stays
a keycap after the name as on every row. Outside the mode (root search)
a snippet row is unchanged: "Snippet · ;addr".

## The preview

**Top: the snippet as it would type now**, in a soft tile (`SoftTile`),
from the code that types it: `Snippet.expansion(_:)`, the pieces
`Snippet.expanded(_:)` joins, with the values `SnippetExpander` passes
(`SnippetExpander.values`). So:

- `{date}`, `{time}`, `{day}`, `{app}`, `{name}`… show today's date, the
  app in front (where ↩ types it)… on a soft accent wash, rounded: filled
  now.
- `{clipboard}` shows the current copy when skil.li may read it without
  macOS asking (Paste from Other Apps → Allow); otherwise the token stays
  as written on a grey wash: filled when typed. Never a prompt from a
  preview.
- `{cursor}` is a thin accent caret where the caret ends.
- A value that types nothing (`{selection}`: the launcher has none) shows
  nothing, as typing does.
- Monospaced (11.5 pt) under its language's name when the text is code
  (`CodeLanguage`, as the clipboard), else 13 pt system. A long text
  fades at the bottom.

**Information**, then label/value rows as the clipboard's, only what is
known for sure, each row left out when it holds nothing:

| Row | Value |
|---|---|
| Keyword | as written |
| Expands | Settings → Snippets → Expand's title ("After a space or ↩"); "Off" when keywords do not expand; "Not in 1Password" when the app in front is one where keywords stay as typed |
| Placeholders | the tokens as written, once each: "{date}, {clipboard}, {cursor}" |
| Alias | its launcher alias |
| Shortcut | its shortcut from Settings → Keys ("⌥⇧⌘9", a chain "✦K S") |
| Size | of what types now: words · characters (· lines when more than one) |
| Modified | the snippet file's date ("2 hours ago"), read with the folder |

## States

- No snippet at all: the list says "No snippet yet: add one in
  Settings → Snippets" (two lines in the narrow list), the tile shows the
  quiet `text.quote` symbol, no Information.
- Nothing matches, or ⇥ is asking: the same quiet tile; the list's line
  as today.
- ⇥ by meaning: the rows it picked, the pane follows the selection as
  for typed searches.
- Light and dark: semantic colors only (`labelColor` washes, the accent
  at 16 % under filled parts, `secondaryLabelColor` for unfilled tokens).

## Speed

Showing a row: the pieces (a scan of the text), the values only when the
text has a placeholder, the clipboard read only when it has `{clipboard}`
and reading cannot ask, the code guess cached by snippet. The shortcut,
alias, Expands line and file dates are read as the mode opens. No file,
no network on the selection path. The self-test checks a row shows in
under 8 ms.

## Checked by

`selftest snippets` (Mac mini): the pane shows the selected snippet with
`{date}` filled, `{cursor}` as the caret, its information rows; ↓ moves
the pane; captures `launcher-snippets-light/-dark.png`.
