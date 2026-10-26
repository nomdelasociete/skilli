# Skillie files: double-click to add

Proposal, 2026-10-25 (asked: "Skillies should have a file format like
.skilli so you can double-click them to install them automatically").

**Status**: phase 1 built the same day: `.skilli` files and
`skilli://skillies/import?url=…`, both through one sheet in Settings →
Skillies. Not built yet: the website's files as `.skilli` and its "Add to
skil.li" button (phase 2, once phase 1 was tried), sharing a skillie from
skil.li as a `.skilli` file, a diff when one replaces another.

## Short answer

A `.skilli` file is a skillie, renamed: the very script, its shebang and
`@skilli` header, as plain text. No archive, no bundle: Quick Look,
GitHub and any editor still show what it runs, so "read it before adding
it" stays true. skil.li owns the extension. Double-clicking one (or
dropping it on skil.li in the Dock, or Open With) opens Settings →
Skillies on a sheet that shows it whole: what it is, where it came from,
every line of its code. ↩ adds it, esc does not. Nothing runs on add.

"Automatically" stops at that sheet. A skillie is code that runs as the
user, with their files and apps (`needsConfirmation` asks before a run; it
is not a sandbox). A file that installed itself on a double-click would
make every shared `.skilli` a way in. Apps and commands already work this
way (`skilli://apps/import`, `skilli://commands/import`: shown whole, then
Add); skillies join them.

## Moment

1. **When.**
   - *Found on the website or GitHub*: the user clicked Download, the file
     is in the browser's downloads bar or in Downloads. Today they must
     find skil.li's hidden folder (Settings → Skillies → Show in Finder)
     and drag the file in: the step most people stop at.
   - *Sent by someone*: AirDrop, Messages, Slack, mail. Today it is a `.sh`,
     and a double-click opens Terminal or Xcode: the wrong app, which may
     even run it.
   - *A link on a page* (`skilli://skillies/import?url=…`): the website's
     "Add to skil.li" in phase 2, or anyone's page or README.
   - *Not*: writing one's own skillie (the folder, or `create_skillie`),
     Raycast's scripts (their import), agents.
2. **The path.** The double-click the user already does on a downloaded or
   received file, or the link they click. skil.li comes forward on Settings
   → Skillies with the sheet; ↩ adds. Several files at once: one sheet with
   each.
3. **Hint or push.** Neither. Opening the file is the user's own act; the
   sheet is the answer. Added: the sheet closes and the skillie is in the
   pane's list, nothing announced (MANIFESTO 8). Finder names the kind
   ("skil.li Skillie") and the icon says which app opens it: nothing to
   teach. A file that is not a skillie says why in the sheet, in words
   (rule 6).
4. **Deterministic or AI.** Code only: the header is read as the skillie
   folder reads it (`ScriptCommand.parse` on the first 8 KB), the
   interpreter from the shebang, the source from the file's own download
   record (macOS's "Where from", the site it was downloaded from). No SI:
   whether to trust a script is the user's call, and a model saying "looks
   safe" would be the wrong comfort. Nothing leaves the Mac for a file; a
   link's `url=` is downloaded once from the https address it names, no
   cookies, as `apps/import` does.
5. **Wrong.**
   - *A harmful script added*: it does nothing until run, from the
     launcher, a key, Ask or an agent; but an inline one with no argument
     runs each time the launcher opens (its line is read then), and its
     card says so. The sheet says what a skillie can do, shows every line
     and where it came from before Add. Removed as any
     skillie: its file, Settings → Skillies → Show in Finder.
   - *A skillie replaced by mistake*: one with the same title as one the
     user has replaces it, in place (its keys, menu bar line and learning
     follow its path). The sheet says "Replaces your …" and the button says
     Replace: overwriting is asked (rule 1). The same text again: "Already
     in your skillies", nothing to add.
   - *Not a skillie* (no title or mode in its header, no shebang, not text,
     too large): said in the sheet, nothing to add.

## The file

- Extension `.skilli`; type `com.nomdelasociete.skilli.skillie`, exported
  by skil.li (`UTExportedTypeDeclarations`), conforming to
  `public.plain-text` so Quick Look shows the code; skil.li is its owner
  (`CFBundleDocumentTypes`, `LSHandlerRank` Owner, role Viewer).
- Content: a skillie as the folder takes it (docs/skillies/header.md). Checked
  as the folder will read it: UTF-8, 256 KB at most, a `#!` line naming an
  absolute interpreter (skil.li runs a skillie by its shebang when it is
  not executable), title and mode in the first 60 lines within 8 KB,
  schemaVersion 1.
- Added as `<name>.<ext>` in the skillies folder, executable: the file's
  own name without `.skilli` (a link's: the last part of its address), in
  lowercase words joined by hyphens; the extension from the shebang (bash,
  sh, zsh → `sh`, python → `py`, node → `js`, swift, ruby → `rb`,
  osascript → `js` with `-l JavaScript`, `applescript` otherwise; another
  interpreter: none). A name another skillie has becomes `name-2`.

## The link

`skilli://skillies/import?url=https://…` (repeatable, 10 at most): each address
downloaded (https only, 256 KB at most, 15 s, ephemeral session), then the
same sheet, "from example.com". A link alone adds nothing.

## Phase 2 (not built)

- The website's downloads as `<name>.skilli` and its main button "Add to
  skil.li" (`skilli://skillies/import?url=…`), download kept beside it.
  Waits until phase 1 was tried.
- ⌘K → Share on a skillie: the file as `.skilli`, or its link.
- Replace shows what changed, line by line.
