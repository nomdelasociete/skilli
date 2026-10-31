# GitHub workflow runs: start one, follow it

Proposal and build, 2026-10-30 (asked: releasing skil.li is something the
maintainer cannot do alone, nor see while it runs; Raycast makes this
trivial).

**Status**: built in one PR with the release workflow's version input.
Not tried yet by the maintainer: the `release` environment still needs
its secrets (`script/release/ci-secrets.sh`, once).

## Short answer

Two changes, one per side:

- **The release workflow takes the version as an input.** `bump`
  (`patch` or `minor`) and `critical`. The version is the last release's
  tag raised by `bump` (`script/release/version.sh`), passed to the build
  as `MARKETING_VERSION`. No version-bump pull request any more.
- **skil.li starts a workflow and follows it.** A `workflow_dispatch`
  workflow of any repository the user's GitHub sign-in can run, with its
  inputs: asked once in the card, started, its environment approved when
  the user may approve it, then each job and step live in the menu bar, and
  one card at the end with the release it published or the step that
  failed. Reached from a skillie (`Release skil.li`, a dropdown: Patch,
  Minor, Critical patch), a `skilli://github/workflow` link, or
  `$SKILLI_CLI call run_github_workflow`.

## Moment

1. **When.**
   - *Ready to ship*: the maintainer merged what the release should carry,
     usually in the browser, and wants users to have it. Today he asks an
     agent, which opens a bump pull request he must approve, then starts
     the workflow, which waits for his approval on GitHub.
   - *An agent was asked to release*: it calls the same tool, and the
     maintainer answers in skil.li's card, as for any change an agent asks.
   - *While it runs* (about 15 minutes): he works on something else and
     wants to glance at where it is (building, notarizing, publishing).
   - *At the end*: it is published (the release's link, what users get) or
     it failed (which step, its log).
2. **The path.**
   - Start: the launcher's row of the skillie that names the workflow
     ("Release skil.li"), ↩, pick Patch, Minor or Critical patch, ↩. The
     card asks once, naming the repository, the branch and the inputs; ↩
     starts it. A link (a Stream Deck key) or an agent's call reaches the
     same card.
   - Follow: an item in the menu bar while it runs (a shipping box and the
     step it is on, "3/7"), the place a long job already shows itself in
     skil.li (Keep Awake's cup, the recorder's dot). Its menu lists each
     job and step with its state, and Open on GitHub, Cancel Run.
   - End: the card, once the user is free (the launcher closed, not
     typing), as a scheduled ask's answer comes.
3. **Hint or push.**
   - The start asks every time, with no Always: it publishes to every user
     of the repository's app (MANIFESTO 6: ask before what cannot be taken
     back). Its ↩ also approves the run's environment when GitHub says the
     user may approve it: one key, the same decision the maintainer made
     on GitHub's Review deployments page. The card says so.
   - While it runs: a hint, the menu bar item, nothing else: no card, no
     sound, no badge (MANIFESTO 9). The item goes when the run ends.
   - At the end: one card, a push, because the outcome happened out of
     sight and is what the user waits for (MANIFESTO 8): a failure needs
     an action, a success gives the link to check or share. Once, then
     gone; ↩ opens the release (or the failed step's log), esc closes.
   - No default shortcut (AGENTS.md → Shortcuts): the skillie's row gets
     one only when the user gives it one.
4. **Deterministic or AI.** All of it is GitHub's own answer: the run's
   state, its jobs and steps, the environment waiting, the release made
   during the run. No SI. What leaves the Mac: the user's GitHub sign-in
   with the start, the approval and the reads of that run, to GitHub only
   (Settings → Privacy → GitHub workflow runs). Nothing to the relay.
5. **Wrong.**
   - A wrong pick (Minor for Patch): the card shows the inputs before ↩;
     esc starts nothing. Once started, Cancel Run in the menu stops it on
     GitHub; before "Build, notarize, publish" ends nothing is public.
     After it, a release is out: the next release replaces it (the feed
     holds one release).
   - GitHub's answer to the start does not name its run (it always does
     today): the card says so with the workflow's runs page; nothing is
     followed or approved. A run is never picked from the list by time:
     it could be another one this user started, approved unasked.
   - The user may not approve the environment: the run is followed as
     "Waiting for approval", with Open on GitHub for whoever can.
   - skil.li quits during the run: the run goes on, on GitHub; the menu
     bar item does not come back (not kept across launches), the run's
     link was in the card that started it, and `get_github_workflow_run`
     reads it.
   - Signed out of GitHub, or a token without the right (GitHub's 403 or
     404): GitHub's message, in the card, and Settings → GitHub.

