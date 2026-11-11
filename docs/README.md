# Documentation

Where each kind of document lives, and who it is for. Start from the row
that matches what you want.

| You want to | Read | Where |
| --- | --- | --- |
| Use skil.li | The guides, one per area, with screenshots | [website/guides/](../website/guides/README.md), published at [skil.li/guides](https://skil.li/guides/) |
| Look up every feature, key and setting | Features, the reference kept complete by tests | [FEATURES.md](FEATURES.md) |
| Know why skil.li is the way it is | The manifesto | [MANIFESTO.md](MANIFESTO.md) |
| Write a skillie (a script as a command) | The skillies docs | [skillies/docs/](../skillies/docs/README.md), published at [skil.li/skillies/docs](https://skil.li/skillies/docs/) |
| Contribute a change | Contributing, then the rules every change follows | [CONTRIBUTING.md](../CONTRIBUTING.md), [AGENTS.md](../AGENTS.md) |
| Change the website | The approved design, then how it builds | [website-design.md](website-design.md), [website/README.md](../website/README.md) |
| Report a vulnerability | The security policy | [SECURITY.md](../SECURITY.md) |

The guides are for people using skil.li: plain words, what to press,
where to change it. Everything else in this folder is for people
building it.

## Design specs

How a feature was designed before it was built: the request, the
choices, the measures. Each one starts with its status and date.

| Spec | About |
| --- | --- |
| [onboarding.md](onboarding.md) | The first launch's welcome |
| [smart-layout.md](smart-layout.md) | Windows that go where you put them |
| [si-commands.md](si-commands.md) | SI commands, from rewriting text to acting |
| [ai-architecture.md](ai-architecture.md) | How skil.li talks to Claude, ChatGPT and the decision models |
| [click-what-you-see.md](click-what-you-see.md) | Do It Here in any app |
| [do-it-here-from-anywhere.md](do-it-here-from-anywhere.md) | Do It Here from links, skillies and agents |
| [apps.md](apps.md) | The apps skil.li drives, CleanShot X first |
| [gif-search.md](gif-search.md) | GIF Search |
| [snippet-preview.md](snippet-preview.md) | Search Snippets' list and preview |
| [clipboard-text-selection.md](clipboard-text-selection.md) | Clipboard History: a part of a copy picked with the pointer, an image's whole text |
| [clipboard-rows-and-search.md](clipboard-rows-and-search.md) | Clipboard History: rows say when, the header the day; search inside words, by a link's piece, by app |
| [clipboard-pins-filter-actions.md](clipboard-pins-filter-actions.md) | Clipboard History: pins, what a copy can do (open, show, mail), one kind at a time |
| [clipboard-review.md](clipboard-review.md) | Clipboard History against the other apps: what is behind, what was fixed since |
| [skillie-files.md](skillie-files.md) | `.skilli` files: double-click to add |
| [adding-a-shortcut.md](adding-a-shortcut.md) | Giving anything a shortcut |
| [meeting-recorder.md](meeting-recorder.md) | The meeting recorder |
| [meeting-recorder-views.md](meeting-recorder-views.md) | The recorder's windows, cards and menus |
| [github-single-sign-in.md](github-single-sign-in.md) | One GitHub sign-in instead of three |
| [github-sign-in-without-app.md](github-sign-in-without-app.md) | GitHub sign-in and server sync without the GitHub App |
| [github-workflow-runs.md](github-workflow-runs.md) | Start a GitHub workflow, follow it; releases without a bump pull request |
| [currency-conversion.md](currency-conversion.md) | Currencies in the calculator, at the day's rates |
| [file-search.md](file-search.md) | Search Files that finds your files, not your dependencies' |
| [launcher-app-in-front.md](launcher-app-in-front.md) | The empty launcher learns the app in front; names mistyped found |
| [launcher-row-numbers-hex.md](launcher-row-numbers-hex.md) | ⌘1–⌘9 open a row; the calculator reads hex |
| [auto-quit.md](auto-quit.md) | Auto Quit: its own pane, only the apps listed, each its own delay; self-tests keep their own settings |
| [pick-from-a-list.md](pick-from-a-list.md) | `Skilli pick`: a script's lines in the launcher, the row picked on standard output |

## Plans, reviews and lab notes

| Document | About |
| --- | --- |
| [roadmap.md](roadmap.md) | Raycast parity, then past it |
| [implementation-status.md](implementation-status.md) | What is built, phase by phase |
| [interactions-review.md](interactions-review.md) | The review behind the six interaction rules |
| [ai-engines.md](ai-engines.md) | Each SI engine measured: time, tokens, memory |
| [live-checks-2026-10-21.md](live-checks-2026-10-21.md) | Merged features tried for real on the test Mac |

## Adding a document

- **A guide** for people using skil.li: a file in `website/guides/`, its
  line in `GUIDES` in `website/build.py` and in `website/sitemap.xml`,
  and a link from the guides' [overview](../website/guides/README.md).
  Screenshots go in `website/guides/images/`
  ([how they are made](../website/guides/images/README.md)).
- **A spec** for a feature: a file here, starting with its status and
  date, and its line in the table above. When the feature ships, the
  guide for its area says how to use it, and [FEATURES.md](FEATURES.md)
  lists it.
