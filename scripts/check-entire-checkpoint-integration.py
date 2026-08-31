#!/usr/bin/env python3
"""Isolated Entire 0.7.7 hook replay. Never operates on the invoking repository.

Run: python3 -B scripts/check-entire-checkpoint-integration.py --wrapper /absolute/path/entire-codex-hook.py
Only Entire hooks codex {session-start,user-prompt-submit,post-tool-use,stop}
and hooks git {prepare-commit-msg,commit-msg,post-commit} are allowed.
Each execution creates fresh independent Git repositories in /private/tmp (or /tmp).
No Entire enable/doctor/clean/resume/attach or global configuration writes.
No existing repository can be supplied as a target. No side effects on import.
After copying beside entire-codex-hook.py, --wrapper may be omitted.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

RUN = None
ENTIRE = Path('/opt/homebrew/Caskroom/entire/0.7.7/entire')
GIT = '/usr/bin/git'
ALLOWED_CODEX = {'session-start', 'user-prompt-submit', 'post-tool-use', 'stop'}
ALLOWED_GIT = {'prepare-commit-msg', 'commit-msg', 'post-commit'}
WRAPPER = Path(__file__).resolve().with_name('entire-codex-hook.py')

def clean_env():
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('GIT_', 'CODEX_', 'ENTIRE_'))}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
               GIT_TERMINAL_PROMPT='0', GIT_OPTIONAL_LOCKS='0')
    return env

def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')

def ts():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def run_case(name, commit_before_stop, desktop=False, project_marker=False, use_wrapper=False):
    case = RUN / name
    repo = case / 'repo'
    evidence = case / 'evidence'
    transcripts = case / 'synthetic-transcripts'
    for directory in (repo, evidence, transcripts):
        directory.mkdir(parents=True)
    # No caller-supplied repo/cwd is accepted. Every command targets a freshly
    # created child of this run's mkdtemp directory, including the Git hook runner.
    assert repo.resolve().is_relative_to(RUN.resolve()) and not (repo / '.git').exists()
    sid = str(uuid.uuid4())
    transcript = transcripts / ('rollout-synthetic-' + sid + '.jsonl')
    env = clean_env()
    env['ENTIRE_TEST_CODEX_SESSION_DIR'] = str(transcripts)
    if use_wrapper:
        # The real project wrapper removes GIT_* / ENTIRE_* by design. A temp
        # launcher restores only test isolation controls after that boundary.
        # It calls the real installed binary, forwards stdin and exit status,
        # and never changes the validated identity or synthetic hook payload.
        bindir = case / 'test-bin'
        bindir.mkdir()
        isolation = {k: v for k, v in env.items() if k.startswith(('GIT_', 'ENTIRE_'))}
        launcher = bindir / 'entire'
        launcher.write_text(
            '#!/usr/bin/python3\n'
            'import json,os,subprocess,sys\n'
            'from pathlib import Path\n'
            'assert sys.argv[1:3]==["hooks","codex"]\n'
            'assert sys.argv[3] in ' + repr(ALLOWED_CODEX) + '\n'
            'data=sys.stdin.read()\n'
            'ids={k:os.environ[k] for k in ["CODEX_SESSION_ID","CODEX_THREAD_ID"] if k in os.environ}\n'
            'env={k:v for k,v in os.environ.items() if not k.startswith(("GIT_","CODEX_","ENTIRE_"))}\n'
            'env.update(' + repr(isolation) + ')\n'
            'env.update(ids)\n'
            'p=subprocess.run(' + repr([str(ENTIRE)]) + '+sys.argv[1:],input=data,text=True,env=env,cwd=' + repr(str(repo)) + ',capture_output=True,timeout=23,start_new_session=True)\n'
            'record={"argv":sys.argv[1:],"validated_ids":ids,"payload":json.loads(data),"exit_code":p.returncode,"stdout":p.stdout,"stderr":p.stderr}\n'
            'with Path(' + repr(str(evidence / 'wrapper-forwarding.jsonl')) + ').open("a") as f: f.write(json.dumps(record)+"\\n")\n'
            'sys.stdout.write(p.stdout)\n'
            'sys.stderr.write(p.stderr)\n'
            'sys.exit(p.returncode)\n')
        launcher.chmod(0o700)
        env['PATH'] = str(bindir) + os.pathsep + env.get('PATH', '/usr/bin:/bin')
    commands = []
    save(evidence / 'environment-overrides.json',
         {k: v for k, v in env.items() if k.startswith(('GIT_', 'CODEX_', 'ENTIRE_'))})

    def command(argv, label, input_text=None, check=True):
        argv = [str(x) for x in argv]
        if argv[0] == str(ENTIRE):
            assert argv[1:3] in [['hooks', 'codex'], ['hooks', 'git']]
            assert argv[3] in (ALLOWED_CODEX if argv[2] == 'codex' else ALLOWED_GIT)
        proc = subprocess.run(argv, cwd=repo, env=env, input=input_text,
                              text=True, capture_output=True, timeout=30,
                              start_new_session=True)
        record = {'label': label, 'argv': argv, 'cwd': str(repo),
                  'exit_code': proc.returncode, 'stdout': proc.stdout,
                  'stderr': proc.stderr, 'timestamp': ts()}
        commands.append(record)
        save(evidence / ('command-%02d-%s.json' % (len(commands), label)), record)
        if check and proc.returncode:
            raise RuntimeError('%s exited %s: %s' % (label, proc.returncode, proc.stderr))
        return proc

    def git(*args):
        return command([GIT, *args], 'git-' + args[0])

    def append(payload_type, payload):
        with transcript.open('a') as f:
            f.write(json.dumps({'timestamp': ts(), 'type': payload_type,
                                'payload': payload}) + '\n')

    def hook(verb, **extra):
        event_names = {'session-start': 'SessionStart', 'user-prompt-submit': 'UserPromptSubmit',
                       'post-tool-use': 'PostToolUse', 'stop': 'Stop'}
        payload = {'session_id': sid, 'transcript_path': str(transcript),
                   'cwd': str(repo), 'hook_event_name': event_names[verb],
                   'model': 'synthetic-test', 'permission_mode': 'default', **extra}
        save(evidence / (verb + '-input.json'), payload)
        argv = [sys.executable, WRAPPER, verb] if use_wrapper else [ENTIRE, 'hooks', 'codex', verb]
        return command(argv, verb,
                       json.dumps(payload), check=False)

    def snapshot(label):
        state_path = repo / '.git/entire-sessions' / (sid + '.json')
        state = json.loads(state_path.read_text()) if state_path.exists() else None
        refs = git('for-each-ref', '--format=%(refname) %(objectname)', 'refs/heads/entire').stdout
        result = {'state': state, 'refs': refs, 'timestamp': ts()}
        save(evidence / ('snapshot-' + label + '.json'), result)
        return result

    # No remotes, no worktrees, no global Git configuration, no real transcripts.
    git('init', '-b', 'synthetic')
    git('config', 'user.name', 'Synthetic Replay')
    git('config', 'user.email', 'synthetic@example.invalid')
    git('config', 'commit.gpgsign', 'false')
    (repo / '.gitignore').write_text('.entire/\n.codex/\n')
    (repo / 'sample.txt').write_text('before\n')
    git('add', '.gitignore', 'sample.txt')
    git('commit', '-m', 'synthetic baseline')
    save(repo / '.entire/settings.local.json', {
        'enabled': True, 'telemetry': False,
        'strategy_options': {'push_sessions': False}, 'absolute_git_hook_path': True})
    if project_marker:
        # The only variable changed versus local-only configuration.
        # Local enabled/telemetry/push settings still provide identical values.
        save(repo / '.entire/settings.json', {})

    append('session_meta', {'id': sid, 'timestamp': ts(), 'cwd': str(repo),
                            'originator': 'synthetic-replay', 'source': 'cli'})
    hook('session-start', source='startup')
    append('response_item', {'type': 'message', 'role': 'user',
                            'content': [{'type': 'input_text', 'text': 'Change sample to after.'}]})
    hook('user-prompt-submit', prompt='Change sample to after.', turn_id='synthetic-turn')

    # Git invokes these Python hooks naturally. Each scrubs inherited host/Git
    # variables again before invoking the allowlisted Entire Git hook. No shell.
    # Install after first TurnStart: Entire auto-installs its own Git hooks there.
    # This prevents duplicate/chained execution and guarantees captured stderr.
    for verb in sorted(ALLOWED_GIT):
        hook_path = repo / '.git/hooks' / verb
        code = ('#!/usr/bin/python3\n'
                'import json,os,subprocess,sys\n'
                'from pathlib import Path\n'
                'env={k:v for k,v in os.environ.items() if not k.startswith(("GIT_","CODEX_","ENTIRE_"))}\n'
                'env.update(' + repr({k: v for k, v in env.items()
                                     if k.startswith(('GIT_', 'CODEX_', 'ENTIRE_'))}) + ')\n'
                'argv=' + repr([str(ENTIRE), 'hooks', 'git', verb]) + '+sys.argv[1:]\n'
                'p=subprocess.run(argv,cwd=' + repr(str(repo)) + ',env=env,text=True,capture_output=True,timeout=25,start_new_session=True)\n'
                'path=Path(' + repr(str(evidence / ('git-hook-' + verb + '.jsonl'))) + ')\n'
                'with path.open("a") as f: f.write(json.dumps({"argv":argv,"exit_code":p.returncode,"stdout":p.stdout,"stderr":p.stderr})+"\\n")\n'
                'sys.exit(0)\n')
        hook_path.write_text(code)
        hook_path.chmod(0o700)

    patch = '*** Begin Patch\n*** Update File: sample.txt\n@@\n-before\n+after\n*** End Patch'
    (repo / 'sample.txt').write_text('after\n')
    if desktop:
        append('response_item', {'type': 'custom_tool_call', 'name': 'exec',
                                'call_id': 'synthetic-call',
                                'input': 'text(await tools.apply_patch(' + json.dumps(patch) + '));'})
        append('event_msg', {'type': 'item_completed', 'thread_id': sid,
                             'turn_id': 'synthetic-turn',
                             'item': {'type': 'FileChange', 'status': 'completed',
                                      'id': 'synthetic-call', 'changes': {
                                          str(repo / 'sample.txt'): {'type': 'update',
                                              'unified_diff': '@@ -1 +1 @@\n-before\n+after\n',
                                              'move_path': None}}}})
    else:
        append('response_item', {'type': 'custom_tool_call', 'name': 'apply_patch',
                                'call_id': 'synthetic-call', 'input': patch})
    hook('post-tool-use', tool_name='apply_patch', tool_use_id='synthetic-call',
         tool_input={'command': patch}, tool_response='Success')
    before = snapshot('before-stop-or-commit')

    def stop():
        append('response_item', {'type': 'message', 'role': 'assistant',
                                'content': [{'type': 'output_text', 'text': 'Changed sample.'}]})
        append('event_msg', {'type': 'task_complete', 'turn_id': 'synthetic-turn'})
        return hook('stop', turn_id='synthetic-turn', stop_hook_active=False,
                    last_assistant_message='Changed sample.')

    if not commit_before_stop:
        stop()
        after_stop = snapshot('after-stop-before-commit')
    git('add', 'sample.txt')
    git('commit', '-m', 'synthetic change')
    after_commit = snapshot('after-commit')
    if commit_before_stop:
        stop()
        after_stop = snapshot('after-stop-after-commit')
    message = git('log', '-1', '--format=%B').stdout
    head = git('rev-parse', 'HEAD').stdout.strip()
    trailer = next((l.split(':', 1)[1].strip() for l in message.splitlines()
                    if l.startswith('Entire-Checkpoint:')), None)
    metadata = command([GIT, 'ls-tree', '-r', '--name-only', 'refs/heads/entire/checkpoints/v1'],
                       'git-metadata-tree', check=False)
    save(evidence / 'commands.json', commands)
    def brief(snap):
        state = snap['state'] or {}
        return {k: state.get(k) for k in ['phase', 'checkpoint_count', 'files_touched',
                                         'last_checkpoint_id', 'base_commit', 'session_turn_count']}
    result = {'case': name, 'project_settings_marker': project_marker, 'real_wrapper': use_wrapper,
              'repo': str(repo), 'evidence': str(evidence), 'session_id': sid,
              'before': brief(before), 'after_stop': brief(after_stop),
              'after_commit': brief(after_commit), 'head': head,
              'trailer': trailer, 'metadata_tree': metadata.stdout.splitlines(),
              'hook_exit_codes': {c['label']: c['exit_code'] for c in commands
                                  if c['label'] in ALLOWED_CODEX}}
    result['git_hook_exit_codes'] = {
        p.stem: [json.loads(line)['exit_code'] for line in p.read_text().splitlines()]
        for p in evidence.glob('git-hook-*.jsonl')}
    if use_wrapper:
        forwards = [json.loads(line) for line in (evidence / 'wrapper-forwarding.jsonl').read_text().splitlines()]
        result['wrapper_actual_forward_count'] = len(forwards)
        result['wrapper_forward_ids_match'] = all(
            f['validated_ids'] == {'CODEX_SESSION_ID': sid, 'CODEX_THREAD_ID': sid} for f in forwards)
        result['wrapper_actual_entire_exit_codes'] = [f['exit_code'] for f in forwards]
        result['wrapper_payloads_preserved'] = all(
            f['payload'] == json.loads((evidence / (f['argv'][2] + '-input.json')).read_text())
            for f in forwards)
    if trailer:
        prefix = trailer[:2] + '/' + trailer[2:] + '/0/'
        meta_raw = command([GIT, 'show', 'refs/heads/entire/checkpoints/v1:' + prefix + 'metadata.json'],
                           'git-read-session-metadata').stdout
        meta = json.loads(meta_raw)
        stored = command([GIT, 'show', 'refs/heads/entire/checkpoints/v1:' + prefix + 'full.jsonl'],
                         'git-read-stored-transcript').stdout
        stored_lines = [json.loads(line) for line in stored.splitlines() if line.strip()]
        stored_sid = stored_lines[0].get('payload', {}).get('id') if stored_lines else None
        result['metadata_session_id'] = meta.get('session_id')
        result['stored_transcript_session_id'] = stored_sid
        result['metadata_identity_matches'] = meta.get('session_id') == sid and stored_sid == sid
        result['stored_FileChange_count'] = sum(
            1 for line in stored_lines if line.get('type') == 'event_msg'
            and line.get('payload', {}).get('item', {}).get('type') == 'FileChange')
        result['stored_exec_count'] = sum(
            1 for line in stored_lines if line.get('type') == 'response_item'
            and line.get('payload', {}).get('name') == 'exec')
    save(evidence / 'commands.json', commands)
    checks = {
        'all_codex_hooks_succeeded': len(result['hook_exit_codes']) == 4 and all(
            c == 0 for c in result['hook_exit_codes'].values()),
        'all_git_hooks_ran_once_and_succeeded': len(result['git_hook_exit_codes']) == 3 and all(
            codes == [0] for codes in result['git_hook_exit_codes'].values()),
        'trailer_matches_marker_gate': bool(trailer) == project_marker,
        'metadata_matches_marker_gate': bool(result['metadata_tree']) == project_marker,
        'expected_counter_after_commit': result['after_commit']['checkpoint_count'] == (
            0 if project_marker or commit_before_stop else 1),
        'expected_counter_after_stop': result['after_stop']['checkpoint_count'] == (
            0 if commit_before_stop else 1),
    }
    if project_marker:
        checks['last_checkpoint_id_matches_trailer'] = result['after_commit']['last_checkpoint_id'] == trailer
        checks['metadata_identity_matches'] = result['metadata_identity_matches']
    if use_wrapper:
        checks.update(wrapper_forward_ids_match=result['wrapper_forward_ids_match'],
                      wrapper_payloads_preserved=result['wrapper_payloads_preserved'],
                      wrapper_forwarded_all_four=result['wrapper_actual_forward_count'] == 4,
                      wrapper_actual_hooks_succeeded=result['wrapper_actual_entire_exit_codes'] == [0] * 4)
    if desktop:
        checks['desktop_records_preserved'] = result.get('stored_FileChange_count') == 1 and result.get('stored_exec_count') == 1
    result['checks'] = checks
    result['passed'] = all(checks.values())
    save(evidence / 'result.json', result)
    return result

def main():
    global RUN, ENTIRE, WRAPPER
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wrapper', type=Path, default=WRAPPER)
    parser.add_argument('--entire', type=Path, default=ENTIRE)
    parser.add_argument('--desktop-only', action='store_true')
    args = parser.parse_args()
    WRAPPER = args.wrapper.resolve()
    ENTIRE = args.entire.resolve()
    if not WRAPPER.is_file() or not ENTIRE.is_file():
        parser.error('wrapper and Entire executable must exist; no install/download is attempted')
    temp_base = Path('/private/tmp') if Path('/private/tmp').is_dir() else Path('/tmp')
    RUN = Path(tempfile.mkdtemp(prefix='agentpager-entire-integration-', dir=temp_base))
    initial_wrapper_hash = hashlib.sha256(WRAPPER.read_bytes()).hexdigest()
    (RUN / 'replay.py').write_text(Path(__file__).read_text())
    save(RUN / 'run-info.json', {'started': ts(), 'script': str(Path(__file__).resolve()),
                               'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                               'wrapper_path': str(WRAPPER),
                               'wrapper_sha256': initial_wrapper_hash,
                               'entire_binary': str(ENTIRE),
                               'entire_sha256': hashlib.sha256(ENTIRE.read_bytes()).hexdigest(),
                               'scope': 'synthetic independent temp Git repositories only'})
    results = []
    for name, midturn, desktop, marker, wrapper in [
            ('local-only-stop-then-commit', False, False, False, False),
            ('local-only-midturn-commit', True, False, False, False),
            ('project-marker-stop-then-commit', False, False, True, False),
            ('project-marker-midturn-commit', True, False, True, False),
            ('wrapper-stop-then-commit', False, False, True, True),
            ('wrapper-midturn-commit', True, False, True, True),
            ('wrapper-desktop-stop-then-commit', False, True, True, True),
            ('wrapper-desktop-midturn-commit', True, True, True, True)]:
        if args.desktop_only and not desktop:
            continue
        try:
            results.append(run_case(name, midturn, desktop, marker, wrapper))
        except Exception as exc:
            results.append({'case': name, 'error': str(exc), 'passed': False})
    save(RUN / 'results.json', results)
    unchanged = hashlib.sha256(WRAPPER.read_bytes()).hexdigest() == initial_wrapper_hash
    report = {'run': str(RUN), 'wrapper_unchanged_during_run': unchanged,
              'passed': unchanged and all(r['passed'] for r in results),
              'cases': [{k: r.get(k) for k in ['case', 'passed', 'trailer', 'error']} for r in results]}
    save(RUN / 'summary.json', report)
    print(json.dumps(report, indent=2))
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    sys.exit(main())
