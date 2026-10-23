#!/usr/bin/env python3
"""Claude Code PreToolUse hook: no way around the linter.

Registered in .claude/settings.json for two kinds of tool call.

Bash. Blocks (exit 2, reason on stderr) any command that:
  1. skips git hooks: --no-verify, any abbreviation of it git accepts, or
     -n on git commit (git's short form of --no-verify);
  2. points git's hooks somewhere else: core.hooksPath set to anything but
     .githooks, or unset, by git config or git -c; or git config passed
     through GIT_CONFIG_* environment variables;
  3. turns Claude Code's hooks off: disableAllHooks;
  4. changes a lint file through the shell: .githooks/, scripts/lint.sh,
     scripts/lint-selftest.sh, .checkpatch.conf, .claude/, and
     .git/config and .git/hooks/. The Edit tool already has to ask before
     touching most of these (settings.json); this closes the shell route.
     Reading them and running the lint scripts is allowed.

Edit, Write and MultiEdit on C files under src/. Asks Zach (permission
"ask") when the change adds a lint suppression: a cppcheck-suppress comment
or a GCC or clang diagnostic pragma. D33 allows suppressing a false
positive in the code with a comment giving the reason; this makes each new
one a decision Zach sees.

The checks match text, so they stop the obvious and the accidental, not a
determined attempt (a script written to a file and then run, say). The
pre-commit hook and a CI lint run remain the backstop.

Exit 0: no objection; the normal permission flow applies.
Exit 2: blocked; stderr tells Claude why.
Any crash also blocks, because the hook is registered with
onFailure "block".

Test without Claude Code by piping in the JSON it would send:
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -n -m x"}}' |
    .claude/hooks/guard-lint.py; echo "exit $?"
"""

import json
import os
import re
import shlex
import sys
from pathlib import Path

# ------------------------------------------------------------------ Bash

# git accepts any unambiguous prefix of a long option, so --no-veri works
# too. --no-v is the shortest form git accepts for commit and push.
NO_VERIFY = re.compile(r"--no-v(?:e(?:r(?:i(?:fy?)?)?)?)?(?![\w-])")
HOOKS_PATH = re.compile(r"core\.hookspath", re.I)
GIT_ENV_CONFIG = re.compile(r"\bGIT_CONFIG_(?:PARAMETERS|COUNT|KEY_|VALUE_)")
DISABLE_HOOKS = re.compile(r"disableAllHooks", re.I)

# Paths the shell must not change. Matched against each word of the
# command, after stripping quotes.
PROTECTED = re.compile(
    r"(?:^|/)(?:"
    r"\.githooks(?:/|$)"
    r"|scripts/lint(?:-selftest)?\.sh$"
    r"|\.checkpatch\.conf$"
    r"|\.claude(?:/|$)"
    r"|\.git/(?:config$|hooks(?:/|$))"
    r")")

# Commands that only read their arguments.
READ_ONLY = {"cat", "less", "more", "head", "tail", "grep", "egrep", "fgrep",
             "rg", "diff", "cmp", "wc", "ls", "stat", "file", "sha256sum",
             "md5sum", "realpath", "readlink", "test", "["}
# git subcommands that leave the working tree as it is. add and commit
# record a lint file Zach changed; they don't change it.
GIT_READ_ONLY = {"diff", "log", "show", "status", "blame", "ls-files",
                 "rev-parse", "cat-file", "grep", "add", "commit"}

# Scripts that may be run (not changed) by naming them.
RUNNABLE = re.compile(r"(?:^|/)(?:scripts/lint(?:-selftest)?\.sh"
                      r"|\.githooks/pre-commit|\.claude/hooks/[^/]+)$")

SEPARATORS = {";", "&&", "||", "|", "&", "|&", "(", ")", "\n"}
REDIRECTS = {">", ">>", ">|", "&>", "&>>", "<>"}


def subcommands(cmd):
    """Split a command line into its simple commands, as word lists."""
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()<>")
    lex.whitespace_split = True
    lex.commenters = ""
    words, current = [], []
    for tok in lex:
        if tok in SEPARATORS:
            if current:
                words.append(current)
            current = []
        else:
            current.append(tok)
    if current:
        words.append(current)
    return words


def strip_assignments(words):
    i = 0
    while i < len(words) and re.match(r"^[A-Za-z_]\w*=", words[i]):
        i += 1
    return words[i:]


def git_subcommand(words):
    """For a git command, return (subcommand, its arguments), skipping
    git's global options. -c values are returned separately."""
    i, configs = 1, []
    while i < len(words) and words[i].startswith("-"):
        if words[i] in ("-c", "-C", "--git-dir", "--work-tree",
                        "--namespace", "--exec-path") and i + 1 < len(words):
            if words[i] == "-c":
                configs.append(words[i + 1])
            i += 2
        else:
            i += 1
    sub = words[i] if i < len(words) else ""
    return sub, words[i + 1:], configs


def commit_short_no_verify(args):
    """True if a short-option cluster on git commit contains -n.

    In a cluster such as -anm, each letter is its own option until one
    that takes a value (m, F, C, c, t); the rest of the cluster is that
    value, so -mn is a message "n", not -n.
    """
    takes_value = set("mFCct")
    skip_next = False
    for a in args:
        if skip_next:
            skip_next = False
            continue
        if a == "--":
            break
        if not a.startswith("-") or a.startswith("--") or a == "-":
            continue
        for j, ch in enumerate(a[1:]):
            if ch == "n":
                return True
            if ch in takes_value:
                skip_next = j == len(a) - 2  # value is the next word
                break
    return False


