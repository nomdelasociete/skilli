import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('site_build', Path(__file__).parents[1] / 'build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.source = self.root / 'skillies'
        self.path = self.source / 'everyday/week-number.sh'
        self.path.parent.mkdir(parents=True)
        self.path.write_bytes((build.ROOT / 'skillies/everyday/week-number.sh').read_bytes())

    def test_download_and_manifest_match_original_and_remove_old_files(self):
        target = self.root / 'out'
        target.mkdir()
        (target / 'files').mkdir()
        (target / 'files/removed.sh').write_text('old')
        entries = build.catalog(self.source)
        build.render(entries, build.ROOT / 'website/skillies/index.template.html', target)
        self.assertEqual((target / 'files/week-number.sh').read_bytes(), self.path.read_bytes())
        self.assertFalse((target / 'files/removed.sh').exists())
        self.assertIn(entries[0]['sha256'], (target / 'catalog.json').read_text())
        self.assertNotIn('{{', (target / 'index.html').read_text())

    def test_contributor_content_is_escaped(self):
        text = self.path.read_text().replace('Show the current ISO week number.', '<script>alert("x")</script>')
        self.path.write_text(text)
        target = self.root / 'out'
        build.render(build.catalog(self.source), build.ROOT / 'website/skillies/index.template.html', target)
        html = (target / 'index.html').read_text()
        self.assertNotIn('<script>alert', html)
        self.assertIn('&lt;script&gt;', html)

    def test_invalid_metadata_and_duplicate_ids_fail(self):
        original = self.path.read_text()
        for old, new in [('@skilli.title', '@skilli.wrong'), ('@skilli.mode compact', '@skilli.mode unknown'), ('MIT License', 'No license')]:
            with self.subTest(old=old):
                self.path.write_text(original.replace(old, new))
                with self.assertRaises(ValueError):
                    build.catalog(self.source)
        self.path.write_text(original)
        other = self.source / 'developer/week-number.sh'
        other.parent.mkdir()
        other.write_text(original)
        with self.assertRaisesRegex(ValueError, 'duplicate slug'):
            build.catalog(self.source)

    def test_symlinks_fail(self):
        self.path.unlink()
        self.path.symlink_to(build.ROOT / 'skillies/everyday/week-number.sh')
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            build.catalog(self.source)
