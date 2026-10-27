from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
INDEX = (ROOT / 'index.html').read_text()
HERO_CSS = (ROOT / 'brand-glass' / 'hero.css').read_text()
HERO_JS = (ROOT / 'brand-glass' / 'hero.js').read_text()
SCENE_JS = (ROOT / 'brand-glass' / 'scene.js').read_text()


class LandingContracts(unittest.TestCase):
    def test_nav_targets_exist_on_the_page(self):
        for href in ('#launcher', '#speed', '#experience', 'skillies/', 'skillies/docs/', '#byok', '#questions', '#download'):
            self.assertIn(f'href="{href}"', INDEX)
        self.assertIn('id="launcher"', INDEX)
        self.assertIn('id="speed"', INDEX)
        self.assertIn('id="experience"', INDEX)
        self.assertIn('id="byok"', INDEX)
        self.assertIn('id="questions"', INDEX)
        self.assertIn('id="download"', INDEX)
        self.assertIn('How do I get it?', INDEX)
        self.assertIn('href="/download"', INDEX)
        self.assertIn('brew install --cask nomdelasociete/tap/skilli', INDEX)
        self.assertNotRegex(INDEX, r'download\.(dmg|zip|pkg)')

    def test_one_entry_for_guides_and_docs(self):
        # Guides only: the skillies docs are the last part of the guides' menu.
        nav = INDEX[INDEX.index('<nav id="site-nav"'):INDEX.index('</nav>', INDEX.index('<nav id="site-nav"'))]
        self.assertNotIn('>Docs<', nav)
        self.assertIn('id="own-commands"', INDEX)
        for page in ('index.html', 'manifesto.html', 'legal.html', 'skillies/index.template.html',
                     'skillies/docs.template.html', 'guides.template.html'):
            self.assertNotIn('>Docs</a>', (ROOT / page).read_text(), page)

    def test_the_guides_are_one_click_away(self):
        nav = INDEX[INDEX.index('<nav id="site-nav"'):INDEX.index('</nav>', INDEX.index('<nav id="site-nav"'))]
        self.assertIn('href="guides/">Guides<', nav)
        # The Windows card leads to its guide.
        card = INDEX[INDEX.index('<h3>Windows</h3>'):]
        self.assertIn('href="guides/windows.html"', card[:card.index('</article>')])
        # Every page's footer, by its own path.
        for page, href in (('index.html', 'guides/'), ('manifesto.html', 'guides/'), ('legal.html', 'guides/'),
                           ('skillies/index.template.html', '../guides/'), ('skillies/docs.template.html', '../../guides/'),
                           ('guides.template.html', './')):
            html = (ROOT / page).read_text()
            footer = html[html.index('<nav aria-label="Footer">'):]
            self.assertIn(f'<a href="{href}">Guides</a>', footer[:footer.index('</nav>')], page)

    def test_get_it_lands_on_the_download_section(self):
        section = INDEX[INDEX.index('id="download"'):]
        section = section[:section.index('</section>')]
        self.assertIn('app-icon.png', section)
        self.assertIn('href="/download"', section)
        self.assertIn('brew install --cask nomdelasociete/tap/skilli', section)
        self.assertEqual(INDEX.count('id="download"'), 1)
        self.assertTrue((ROOT.parent / 'assets' / 'brand' / 'app-icon.png').exists())

    def test_hamburger_is_accessible(self):
        self.assertIn('class="nav-menu"', INDEX)
        self.assertIn('aria-controls="site-nav"', INDEX)
        self.assertIn('aria-expanded="false"', INDEX)
        self.assertIn('id="site-nav"', INDEX)
        self.assertIn("event.key === 'Escape'", HERO_JS)
        self.assertIn('aria-expanded', HERO_JS)

    def test_hero_keeps_the_desktop_scroll_rise(self):
        self.assertIn('height:170svh', HERO_CSS)
        self.assertIn('margin-top:-65svh', HERO_CSS)
        self.assertIn('logo.scale.setScalar(0.78)', SCENE_JS)
        self.assertIn('1.18 + leave * 0.85', SCENE_JS)
        self.assertIn('innerHeight / innerWidth', SCENE_JS)
        self.assertNotIn('progress: 0', HERO_JS)
        self.assertNotIn('compact()', SCENE_JS)
        self.assertIn('antialias: true', SCENE_JS)

    def test_github_and_hamburger_live_in_the_nav(self):
        opening = INDEX.split('<main>')[0]
        self.assertNotIn('github-link', opening)
        self.assertNotIn('nav-menu', opening)
        nav = INDEX[INDEX.index('<header class="nav">'):INDEX.index('</header>')]
        self.assertIn('github-link', nav)
        self.assertIn('nav-menu', nav)
        self.assertGreater(nav.index('github-link'), nav.index('nav-end'))
        self.assertGreater(nav.index('nav-get'), nav.index('github-link'))
        self.assertNotIn('nav-get', nav[:nav.index('nav-end')])
        self.assertNotIn('api.github.com', HERO_JS)
        self.assertNotIn('opening-glass + .nav{margin-top:0', HERO_CSS)
        self.assertEqual(HERO_CSS.split('@media(max-width:700px)')[0].count('170svh'), 1)
        self.assertIn('margin-top:-65svh', HERO_CSS.split('@media(max-width:700px)')[0])

    def test_orientation_runs_in_the_scene_iframe(self):
        self.assertIn('allow="accelerometer; gyroscope"', INDEX)
        self.assertIn("type: 'logo-tilt'", HERO_JS)
        self.assertNotRegex(HERO_JS, r'requestPermission\s*\(')
        self.assertNotRegex(SCENE_JS, r'requestPermission\s*\(')
        self.assertNotIn('askOrient', HERO_JS)
        self.assertIn('deviceorientation', HERO_JS)
        self.assertNotIn('enableOrient', SCENE_JS)
        self.assertIn('deviceorientation', SCENE_JS)
        self.assertIn('tiltFromOrientation', SCENE_JS)
        self.assertIn("tiltSource = 'idle'", SCENE_JS)
        self.assertIn('iosMotionPrompt', SCENE_JS)
        self.assertNotIn('opening-glass-scene{pointer-events:none', HERO_CSS)

    def test_no_em_dashes_in_new_copy(self):
        self.assertNotIn('\u2014', INDEX)
        self.assertNotIn('\u2014', HERO_JS)


class TiltMath(unittest.TestCase):
    def test_orientation_is_clamped_to_the_desktop_range(self):
        script = ROOT / 'tests' / 'tilt_check.mjs'
        result = subprocess.run(['node', script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
