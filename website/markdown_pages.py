"""The Markdown the skillies docs are written in, as HTML. Python's standard library
only, like the rest of the build: headings, paragraphs, lists (nested), fenced code,
tables, inline code, bold and links. Anything else stays plain text."""
import html
import re

LIST_ITEM = re.compile(r'( *)(-|\d+\.) (.*)')
HEADING = re.compile(r'(#{1,6}) +(.*?) *#*$')
FENCE = re.compile(r'```(\w*)$')
TABLE_RULE = re.compile(r'\|? *:?-+:? *(\| *:?-+:? *)*\|?$')
CODE_SPAN = re.compile(r'(`+)(.+?)\1')
LINK = re.compile(r'\[([^\]]+)\]\(([^)\s]+)\)')
BOLD = re.compile(r'\*\*(.+?)\*\*')


def slug(text):
    """A heading's id as GitHub makes it, so links written for GitHub land here too."""
    text = re.sub(r'<[^>]+>', '', text)
    text = html.unescape(text).lower()
    return re.sub(r'[^\w\- ]', '', text).replace(' ', '-')


class Page:
    def __init__(self, link):
        # link(href) → the address this page should use for a link written in the file.
        self.link = link
        self.headings = []
        self.ids = {}

    def inline(self, text):
        spans = []

        def keep(match):
            spans.append(f'<code>{html.escape(match.group(2).strip())}</code>')
            return f'\x00{len(spans) - 1}\x00'

        text = html.escape(CODE_SPAN.sub(keep, text), quote=False)
        text = LINK.sub(lambda m: f'<a href="{html.escape(self.link(html.unescape(m.group(2))))}">{m.group(1)}</a>', text)
        text = BOLD.sub(r'<strong>\1</strong>', text)
        return re.sub('\x00(\\d+)\x00', lambda m: spans[int(m.group(1))], text)

    def heading(self, level, text):
        content = self.inline(text)
        base = slug(content)
        count = self.ids.get(base, 0)
        self.ids[base] = count + 1
        anchor = base if count == 0 else f'{base}-{count}'
        self.headings.append((level, anchor, content))
        return f'<h{level} id="{anchor}"><a class="anchor" href="#{anchor}">{content}</a></h{level}>'

    def cells(self, row):
        # Split on | outside code spans.
        parts, current, ticks = [], '', 0
        for char in row.strip().strip('|') if row.strip().startswith('|') else row.strip():
            if char == '`':
                ticks ^= 1
            if char == '|' and not ticks:
                parts.append(current)
                current = ''
            else:
                current += char
        parts.append(current)
        return [part.strip() for part in parts]

    def blocks(self, lines):
        out = []
        i = 0
        while i < len(lines):
            line = lines[i]
            if not line.strip():
                i += 1
                continue
            if line.lstrip().startswith('<!--'):
                # A note for whoever edits the file, hidden as GitHub hides it.
                while i < len(lines) and '-->' not in lines[i]:
                    i += 1
                i += 1
                continue
            if fence := FENCE.match(line.strip()):
                language = fence.group(1)
                body = []
                i += 1
                while i < len(lines) and lines[i].strip() != '```':
                    body.append(lines[i])
                    i += 1
                i += 1
                label = f' data-language="{html.escape(language)}"' if language else ''
                out.append(f'<pre{label}><code>{html.escape(chr(10).join(body))}</code></pre>')
                continue
            if heading := HEADING.match(line):
                out.append(self.heading(len(heading.group(1)), heading.group(2)))
                i += 1
                continue
            if line.lstrip().startswith('|') and i + 1 < len(lines) and TABLE_RULE.match(lines[i + 1].strip()):
                head = self.cells(line)
                rows = []
                i += 2
                while i < len(lines) and lines[i].lstrip().startswith('|'):
                    rows.append(self.cells(lines[i]))
                    i += 1
                th = ''.join(f'<th>{self.inline(c)}</th>' for c in head)
                body = ''.join('<tr>' + ''.join(f'<td>{self.inline(c)}</td>' for c in row) + '</tr>' for row in rows)
                out.append(f'<div class="table"><table><thead><tr>{th}</tr></thead><tbody>{body}</tbody></table></div>')
                continue
            if item := LIST_ITEM.match(line):
                ordered = item.group(2) != '-'
                items = []
                while i < len(lines) and (item := LIST_ITEM.match(lines[i])) and not item.group(1) and (item.group(2) != '-') == ordered:
                    width = len(item.group(2)) + 1
                    content = [item.group(3)]
                    i += 1
                    # Its lines: indented under it, blank lines included when more follows.
                    while i < len(lines):
                        if lines[i].startswith(' ' * width):
                            content.append(lines[i][width:])
                        elif not lines[i].strip() and i + 1 < len(lines) and lines[i + 1].startswith(' ' * width):
                            content.append('')
                        else:
                            break
                        i += 1
                    inner = self.blocks(content)
                    # A tight item (no blank line in it) reads as text, not paragraphs.
                    if '' not in content:
                        inner = inner.replace('<p>', '').replace('</p>', '')
                    items.append(f'<li>{inner}</li>')
                    while i < len(lines) and not lines[i].strip() and i + 1 < len(lines) and LIST_ITEM.match(lines[i + 1]):
                        i += 1
                tag = 'ol' if ordered else 'ul'
                out.append(f'<{tag}>{"".join(items)}</{tag}>')
                continue
            paragraph = []
            while i < len(lines) and lines[i].strip() and not (HEADING.match(lines[i]) or FENCE.match(lines[i].strip())
                                                             or LIST_ITEM.match(lines[i]) or lines[i].lstrip().startswith(('|', '<!--'))):
                paragraph.append(lines[i].strip())
                i += 1
            if not paragraph:
                # A line no block takes (a lone |): kept as text.
                paragraph.append(lines[i].strip())
                i += 1
            out.append(f'<p>{self.inline(" ".join(paragraph))}</p>')
        return '\n'.join(out)

    def render(self, text):
        return self.blocks(text.split('\n'))
