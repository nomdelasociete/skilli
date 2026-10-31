---
name: release
description: Release skil.li to users — Developer ID build, notarization, GitHub release, Sparkle update feed, Homebrew cask. Use when asked to release, publish or ship a new version.
---

# Release skil.li

How a release is built and why: AGENTS.md → Releases. This is the run.

## 1. Ready

- On `main`, clean, equal to `origin/main` (`git status -sb` says `## main...origin/main` and nothing else).
- Everything the release should carry is merged, and its mini self-tests passed when it merged.
- Version: nothing to commit. The run's `bump` raises the newest release tag: `patch` for fixes, `minor` for new features (`script/release/version.sh patch` prints what it will be). `project.yml`'s `MARKETING_VERSION` is only a floor, raised in a pull request to jump (1.0.0). The build number takes care of itself (commit count + 900).

Done when all three hold.

## 2. Publish

The maintainer releases alone from skil.li: the "Release skil.li" skillie (`script/release/release.skilli`, added once by double-clicking it), Patch, Minor or Critical patch. skil.li asks in its card, starts the workflow, approves the `release` environment with that answer, follows each step in the menu bar and says at the end where the release is. Point him there first.

Asked to release it yourself: on GitHub's Macs (`.github/workflows/release.yml`), never on the developer's Mac or the Mac mini, through skil.li's tool when you run under skil.li (`"$SKILLI_CLI" call run_github_workflow repo=nomdelasociete/skilli workflow=release.yml ref=main inputs='{"bump":"patch"}'`: the maintainer answers in its card), else:

```sh
gh workflow run release.yml --repo nomdelasociete/skilli --ref main -f bump=patch
```

A critical release (a security fix, a fix users must not stay without), only when the maintainer asks for one: add `-f critical=true` (`"critical":true`). Sparkle then shows it at once to every older build, even with automatic updates on, and it cannot be skipped; later releases stay critical for builds below it.

Started with `gh`, the run waits for the maintainer's approval (the `release` environment): tell the maintainer it is waiting, with its link (`gh run list --workflow release.yml --limit 1`). Then about 15 minutes: archive, two notarizations, the signed feed, the GitHub release, the cask. Done when the run is green and its log ends with `Published skil.li <version> (<build>)` (`gh run watch <id>`; `gh run view <id> --log-failed` when it is not).

- The environment has no secrets yet (`gh secret list --env release --repo nomdelasociete/skilli`): the maintainer runs `script/release/ci-secrets.sh <.p12> <AuthKey_….p8>` once; its header says where each file comes from.
- "The feed already has build N" (before the build, within a minute): nothing new was committed since the last release; commit, then run it again.
- "No Developer ID Application identity": `DEVELOPER_ID_P12` or its password is wrong; the maintainer runs `ci-secrets.sh` again.
- A notarization `Invalid`: the log's submission id, then `xcrun notarytool log <id> --key <.p8> --key-id <id> --issuer <issuer>` on a Mac that has the key, or the keychain profile `dsmn-notary`; fix, commit, run again.
- "Upload failed 3 times": the draft release waits on GitHub, unseen; run it again, it uploads to that draft and publishes it.
- "No Klipy key": `SKILLI_KLIPY_KEY` is missing from the environment; the build goes on, but its Search GIFs finds only GIFs on the Mac. `ci-secrets.sh … --klipy` asks for it.
- GitHub's Macs unavailable: `./script/release/publish.sh patch` (or `minor`) from a clean main on a Mac still works, every credential from the login keychain (as before 2026-10-19) except the Klipy key, taken from that Mac's own `daily` skil.li; only with the maintainer's go-ahead.

## 3. Check what users get

- `curl -sI https://skil.li/download` → `302` to the new release's `skil.li.dmg`; `curl -sL https://skil.li/appcast.xml` holds `<sparkle:version><build></sparkle:version>`, and `<sparkle:criticalUpdate` exactly when this release or one before it was critical.
- On the Mac mini, under its lock (AGENTS.md → Where tests run): `brew update`, `brew install --cask nomdelasociete/tap/skilli` (or `upgrade`), `spctl -a -vv --type execute /Applications/Skilli.app` says `source=Notarized Developer ID`, the app opens. Then `brew uninstall --cask skilli` and reopen `~/skilli-selftest/Skilli.app`: the mini's test app shares the bundle ID.
- `brew audit --cask --online nomdelasociete/tap/skilli` over SSH: unset `HTTPS_PROXY`/`HTTP_PROXY` for it (the session's proxy adds responses Homebrew counts as redirects).

Done when every check passed on the new build.

## 4. Tell the maintainer

The version and build, the release link (`https://github.com/nomdelasociete/skilli/releases/tag/v<version>-<build>`), and what changed for users. His own Mac runs the development build (no updater): deploy it as usual, separately.
