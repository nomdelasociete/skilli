#!/usr/bin/env python3
"""Build the static site from the repository's skillies. Never execute scripts."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import sys

# The renderer beside this file, also when the build is loaded by the tests.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from markdown_pages import Page  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SLUG = re.compile(r'[a-z0-9]+(?:-[a-z0-9]+)*')
# What macOS itself has (skillies/README.md, "What runs on every Mac").
SHIPPED = {'sh', 'bash', 'zsh', 'dash', 'osascript', 'perl', 'ruby', 'awk'}
# /usr/bin stubs that only work once Xcode's Command Line Tools are installed.
XCODE_TOOLS = {'swift', 'git'}
REQUIREMENT = re.compile(r'xcode-tools|homebrew:[a-z0-9][a-z0-9+@._-]*')


def program(code):
    """`#!/usr/bin/env python3` → ('python3', []); `#!/usr/bin/osascript -l JavaScript` →
    ('osascript', ['-l', 'JavaScript']). None without an absolute path, which skil.li needs."""
    parts = code.split('\n', 1)[0][2:].split()
    if not parts or not parts[0].startswith('/'):
        return None
    name, rest = parts[0].rsplit('/', 1)[-1], parts[1:]
    if name == 'env':
        # Its options and assignments, then the command and the command's own words.
        start = next((i for i, w in enumerate(rest) if not w.startswith('-') and '=' not in w), None)
        if start is None:
            return None
        name, rest = rest[start].rsplit('/', 1)[-1], rest[start + 1:]
    return name, rest


def requirements(name, declared):
    """What has to be installed first: its interpreter's, then what it says it calls."""
    found = []
    if name in XCODE_TOOLS or name.startswith('python'):
        found.append('xcode-tools')
    elif name not in SHIPPED:
        found.append(f'homebrew:{name}')
    for token in filter(None, (t.strip() for t in declared.split(','))):
        if not REQUIREMENT.fullmatch(token):
            raise ValueError(f'unknown requirement {token!r}: xcode-tools or homebrew:<formula>')
        if token not in found:
            found.append(token)
    return found


def needs_label(found):
    if not found:
        return 'Nothing to install'
    return 'Needs ' + ', '.join('Xcode Command Line Tools' if r == 'xcode-tools' else f'{r[9:]} from Homebrew' for r in found)


def catalog(source):
    entries = []
    seen = set()
    for path in sorted(source.glob('*/*')):
        if path.suffix not in ('.sh', '.py', '.js', '.rb', '.swift'):
            continue
        if path.is_symlink() or path.parent.is_symlink():
            raise ValueError(f'{path}: symlinks are not allowed')
        slug, category = path.stem, path.parent.name
        if not SLUG.fullmatch(slug) or not SLUG.fullmatch(category) or slug in seen:
            raise ValueError(f'{path}: invalid or duplicate slug')
        seen.add(slug)
        data = path.read_bytes()
        code = data.decode('utf-8')
        if not code.startswith('#!'):
            raise ValueError(f'{path}: missing shebang')
        runs = program(code)
        if runs is None:
            raise ValueError(f'{path}: the shebang must name an absolute path (#!/bin/sh, #!/usr/bin/env python3)')
        metadata = {}
        for line in data[:8192].decode('utf-8', errors='ignore').splitlines()[:60]:
            match = re.match(r'\s*(?:#|//)\s*@skilli\.(\w+)\s+(.+)', line)
            if match:
                key, value = match.groups()
                if key in metadata:
                    raise ValueError(f'{path}: duplicate metadata {key}')
                metadata[key] = value.strip()
        for key in ('title', 'description', 'packageName'):
            if not metadata.get(key):
                raise ValueError(f'{path}: missing @skilli.{key}')
        if metadata.get('schemaVersion') != '1' or metadata.get('mode') not in ('silent', 'compact', 'fullOutput', 'inline'):
            raise ValueError(f'{path}: unsupported schema or output mode')
        if metadata.get('needsConfirmation', 'false') not in ('true', 'false'):
            raise ValueError(f'{path}: needsConfirmation must be true or false')
        if metadata.get('showsRunning', 'true') not in ('true', 'false'):
            raise ValueError(f'{path}: showsRunning must be true or false')
        if 'MIT License' not in code or 'Permission is hereby granted' not in code or 'Copyright' not in code:
            raise ValueError(f'{path}: include the MIT license and copyright notice')
        arguments = []
        for number in range(1, 4):
            raw = metadata.get(f'argument{number}')
            if raw:
                value = json.loads(raw)
                if not isinstance(value, dict) or value.get('type') not in ('text', 'password', 'dropdown') or not isinstance(value.get('placeholder'), str) or not value['placeholder'].strip():
                    raise ValueError(f'{path}: invalid argument{number}')
                arguments.append(value['placeholder'])
        if any(k.startswith('argument') and k not in ('argument1', 'argument2', 'argument3') for k in metadata):
            raise ValueError(f'{path}: at most three arguments are supported')
        try:
            requires = requirements(runs[0], metadata.get('requires', ''))
        except ValueError as error:
            raise ValueError(f'{path}: {error}') from None
        entries.append(dict(id=slug, category=category, title=metadata['title'], description=metadata['description'],
                            package=metadata['packageName'], mode=metadata['mode'], arguments=arguments,
                            needsConfirmation=metadata.get('needsConfirmation') == 'true', requires=requires,
                            program=runs[0], arguments_of_program=runs[1], license='MIT',
                            # A .skilli file: the script itself, which skil.li opens to add it (docs/skillie-files.md).
                            download=f'files/{slug}.skilli', source=f'skillies/{category}/{path.name}',
                            sha256=hashlib.sha256(data).hexdigest(), code=code, path=path))
    if not entries:
        raise ValueError('No skillies found')
    return entries


