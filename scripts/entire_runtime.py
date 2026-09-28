"""Shared local Entire runtime selection. No CLI calls or automatic upgrades."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def git_read(root, *args):
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    env.update(GIT_OPTIONAL_LOCKS='0', GIT_NO_LAZY_FETCH='1')
    return subprocess.check_output(
        ['git', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
         '-c', 'core.useReplaceRefs=false', '-C', str(root), *args],
        env=env, text=True, stderr=subprocess.DEVNULL, timeout=15).strip()


def common_dir(root):
    return Path(git_read(root, 'rev-parse', '--path-format=absolute', '--git-common-dir'))


def resolve_runtime(root):
    try:
        pin = common_dir(root) / 'entire-runtime.json'
    except subprocess.CalledProcessError:
        pin = None
    if pin is not None and pin.exists():
        data = json.loads(pin.read_text())
        binary = Path(data['binary'])
        if not binary.is_absolute() or not binary.is_file():
            raise ValueError('pinned Entire runtime is unavailable')
        if hashlib.sha256(binary.read_bytes()).hexdigest() != data['sha256']:
            raise ValueError('pinned Entire runtime changed; isolated verification is required')
        return str(binary)
    binary = shutil.which('entire')
    if binary is None:
        raise ValueError('Entire runtime is unavailable')
    return binary
