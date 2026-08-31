"""Regression tests use disposable repos; never run Entire against the real repo."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

READER = Path(__file__).with_name("entire-review-readonly.py")
SID = "11111111-1111-1111-1111-111111111111"


class ReadOnlyReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="entire-reader-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
        self.git("init", "-q", "-b", "test")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.hooksPath", os.devnull)
        (self.root / "file.txt").write_text("before\n")
        self.git("add", "file.txt")
        self.git("-c", "commit.gpgsign=false", "commit", "-qm", "before")
        (self.root / "file.txt").write_text("after\n")
        self.git("add", "file.txt")
        self.git("-c", "commit.gpgsign=false", "commit", "-qm", "after")
        sessions = self.root / ".git/entire-sessions"
        sessions.mkdir()
        self.state_path = sessions / (SID + ".json")
        transcript = self.root / ".git/transcript.jsonl"
        transcript.write_text(json.dumps({"type": "session_meta", "payload": {"id": SID}}) + "\n")
        self.state = {"session_id": SID, "worktree_path": str(self.root), "branch": "test",
                      "phase": "ended", "checkpoint_count": 0, "last_interaction_time": "2000-01-01T00:00:00Z",
                      "transcript_path": str(transcript)}
        self.state_path.write_text(json.dumps(self.state))
        self.before = self.fingerprint()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], env=self.env, text=True).strip()

    def fingerprint(self):
        return {str(p.relative_to(self.root)): hashlib.sha256(p.read_bytes()).hexdigest()
                for directory in [self.root / ".git/entire-sessions", self.root / ".entire"]
                if directory.exists() for p in directory.rglob("*") if p.is_file()}

    def run_reader(self, *args):
        result = subprocess.run([sys.executable, str(READER), "--repo", str(self.root), *args],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(self.fingerprint(), self.before, "Reader changed tracking evidence")
        return result

    def test_stale_sessions_are_never_cleaned_and_cli_is_never_called(self):
        trap = self.root / "bin"
        trap.mkdir()
        sentinel = self.root / "CLI_WAS_EXECUTED"
        cli = trap / "entire"
        cli.write_text(f"#!/bin/sh\ntouch '{sentinel}'\nexit 99\n")
        cli.chmod(0o700)
        self.env["PATH"] = str(trap) + os.pathsep + self.env["PATH"]
        result = self.run_reader("preflight", "--base", "HEAD^", "--session", SID)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["mode"], "commit-without-checkpoint")
        self.assertEqual(report["changed_files"], ["file.txt"])
        self.assertEqual(report["session"]["issues"], [])
        self.assertFalse(sentinel.exists())

    def test_no_implicit_newest_session_selection(self):
        result = self.run_reader("preflight", "--base", "HEAD^")
        self.assertIsNone(json.loads(result.stdout)["session"])

    def test_mismatched_transcript_is_reported(self):
        path = Path(self.state["transcript_path"])
        path.write_text(json.dumps({"type": "session_meta", "payload": {"id": "other-session"}}))
        result = self.run_reader("preflight", "--base", "HEAD^", "--session", SID)
        self.assertIn("transcript-session-mismatch-or-missing", json.loads(result.stdout)["session"]["issues"])

    def test_dangerous_commands_are_rejected_before_execution(self):
        for command in ["doctor", "clean", "resume", "attach", "rewind", "hooks", "shell"]:
            with self.subTest(command=command):
                self.assertEqual(self.run_reader(command).returncode, 2)

    def test_bad_refs_and_missing_sessions(self):
        self.assertNotEqual(self.run_reader("preflight", "--base=--help").returncode, 0)
        self.assertNotEqual(self.run_reader("preflight", "--base", "missing-ref").returncode, 0)
        result = self.run_reader("preflight", "--base", "HEAD^", "--session", "missing-session")
        self.assertFalse(json.loads(result.stdout)["session"]["present"])

    def test_session_path_escape_is_rejected(self):
        self.assertNotEqual(self.run_reader("preflight", "--base", "HEAD^", "--session", "../../config").returncode, 0)

    def test_local_only_configuration_is_not_called_complete(self):
        settings = self.root / ".entire"
        settings.mkdir()
        (settings / "settings.local.json").write_text(json.dumps({"enabled": True}))
        self.before = self.fingerprint()
        report = json.loads(self.run_reader("preflight", "--base", "HEAD^").stdout)
        self.assertTrue(report["tracking_enabled_in_file"])
        self.assertFalse(report["project_settings_marker_present"])
        self.assertIn("missing-project-settings-marker", report["warnings"][0])
        (settings / "settings.json").write_text("{}\n")
        self.before = self.fingerprint()
        report = json.loads(self.run_reader("preflight", "--base", "HEAD^").stdout)
        self.assertEqual(report["warnings"], [])

    def test_git_fsmonitor_cannot_launch_a_command(self):
        sentinel = self.root / "FSMONITOR_WAS_EXECUTED"
        hook = self.root / ".git/malicious-fsmonitor"
        hook.write_text(f"#!/bin/sh\ntouch '{sentinel}'\n")
        hook.chmod(0o700)
        self.git("config", "core.fsmonitor", str(hook))
        self.assertEqual(self.run_reader("preflight", "--base", "HEAD^").returncode, 0)
        self.assertFalse(sentinel.exists())

    def test_checkpoint_reader_and_path_restrictions(self):
        cp = "abcdef123456"
        self.git("checkout", "-qb", "entire/checkpoints/v1")
        path = self.root / cp[:2] / cp[2:] / "metadata.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"checkpoint_id": cp}))
        self.git("add", str(path.relative_to(self.root)))
        self.git("-c", "commit.gpgsign=false", "commit", "-qm", "synthetic checkpoint")
        self.git("checkout", "-q", "test")
        report = json.loads(self.run_reader("checkpoint", cp).stdout)
        self.assertEqual(json.loads(report["content"])["checkpoint_id"], cp)
        self.assertNotEqual(self.run_reader("checkpoint", cp, "--file", "../../config").returncode, 0)
        self.assertNotEqual(self.run_reader("checkpoint", "--help-id").returncode, 0)


if __name__ == "__main__":
    unittest.main()
