# Search Files that finds your files

Proposal and build, 2026-10-28.

**Status**: built the same day: the ranking, the places left out, cloud
drives, folder words. Asked: "in the files search, it needs to be way
smarter than now… now it also searches in gh repos in the packages
installation and such." Not built: ⇥ by meaning run on its own when no
name fits (see Moment, 4).

## Short answer

Search Files asked Spotlight for every name containing the text, kept the
first 400 Spotlight happened to return, and sorted those by date. On a
developer's Mac most of a common word's matches are someone else's files:
measured on 2026-10-28 on one Mac, "readme" matched 15 710 names in the
home folder, 15 252 of them in `node_modules`; "logo" 2 106, half in
`node_modules`, most of the rest in cloned repositories and an unzipped
WordPress theme. The 400 kept were Spotlight's order, not the user's:
their own files were often not among them at all.

Now the rows are ranked by rules on what macOS already knows, with no SI:

1. **Left out**: what a person never looks for by name: dependency
   folders (`node_modules`, `Pods`, `vendor`, `site-packages`, a
   `venv`…), anything inside a package (an app, a framework, a Photos
   library, an asset catalog), hidden folders, `~/Library`, and a code
   project's build output (`build`, `dist`, `target`…) unless opened.
2. **Behind**: files inside a code project (a folder with `.git`,
   `package.json`, `Package.swift`, `Cargo.toml`…) the user never
   opened. Typing an extension (`config.ts`) says code is wanted: no
   longer behind.
3. **First**: the name that is what was typed, then names starting with
   it, then words starting with it; files the user opened, recently
   first.
4. **Added**: Google Drive, Dropbox, OneDrive and iCloud Drive
   (`~/Library/CloudStorage`, `~/Library/Mobile Documents`), left out
   until now with the rest of `~/Library`, shown as "Google Drive/…",
   "iCloud Drive/…".
5. **Folder words**: "martin invoice" finds `Clients/Margot Martin/
   Invoice.pdf`: every word in the name or in a folder above it, one at
   least in the name.

The same rules clean what ⇥ (by meaning) chooses among: Jev or Decisions
no longer receive `node_modules` names, and see cloud files.

## Moment

1. **When**: (a) the user remembers a name or part of one ("facture
   edf", "logo"): most searches; (b) they remember where it is and what it
   is ("martin invoice"); (c) they remember what it was about, not its
   name ("mon bail").
2. **The path**: `f ` (or Search Files) in the launcher, as before. No new
   key, no new setting.
3. **Hint or push**: nothing new is shown. The rows are better; the
   header and the ⇥ hint stay as they were.
4. **Deterministic or AI**: (a) and (b) are code: Spotlight's index, the
   path, the user's own "last opened" date (`kMDItemLastUsedDate`, set
   when a file is opened from Finder or an app): which files are someone
   else's is a fact of the path, not a judgment, and every keystroke has
   to answer in a few hundred milliseconds. (c) is a judgment: Jev or
   Decisions on ⇥, the user's action, as the setting and Settings →
   Privacy say ("Search files by meaning with ⇥"). What ⇥ sends: the
   request, and for up to 240 candidates (the cleaned name matches, then
   files opened in 90 days, then documents changed this week, cloud
   drives' included) each one's name, kind, folder and modified date;
   never a file's content. Running it on its own
   when no name fits would send file names without a key pressed: not
   done; to be decided with the setting's wording if wanted.
5. **Wrong**: a file left out that was wanted (a README in a dependency
   the user is reading): Finder's own search still finds it, and once
   opened from there it is "used" and comes back for build output (not
   for dependency folders: they stay out). A wrong order costs a ↓.

## Measures

One Mac's home folder (≈ 1 M files, three cloned monorepos, a Google
Drive), 2026-10-28, warm Spotlight, the whole search: queries, filter,
order.

| Typed | Before | Now | Before, first rows | Now, first rows |
| --- | --- | --- | --- | --- |
| invoice | 422 ms | 121 ms | an Android build's test reports | the invoices (PDFs, a folder) |
| facture | 448 ms | 132 ms | invoices | invoices, cloud drive's too |
| logo | 139 ms | 194 ms | `next-logo.d.ts` in `node_modules`, `logo.tsx`, built chunks | logo files and folders |
| readme | 188 ms | 382 ms | READMEs of the repositories being worked on | the same, a cloud one first |
| png | 241 ms | 729 ms | — | — |

A word many names hold costs more now: every match is gathered (up to
6 000, was 400) so that the order is skil.li's, not Spotlight's. Words'
starts (`"x*"cdw`) are Spotlight's word index, ≈ 3× faster than the
substring query (129 ms against 389 ms for "facture"), which only runs
when fewer than 15 files fit. Dates and kind come with the results
(value-list attributes): read one by one, a common word's dates took
seconds. Reading each path to filter it costs ≈ 7 µs; the project
lookups 20–100 ms the first time, nothing after.

## Where it lives

- `SkilliCore/FileRanking.swift`: the rules, path in, decision out:
  `exclusion`, `projectMarkers`, `isBuildOutput`, `score`, `matchesFolderWords`,
  `isCodeQuery`; tested in `FileRankingTests`.
- `FileSearch.swift`: the Spotlight queries, the project roots (one
  look per folder, kept while skil.li runs), the order.
- `FileMeaning.folder`: cloud folders read as "Google Drive/…".
