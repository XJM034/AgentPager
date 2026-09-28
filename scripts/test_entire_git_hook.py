import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class EntireGitHookTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='entire-sync-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = {k:v for k,v in os.environ.items() if not k.startswith(('GIT_', 'CODEX_', 'ENTIRE_'))}
        self.env.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1')
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'core.hooksPath', '/dev/null')
        (self.root/'a').write_text('a')
        self.git('add', 'a')

    def git(self,*args):
        return subprocess.check_output(['git',*args],cwd=self.root,env=self.env,text=True).strip()

    def load(self):
        path=Path(__file__).with_name('entire-git-hook.py')
        spec=importlib.util.spec_from_file_location('git_hook',path)
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_success_exit_is_not_proof_of_checkpoint(self):
        self.git('commit','-qm','test\n\nEntire-Checkpoint: 123456789abc')
        result=self.load().checkpoint_status(self.root)
        self.assertEqual(result['status'],'missing-checkpoint')

    def test_commit_without_trailer_is_explicit(self):
        self.git('commit','-qm','test')
        self.assertEqual(self.load().checkpoint_status(self.root)['status'],'no-checkpoint-trailer')

    def test_metadata_must_identify_the_checkpoint_and_sessions(self):
        cid='123456789abc'
        self.git('commit','-qm','test\n\nEntire-Checkpoint: '+cid)
        # A nonempty file alone must not be treated as verified evidence.
        folder=self.root/'12'/'3456789abc';folder.mkdir(parents=True)
        (folder/'metadata.json').write_text('{}')
        self.git('add','12');self.git('commit','-qm','metadata')
        self.git('branch','entire/checkpoints/v1')
        self.git('checkout','-q','HEAD^')
        self.assertEqual(self.load().checkpoint_status(self.root)['status'],'invalid-checkpoint-metadata')

    def test_pinned_runtime_does_not_silently_follow_an_upgrade(self):
        from entire_runtime import resolve_runtime
        binary=self.root/'entire';binary.write_text('first')
        import hashlib
        pin={'binary':str(binary),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest()}
        (self.root/'.git/entire-runtime.json').write_text(json.dumps(pin))
        self.assertEqual(resolve_runtime(self.root),str(binary))
        binary.write_text('replaced')
        with self.assertRaises(ValueError):resolve_runtime(self.root)
