---
id: D34
title: "Lint bypass guard"
status: accepted
date: 2026-10-23
decided_in: docs/plans/build-gaurd-and-index-check.md
---

# D34: Lint bypass guard

**Decision.** `.claude/hooks/guard-lint.py`, a Claude Code PreToolUse hook on Bash and on Edit, Write and MultiEdit, keeps every route around the lint (D33) closed. On Bash it blocks (exit 2): `--no-verify` and any abbreviation git accepts, and `-n` on `git commit`; `core.hooksPath` set to anything but `.githooks`, or unset, through `git config`, `git -c` or `GIT_CONFIG_*` variables; `disableAllHooks`; and shell commands that change `.githooks/`, `scripts/lint*.sh`, `scripts/hooks-selftest.sh`, `.checkpatch.conf`, `.claude/`, `.git/config` or `.git/hooks/`. Reading these files, running the lint scripts, running a hook script with `python3` (D37), and `git add` or `git commit` stay allowed. An edit to a C file under `src/` that adds a suppression (a `cppcheck-suppress` comment, or a GCC or clang diagnostic pragma) returns "ask", so Zach sees each one. It is registered with `onFailure: "block"`, so a crashing guard blocks the call. Dev tooling only; nothing is added to the image.

**Rationale.** The pre-commit hook alone can be skipped with one `--no-verify`, and plan mode removes Zach's approval prompts, so the bypass routes need closing where Claude runs commands. Suppressions are legitimate under D33, but each is a judgment a human should see.

**Alternatives considered.** Allowing suppressions automatically when they carry a reason comment (no prompt, but no human sees the call either); relying on the pre-commit hook alone (one `--no-verify` skips it).
