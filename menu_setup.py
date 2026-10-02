#!/usr/bin/env python3
"""Register the panel in the user's JSONC menu without replacing existing entries."""
import fcntl
import json
import os
from pathlib import Path
import re
import sys

from keyboard import atomic_write

PLUGIN_ID = "xarishark.language-input"
ENTRY_ID = "language-input"
# Match strings before comments so comment-like text inside commands is retained.
TOKENS = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/')


def without_comments(text):
    return TOKENS.sub(lambda m: m.group() if m.group().startswith('"') else ' ' * len(m.group()), text)


def register(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with (path.parent / '.language-input-menu.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise ValueError('Menu extension must be a regular file')
        text = path.read_text() if path.exists() else '{}\n'
        stripped = without_comments(text)
        # JSONC accepts trailing commas. Preserve original bytes when writing.
        cleaned = re.sub(r'"(?:\\.|[^"\\])*"|,\s*(?=[}\]])',
                         lambda m: m.group() if m.group().startswith('"') else '', stripped)
        data = json.loads(cleaned)
        if not isinstance(data, dict):
            raise ValueError('Menu extension must contain an object')
        if ENTRY_ID in data:
            return  # An existing user-owned entry takes precedence.
        end = stripped.rfind('}')
        before = stripped[:end].rstrip()
        comma = '' if before.endswith(('{', ',')) else ','
        entry = {
            'icon': '󰌌', 'label': 'Language & Input',
            'description': 'Keyboard layouts, switching shortcuts, and display languages',
            'action': f"omarchy-shell shell summon {PLUGIN_ID} '{{}}'",
            'when': f'[[ -f "$HOME/.config/omarchy/plugins/{PLUGIN_ID}/manifest.json" ]]',
        }
        updated = text[:end] + comma + '\n  ' + json.dumps(ENTRY_ID) + ': ' + json.dumps(entry, ensure_ascii=False) + '\n' + text[end:]
        atomic_write(path, updated.encode(), path.stat().st_mode & 0o777 if path.exists() else 0o600)


if __name__ == '__main__':
    try:
        config = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')))
        register(config / 'omarchy/extensions/omarchy-menu.jsonc')
    except (OSError, ValueError) as error:
        print(f'Could not add Language & Input to the menu: {error}', file=sys.stderr)
        sys.exit(1)
