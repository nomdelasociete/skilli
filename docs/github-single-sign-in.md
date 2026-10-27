# GitHub: one sign-in instead of three

Proposal, 2026-10-27, agreed the same day.

**Status**: built in a relay PR and a skil.li PR, both open; not deployed.
To check live: whether GitHub's device page still asks for Authorize once
the skil.li OAuth App is authorized.

## Today

A new user goes to the browser three times, with clicks in Settings in
between:

| # | Step | Browser trip | What it proves | What it gives |
|---|---|---|---|---|
| 1 | Sign In with GitHub… | github.com/login/device: paste a code, Continue, Authorize "skil.li" | The Mac holds a token for this GitHub user | Native token (Keychain `github-token`): reads, merge, update branch, mark read |
| 2 | Live updates → Authorize this Mac… | relay `/enroll` → GitHub App OAuth → choose accounts → Associate | The browser's GitHub user (numeric id) and which App installations to listen to | This Mac's relay pairing (`relay-device-v2`): the stream, wakes |
| 3 | Server sync → Turn On… → Continue → Authorize in Browser… | relay `/inbox/authorize` → GitHub OAuth (skil.li OAuth App) | The OAuth grant belongs to the same numeric id as the pairing | The relay's encrypted inbox copy for all the user's Macs |

Each step only starts once the one before has finished.

## Proposal

One button, **Sign In with GitHub…**, and one browser tab that goes
through every page in a row. Nothing to click in skil.li in between.

```
skil.li                                  browser (one tab)
───────                                  ─────────────────
Sign In with GitHub…
 ├ POST github.com/login/device/code ──→ user code (copied)
 ├ POST relay /devices ────────────────→ /enroll?app&code
 └ open /enroll?…&inbox=1&user_code=…    1. GitHub App OAuth   (skipped after the first time)
                                         2. Choose accounts    (one click; the only account is ticked already)
                                         3. skil.li OAuth      (skipped after the first time)
                                         4. "Last step: code ABCD-1234" → Continue on GitHub
                                         5. github.com/login/device: paste, Authorize
 polls both: GitHub token, relay pair
 saves the token, checks the ids match,
 saves the pairing, server sync on
```

- **The relay's pages come first, the GitHub code last.** GitHub's device
  page goes nowhere once it is done, so it must be the tab's last page.
  The relay pages chain by redirects: after Associate, the enrollment flow
  goes straight on to the inbox grant (step 3), then to a final page.
- **The final page shows the code** (`user_code` in the URL skil.li opens,
  checked as `XXXX-XXXX`, kept sealed in the flow, never logged). The code is
  also in the clipboard and in Settings. Showing it to the relay costs
  nothing: the code is only useful to someone signed in to GitHub, and a code
  approved by another account gives a token that fails the id check below.
- **Already signed in on this Mac** (existing users): no `user_code`, the
  final page says "Done". Live updates and server sync take one trip.
- **The inbox grant asks for the same scopes as the native token**
  (`repo notifications read:user`, today `read:user repo`). GitHub then
  shows one consent screen for the skil.li OAuth App, at step 3, and skips
  it later; step 5 may still ask for its own Authorize click (to check live).

### What each step proves (unchanged)

- Pairing: GitHub App OAuth in this browser gives the numeric id (subject)
  and the installations; the pairing is only redeemed by the Mac holding
  the private `device_code`.
- Inbox grant: the relay saves it only if GitHub says the grant's user is
  that same subject (`InboxState.save`, otherwise 403 and nothing stored).
  In the chained flow the subject comes from the enrollment that just
  finished in this tab, instead of from a device bearer.
- Native token: skil.li compares `/user` (its own token, sent only to
  GitHub) with `/computers/identity` (the pairing) before saving the pairing,
  as today. One browser means one GitHub session: a mismatch now only comes
  from a switch of account halfway through.

### What stays native

