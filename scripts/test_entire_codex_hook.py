import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("entire-codex-hook.py")
spec = importlib.util.spec_from_file_location("entire_hook", SCRIPT)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)


class CodexIdentityHookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="entire-hook-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.sid = "parent-id"
        self.path = self.root / "rollout-parent-id_continuation-id.jsonl"
        self.path.write_text(json.dumps({"type": "session_meta", "payload": {"id": self.sid, "cwd": str(self.root)}}) + "\n")
        self.payload = {"session_id": self.sid, "transcript_path": str(self.path),
                        "cwd": str(self.root), "hook_event_name": "Stop"}

    def test_accepts_continuation_filename_by_actual_identity(self):
        original = self.path.read_bytes()
        cwd, env = hook.validate(self.payload, "stop")
        self.assertEqual(cwd, self.root)
        self.assertEqual(env["CODEX_SESSION_ID"], self.sid)
        self.assertEqual(env["CODEX_THREAD_ID"], self.sid)
        self.assertEqual(self.path.read_bytes(), original)

    def test_mismatch_is_not_forwarded_to_cli(self):
        self.payload["session_id"] = "other-id"
        trap = self.root / "entire"
        marker = self.root / "CLI_CALLED"
        trap.write_text(f"#!/bin/sh\ntouch '{marker}'\n")
        trap.chmod(0o700)
        env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ["PATH"])
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "stop"], input=json.dumps(self.payload),
                                text=True, capture_output=True, env=env)
        self.assertEqual(result.returncode, 0)
        self.assertIn("skipped safely", json.loads(result.stdout)["systemMessage"])
        self.assertFalse(marker.exists())

    def test_missing_path_and_wrong_directory_fail_closed(self):
        for update in [{"transcript_path": None}, {"cwd": "/"}, {"hook_event_name": "SessionStart"}]:
            with self.subTest(update=update), self.assertRaises((ValueError, OSError)):
                hook.validate(dict(self.payload, **update), "stop")

    def test_forwards_exact_payload_and_corrects_inherited_ids(self):
        trap = self.root / "entire"
        trap.write_text("#!/usr/bin/env python3\nimport json,os,sys\n"
                        "print(json.dumps({'payload':json.load(sys.stdin),'args':sys.argv[1:],"
                        "'session':os.getenv('CODEX_SESSION_ID'),'thread':os.getenv('CODEX_THREAD_ID')}))\n")
        trap.chmod(0o700)
        env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ["PATH"],
                   CODEX_SESSION_ID="wrong-parent", CODEX_THREAD_ID="wrong-thread")
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "stop"], input=json.dumps(self.payload),
                                text=True, capture_output=True, env=env)
        report = json.loads(result.stdout)
        self.assertEqual(report["payload"], self.payload)
        self.assertEqual(report["session"], self.sid)
        self.assertEqual(report["thread"], self.sid)
        self.assertEqual(report["args"], ["hooks", "codex", "stop"])


if __name__ == "__main__":
    unittest.main()
