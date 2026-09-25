#!/usr/bin/env python3
"""Safely install/merge AI Agent Security Guard hooks into ~/.codex/hooks.json."""
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE_HOOK = ROOT / 'hooks' / 'agent_guard_hook.py'
CODEX_DIR = Path.home() / '.codex'
HOOK_DIR = CODEX_DIR / 'hooks'
DEST_HOOK = HOOK_DIR / 'agent_guard_hook.py'
CONFIG = CODEX_DIR / 'hooks.json'


def handler(event):
    command = f'"{sys.executable}" "{DEST_HOOK}"'
    item = {
        'type': 'command',
        'command': command,
        'timeout': 180,
        'statusMessage': {
            'UserPromptSubmit': 'Checking prompt with AI Agent Security Guard',
            'PreToolUse': 'Checking tool action with AI Agent Security Guard',
            'PostToolUse': 'Checking tool output with AI Agent Security Guard',
        }[event],
    }
    group = {'hooks': [item]}
    if event in {'PreToolUse', 'PostToolUse'}:
        group['matcher'] = '*'
    return group


def main():
    CODEX_DIR.mkdir(parents=True, exist_ok=True)
    HOOK_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE_HOOK, DEST_HOOK)
    if CONFIG.exists():
        backup = CONFIG.with_name(f'hooks.json.bak-{datetime.now().strftime("%Y%m%d-%H%M%S")}')
        shutil.copy2(CONFIG, backup)
        try:
            config = json.loads(CONFIG.read_text(encoding='utf-8'))
        except Exception as exc:
            raise SystemExit(f'Existing {CONFIG} is not valid JSON. Backup created at {backup}. Error: {exc}')
    else:
        backup = None
        config = {'description': 'Codex lifecycle hooks', 'hooks': {}}
    hooks = config.setdefault('hooks', {})
    for event in ('UserPromptSubmit', 'PreToolUse', 'PostToolUse'):
        groups = hooks.setdefault(event, [])
        cleaned = []
        for group in groups:
            handlers = group.get('hooks', []) if isinstance(group, dict) else []
            if any('agent_guard_hook.py' in str(h.get('command', '')) for h in handlers if isinstance(h, dict)):
                continue
            cleaned.append(group)
        cleaned.append(handler(event))
        hooks[event] = cleaned
    CONFIG.write_text(json.dumps(config, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f'Installed hook: {DEST_HOOK}')
    print(f'Updated config: {CONFIG}')
    if backup:
        print(f'Backup: {backup}')
    print('Restart Codex/VS Code after setting AGENT_GUARD_URL and AGENT_GUARD_TOKEN.')


if __name__ == '__main__':
    main()
