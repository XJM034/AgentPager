#!/usr/bin/env python3
"""Install the backed-up, project-owned Git adapters after isolated verification."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
from entire_runtime import common_dir, git_read


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    root = Path(git_read(Path.cwd(), 'rev-parse', '--show-toplevel'))
    common = common_dir(root)
    # git_read deliberately disables hooks, so its --git-path hooks is /dev/null.
    # rev-parse itself launches no hooks; inspect the actual configured location.
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    hooks = Path(subprocess.check_output(
        ['git', '-c', 'core.fsmonitor=false', '-C', str(root), 'rev-parse',
         '--path-format=absolute', '--git-path', 'hooks'], env=env, text=True).strip())
    if hooks != common / 'hooks':
        parser.error('custom hooks path; preserve it and inspect before installation')
    events = ('prepare-commit-msg', 'commit-msg', 'post-commit', 'post-rewrite', 'pre-push')
    # Never replace third-party hooks or an unrecognized chain.
    for event in events:
        path = hooks / event
        if path.is_symlink():
            parser.error('symlinked Git hook; preserve it and inspect before installation')
        if path.exists():
            content = path.read_text()
            if '# AgentPager verified Entire adapter' not in content and (
                '# Entire CLI hooks' not in content or
                any(line.strip() and not line.startswith(('#', 'if ', 'else ', 'fi'))
                    for line in content.splitlines())
            ):
                parser.error('unrecognized Git hook; preserve it and inspect before installation')
    backup = common / 'entire-recovery' / (
        datetime.datetime.now().strftime('%Y%m%dT%H%M%S%f') + '-git-adapters')
    backup.mkdir(parents=True, mode=0o700)
    pin = common / 'entire-runtime.json'
    if pin.exists():
        shutil.copy2(pin, backup / pin.name)
    hooks.mkdir(parents=True, exist_ok=True)
    for event in events:
        path = hooks / event
        if path.exists():
            shutil.copy2(path, backup / event)
    pin.write_text(json.dumps({'binary': str(binary),
                              'sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}, indent=2))
    pin.chmod(0o600)
    adapter = root / 'scripts/entire-git-hook.py'
    for event in events:
        path = hooks / event
        path.write_text('#!/bin/sh\n# Entire CLI hooks\n# AgentPager verified Entire adapter\n' +
                        'exec ' + shlex.quote(sys.executable) + ' -B ' + shlex.quote(str(adapter)) +
                        ' ' + shlex.quote(event) + ' "$@"\n')
        path.chmod(0o700)
    for path in backup.iterdir():
        path.chmod(0o600)
    print('Installed shared runtime and verified Git adapters; backup: ' + str(backup))


if __name__ == '__main__':
    main()