def hooks_path_ok(sub, args, configs):
    """core.hooksPath may only be read, or set to .githooks."""
    for c in configs:
        if HOOKS_PATH.match(c):
            return False
    if sub != "config":
        return True
    plain = [a for a in args if not a.startswith("-")]
    flags = [a for a in args if a.startswith("-")]
    if not any(HOOKS_PATH.fullmatch(a) for a in plain):
        return True
    if any(f.startswith(("--unset", "--remove", "--replace", "--add",
                         "--edit", "-e")) for f in flags):
        return False
    key_at = next(i for i, a in enumerate(plain) if HOOKS_PATH.fullmatch(a))
    value = plain[key_at + 1:]
    return value in ([], [".githooks"], [".githooks/"])


def check_bash(cmd):
    if NO_VERIFY.search(cmd):
        return ("skips git hooks (--no-verify). Commits must pass the "
                "pre-commit lint. Fix the findings, or ask Zach.")
    if GIT_ENV_CONFIG.search(cmd):
        return ("passes git configuration through GIT_CONFIG_* variables, "
                "which can redirect or skip git hooks.")
    if DISABLE_HOOKS.search(cmd):
        return "would turn off Claude Code's hooks (disableAllHooks)."

    try:
        cmds = subcommands(cmd)
    except ValueError:
        # Unbalanced quotes: we can't tell what it runs, so refuse.
        return "can't be parsed reliably (unbalanced quotes); rewrite it."

    for raw in cmds:
        words = strip_assignments(raw)
        if not words:
            continue
        name = os.path.basename(words[0])

        if name == "git":
            sub, args, configs = git_subcommand(words)
            if sub == "commit" and commit_short_no_verify(args):
                return ("uses git commit -n, which skips the pre-commit "
                        "lint. Fix the findings, or ask Zach.")
            if not hooks_path_ok(sub, args, configs):
                return ("changes core.hooksPath. It must stay .githooks, "
                        "where the pre-commit lint lives.")

        # Redirection into a protected path is a write, whatever the command.
        for i, w in enumerate(words[:-1]):
            if w in REDIRECTS and PROTECTED.search(words[i + 1]):
                return f"writes to {words[i + 1]}, a lint file."

        if name == "git":
            sub, args, _ = git_subcommand(words)
            if sub == "config":
                # hooks_path_ok() above has vetted any core.hooksPath value,
                # including the opt-in ".githooks". Only a config file named
                # in a lint location is left to refuse.
                for i, a in enumerate(args[:-1]):
                    if a in ("--file", "-f") and PROTECTED.search(args[i + 1]):
                        return f"writes git config into {args[i + 1]}."
                continue

        touched = [w for w in words[1:] if PROTECTED.search(w)]
        if not touched:
            continue
        if name in READ_ONLY:
            continue
        if name == "git":
            sub, _, _ = git_subcommand(words)
            if sub in GIT_READ_ONLY:
                continue
        if name in ("bash", "sh") and RUNNABLE.search(words[1]) \
                and touched == [words[1]]:
            continue
        return (f"uses {name} on {touched[0]}, a lint file. Read it with "
                "cat or grep; changes to lint files go through Zach.")

    # Running a lint script directly is fine; it isn't an argument above.
    return None


# ------------------------------------------------- Edit / Write on src/

SUPPRESSION = re.compile(r"cppcheck-suppress|#\s*pragma\s+(?:GCC|clang)"
                         r"\s+diagnostic", re.I)


def new_suppressions(tool, ti, project):
    path = ti.get("file_path", "")
    rel = os.path.relpath(path, project) if project else path
    if not re.search(r"(?:^|/)src/.*\.[ch]$", rel):
        return 0
    if tool == "Write":
        before = ""
        try:
            before = Path(path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            pass
        return (len(SUPPRESSION.findall(ti.get("content", "")))
                - len(SUPPRESSION.findall(before)))
    if tool == "Edit":
        return (len(SUPPRESSION.findall(ti.get("new_string", "")))
                - len(SUPPRESSION.findall(ti.get("old_string", ""))))
    if tool == "MultiEdit":
        return sum(len(SUPPRESSION.findall(e.get("new_string", "")))
                   - len(SUPPRESSION.findall(e.get("old_string", "")))
                   for e in ti.get("edits", []))
    return 0


def main():
    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    ti = data.get("tool_input", {}) or {}

    if tool == "Bash":
        reason = check_bash(ti.get("command", ""))
        if reason:
            print(f"Lint guard: this command {reason}", file=sys.stderr)
            sys.exit(2)
        return

    if tool in ("Edit", "Write", "MultiEdit"):
        added = new_suppressions(tool, ti, os.environ.get("CLAUDE_PROJECT_DIR"))
        if added > 0:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask",
                "permissionDecisionReason":
                    "Lint guard: this edit adds a lint suppression to "
                    f"{os.path.basename(ti.get('file_path', ''))}. Check "
                    "that the finding is a false positive and the comment "
                    "gives the reason (D33)."}}))


if __name__ == "__main__":
    main()
