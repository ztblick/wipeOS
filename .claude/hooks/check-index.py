#!/usr/bin/env python3
"""Claude Code Stop hook: don't end a turn with context/INDEX.md stale.

Registered in .claude/settings.json (D36). Every session imports
context/INDEX.md through CLAUDE.md, so a record changed without
regenerating the index misleads the next session. This runs
scripts/context_index.py --check from the project root.

Exit 0, no output: the index is current.
Exit 2: the index is stale, or the check couldn't run. Claude Code keeps
  the turn going and shows stderr to Claude, which regenerates the index.
Exit 0, JSON with systemMessage: the same problem on the retry
  (stop_hook_active is true). The turn ends and Zach sees a warning, so a
  broken index can't loop the session.

Test without Claude Code by piping in the JSON it would send:
  echo '{"hook_event_name":"Stop","stop_hook_active":false}' |
    CLAUDE_PROJECT_DIR=$PWD python3 .claude/hooks/check-index.py
  echo "exit $?"
"""

import json
import os
import subprocess
import sys


def problem():
    """None if the index is current, else what is wrong."""
    project = os.environ.get("CLAUDE_PROJECT_DIR")
    if not project:
        return "the index check failed: CLAUDE_PROJECT_DIR is not set."
    # From the project root, not the shell's directory: from buildroot/,
    # context_index.py's git rev-parse would find Buildroot's checkout.
    try:
        r = subprocess.run([sys.executable, "scripts/context_index.py",
                            "--check"], cwd=project, capture_output=True,
                           text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"the index check failed: {e}"
    if r.returncode == 0:
        return None
    if r.returncode == 1:
        return ("context/INDEX.md is out of date; run "
                "scripts/context_index.py")
    detail = (r.stderr or r.stdout).strip() or f"exit {r.returncode}"
    return f"the index check failed: {detail}"


def main():
    try:
        data = json.load(sys.stdin)
        retry = bool(data.get("stop_hook_active"))
    except ValueError:
        # Treated like a failed check. Without the input we can't tell a
        # retry, so this blocks; Claude Code caps repeated Stop blocks.
        print("Index check: the hook input was not valid JSON, so the "
              "index check failed.", file=sys.stderr)
        sys.exit(2)

    msg = problem()
    if msg is None:
        return
    if retry:
        print(json.dumps({"systemMessage":
                          f"Index check: {msg} (still, after a retry; the "
                          "turn ends anyway)."}))
        return
    print(f"Index check: {msg}", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
