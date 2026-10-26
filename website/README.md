# Website and Skillies publishing

For website design, copy, demos, navigation or social assets, read the
[approved design decisions](../docs/website-design.md) before editing.

The native app and static website share the repository, not their build pipeline.
Website changes use Python, JavaScript syntax checks and the static server image.
Do not run Swift tests, app benchmarks or native self-tests for website-only work.

## Local preview

From the repository root:

```sh
python3 website/build.py --preview
python3 -m http.server 8770 --bind 127.0.0.1
```

Open http://127.0.0.1:8770/website/. Re-run the generator after editing a skillie.
`skillies/` is canonical; `website/skillies/index.template.html` controls layout.
Generated HTML, JSON and download copies are ignored by Git.

The skillies docs at `/skillies/docs/` are generated the same way from
`skillies/docs/*.md` (`render_docs` in `build.py`, the Markdown subset in
`markdown_pages.py`: headings, lists, fenced code, tables, inline code, bold,
links). Layout: `website/skillies/docs.template.html` and `docs.css`. Edit the
Markdown, never the generated pages. A new file there needs its line in `DOCS`
(`website/tests/test_docs.py` says so). Links to another doc become links to
its page; links to the rest of the repository go to GitHub. A
`<!-- … -->` block is a note for maintainers, left out of the page.

## Build and checks

```sh
python3 website/build.py
```

For catalog-generator changes, also run
`python3 -m unittest discover -s website/tests`. Check changed JavaScript with
`node --check` and verify affected interactions in the browser. Documentation-only
changes need no application tests.

Output: `dist/site`. This includes the landing page, catalog, fonts and brand
assets. Restricted local font trials are excluded. The public JSON catalog at
`/website/skillies/catalog.json` has stable IDs, metadata (with `requires`: what
to install first, `xcode-tools` or `homebrew:<formula>`), relative download URLs
and SHA-256 hashes. It is available for future consumers; the native app does
not currently fetch it.

## Cloudflare

Live at **https://skil.li**. The Worker `skilli-website`
(`website/wrangler.jsonc`) serves the static build. `skil.li` is that Worker's
custom domain. There is no database, no tracking endpoint, and no execution of
submitted skillies.

A merge to `main` publishes when it changes `website/`, `skillies/` or
`assets/brand/`. Workers Builds on `skilli-website` runs
`python3 website/build.py`, then
`npx wrangler@4.151.3 deploy --config website/wrangler.jsonc`, from the
repository root. No GitHub Action publishes the site. Preview branches do not
publish. Other commits on `main` do not publish.

The same commands publish by hand before that merge, or when Builds is down:

```sh
python3 website/build.py
python3 -m unittest discover -s website/tests
node --test website/tests/worker.test.mjs
npx wrangler@4.151.3 deploy --config website/wrangler.jsonc
```

`CLOUDFLARE_API_TOKEN` is required for a non-interactive deploy from a machine.
It stays out of the repository. Workers Builds uses its own token, also kept
out of the repository. The account id is in `wrangler.jsonc`.

`website/worker.mjs` keeps the routes the site already had:

- `/download` redirects (302) to the latest DMG on GitHub.
- `/appcast.xml` redirects (302) to the latest Sparkle feed.
- `/website` and `/website/…` redirect (301) to the same path at the root, query kept.
- `/health` answers `ok`.
- `/skillies/files/*` is served as a download (`Content-Disposition: attachment`).
- Responses send `Cache-Control: public, max-age=0, must-revalidate`.

Python validates metadata and builds the catalog, then the Worker serves only
the files in `dist/site`. Check the live site after the build finishes, whether
Builds ran it or you did. A local build is not proof of deployment.

## Motion and performance copy

Counters and speed particles use self-hosted Motion 14.1.0 (`assets/vendor/`),
from the official npm `motion` package; its MIT license is included. No CDN
request is made. The email demo streams scripted chunks, not a live AI response
or a timing benchmark.

Displayed metrics: launcher ~7 ms and idle ~26 MB from the Release benchmark on
the Mac mini (`./script/build_and_run.sh remote-benchmark`, 2026-10-16: show
median 7.11 ms, p95 9.93 ms over 39 shows; memory idle 25.91 MB, 29.22 MB after
use); before, 10.06 ms and 32.61 MB. AI first word 0.50–0.70 s over four warm
Claude Code runs recorded in `docs/ai-engines.md` (2026-10-11). This is not an
all-model or all-request latency guarantee. Update the copy when measurements
change.

## Search and social previews

Production origin: `https://skil.li`. The landing page and Skillies collection
have separate descriptions, canonical URLs, Open Graph and X card metadata,
and JSON-LD (SoftwareApplication and CollectionPage). Public URLs use the domain root;
The Worker redirects old `/website/…` links to the root paths. The custom domain is `skil.li`.
Public social crawlers cannot access the localhost preview.

`assets/social-preview-v4.jpg` is the shared 1200 × 630 social image. Its editable
source is `social-preview.html`, using the site's Three.js v4 logo (frost 0.1), frozen mint halo and
licensed fonts. Capture that page at a CSS viewport of 1200 × 630 with fonts
loaded; check the exported image dimensions, since browser zoom can change the capture size.
The source page is excluded from the production build.

The build publishes `robots.txt` and `sitemap.xml` at the domain root. The sitemap
contains the landing page, Skillies collection, the skillies docs and legal
page, not downloads or development previews. No tracking,
analytics or external font requests are added. If the domain or paths change,
update the canonical URLs in all page heads, social metadata and sitemap/robots
files together.

To preview the production URL layout, run `python3 website/build.py`, then
`python3 -m http.server 8771 --directory dist/site --bind 127.0.0.1` and open
`http://127.0.0.1:8771/`. The repository preview above still uses `/website/`.

Social preview v4 uses a new filename to refresh social caches. Keep the old
PNG available for previously cached shares. The JPEG is 1200 × 630; update
Open Graph, X and JSON-LD together when changing its public URL.
