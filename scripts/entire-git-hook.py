#!/usr/bin/env python3
"""Forward Git hooks to the shared runtime and verify actual checkpoint storage.

No repair, synthetic events, retries, history rewriting, or session uploads.
The post-commit report is private and does not claim intent verification.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from entire_runtime import common_dir, git_read, resolve_runtime

EVENTS = {'prepare-commit-msg', 'commit-msg', 'post-commit', 'post-rewrite', 'pre-push'}


def checkpoint_status(root):
    head = git_read(root, 'rev-parse', 'HEAD')
    message = git_read(root, 'show', '-s', '--format=%B', head)
    ids = re.findall(r'^Entire-Checkpoint:\s*([a-f0-9]{12})\s*$', message, re.M)
    report = {'head': head, 'status': 'no-checkpoint-trailer'}
    if not ids:
        return report
    if len(set(ids)) != 1:
        return dict(report, status='ambiguous-checkpoint-trailer')
    cid = ids[0]
    report['checkpoint_id'] = cid
    prefix = cid[:2] + '/' + cid[2:] + '/'
    ref = 'refs/heads/entire/checkpoints/v1:'
    try:
        raw = git_read(root, 'show', ref + prefix + 'metadata.json')
    except subprocess.CalledProcessError:
        return dict(report, status='missing-checkpoint')
    try:
        meta = json.loads(raw)
        sessions = meta['sessions']
        if meta['checkpoint_id'] != cid or not isinstance(sessions, list) or not sessions:
            raise ValueError('metadata identity')
        for session in sessions:
            for key in ('metadata', 'transcript'):
                path = session[key].lstrip('/')
                expected = re.escape(prefix) + r'\d+/' + re.escape('metadata.json' if key == 'metadata' else 'full.jsonl')
                if not re.fullmatch(expected, path):
                    raise ValueError('unexpected checkpoint path')
                git_read(root, 'cat-file', '-e', ref + path)
                if key == 'metadata':
                    if not json.loads(git_read(root, 'show', ref + path)).get('session_id'):
                        raise ValueError('missing session identity')
    except (ValueError, KeyError, TypeError, AttributeError, subprocess.CalledProcessError):
        return dict(report, status='invalid-checkpoint-metadata')
    return dict(report, status='metadata-present', session_count=len(sessions))


def save_report(root, report):
    folder = common_dir(root) / 'entire-sync'
    folder.mkdir(mode=0o700, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=folder, delete=False) as f:
        json.dump(report, f)
        name = f.name
    os.replace(name, folder / (report['head'] + '.json'))


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in EVENTS:
        print('Unsupported Entire Git hook.', file=sys.stderr)
        return 2
    event = sys.argv[1]
    root = Path.cwd()
    # Pairing/session data stays local even when the user's code is pushed.
    # Entire's pre-push has no other project responsibility; never upload here.
    if event == 'pre-push':
        return 0
    try:
        binary = resolve_runtime(root)
        result = subprocess.run([binary, 'hooks', 'git', event, *sys.argv[2:]],
                                cwd=root, text=True, capture_output=True, timeout=120)
        code = result.returncode
        if result.stdout:
            sys.stdout.write(result.stdout)
        if code or result.stderr:
            print('[entire] Git hook returned a diagnostic; see local .entire/logs. '
                  'Checkpoint synchronization is not yet verified.', file=sys.stderr)
        if event in {'post-commit', 'post-rewrite'}:
            report = checkpoint_status(root)
            report.update(hook_exit_code=code, runtime=str(Path(binary).resolve()))
            save_report(root, report)
            if report['status'] != 'metadata-present' or code:
                print('[entire] WARNING: Git commit exists, but checkpoint synchronization '
                      'is NOT verified: ' + report['status'] + '. No automatic repair was run.', file=sys.stderr)
            else:
                print('[entire] Checkpoint metadata and session files are present (intent not audited).', file=sys.stderr)
        return code
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        print('[entire] WARNING: hook or checkpoint verification failed. Git and checkpoint '
              'success are separate; inspect local evidence before claiming synchronization.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
