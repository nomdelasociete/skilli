#!/usr/bin/env python3
"""Build the static site from the repository's skillies. Never execute scripts."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
SLUG = re.compile(r'[a-z0-9]+(?:-[a-z0-9]+)*')


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
        entries.append(dict(id=slug, category=category, title=metadata['title'], description=metadata['description'],
                            package=metadata['packageName'], mode=metadata['mode'], arguments=arguments,
                            needsConfirmation=metadata.get('needsConfirmation') == 'true', license='MIT',
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
        language = {'.sh': 'Shell', '.py': 'Python', '.js': 'JavaScript', '.rb': 'Ruby', '.swift': 'Swift'}[item['path'].suffix]
        search = esc(' '.join((item['title'], item['description'], item['package'])).lower())
        cards.append(f'''<article class="skillie-entry" id="{slug}" data-category="{item['category']}" data-search="{search}">
<div class="skillie-meta">{esc(item['package'])} <span>{language} · MIT</span></div>
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
    public = [{k: v for k, v in item.items() if k not in ('path', 'code')} for item in entries]
    (target / 'catalog.json').write_text(json.dumps({'schemaVersion': 1, 'skillies': public}, ensure_ascii=False, indent=2) + '\n')


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
    if not preview:
        (output / '_headers').write_text(
            "/*\n"
            "  Cache-Control: public, max-age=0, must-revalidate\n"
            "\n"
            "/skillies/files/*\n"
            "  Cache-Control: public, max-age=0, must-revalidate\n"
            "  Content-Disposition: attachment\n"
        )
    print(f'Built {len(entries)} skillies → {target}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview', action='store_true', help='Generate catalog in the local website folder')
    try:
        build(parser.parse_args().preview)
    except (ValueError, OSError) as error:
        parser.exit(1, f'Catalog build failed: {error}\n')
