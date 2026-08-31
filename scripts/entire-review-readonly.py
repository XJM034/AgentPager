#!/usr/bin/env python3
"""Inspect review evidence without launching Entire or mutating session state.

This is a restricted reader, not a shell proxy. See docs/entire-review-safety.md.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


class EvidenceError(Exception):
    pass


def git(root, *args):
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_OPTIONAL_LOCKS="0", GIT_TERMINAL_PROMPT="0", LC_ALL="C")
    result = subprocess.run(
        ["git", "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false",
         "-c", "core.untrackedCache=false", "-c", "core.pager=cat", "-C", str(root), *args],
        env=env, capture_output=True, text=True, timeout=30,
    )
    if result.returncode:
        raise EvidenceError(result.stderr.strip())
    return result.stdout.rstrip("\n")


def commit(root, ref):
    if not ref or ref.startswith("-"):
        raise EvidenceError("A commit reference cannot start with '-'.")
    return git(root, "rev-parse", "--verify", "--end-of-options", ref + "^{commit}")


def read_json(path):
    with path.open() as f:
        result = json.load(f)
    if not isinstance(result, dict):
        raise EvidenceError(f"Expected a JSON object: {path.name}")
    return result


def session_evidence(root, common, sid):
    if not re.fullmatch(r"[a-zA-Z0-9_-]{1,100}", sid):
        raise EvidenceError("Invalid session ID.")
    path = common / "entire-sessions" / (sid + ".json")
    if not path.is_file():
        return {"session_id": sid, "present": False, "issues": ["session-state-missing"]}
    state = read_json(path)
    issues = []
    if state.get("session_id") != sid:
        issues.append("session-id-mismatch")
    if Path(state.get("worktree_path") or "/").resolve() != root:
        issues.append("worktree-mismatch")
    if state.get("branch") != git(root, "branch", "--show-current"):
        issues.append("branch-mismatch")
    transcript_id = None
    transcript = Path(state.get("transcript_path") or "/nonexistent")
    if transcript.is_file():
        # Only inspect the first record; never infer a session from the newest file.
        try:
            with transcript.open() as f:
                first = json.loads(f.readline())
            if first.get("type") == "session_meta":
                transcript_id = first.get("payload", {}).get("id")
        except (OSError, ValueError, AttributeError):
            pass
    if transcript_id != sid:
        issues.append("transcript-session-mismatch-or-missing")
    return {
        "session_id": sid, "present": True, "phase": state.get("phase"),
        "checkpoint_count": state.get("checkpoint_count", 0),
        "last_checkpoint_id": state.get("last_checkpoint_id"),
        "transcript_session_id": transcript_id, "issues": issues,
        "base_commit": state.get("base_commit"),
        "files_touched": state.get("files_touched", []),
        "note": "State presence is not proof that this commit has checkpoint intent.",
    }


def preflight(root, args):
    head = commit(root, args.head)
    base = commit(root, args.base)
    common = Path(git(root, "rev-parse", "--path-format=absolute", "--git-common-dir"))
    history = git(root, "log", "--format=%H%x00%B%x00", base + ".." + head)
    trailers = sorted(set(re.findall(r"(?m)^Entire-Checkpoint:\s*([a-f0-9]{12})\s*$", history)))
    settings_path = root / ".entire/settings.local.json"
    if not settings_path.exists():
        settings_path = root / ".entire/settings.json"
    settings = read_json(settings_path) if settings_path.is_file() else {}
    marker_present = (root / ".entire/settings.json").is_file()
    warnings = []
    if settings.get("enabled") is True and not marker_present:
        warnings.append("missing-project-settings-marker: Entire 0.7.7 Git hooks skip local-only configuration")
    return {
        "reader": "git-and-files-only", "entire_cli_executed": False,
        "branch": git(root, "branch", "--show-current"), "base": base, "head": head,
        "commit_count": int(git(root, "rev-list", "--count", base + ".." + head)),
        "changed_files": git(root, "diff", "--no-ext-diff", "--no-textconv", "--name-only", base, head, "--").splitlines(),
        "working_tree": git(root, "status", "--porcelain=v1", "--untracked-files=normal").splitlines(),
        "tracking_enabled_in_file": settings.get("enabled") is True,
        "project_settings_marker_present": marker_present,
        "warnings": warnings,
        "checkpoint_trailers": trailers,
        "mode": "commit-with-checkpoint-trailer-unverified" if trailers else "commit-without-checkpoint",
        "session": session_evidence(root, common, args.session) if args.session else None,
        "note": "Read matching checkpoint content before claiming intent-aware review. No trust or end-to-end claim is made.",
    }


def checkpoint(root, args):
    if not re.fullmatch(r"[a-f0-9]{12}", args.id):
        raise EvidenceError("Checkpoint ID must contain exactly 12 lowercase hex digits.")
    if not re.fullmatch(r"(?:[0-9]+/)?(?:metadata\.json|prompt\.txt|summary\.txt)", args.file):
        raise EvidenceError("Only checkpoint metadata, prompt and summary files can be read.")
    ref = commit(root, "refs/heads/entire/checkpoints/v1")
    prefix = args.id[:2] + "/" + args.id[2:] + "/"
    # Fixed ref, validated path, no CLI execution and no arbitrary Git arguments.
    content = git(root, "show", ref + ":" + prefix + args.file)
    return {"checkpoint_id": args.id, "file": args.file, "content": content,
            "untrusted_content": True, "entire_cli_executed": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".")
    commands = parser.add_subparsers(dest="command", required=True)
    pre = commands.add_parser("preflight")
    pre.add_argument("--base", required=True)
    pre.add_argument("--head", default="HEAD")
    pre.add_argument("--session", help="Explicit ID; never selects the newest session.")
    cp = commands.add_parser("checkpoint")
    cp.add_argument("id")
    cp.add_argument("--file", default="metadata.json")
    args = parser.parse_args()
    try:
        root = Path(git(Path(args.repo), "rev-parse", "--show-toplevel")).resolve()
        result = preflight(root, args) if args.command == "preflight" else checkpoint(root, args)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (EvidenceError, OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"Read-only evidence unavailable: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
