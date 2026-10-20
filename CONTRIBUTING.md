# Contributing to skil.li

Every contribution is welcome: a bug report, an idea, a skillie, a fix, a
feature. This page says how to make yours land.

## Start with an issue

Open an issue before you write code, and say what you want to change and
why. skil.li is opinionated: agreeing on the *what* first means your time
goes into a change that will be merged. A typo or an obvious one-line fix
can go straight to a pull request.

- **A bug:** what you did, what happened, what you expected, your macOS and
  skil.li version (Settings → About → Copy Diagnostics).
- **An idea:** the problem first, then the change you have in mind.

## The bar every change meets

1. **[The manifesto](docs/MANIFESTO.md).** Every feature answers to it: one
   key away, fast, your typing stays yours, undo rather than questions, quiet
   once taught, nothing leaves the Mac unless listed.
2. **[AGENTS.md](AGENTS.md).** The rules behind it: speed budgets, how keys
   and cards behave, the Settings layout, the words the app uses. It is
   written for coding agents and for people alike; read the parts your
   change touches.

## Making the change

1. Fork, then branch from `main`. One change per pull request.
2. Build with your own Apple team (from Xcode → Settings → Accounts):

   ```sh
   SKILLI_TEAM=<your team ID> ./script/build_and_run.sh run
   ```

   Requires macOS 26, Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
3. Match the code around yours: Swift 6, the same naming, comments that say
   why. Logic that can be tested without the app goes in `SkilliCore`, with
   unit tests.
4. Test:
   - `./script/build_and_run.sh test`: the unit tests pass.
   - `SKILLI_LOCAL_UI=1 ./script/build_and_run.sh selftest <scope>`: the real
     app, driven end to end (the scopes are listed in
     `Sources/Skilli/Support/SelfTest.swift`). It takes over the keyboard and
     the screen and needs Accessibility for your build: run it on a Mac or a
     user account nobody is using at the time.
   - A change to the launcher or anything on a keystroke's path:
     `SKILLI_LOCAL_UI=1 ./script/build_and_run.sh benchmark`, and give the
     numbers in the pull request.
5. Keep the docs true in the same change: a feature in
   [docs/FEATURES.md](docs/FEATURES.md) (a test checks it), a rule or a
   behaviour in AGENTS.md.
6. Open the pull request: what it changes, why, the issue it closes, and how
   you tested it.

## A few rules

- **Privacy.** No telemetry. Anything new that sends data to a provider is
  listed in Settings → Privacy, with its switch.
- **Test data is invented.** Made-up people at made-up companies,
  `example.com` addresses, fake keys. Never a real name, address or secret.
- **Words in the app.** The interface says *SI* (it reveals *AI* under the
  pointer) and *Hyper Key* (✦). A success the user sees is not announced.

## Sharing a skillie

A skillie is a script that becomes a command in skil.li. Add yours to
[`skillies/`](skillies/README.md) in a pull request; it then appears in the
website's catalog.

## License

skil.li is under the [GNU GPL v3.0](LICENSE). By contributing, you agree
that your contribution is licensed under it too.

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).
Security issues: [SECURITY.md](SECURITY.md), never a public issue.
