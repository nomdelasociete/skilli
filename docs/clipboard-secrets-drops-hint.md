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
   - A key kept (a shape not in the list): as before this change. ⌘⌫
     forgets it.
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
| `-----BEGIN … PRIVATE KEY-----` anywhere in the copy, whatever its length | a private key |

- Settings → Clipboard → Advanced → **Never keep keys and tokens**, on
  out of the box, as the password managers' apps are excluded out of
  the box; `clipboardSkipSecrets` for skillies and agents
  (`set_setting`).
- Checked when copied: a few patterns on one word of at most 8,192
  characters, and the header looked for. On the main thread for a copy
  up to 100,000 characters, off it for a longer one (with its hash).
- Not kept means nowhere: no row, no file, no log of its text. The log
  says its shape's name only.
- Nothing leaves the Mac.

### A key inside a longer copy

`ClipboardSecret.held(in:)`, since 2026-11-12. The moment: a whole
`.env` copied to another file, a `curl` line with its header copied
from a terminal or a page of documentation, a sentence in a chat that
gives a token. Nothing to do, nothing to learn: the copy is not kept,
and the history opened next says "Not kept: it holds a GitHub token
(Zed, 14:02). To keep them: Settings → Clipboard → Advanced." Code
only, the same switch.

- One of the shapes above as a whole word of the text (nothing a key is
  made of before or after it), or a sign-in header with its value
  (`Authorization: Bearer …`, `Basic`, `Token`, 20 characters or more
  with a digit among them: "a sign-in header").
- Kept, since they only name a key: `ghp_` or `sk_live_` alone in a
  sentence; a header with a placeholder (`Bearer $TOKEN`, `Bearer
  YOUR_TOKEN_GOES_HERE`); `sk-` followed by plain lowercase words (a
  class name, a slug): inside a text `sk-…` counts with a digit and a
  capital in it.
- Wrong one way: a page of documentation with an example key, a log
  with a sign-in token in it are not kept; the line says so, the copy
  is still on the clipboard, the switch keeps them. Wrong the other
  way: a value with no shape of its own (`PASSWORD=…`, `SECRET_KEY=…`
  with random letters) is kept, as nothing tells it from any other
  setting.
- One pass over the text for every shape. A copy over 20,000
  characters is looked through off the main thread (100,000 characters
  take 4 to 6 ms).

Not done: a value with no shape of its own (`PASSWORD=…`); nothing
expires after minutes; the history's file is not encrypted.

## Not kept, and said

- `ClipboardNotKept`: the reason (a key's shape name, a text over 5 MB,
  a picture over 40 MB), the app's name, the time. In memory, the last
  one only, for a day; never the copy.
- Said by `LauncherController.sayClipNotKept` as clipboard mode opens,
  after the clipboard was read (a copy made a moment before ✦C is said
  too); once the panel is up when the history was kept from last time;
  and at once in an open history when a long copy turns out not kept.
- Not said: a screenshot of the watched folder over 40 MB, a copy from
  an excluded app, a copy a password manager marked secret (those are
  the user's own choice or the app's).

## Checks

- Unit: each shape, and what must be kept (a SHA-256, a UUID, a
  sentence naming a token, a link, a certificate); the line said; the
  footer with a second key.
- Unit: a key in a `.env`, a `curl` line, a sentence, at the end of a
  long file; what only names a key is kept; the time on 100,000
  characters.
- Self-test (`previews`): the token among other lines is not kept and
  said as what the copy holds; a sentence naming `ghp_` is kept.
- Self-test (`previews`): a copy shaped as a GitHub token is not kept,
  the history opened next says it without the token, not a second
  time; with the setting off it is kept; the invoice's footer says
  Paste Text ⇧↩.