The GitHub token never goes to the relay. Merge, Update Branch and Mark Read
stay native, then ask the relay to reread, as today. The GitHub App only
serves webhooks and the installations to listen to; the skil.li OAuth App
reads (native, or the relay's grant).

### Consent for server sync

Server sync stores a copy (titles, links, checks; never code or comments)
on the relay. It stays a choice, made **before** the trip, beside the
button: a checkbox "Keep my pull requests on the relay for all my Macs
(server sync)", ticked by default, with today's consent text under it
(no separate alert any more). Checked → `inbox=1` in the
URL and `githubServerSync` turned on once the pairing is saved. Unchecked →
the chain skips step 3.

### Existing users and old versions

- Paired, server sync off: Server sync → Turn On… keeps today's single trip.
- Signed in, not paired: the Live updates button now also offers server sync
  in the same trip.
- The new relay says so in `POST /devices`'s answer (`"chain": ["inbox",
  "user_code"]`, a field old clients ignore). Without it, skil.li adds
  nothing to the URL: the trip ends after Associate, server sync shows
  "Authorize in Browser…" as today, and skil.li opens GitHub's device page
  itself once the pairing arrives.
- An old skil.li with the new relay: same endpoints, same pages.
- Relay unreachable or enrollment closed (`POST /devices` ≠ 201): today's
  device flow alone, live updates later.

## Moment

- **When**: Settings → GitHub, the first time (and after Sign Out).
- **Path**: one button, one checkbox under it; the browser does the rest.
- **Hint/push**: none added; Settings → GitHub already says what is missing.
- **Deterministic**: no AI.
- **Cost of being wrong**: a mismatched account gives no pairing and says
  so (as today); a trip abandoned halfway leaves what finished (native token
  alone, or the pairing without the inbox) and each step can be done again
  on its own.

## Not in this change

- **Without the GitHub App installed**, step 2 has nothing to tick and the
  trip stops there (its "Install the GitHub App" link comes back to the
  choice page). Pairing with zero installations (sign-in and server sync
  without live updates) touches the relay's core rule that a pairing has at
  least one installation (computer records, renewal's rights check, the Go
  service): a separate change.
- Replacing the device code with a browser redirect: GitHub's web flow needs
  the OAuth App's client secret, which an open-source app cannot keep, and a
  relay doing the exchange would see the native token.

## Changes

**relay** (`cloudflare/src/auth.ts`, `inbox.ts`):

1. `POST /devices` answers `chain: ["inbox", "user_code"]`; `/enroll`
   accepts optional `inbox=1` and `user_code` (strict format, at most once
   each); `BrowserFlow` keeps them sealed with the flow.
2. After a successful Associate with `inbox=1`: 303 to a new inbox flow
   bound to (product, subject) without a device bearer
   (`InboxAuthorization.beginFromEnrollment`), then GitHub, then the final
   page. The choice page's CSP `form-action` allows that redirect.
3. Final page: the code and "Continue on GitHub"
   (`https://github.com/login/device`) when `user_code` was given, else
   "Done".
4. Inbox OAuth scope `repo notifications read:user`.
5. Tests: the redirects and the GitHub authorize URL (client, redirect,
   scope, state), a grant from another account refused, no `inbox` → no
   inbox flow, bad `user_code` refused, the device-bearer flow unchanged.

**skil.li** (`GitHubBook`, `RelayDeviceSession`, `GitHubPane`):

1. `GitHubBook.signIn()` starts the device flow and the relay enrollment
   together and opens one URL; it polls both.
2. `RelayDeviceSession.enroll` takes `inbox` and `userCode`, appends them to
   the verification URL, and waits for the native token (up to the device
   code's expiry) before the id check and the save.
3. Settings → GitHub: one sign-in section (button, server sync checkbox);
   Live updates and Server sync below stay for managing and revoking.
4. Tests (`RelayDeviceSessionTests`): the requests sent (`/devices`, the URL
   opened with its parameters, `/devices/token`, GitHub `/user`,
   `/computers/identity`), pairing saved only after the native token
   arrives and the ids match, never with a mismatch; the fallback when
   `/devices` fails. `selftest github` on the mini for the pane.

Deploy order: relay first (backward compatible), then skil.li.
