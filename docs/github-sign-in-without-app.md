# GitHub: sign in without installing the GitHub App

Proposal, 2026-10-27. Follows [github-single-sign-in.md](github-single-sign-in.md).

## Today

Single sign-in runs one browser tab: the relay's GitHub App sign-in, the
choice of accounts, the server sync grant, then GitHub's code. Someone who
never installed the GitHub App has nothing to tick on the choice page. The
only way on is Cancel, which ends the pairing, and with it server sync:
skil.li signs in natively and reads GitHub from this Mac alone.

Server sync does not need the App. The relay reads pull requests and
notifications with the skil.li OAuth App grant. The App only brings
webhooks, which wake the Macs when a repository changes.

## Proposal

A pairing may cover **no installation**. On the choice page, when GitHub
lists no installation for this user, a button **Continue without live
updates** associates the Mac anyway. The tab goes on to the server sync
grant and GitHub's code, as with an installation.

Such a Mac has its relay identity, renews it, and reads the relay's inbox
copy. It gets no wakes: no installation means no webhook. skil.li therefore
does not open the stream for it and keeps reading on its timers: the relay
copy every 30 s with server sync, GitHub directly without.

Installing the App later is optional. Settings → GitHub → Live updates says
"No GitHub account for live updates" with **Add accounts…**, which pairs
again (a new pairing with the chosen accounts, as Manage connected accounts
does today).

### The skil.li OAuth App stays

Notifications are read with it, and GitHub's notifications API takes only
classic or OAuth tokens. GitHub's REST docs for `/notifications` say: "These
endpoints only support authentication using a personal access token
(classic)". The GitHub App's user tokens cannot read them. A user therefore
always grants the skil.li OAuth App, and installs the GitHub App only for
instant updates.

### What each check still proves

- **Pairing**: the GitHub App sign-in in the browser still gives the numeric
  user id (subject). Only the list of installations may be empty.
- **Renewal**: the relay checks again that the user's GitHub token is live
  and that each installation is still accessible. For none, the second
  check passes, and a token the user revoked on GitHub still ends the
  pairing.
- **Webhooks and repository checks**: they go by installation, so a Mac
  with none receives no webhook, and `/repositories/check` answers 403.
- **Personal hooks** (`POST /hooks`) need an installation to wake: refused
  with 403 for a pairing without one.

### Abuse

A pairing without the App costs the same as one with it: the App is free
and installs in two clicks. The relay's existing limits on `POST /devices`
apply unchanged (per product and per address), and each pairing still needs
a GitHub sign-in in the browser.

## Moment

**First sign-in without the App**

- **When**: a new user, who never installed the GitHub App, clicks Sign In
  with GitHub… in Settings → GitHub.
- **Path**: the same tab as today. On the choice page, which says no account
  has the App, one click on Continue without live updates.
- **Hint/push**: the choice page offers Install the GitHub App above the
  button. skil.li adds nothing.
- **Deterministic**: no AI. To the relay: the same as single sign-in, with
  an empty selection.
- **Cost of being wrong**: none to undo. Without the App, pull requests
  update every 30 s instead of at once. Add accounts… brings live updates
  later.

**Signed in, paired without the App**

- **When**: the user installs the GitHub App later and wants instant
  updates.
- **Path**: Settings → GitHub → Live updates → Add accounts…, then choose
  accounts, as Manage connected accounts today.
- **Hint/push**: the Live updates line says there is no account.
- **Deterministic**: no AI.
- **Cost of being wrong**: the old pairing stays until the new one is saved.

## Changes

**relay** (`cloudflare/src`):

1. `policy.ts` `validSet`, `computer.ts` `validNewComputer` (new
   computers; imports unchanged), `authority.ts` `inspectSession`,
   `credentials.ts` `validate`: an empty installation list is valid. The
   renewal check matters most: left as it is, it answers `deny` and the
   first renewal revokes the Mac.
2. `auth.ts` choice page: with no installation listed, a **Continuer sans
   mises à jour en direct** button posts `none=1`. `/choose` accepts an
   empty selection only with `none=1` and only when GitHub lists no
   installation. The "annulez" hint goes.
3. `hooks.ts` `POST /hooks`: 403 for a session without an installation.
4. Tests: the chained sign-in without the App pairs, claims, reads the
   inbox and notifications, opens the stream; a renewal with no
   installation (real rights check) is not revoked; `/choose` with
   `none=1` while installations exist is refused; `POST /hooks` 403.
5. README: a pairing may have no installation.

The Go reference service is not deployed and is not compared with the
Workers on this rule: unchanged.

**skil.li**:

1. `RelayDeviceSession.enroll`: accepts an empty `installations`, with its
   own message ("This Mac is paired without live updates.").
2. `GitHubBook`: live updates need at least one installation. Without, no
   stream, and reads stay on their timers (`relayIsConfigured`).
3. Settings → GitHub → Live updates: "No GitHub account for live updates"
   and Add accounts… when the pairing has none.
4. Tests (`RelayDeviceSessionTests`): an empty list pairs and is saved; a
   non-numeric id is still refused.

## Not in this change

- Turning a pairing's installations up or down in place: adding accounts
  still pairs again.
