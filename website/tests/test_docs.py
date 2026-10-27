"""The skillies docs on the site: skillies/docs/*.md, each as a page, every
link between them landing on a page and a heading that exist."""
import importlib.util
from pathlib import Path
import re
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('site_build', Path(__file__).parents[1] / 'build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
Page = build.Page


def render(text):
    return Page(lambda href: href).render(text)


class DocsPages(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        scratch = tempfile.TemporaryDirectory()
        cls.addClassCleanup(scratch.cleanup)
        cls.target = Path(scratch.name)
        build.render_docs(build.ROOT / 'website/skillies/docs.template.html', cls.target)
        cls.pages = {path.name: path.read_text(encoding='utf-8') for path in cls.target.glob('*.html')}

    def test_every_markdown_file_has_its_page(self):
        sources = sorted(path.name for path in (build.ROOT / 'skillies/docs').glob('*.md'))
        self.assertEqual(sorted(source for source, _, _ in build.DOCS), sources, 'add each file to DOCS in website/build.py')
        self.assertEqual(sorted(self.pages), sorted(page for _, page, _ in build.DOCS))

    def test_links_between_pages_land_on_a_heading(self):
        ids = {name: set(re.findall(r'id="([^"]+)"', html)) for name, html in self.pages.items()}
        for name, html in self.pages.items():
            article = html[html.index('<article'):html.index('</article>')]
            for href in re.findall(r'href="([^"]+)"', article):
                if href.startswith(('http', 'mailto:')):
                    continue
                page, _, anchor = href.partition('#')
                page = 'index.html' if page == './' else page or name
                self.assertIn(page, self.pages, f'{name}: {href}')
                if anchor:
                    self.assertIn(anchor, ids[page], f'{name}: {href}')

    def test_repository_links_go_to_github(self):
        index = self.pages['index.html']
        self.assertIn('href="https://github.com/nomdelasociete/skilli/tree/main/skillies"', index)
        relative = [href for html in self.pages.values() for href in re.findall(r'href="([^"]+)"', html) if not href.startswith('http')]
        self.assertEqual([href for href in relative if '.md' in href], [])

    def test_each_page_names_itself_and_marks_where_it_is(self):
        for _, page, label in build.DOCS:
            html = self.pages[page]
            self.assertRegex(html, r'<title>[^<|]+ \| Skillies docs \| skil.li</title>')
            self.assertIn(f' aria-current="page">{label}</a>', html)
            self.assertNotIn('{{', html)

    def test_no_em_dashes(self):
        for name, html in self.pages.items():
            self.assertNotIn('—', html, name)


class GuidesPages(unittest.TestCase):
    """The guides to skil.li's features: website/guides/*.md, the same way."""

    @classmethod
    def setUpClass(cls):
        scratch = tempfile.TemporaryDirectory()
        cls.addClassCleanup(scratch.cleanup)
        cls.target = Path(scratch.name)
        build.render_docs(build.ROOT / 'website/guides.template.html', cls.target, book='guides')
        cls.pages = {path.name: path.read_text(encoding='utf-8') for path in cls.target.glob('*.html')}

    def test_every_markdown_file_has_its_page(self):
        sources = sorted(path.name for path in (build.ROOT / 'website/guides').glob('*.md'))
        self.assertEqual(sorted(source for source, _, _ in build.GUIDES), sources, 'add each file to GUIDES in website/build.py')
        self.assertEqual(sorted(self.pages), sorted(page for _, page, _ in build.GUIDES))

    def test_links_land_on_a_page_and_a_heading(self):
        ids = {name: set(re.findall(r'id="([^"]+)"', html)) for name, html in self.pages.items()}
        docs = {page for _, page, _ in build.DOCS}
        for name, html in self.pages.items():
            article = html[html.index('<article'):html.index('</article>')]
            for href in re.findall(r'href="([^"]+)"', article):
                if href.startswith(('http', 'mailto:')):
                    continue
                page, _, anchor = href.partition('#')
                # A page of the skillies docs, from /guides/.
                if page.startswith('../skillies/docs/'):
                    self.assertIn(page.removeprefix('../skillies/docs/') or 'index.html', docs, f'{name}: {href}')
                    continue
                page = 'index.html' if page == './' else page or name
                self.assertIn(page, self.pages, f'{name}: {href}')
                if anchor:
                    self.assertIn(anchor, ids[page], f'{name}: {href}')

    def test_each_page_names_itself_and_marks_where_it_is(self):
        for _, page, label in build.GUIDES:
            html = self.pages[page]
            self.assertRegex(html, r'<title>[^<|]+ \| Guides \| skil.li</title>')
            self.assertIn(f' aria-current="page">{label}</a>', html)
            self.assertIn('<a href="./" aria-current="true">Guides</a>', html)
            self.assertNotIn('{{', html)
            self.assertNotIn('—', html, page)

    def test_the_menu_is_in_parts(self):
        menu = self.pages['index.html'].split('class="docs-menu">', 1)[1].split('</ul>', 1)[0]
        parts = re.findall(r'docs-menu-part">([^<]+)<', menu)
        self.assertEqual(parts, list(build.MENU_PARTS['guides'].values()))
        self.assertLess(menu.index('Start here'), menu.index('>Getting started<'))

    def test_pictures_are_in_the_book_and_copied(self):
        for name, html in self.pages.items():
            for src in re.findall(r'<(?:img|video|source)[^>]+(?:src|srcset)="([^"]+)"', html):
                self.assertTrue((self.target / src).is_file(), f'{name}: {src}')

    def test_the_windows_guide_says_how_to_undo(self):
        windows = self.pages['windows.html']
        for words in ('Run it again within 10 seconds', '✦W R', 'off by default', 'Nothing leaves your Mac'):
            self.assertIn(words, windows)


class Markdown(unittest.TestCase):
    def test_nested_lists_and_code_inside_items(self):
        html = render('1. **One.**\n   - a\n   - b\n2. Two:\n\n   ```bash\n   echo "<hi>"\n   ```\n')
        self.assertEqual(html, '<ol><li><strong>One.</strong>\n<ul><li>a</li><li>b</li></ul></li>'
                               '<li><p>Two:</p>\n<pre data-language="bash"><code>echo &quot;&lt;hi&gt;&quot;</code></pre></li></ol>')

    def test_a_fence_closes_with_as_many_backticks_or_more(self):
        html = render('```\n``\ncode\n````\n\n## After\n')
        self.assertEqual(html, '<pre><code>``\ncode</code></pre>\n<h2 id="after"><a class="anchor" href="#after">After</a></h2>')
        html = render('````md\n```\ninside\n```\n````\n')
        self.assertEqual(html, '<pre data-language="md"><code>```\ninside\n```</code></pre>')

    def test_preview_pages_are_not_published(self):
        stale = build.ROOT / 'website/skillies/docs/removed.html'
        stale.parent.mkdir(parents=True, exist_ok=True)
        stale.write_text('old')
        self.addCleanup(stale.unlink)
        build.build()
        self.assertFalse((build.ROOT / 'dist/site/skillies/docs/removed.html').exists())
        self.assertTrue((build.ROOT / 'dist/site/skillies/docs/index.html').exists())

    def test_tables_keep_pipes_inside_code(self):
        html = render('| Key | Value |\n| --- | --- |\n| `a|b` | **x** |\n')
        self.assertIn('<td><code>a|b</code></td><td><strong>x</strong></td>', html)

    def test_headings_get_githubs_ids(self):
        page = Page(lambda href: href)
        page.render("## Use skil.li's other features\n## `\"$SKILLI_CLI\" call`\n## Modes\n## Modes\n")
        self.assertEqual([anchor for _, anchor, _ in page.headings],
                         ['use-skillis-other-features', 'skilli_cli-call', 'modes', 'modes-1'])

    def test_notes_for_maintainers_stay_out(self):
        self.assertEqual(render('Before.\n\n<!-- Maintainers: change\nthis too. -->\n\nAfter.'), '<p>Before.</p>\n<p>After.</p>')

    def test_an_image_alone_is_a_figure_and_mp4_a_video(self):
        html = render('![The launcher](images/a.png "Type, then ↩.")\n\nSee ![x](i.png) here.\n\n![A clip](v.mp4)')
        self.assertEqual(html, '<figure><img src="images/a.png" alt="The launcher" loading="lazy"><figcaption>Type, then ↩.</figcaption></figure>\n'
                               '<p>See <img src="i.png" alt="x" loading="lazy"> here.</p>\n'
                               '<figure><video src="v.mp4" autoplay loop muted playsinline aria-label="A clip"></video></figure>')

    def test_images_on_lines_in_a_row_are_a_figure_each(self):
        html = render('![A](a.png "One")\n![B](b.png "Two")')
        self.assertEqual(html, '<figure><img src="a.png" alt="A" loading="lazy"><figcaption>One</figcaption></figure>\n'
                               '<figure><img src="b.png" alt="B" loading="lazy"><figcaption>Two</figcaption></figure>')

    def test_symlinks_in_images_are_not_published(self):
        images = build.ROOT / 'website/guides/images'
        link = images / 'outside.png'
        link.symlink_to(build.ROOT / 'website/assets/launcher.png')
        self.addCleanup(link.unlink)
        with tempfile.TemporaryDirectory() as scratch:
            build.render_docs(build.ROOT / 'website/guides.template.html', Path(scratch), book='guides')
            self.assertTrue((Path(scratch) / 'images/welcome.png').is_file())
            self.assertFalse((Path(scratch) / 'images/outside.png').exists())

    def test_a_picture_that_is_a_symlink_stops_the_build(self):
        link = build.ROOT / 'website/guides/images/linked.png'
        link.symlink_to('welcome.png')
        self.addCleanup(link.unlink)
        with self.assertRaises(ValueError):
            build.docs_asset('images/linked.png', 'guides')

    def test_a_dark_twin_shows_in_dark_mode(self):
        page = Page(lambda href: href, lambda src: {'src': src, 'dark': 'a-dark.png', 'size': (400, 300)})
        self.assertEqual(page.render('![A](a.png)'),
                         '<figure><picture><source srcset="a-dark.png" media="(prefers-color-scheme: dark)">'
                         '<img src="a.png" alt="A" width="400" height="300" loading="lazy"></picture></figure>')

    def test_a_missing_picture_stops_the_build(self):
        with self.assertRaises(ValueError):
            build.docs_asset('images/none.png', 'guides')

    def test_italics_leave_lone_stars_alone(self):
        self.assertEqual(render('Turn on *Usual places*: 2 * 3, `a*b*`.'),
                         '<p>Turn on <em>Usual places</em>: 2 * 3, <code>a*b*</code>.</p>')

    def test_text_is_escaped_and_links_rewritten(self):
        html = Page(lambda href: href.replace('.md', '.html')).render('See [the <header>](header.md#keys) & `<tool>`.')
        self.assertEqual(html, '<p>See <a href="header.html#keys">the &lt;header&gt;</a> &amp; <code>&lt;tool&gt;</code>.</p>')


if __name__ == '__main__':
    unittest.main()
