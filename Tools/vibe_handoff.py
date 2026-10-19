#!/usr/bin/env python3
"""Deterministic current-state section for Vibe Coding handoffs.

No commits, pushes, tags, releases, hooks, or app builds are performed.
The Git index, not the worktree, is authoritative for source version metadata.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

START = '<!-- VIBE-CURRENT-STATE:START -->'
END = '<!-- VIBE-CURRENT-STATE:END -->'
HANDOFF = 'VIBECODING_HANDOFF.md'
OWNER = 'TheCuriousProcrastinator'


def cmd(*args, cwd=None, allowed=(0,)):
    p = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if p.returncode not in allowed:
        raise RuntimeError(f"{' '.join(args)}: {p.stderr.strip() or p.stdout.strip()}")
    return p.stdout.strip()


def index_paths(root):
    return set(cmd('git', 'ls-files', cwd=root).splitlines())


def index_text(root, path):
    try:
        return cmd('git', 'show', f':{path}', cwd=root)
    except RuntimeError:
        return None


def index_text_exact(root, path):
    result = subprocess.run(['git', 'show', f':{path}'], cwd=root, text=True,
                            capture_output=True)
    if result.returncode:
        raise RuntimeError('Missing staged file: ' + path)
    return result.stdout


def source_metadata(root, names):
    """Read only staged/tracked sources; report unknown instead of guessing."""
    metadata = []
    spec = [
        ('project.yml', 'xcodegen'),
        ('chrome-extension/manifest.json', 'chrome'),
        ('manifest.json', 'manifest'),
        ('pyproject.toml', 'python'),
        ('package.json', 'npm'),
        ('appcast.xml', 'sparkle'),
    ]
    spec += [(x, 'xcode') for x in sorted(names) if x.endswith('.xcodeproj/project.pbxproj')]
    spec += [(x, 'npm') for x in sorted(names) if x.endswith('/package.json') and x.count('/') <= 2]
    seen = set()
    for path, kind in spec:
        if path not in names or path in seen:
            continue
        seen.add(path)
        src = index_text(root, path)
        if src is None:
            continue
        version, build = None, None
        try:
            if kind in ('chrome', 'manifest', 'npm'):
                version = str(json.loads(src).get('version', '')).strip() or None
            elif kind in ('xcode', 'xcodegen'):
                found = re.findall(r'(?:MARKETING_VERSION|CURRENT_PROJECT_VERSION)\s*[:=]\s*["\']?([0-9][\w.\-]*)', src)
                vers = re.search(r'MARKETING_VERSION\s*[:=]\s*["\']?([0-9][\w.\-]*)', src)
                bld = re.search(r'CURRENT_PROJECT_VERSION\s*[:=]\s*["\']?([0-9][\w.\-]*)', src)
                version = vers.group(1) if vers else None
                build = bld.group(1) if bld else None
            elif kind == 'python':
                v = re.search(r'^version\s*=\s*["\']([^"\']+)', src, re.M)
                version = v.group(1) if v else None
            elif kind == 'sparkle':
                xml = ET.fromstring(src)
                item = xml.find('./channel/item')
                if item is not None:
                    ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
                    version = item.findtext(ns + 'shortVersionString')
                    build = item.findtext(ns + 'version')
            if version or build:
                metadata.append((path, version or 'unavailable', build))
        except (ValueError, ET.ParseError):
            raise RuntimeError('Invalid tracked version metadata: ' + path)
    return metadata


def latest_release(repo):
    """States: verified GitHub release, no published release, or unverified error."""
    p = subprocess.run(['gh', 'api', f'repos/{OWNER}/{repo}/releases/latest'], text=True, capture_output=True)
    if p.returncode == 0:
        try:
            obj = json.loads(p.stdout)
            tag = obj['tag_name']
            if obj.get('draft') or obj.get('prerelease'):
                return 'Unverified: latest response is not a stable published release'
            return f'Published GitHub release `{tag}` (reported by GitHub API)'
        except (ValueError, KeyError):
            return 'Unverified: could not parse GitHub release response'
    message = p.stderr.lower()
    if '404' in message and ('not found' in message or 'http 404' in message):
        return 'No published GitHub release returned by the API'
    return 'Unverified: GitHub API unavailable or access denied'


def block(repo, branch, metadata, release):
    lines = [
        START,
        '## Current repository facts (generated, authoritative only for the facts listed)',
        '',
        f'- Repository: `{OWNER}/{repo}`; local working branch: `{branch}`.',
        '- Version data below is read from the **Git index** (the files staged for commit).',
    ]
    if metadata:
        for path, version, build in metadata:
            suffix = f', build `{build}`' if build else ''
            lines.append(f'- Source `{path}`: version `{version}`{suffix}.')
    else:
        lines.append('- Source version: not determined from supported tracked metadata; verify manually.')
    lines += [
        f'- GitHub publication: {release}. Other distribution channels are **unverified**.',
        '- This section does **not** establish local build success, manual QA, App Store/Chrome Web Store approval, notarization, live website deployment, or release-asset integrity.',
        '- The narrative below maintains architecture, decisions, issues and test evidence. Its older status and version claims are **historical** unless explicitly reconciled with this section.',
        '- Before executable changes, inspect the actual checkout and validate the **exact files** on the real Mac. No automatic GitHub Actions.',
        '', END,
    ]
    return '\n'.join(lines)


def get_context(root):
    root = Path(root).resolve()
    real = Path(cmd('git', 'rev-parse', '--show-toplevel', cwd=root)).resolve()
    if root != real:
        raise RuntimeError('Point to the Git root, not a nested folder')
    origin = cmd('git', 'remote', 'get-url', 'origin', cwd=root)
    m = re.search(r'(?:github\.com[:/])([^/]+)/([^/]+?)(?:\.git)?$', origin)
    if not m or m.group(1) != OWNER:
        raise RuntimeError('Unexpected GitHub origin: ' + origin)
    repo = m.group(2)
    branch = cmd('git', 'branch', '--show-current', cwd=root)
    if not branch:
        raise RuntimeError('Detached HEAD; refuse to rewrite a handoff')
    names = index_paths(root)
    if HANDOFF not in names:
        raise RuntimeError('Tracked root VIBECODING_HANDOFF.md is missing')
    return root, repo, branch, names


def replace_section(doc, rendered):
    a, b = doc.count(START), doc.count(END)
    if (a, b) == (0, 0):
        # Preserve every byte of the historical handoff; only prepend facts.
        return rendered + '\n\n' + doc
    if (a, b) != (1, 1):
        raise RuntimeError('Ambiguous current-state markers; no file changed')
    start = doc.index(START)
    end = doc.index(END)
    if end < start:
        raise RuntimeError('Markers are out of order')
    return doc[:start] + rendered + doc[end + len(END):]


def run(root, operation, offline=False):
    root, repo, branch, names = get_context(root)
    path = root / HANDOFF
    old = path.read_text(encoding='utf-8')
    # Do not silently overwrite uncommitted, unrelated handoff edits.
    staged = cmd('git', 'diff', '--cached', '--name-only', cwd=root).splitlines()
    if operation == 'update':
        if HANDOFF in staged:
            raise RuntimeError('Handoff already staged; reconcile changes before regeneration')
        if cmd('git', 'diff', '--', HANDOFF, cwd=root):
            raise RuntimeError('Handoff has unrelated unstaged edits; do not overwrite')
    release = 'Unverified (offline validation)' if offline else latest_release(repo)
    if operation in ('sync-staged', 'check-staged') and not offline and release.startswith('Unverified:'):
        raise RuntimeError('Cannot refresh staged handoff while GitHub release status is unverified')
    rendered = block(repo, branch, source_metadata(root, names), release)
    if operation in ('sync-staged', 'check-staged'):
        staged_text = index_text_exact(root, HANDOFF)
        if operation == 'check-staged':
            if replace_section(staged_text, rendered) != staged_text:
                raise RuntimeError(f'{repo}: staged handoff facts are stale')
            return f'PASS: {repo}: staged handoff matches indexed source and release'
        if old != staged_text:
            raise RuntimeError('Handoff has unstaged changes; stage them manually before committing')
        changed = replace_section(staged_text, rendered)
        if changed != staged_text:
            path.write_text(changed, encoding='utf-8')
            cmd('git', 'add', '--', HANDOFF, cwd=root)
        if index_text_exact(root, HANDOFF) != changed:
            raise RuntimeError('Handoff did not stage correctly')
        return f'PASS: {repo}: handoff generated facts synchronized with staged source'

    updated = replace_section(old, rendered)
    if operation == 'check':
        if old != updated:
            raise RuntimeError(f'{repo}: handoff stale or missing generated facts; run update')
        return f'PASS: {repo}: current-state block matches indexed source + release data'
    if updated != old:
        path.write_text(updated, encoding='utf-8')
    return f'UPDATED: {repo}: handoff prepared locally; no commit or push'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('update', 'check', 'sync-staged', 'check-staged'))
    parser.add_argument('checkout', nargs='?', default='.')
    parser.add_argument('--offline', action='store_true', help='Test only; publish state explicitly unverified')
    args = parser.parse_args()
    try:
        print(run(args.checkout, args.action, args.offline))
    except RuntimeError as exc:
        print('BLOCKED:', str(exc), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
