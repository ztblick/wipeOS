---
id: D37
title: "Conventions for our hooks"
status: accepted
date: 2026-10-23
decided_in: docs/plans/build-gaurd-and-index-check.md
---

# D37: Conventions for our hooks

**Decision.**

- **Registration.** New Claude Code hooks are Python, registered in exec form as `"command": "python3", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.py"]`, so they need no executable bit. PreToolUse hooks also set `"onFailure": "block"`.
- **Project root.** Every hook works from `$CLAUDE_PROJECT_DIR`, never from the current directory. Hooks run in the shell's current directory, and Claude often `cd`s into `buildroot/`, a separate git repository, where `git rev-parse` finds the wrong repo.
- **Self-test.** `scripts/hooks-selftest.sh` feeds each hook the JSON Claude Code would send, for a fixed table of cases, and exits 0 only if every case gives the expected result: block, ask or pass. It is protected like the lint scripts: in the lint guard's protected paths and runnable scripts (D34), and in the `ask` list in `.claude/settings.json`.
- **Running hooks by hand.** The lint guard allows `python3` (or `python`) when the only protected word in the command is a script under `.claude/hooks/` in the first argument position. Running a hook script is not changing it. `python3 -c`, redirects into `.claude/`, and every other write stay blocked.

**Rationale.** Claude can't set the executable bit inside `.claude/`, because the lint guard blocks `chmod` there; exec form sidesteps it. A fixed case table lets Zach recheck every hook decision with one command after any change.

**Alternatives considered.** Bash hooks registered by path (needs the executable bit); registering with `"command"` pointing at the script (same); a test harness in Python (fine either way; the self-test is bash, like `scripts/lint-selftest.sh`).
