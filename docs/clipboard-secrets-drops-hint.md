# Clipboard History: keys never kept, what is not kept said, ⇧↩ told

Three of the gaps in `docs/clipboard-review.md` (#13, #14, #16):

- A token or a key copied from a terminal or a browser was kept in the
  history's file as any text: only what a password manager marks secret
  was skipped.
- A text over 5 MB or a picture over 40 MB was not kept and nothing
  said so: the copy looked for was simply not there.
- An image whose words were read pastes them on ⇧↩, and nothing on
  screen told it.

## Moment

1. **When.**
   - *Keys*: the user copies a token to paste it once (a terminal, a
     dashboard, a `.env`). Nothing to do, nothing to see: it is not
     kept.
   - *Not kept*: the user opens ✦C looking for a copy that is not there
     (a key, something too big).
   - *⇧↩*: ✦C is on a screenshot or a scan and the user wants its words,
     not the picture.
2. **The path.** None to learn. No key, no action.
   - Keys: decided when copied, by code.
   - Not kept: the next time the history opens, one line in the
     footer's place, until the next key: "Not kept: looks like a GitHub
     token (Terminal, 14:02). To keep them: Settings → Clipboard →
     Advanced." Once.
   - ⇧↩: the footer of such a row reads "Paste ↩ · Paste Text ⇧↩ ·
     Actions ⌘K".
3. **Hint or push.** A hint in both cases, in the footer, never a
   notification: the line shows only when the user is already in the
   history.
4. **Deterministic or AI.** All code. A key is known by a shape that
   names itself (below); nothing is guessed from randomness.
5. **Wrong.**
   - A key kept (a shape not in the list, a key inside a longer text):
     as before this change. ⌘⌫ forgets it.
   - A copy taken for a key and not kept: the user loses it from the
     history (it is still on the clipboard until the next copy). The
     line says it, and where to turn it off. This is why only shapes
     that name themselves are in the list: a hash, a UUID, a long random
     word are kept.
   - The line missed (a key pressed at once): the copy is still not
     there, said nowhere else. Accepted: a list of what was not kept
     would be a second history to keep.

## Keys and tokens

`ClipboardSecret.name(of:)`, in SkilliCore. The whole copy is one word
(spaces around it aside) of one of these shapes, or holds a private
key's header:

| Shape | Said as |
|---|---|
| `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_` + 36 or more, `github_pat_…` | a GitHub token |
| `glpat-…` | a GitLab token |
| `sk_live_`, `sk_test_`, `rk_live_`, `rk_test_…` | a Stripe key |
| `sk-` + 20 or more | an API key |
| `AKIA` / `ASIA` + 16 | an AWS access key |
| `xoxb-`, `xoxp-`… | a Slack token |
| `AIza` + 35 | a Google API key |
| `npm_` + 36 | an npm token |
| three base64url parts, the first two starting `eyJ` | a sign-in token |
| `-----BEGIN … PRIVATE KEY-----` anywhere in a copy of at most 20,000 characters | a private key |

- Settings → Clipboard → Advanced → **Never keep keys and tokens**, on
  out of the box, as the password managers' apps are excluded out of
  the box; `clipboardSkipSecrets` for skillies and agents
  (`set_setting`).
- Checked on the main thread when copied: a few patterns on one word of
  at most 8,192 characters, only for copies under 100,000 characters.
- Not kept means nowhere: no row, no file, no log of its text. The log
  says its shape's name only.
- Nothing leaves the Mac.

Not done: a key inside a longer text (a whole `.env`, a `curl` line
with its header) is kept; nothing expires after minutes; the history's
file is not encrypted.

## Not kept, and said

- `ClipboardNotKept`: the reason (a key's shape name, a text over 5 MB,
  a picture over 40 MB), the app's name, the time. In memory, the last
  one only, for a day; never the copy.
- Said by `LauncherController.say` as clipboard mode opens, after the
  clipboard was read (a copy made a moment before ✦C is said too).
- Not said: a screenshot of the watched folder over 40 MB, a copy from
  an excluded app, a copy a password manager marked secret (those are
  the user's own choice or the app's).

## Checks

- Unit: each shape, and what must be kept (a SHA-256, a UUID, a
  sentence naming a token, a link, a certificate); the line said; the
  footer with a second key.
- Self-test (`previews`): a copy shaped as a GitHub token is not kept,
  the history opened next says it without the token, not a second
  time; with the setting off it is kept; the invoice's footer says
  Paste Text ⇧↩.
