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

## Install

Download a script from the collection, inspect it, and put it in your local
skillies folder using Show in Finder above. The app discovers it by its header.
It does not subscribe to the online collection or automatically replace installed
scripts. Website publication and local installation are separate operations.

`skilli://commands/import` imports SI prompt files, not these scripts.