## The release workflow's version

Before, a release took its version from `MARKETING_VERSION` in
`project.yml`, so every release started with a pull request raising it,
approved by the code owner (the main ruleset: a pull request, a code
owner's approval, `check`, signed commits). The ruleset stays as it is.

Now the version comes from the releases themselves:

- `script/release/version.sh <patch|minor>` prints the next version: the
  newest `v<version>-<build>` tag raised by one patch or one minor, or
  `project.yml`'s version when that is higher. `project.yml` is a floor:
  raise it in a pull request only to jump (1.0.0); otherwise it stays.
- `release.yml` takes `bump` (patch, minor) and `critical`, names the run
  after them ("Release patch, critical"), computes the version first, and
  stops before building when nothing was committed since the last
  release (the build number would be the feed's).
- `build.sh` passes the version to `xcodebuild` (`MARKETING_VERSION=`,
  `SKILLI_MARKETING_VERSION` from `publish.sh`); `publish.sh <patch|minor>`
  does the same on a Mac.
- Development builds say the same version: `stamp_build.sh` writes the
  higher of the newest release tag's and `project.yml`'s into the built
  app, so Settings → About on a build of main says the last release it
  contains (and its build number says how far past it).

Why not a pull request that catches `project.yml` up after each release:
one opened by the workflow's own token starts no `check`, so it could
never be merged without bypassing the ruleset, and it would be one more
thing to approve per release: the step this removes.

## Before the first release: the secrets, once

The `release` environment needs the signing and notarization keys, put
there once by the maintainer (agents never handle these files). In
Keychain Access, open the login keychain's **My Certificates**, select
**Developer ID Application: NOM DE LA SOCIETE (JSFMAD28GS)**, then File →
**Export Items…**, format Personal Information Exchange (.p12), saved to
the Desktop with a password of your choice. In App Store Connect, go to
Users and Access → **Integrations** → App Store Connect API → **Team
Keys**, press +, name it "skil.li notarization" with the **Developer**
access, Generate, then **Download API Key** (offered once: the file is
`AuthKey_<its ID>.p8`, keep its name); the **Issuer ID** is shown above
the keys. Also make a fine-grained token at
github.com/settings/personal-access-tokens for nomdelasociete/homebrew-tap
only, Contents: Read and write. Then, in Terminal at the repository's
root (signed in with `gh`, with skil.li built once there so Sparkle's
tools are found): `script/release/ci-secrets.sh ~/Desktop/<file>.p12
~/Downloads/AuthKey_<ID>.p8`. It asks for the .p12's password, the
Issuer ID and the tap token, takes Sparkle's key from the login keychain
(macOS asks to allow it once), sends each to GitHub and lists what the
environment holds. Delete the .p12 from the Desktop afterwards; run it
again only to replace a key.

## What skil.li reads and calls

All with the user's GitHub sign-in (Settings → GitHub; the `repo` scope
covers each one):

| Step | GitHub's API |
| --- | --- |
| Start | `POST /repos/{repo}/actions/workflows/{workflow}/dispatches` (`ref`, `inputs`); the run its answer names (`workflow_run_id`), never one guessed |
| Approve | `GET …/actions/runs/{id}/pending_deployments`; `POST` the same with the environments the user `current_user_can_approve`, `approved` |
| Follow | `GET …/actions/runs/{id}` and `…/runs/{id}/jobs?filter=latest`: every 5 s while it runs, every 30 s while it only waits (an approval only someone else can give, a runner) |
| End | `GET /repos/{repo}/releases?per_page=5`: a release published since the run started is "the release it made" |
| Cancel | `POST …/actions/runs/{id}/cancel` |

A run is followed until it completes. Several can be followed at once;
the menu bar item names the newest, its menu lists every one.

## Reached from everywhere

- Tool: `run_github_workflow` (`repo`, `workflow`, `ref`, `inputs` as a
  JSON object): asked in the card every time; answers once the run is
  found and approved, with its link, and does not wait for the end.
  `get_github_workflow_run` (`run`: its link) says its state, each job
  and step, and the release it made.
- Link: `skilli://github/workflow?repo=owner/name&workflow=release.yml&ref=main&bump=patch`:
  every other query item is an input. Asked first, as the tool is.
- Skillie: `script/release/release.skilli`, "Release skil.li": a dropdown
  (Patch, Minor, Critical patch) that calls the tool. Double-click it once
  to add it.

## Not built

- A list of a repository's workflows to pick from in the launcher: the
  skillie names the one it runs.
- Following a run started elsewhere (on github.com): only runs started
  from skil.li show in the menu bar.
- Keeping followed runs across a relaunch.
