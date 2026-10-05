#!/usr/bin/env python3
"""Produce one complete local catalog snapshot; never writes or logs user data."""
import json
import os
from pathlib import Path
import sys

EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'}


def revision(path):
    try:
        stat = os.stat(path)
        return json.dumps([os.path.realpath(path), stat.st_ino, stat.st_size,
                           stat.st_mtime_ns, stat.st_ctime_ns], separators=(',', ':'))
    except OSError:
        return 'missing'


def snapshot(home, extra):
    state = Path(home) / '.local/state/omarchy/current'
    try:
        theme = (state / 'theme.name').read_text().strip()
    except FileNotFoundError:
        theme = ''
    theme_target = os.path.realpath(state / 'theme')
    user = Path(home) / '.config/omarchy/backgrounds' / theme
    paths = []
    for folder in ([user] if theme else []) + [state / 'theme/backgrounds']:
        try:
            entries = [p for p in folder.iterdir()
                       if not p.name.startswith('.') and p.suffix in EXTENSIONS
                       and p.is_file() and os.access(p, os.R_OK)]
        except FileNotFoundError:
            entries = []
        paths.extend(str(p) for p in sorted(entries, key=lambda p: (p.name.lower(), p.name)))
    revisions = {p: revision(p) for p in dict.fromkeys(paths + extra)}
    try:
        final_theme = (state / 'theme.name').read_text().strip()
    except FileNotFoundError:
        final_theme = ''
    if final_theme != theme or os.path.realpath(state / 'theme') != theme_target:
        raise OSError('theme changed during listing')
    return {'theme': theme, 'themeDirectory': theme_target + '/backgrounds',
            'images': paths, 'revisions': revisions}


if __name__ == '__main__':
    try:
        print(json.dumps(snapshot(sys.argv[1], json.loads(sys.argv[2]))))
    except (OSError, ValueError):
        # Keep diagnostics concise; the caller retains its last complete snapshot.
        sys.exit(1)
