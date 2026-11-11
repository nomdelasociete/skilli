# Clipboard History: a copy pasted another way

One gap in `docs/clipboard-review.md` (#10): a copy could only be pasted
as it was, or as plain text. The color's preview shows Hex, RGB and HSL
and ↩ pasted only the one copied; a link came with its tracking; JSON
copied packed stayed packed.

## Moment

1. **When.** ✦C is on a text copy and the user wants it in another
   form than the one copied: the color as RGB for a stylesheet, the
   link clean before sending it, the JSON laid out to read it, three
   copied lines as one, a title in capitals.
2. **The path.** ⌘K on the row, then the way: *Paste as RGB*, *Paste
   Without Tracking*, *Paste as Pretty JSON*… Typing in ⌘K narrows the
   list ("rgb", "json", "upper"). No new key: the keys are the user's
   to give.
3. **Hint or push.** Neither. ⌘K lists a way only where it changes the
   copy: a row whose list is short says there is nothing to change.
4. **Deterministic or AI.** All code (`ClipboardTransform`, in
   SkilliCore), on this Mac. Nothing leaves it.
5. **Wrong.** The copy itself is never changed: the way is pasted, the
   row stays as copied, and ↩ still pastes it as it was. A way that
   reads the copy wrong (a text taken for JSON) is not offered unless
   the whole copy parses. What is pasted joins the history as any copy
   (it was on the clipboard), so it can be pasted again.

## The ways

After *Paste as Plain Text*, in this order, each only when its result
differs from the copy:

| The copy | ⌘K adds |
|---|---|
| A color | Paste as Hex, Paste as RGB, Paste as HSL (the two not copied) |
| A link with `utm_…` or an ad network's click id | Paste Without Tracking |
| A JSON object or array | Paste as Pretty JSON, Paste as Minified JSON |
| One line with `%XX` | Paste URL-Decoded |
| Several lines | Paste as One Line |
| Spaces or empty lines around it | Paste Trimmed |
| Prose (not a link, an address, a number, code) up to 10,000 characters | Paste UPPERCASE, Paste lowercase, Paste Title Case |

- JSON is laid out again without being read into values: the keys keep
  their order, the numbers their digits (`1.50` stays `1.50`). Two
  spaces a level.
- Tracking: `utm_*`, `fbclid`, `gclid`, `gclsrc`, `dclid`, `gbraid`,
  `wbraid`, `msclkid`, `mc_cid`, `mc_eid`, `igshid`, `yclid`, `twclid`,
  `ttclid`, `li_fat_id`, `_hsenc`, `_hsmi`, `mkt_tok`, `oly_anon_id`,
  `oly_enc_id`, `vero_id`, `s_cid`. Nothing else of the link changes.
- A copy over 100,000 characters gets none: the list is made as ⌘K
  opens.
- No `skilli://` link and no tool: a way is on one row of the list, as
  Pin is. The clipboard's text is already reachable (`get_clipboard`),
  and a skillie changes it as it likes.

Not done: a way kept as the row's ↩; ways for images or files; a
custom way (a script); sorting or numbering lines; Markdown to plain.

## Checks

- Unit (`ClipboardTransformTests`): each way's result; the ways not
  offered where nothing changes, on a long copy, on an address.
- Self-test (`previews`): ⌘K on a color copied as RGB lists Paste as
  Hex and Paste as HSL, not RGB nor the cases; on a link with tracking,
  "tracking" then ↩ pastes the link without it in the app in front.
