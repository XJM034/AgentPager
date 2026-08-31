#!/usr/bin/env python3
"""Validate Codex session identity before forwarding an Entire lifecycle hook.

Preserves original transcripts. Rejects mismatched identities instead of repairing
them heuristically. This adapter does not synthesize checkpoints or tool events.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

EVENTS = {"session-start": "SessionStart", "user-prompt-submit": "UserPromptSubmit",
          "post-tool-use": "PostToolUse", "stop": "Stop"}


def validate(payload, event):
    if payload.get("hook_event_name") != EVENTS[event]:
        raise ValueError("unexpected hook event")
    sid = payload.get("session_id")
    if not isinstance(sid, str) or not sid or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for c in sid):
        raise ValueError("missing or invalid session ID")
    raw_path = payload.get("transcript_path")
    if not isinstance(raw_path, str) or not Path(raw_path).is_absolute():
        raise ValueError("missing absolute transcript path; no newest-file fallback is allowed")
    with Path(raw_path).open() as f:
        first = json.loads(f.readline())
    meta = first.get("payload", {})
    if first.get("type") != "session_meta" or meta.get("id") != sid:
        raise ValueError("session ID does not match transcript session_meta.id; tracking skipped")
    cwd = Path(payload.get("cwd") or "")
    if not cwd.is_absolute() or not cwd.is_dir():
        raise ValueError("missing valid absolute working directory")
    if meta.get("cwd") and Path(meta["cwd"]).resolve() != cwd.resolve():
        raise ValueError("hook and transcript working directories differ; tracking skipped")
    # Both IDs must refer to the validated payload, never an inherited parent.
    env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "ENTIRE_"))}
    env.update(CODEX_SESSION_ID=sid, CODEX_THREAD_ID=sid)
    return cwd, env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("event", choices=EVENTS)
    args = parser.parse_args()
    try:
        payload = json.load(sys.stdin)
        cwd, env = validate(payload, args.event)
    except (ValueError, OSError, AttributeError, TypeError) as exc:
        # Do not block the user's coding turn; fail closed for tracking only.
        print(json.dumps({"systemMessage": f"Entire tracking skipped safely: {exc}. "
                          "Review remains diff-only until session/checkpoint evidence is verified."}))
        return 0
    binary = shutil.which("entire")
    if binary is None:
        print(json.dumps({"systemMessage": "Entire tracking unavailable: CLI is missing. No configuration was changed."}))
        return 0
    try:
        result = subprocess.run([binary, "hooks", "codex", args.event],
                                input=json.dumps(payload), text=True, cwd=cwd, env=env,
                                capture_output=True, timeout=25)
    except (OSError, subprocess.TimeoutExpired):
        print(json.dumps({"systemMessage": "Entire hook failed or timed out; checkpoint was not verified. Do not run cleanup as a retry."}))
        return 0
    if result.returncode:
        # Avoid leaking hook stderr (which may include private paths/prompts).
        print(json.dumps({"systemMessage": f"Entire {args.event} exited {result.returncode}; tracking is not verified. "
                          "Use the read-only preflight; do not run doctor."}))
    else:
        sys.stdout.write(result.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