def render(entries, template, target):
    esc = html.escape
    cards = []
    for item in entries:
        slug = item['id']
        args = ' · '.join(item['arguments']) or 'No arguments'
        if item['needsConfirmation']:
            args += ' · Asks before running'
        args += ' · ' + needs_label(item['requires'])
        language = {'.sh': 'Shell', '.py': 'Python', '.js': 'JavaScript', '.rb': 'Ruby', '.swift': 'Swift'}[item['path'].suffix]
        if item['program'] == 'osascript':
            # `osascript -l JavaScript`: the language its shebang names, AppleScript otherwise.
            flags = item['arguments_of_program']
            named = flags[flags.index('-l') + 1] if '-l' in flags[:-1] else 'AppleScript'
            language = 'JavaScript for Automation' if named == 'JavaScript' else named
        search = esc(' '.join((item['title'], item['description'], item['package'])).lower())
        cards.append(f'''<article class="skillie-entry" id="{slug}" data-category="{item['category']}" data-search="{search}">
<div class="skillie-meta">{esc(item['package'])} <span>{esc(language)} · MIT</span></div>
<h2>{esc(item['title'])}</h2><p>{esc(item['description'])}</p><p class="skillie-args">{esc(args)}</p>
<div class="skillie-actions"><a class="download-skillie" href="{item['download']}" download="{slug}.skilli">Download skillie ↓</a><button data-share="{slug}" type="button">Copy link ↗</button></div>
<details><summary>Read the code</summary><pre><code>{esc(item['code'])}</code></pre></details></article>''')
    categories = sorted(set(item['category'] for item in entries))
    filters = ''.join(f'<button data-filter="{c}" aria-pressed="false">{esc(c.replace("-", " ").title())}</button>' for c in categories)
    page = template.read_text().replace('{{FILTERS}}', filters).replace('{{COUNT}}', str(len(entries))).replace('{{CARDS}}', '\n'.join(cards))
    target.mkdir(parents=True, exist_ok=True)
    downloads = target / 'files'
    if downloads.exists():
        shutil.rmtree(downloads)
    downloads.mkdir()
    for item in entries:
        shutil.copyfile(item['path'], target / item['download'])
    (target / 'index.html').write_text(page)
    public = [{k: v for k, v in item.items() if k not in ('path', 'code', 'program', 'arguments_of_program')} for item in entries]
    (target / 'catalog.json').write_text(json.dumps({'schemaVersion': 1, 'skillies': public}, ensure_ascii=False, indent=2) + '\n')


REPOSITORY = 'https://github.com/nomdelasociete/skilli'
# The skillies docs, in their reading order: source file, page, short name in the menu.
DOCS = [('README.md', 'index.html', 'Overview'), ('header.md', 'header.html', 'Header'),
        ('running.md', 'running.html', 'How it runs'), ('calling-skilli.md', 'calling-skilli.html', 'Calling skil.li')]


def page_address(page):
    """A doc page's address from another one: the overview is the folder itself."""
    return './' if page == 'index.html' else page


def docs_link(href):
    """A link written in skillies/docs/*.md, as the page uses it: another doc → its page,
    the rest of the repository → GitHub, web addresses and anchors as they are."""
    if href.startswith(('#', 'http://', 'https://', 'mailto:')):
        return href
    path, _, anchor = href.partition('#')
    anchor = f'#{anchor}' if anchor else ''
    resolved = (ROOT / 'skillies/docs' / path).resolve()
    pages = {source: page for source, page, _ in DOCS}
    if resolved.parent == ROOT / 'skillies/docs' and resolved.name in pages:
        return page_address(pages[resolved.name]) + anchor
    relative = resolved.relative_to(ROOT).as_posix()
    if resolved.name == 'README.md':
        return f'{REPOSITORY}/tree/main/{resolved.parent.relative_to(ROOT).as_posix()}{anchor}'
    kind = 'tree' if resolved.is_dir() else 'blob'
    return f'{REPOSITORY}/{kind}/main/{relative}{anchor}'


