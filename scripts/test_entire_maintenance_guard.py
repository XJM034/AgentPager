import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest

SCRIPT = Path(__file__).with_name("entire-maintenance-guard.py")
spec = importlib.util.spec_from_file_location("guard", SCRIPT)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class MaintenanceGuardTests(unittest.TestCase):
    def test_blocks_accident_variants(self):
        for cmd in ["entire doctor", "ACCESSIBLE=1 entire doctor", "env ACCESSIBLE=1 entire doctor",
                    "/opt/homebrew/bin/entire clean --all", "entire checkpoint rewind abc",
                    "git status && entire doctor", "printf '1' | entire doctor", "entire doctor </dev/null",
                    "zsh -lc 'ACCESSIBLE=1 entire doctor'", "env -S 'entire doctor'",
                    "eval 'entire doctor'", "entire resume", "entire attach"]:
            with self.subTest(cmd=cmd):
                self.assertTrue(guard.blocked(cmd))

    def test_global_options_cannot_hide_maintenance(self):
        self.assertTrue(guard.blocked("entire --no-pager doctor"))
        self.assertTrue(guard.blocked("env FOO=bar /opt/homebrew/bin/entire --silent doctor"))

    def test_preserves_tracking_git_and_document_reads(self):
        for cmd in ["entire hooks codex stop", "entire hooks git prepare-commit-msg .git/COMMIT_EDITMSG message",
                    "git commit -m 'fix tracking'", "git status --short --branch", "entire version",
                    "rg -n 'entire doctor' docs/entire-review-safety.md",
                    "python3 -B scripts/entire-review-readonly.py preflight --base HEAD^"]:
            with self.subTest(cmd=cmd):
                self.assertFalse(guard.blocked(cmd))

    def test_hook_contract_blocks_with_exit_two(self):
        payload = {"tool_name": "Bash", "tool_input": {"command": "ACCESSIBLE=1 entire doctor"}}
        result = subprocess.run([sys.executable, "-B", str(SCRIPT)], input=json.dumps(payload), text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Entire maintenance blocked", result.stderr)

    def test_malformed_hook_fails_closed(self):
        result = subprocess.run([sys.executable, "-B", str(SCRIPT)], input="{broken", text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
