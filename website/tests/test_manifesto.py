"""The manifesto page says exactly what docs/MANIFESTO.md says: same
statement, same principles, same words, same order."""

from html import unescape
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PAGE = (ROOT / 'manifesto.html').read_text()
SOURCE = (ROOT.parent / 'docs' / 'MANIFESTO.md').read_text()


def text(html):
    return re.sub(r'\s+', ' ', unescape(re.sub(r'<[^>]+>', '', html))).strip()


def plain(markdown):
    return re.sub(r'\s+', ' ', markdown.replace('**', '')).strip()


class ManifestoPage(unittest.TestCase):
    def test_statement_and_lead_match(self):
        statement = re.search(r'^\*\*(.+?)\*\*$', SOURCE, re.M).group(1)
        self.assertEqual(text(re.search(r'<h1>(.*?)</h1>', PAGE, re.S).group(1)), statement)
        lead = SOURCE.split(f'**{statement}**', 1)[1].split('\n1.', 1)[0]
        self.assertEqual(text(re.search(r'class="manifesto-lead">(.*?)</p>', PAGE, re.S).group(1)), plain(lead))

    def test_every_principle_matches_in_order(self):
        source = [(plain(title), plain(body)) for title, body in
                  re.findall(r'^\d+\. \*\*(.+?)\*\*(.*?)(?=^\d+\. |^What skil\.li does|\Z)', SOURCE, re.M | re.S)]
        page = [(text(title), text(body)) for title, body in
                re.findall(r'<li><span class="principle-number"[^>]*>\d+</span><div><h2>(.*?)</h2><p>(.*?)</p></div></li>', PAGE, re.S)]
        self.assertGreater(len(source), 0)
        self.assertEqual(page, source)

    def test_numbers_follow_each_other(self):
        numbers = re.findall(r'class="principle-number"[^>]*>(\d+)<', PAGE)
        self.assertEqual(numbers, [f'{n:02d}' for n in range(1, len(numbers) + 1)])


if __name__ == '__main__':
    unittest.main()
