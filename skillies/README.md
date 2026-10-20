# Community skillies

This folder is the source of truth for the website's Skillies collection.
Each file is a command that skil.li can run locally. Website cards, source
previews, downloads and `catalog.json` are generated from these exact files.

## Contribute

1. Fork this repository. Add one script at `skillies/<category>/<unique-name>.sh`
   (also supported: `.py`, `.js`, `.rb`). Use lowercase hyphenated names.
2. Start with a shebang and the `@skilli` header from an existing example.
   Include `schemaVersion 1`, `title`, `description`, `packageName` and `mode`.
   Keep metadata within the first 60 lines and 8 KB, as required by the app.
3. Include the full MIT license and your copyright notice in the script, so the
   license travels with a downloaded file. Only submit code you can license.
4. Document required applications, external runtimes, network access and effects
   in the description or script comments. Do not embed credentials or personal
   paths. Use arguments for user input (up to three `@skilli.argumentN` JSON
   declarations). Set `@skilli.needsConfirmation true` for commands that change
   or delete data. This asks before the whole script; it is not a sandbox.
5. Try the script on your Mac. In skil.li, open Settings → Launcher → Skillies →
   Show in Finder and put it there. Check arguments, output and failure cases.
6. Run `python3 website/build.py --preview` from the repository root. Open a PR
   describing what you tested and any dependencies. Do not edit generated files
   under `website/skillies/files/` or the generated catalog HTML.

A maintainer reviews the code before merge. The Railway build validates metadata
and builds the site; **it does not execute contributed scripts**. Railway rebuilds the website
on relevant merges to `main` once its GitHub service is connected (see
[`website/README.md`](../website/README.md)). A new skillie needs no manual website edit.

## Act in apps, and wait for the step

A skillie can hand a goal to skil.li's "do it here", which reads the app's
window and clicks for you. skil.li runs every skillie with `SKILLI_CLI`, the
path of its own command line. A step waits until it ends, so the script can
branch on it:

```bash
if said=$("$SKILLI_CLI" call do_in_app app=TextEdit goal="exporte en PDF dans mes documents" 2>&1); then
  echo "Exported."
else
  echo "Not exported: ${said%%$'\n'*}"
fi
```

- Arguments are `name=value` words: `app` (by name, opened if needed;
  without it, the app the user was in) and `goal` (written as the user would
  ask it, the exact text to type in « »). Quote each word, so a `$1` in a
  goal stays one value.
- Exit 0: done, its steps on standard output. Exit 1: not done (stopped,
  declined, esc, no such app), why on the first line of standard error.
  Exit 2: the call is written wrong.
- Each step is asked in skil.li's card as any agent's call is, unless the
  user's tool rights allow "Do it in an app"; what sends, deletes or pays is
  asked again during the step. `needsConfirmation` replaces none of these:
  it asks before the script runs.
- 120 s for the whole script; a step it is waiting for stops with it. A step
  whose result does not matter can open
  `skilli://do?app=…&goal=…` instead: asked first, and the script does not
  wait for it.

`SKILLI_SOCKET` and `SKILLI_SKILLIE` are read by `$SKILLI_CLI` itself:
nothing to do with them. Details: [`docs/do-it-here-from-anywhere.md`](../docs/do-it-here-from-anywhere.md).

## Install

Download a script from the collection, inspect it, and put it in your local
skillies folder using Show in Finder above. The app discovers it by its header.
It does not subscribe to the online collection or automatically replace installed
scripts. Website publication and local installation are separate operations.

`skilli://commands/import` imports SI prompt files, not these scripts.
