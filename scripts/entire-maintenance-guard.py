#!/usr/bin/env python3
"""PreToolUse guard for known destructive Entire shell commands (not a sandbox)."""
import json
import os
import re
import shlex
import sys

MAINTENANCE = {"doctor", "clean", "resume", "attach", "rewind"}
SHELLS = {"sh", "bash", "zsh", "dash", "fish"}


def blocked(command, depth=0):
    if depth > 6:
        return True
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()<>\n")
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        return bool(re.search(r"\bentire\b", command))
    for i, token in enumerate(tokens):
        name = os.path.basename(token)
        rest = tokens[i + 1:]
        if name == "entire" and rest:
            invocation = []
            for arg in rest:
                if arg and all(c in ";&|()<>\n" for c in arg):
                    break
                invocation.append(arg)
            # Include global-option prefixes; conservative for maintenance words.
            if any(arg in MAINTENANCE for arg in invocation):
                return True
        if name in SHELLS:
            for j, arg in enumerate(rest):
                if re.fullmatch(r"-[a-zA-Z]*c[a-zA-Z]*", arg) and j + 1 < len(rest):
                    if blocked(rest[j + 1], depth + 1):
                        return True
        if name == "eval" and rest and blocked(" ".join(rest), depth + 1):
            return True
        if name == "env" and len(rest) > 1 and rest[0] in {"-S", "--split-string"}:
            if blocked(rest[1], depth + 1):
                return True
    return False


def main():
    try:
        payload = json.load(sys.stdin)
        data = payload.get("tool_input", {})
        if isinstance(data, str):
            data = json.loads(data)
        command = data.get("command", data.get("cmd", ""))
        if not isinstance(command, str):
            raise ValueError("command must be a string")
    except (ValueError, AttributeError):
        print("Entire safety guard: malformed hook payload; command was not approved.", file=sys.stderr)
        return 2
    if blocked(command):
        print("Entire maintenance blocked: doctor/clean/resume/attach/rewind may change or delete tracking. "
              "Review must use python3 -B scripts/entire-review-readonly.py. "
              "Do not retry via another shell or interpreter; maintenance needs a separate backed-up procedure.",
              file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