def render_docs(template, target):
    """skillies/docs/*.md as pages: one per file, the menu of all, this page's sections."""
    esc = html.escape
    target.mkdir(parents=True, exist_ok=True)
    for index, (source, name, short) in enumerate(DOCS):
        text = (ROOT / 'skillies/docs' / source).read_text()
        page = Page(docs_link)
        content = page.render(text)
        h1 = next((h for h in page.headings if h[0] == 1), None)
        if h1 is None:
            raise ValueError(f'skillies/docs/{source}: missing # title')
        # The overview's own title is the section's ("Skillies"): its menu name says which page.
        title = short if name == 'index.html' else html.unescape(re.sub(r'<[^>]+>', '', h1[2]))
        first = re.search(r'<p>(.*?)</p>', content, re.S)
        description = re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', '', first.group(1)))).strip() if first else title
        if len(description) > 160:
            description = description[:157].rsplit(' ', 1)[0] + '…'
        current = ' aria-current="page"'
        menu = ''.join(f'<li><a href="{page_address(other)}"{current if other == name else ""}>{esc(label)}</a></li>'
                       for _, other, label in DOCS)
        sections = ''.join(f'<li class="level-{level}"><a href="#{anchor}">{label}</a></li>' for level, anchor, label in page.headings if level in (2, 3))
        steps = []
        if index > 0:
            _, before, label = DOCS[index - 1]
            steps.append(f'<a class="docs-prev" href="{page_address(before)}"><span>Previous</span>{esc(label)}</a>')
        if index + 1 < len(DOCS):
            _, after, label = DOCS[index + 1]
            steps.append(f'<a class="docs-next" href="{page_address(after)}"><span>Next</span>{esc(label)}</a>')
        canonical = 'https://skil.li/skillies/docs/' + ('' if name == 'index.html' else name)
        values = {'{{TITLE}}': esc(title), '{{DESCRIPTION}}': esc(description), '{{CANONICAL}}': canonical,
                  '{{MENU}}': menu, '{{SECTIONS}}': sections, '{{CONTENT}}': content, '{{STEPS}}': ''.join(steps),
                  '{{SOURCE}}': f'{REPOSITORY}/blob/main/skillies/docs/{source}'}
        result = template.read_text()
        for key, value in values.items():
            result = result.replace(key, value)
        (target / name).write_text(result)


def build(preview=False):
    entries = catalog(ROOT / 'skillies')
    if preview:
        target = ROOT / 'website/skillies'
    else:
        output = ROOT / 'dist/site'
        if output.exists():
            shutil.rmtree(output)
        # Publish only website assets, never Python, deployment config or font trials.
        for path in (ROOT / 'website').rglob('*'):
            relative = path.relative_to(ROOT / 'website')
            if path.is_symlink() or any(p in ('font-preview', 'experiments', '__pycache__', 'files', 'tests') for p in relative.parts):
                continue
            if path.is_file() and path.suffix in ('.html', '.css', '.js', '.png', '.jpg', '.svg', '.woff2', '.woff', '.otf', '.ttf', '.txt', '.md') and not path.name.endswith('.template.html') and path.name not in ('README.md', 'social-preview.html', 'robots.txt'):
                dest = output / relative
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, dest)
        shutil.copytree(ROOT / 'assets/brand', output / 'assets/brand', ignore=shutil.ignore_patterns('*.html', '*.md', '*.js', '*.py', '*.blend', 'versions', 'showcase'))
        for name in ('robots.txt', 'sitemap.xml'):
            shutil.copyfile(ROOT / 'website' / name, output / name)
        target = output / 'skillies'
    render(entries, ROOT / 'website/skillies/index.template.html', target)
    render_docs(ROOT / 'website/skillies/docs.template.html', target / 'docs')
    if not preview:
        (output / '_headers').write_text(
            "/*\n"
            "  Cache-Control: public, max-age=0, must-revalidate\n"
            "\n"
            "/skillies/files/*\n"
            "  Cache-Control: public, max-age=0, must-revalidate\n"
            "  Content-Disposition: attachment\n"
        )
    print(f'Built {len(entries)} skillies and {len(DOCS)} doc pages → {target}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview', action='store_true', help='Generate catalog in the local website folder')
    try:
        build(parser.parse_args().preview)
    except (ValueError, OSError) as error:
        parser.exit(1, f'Catalog build failed: {error}\n')
