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
| [skillie-files.md](skillie-files.md) | `.skilli` files: double-click to add |
| [adding-a-shortcut.md](adding-a-shortcut.md) | Giving anything a shortcut |
| [meeting-recorder.md](meeting-recorder.md) | The meeting recorder |
| [meeting-recorder-views.md](meeting-recorder-views.md) | The recorder's windows, cards and menus |
| [github-single-sign-in.md](github-single-sign-in.md) | One GitHub sign-in instead of three |

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
