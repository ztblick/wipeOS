#!/usr/bin/env python3
"""Claude Code PreToolUse hook: the git workflow for agents (D44).

Registered in .claude/settings.json for Bash. Agents develop on a branch,
push it and open a pull request; only Zach merges into main. GitHub's
ruleset on main requires a pull request and the CI check, but agents push
as Zach's account, so GitHub can't tell an agent's merge from Zach's.
This hook stops that, and the other moves an agent should never make,
before they reach GitHub.

Denies (exit 2, reason on stderr, which Claude sees):
  1. git push that forces or deletes: -f, --force, --force-with-lease,
     --force-if-includes, --mirror, --all, --delete, -d, --prune, or a
     refspec starting with + or :.
  2. git push to main: a refspec main or refs/heads/main, <src>:main or
     <src>:refs/heads/main, HEAD (or @) while on main, or no refspec
     while on main.
  3. While on main: git commit, merge, cherry-pick, revert, am, rebase.
     git pull --ff-only stays allowed, to bring main up to date.
  4. gh pr merge, and gh pr review --approve (-a).
  5. gh api writes: -X or --method other than GET, or -f, -F, --field,
     --raw-field or --input.
  6. gh repo edit, delete, rename or archive; gh secret and gh variable
     set or delete; gh auth token, login, logout, refresh or switch.

Everything else passes, including git push -u origin claude/<topic>,
gh pr create, gh pr view, gh pr checks and gh run view.

Each simple command is checked on its own, including commands run through
timeout, env, nice, sudo or bash -c. The checks match words, so they stop
the obvious and the accidental, not a determined attempt (an agent holding
Zach's token could still reach GitHub's API another way).

"On main" means the project's own repo has main checked out: git
symbolic-ref in $CLAUDE_PROJECT_DIR (D37), or GUARD_GIT_BRANCH if set in
the hook's own environment, for scripts/hooks-selftest.sh. A detached
HEAD, or a branch that can't be read, counts as not main.

Exit 0, no output: no objection; the normal permission flow applies.
Exit 2: denied; stderr tells Claude why. A command that can't be parsed
is denied too. Any crash also blocks, because the hook is registered with
onFailure "block".

Test without Claude Code by piping in the JSON it would send:
  echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 3"}}' |
    python3 .claude/hooks/guard-git.py; echo "exit $?"
"""

import json
import os
import re
import shlex
import subprocess
import sys

MAIN = "main"

SEPARATORS = {";", "&&", "||", "|", "&", "|&", "(", ")", "\n"}
ASSIGNMENT = re.compile(r"^[A-Za-z_]\w*=")

# Commands that run the command after them. Their options are skipped;
# timeout also takes a duration.
WRAPPERS = {"env", "timeout", "nice", "nohup", "exec", "command", "time",
            "stdbuf", "xargs", "sudo"}
SHELLS = {"bash", "sh", "dash", "zsh"}


def subcommands(cmd):
    """Split a command line into its simple commands, as word lists.
    The same split as guard-lint.py and guard-build.py."""
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


def unwrap(words):
    """The words from the real command on, after leading VAR=value
    assignments and wrappers such as timeout. As in guard-build.py."""
    i = 0
    while True:
        while i < len(words) and ASSIGNMENT.match(words[i]):
            i += 1
        if i >= len(words):
            return []
        name = os.path.basename(words[i])
        if name not in WRAPPERS:
            return words[i:]
        i += 1
        while i < len(words) and words[i].startswith("-"):
            i += 1
        if name == "timeout" and i < len(words) and words[i][:1].isdigit():
            i += 1


_branch = None


def current_branch():
    """The branch checked out in the project's repo, or "" if detached or
    unknown. Read at most once per call, and only when a rule needs it."""
    global _branch
    if _branch is None:
        _branch = os.environ.get("GUARD_GIT_BRANCH")
    if _branch is None:
        project = os.environ.get("CLAUDE_PROJECT_DIR") or "."
        try:
            out = subprocess.run(
                ["git", "-C", project, "symbolic-ref", "--short", "-q",
                 "HEAD"], capture_output=True, text=True, timeout=5)
            _branch = out.stdout.strip() if out.returncode == 0 else ""
        except (OSError, subprocess.SubprocessError):
            _branch = ""
    return _branch


# ------------------------------------------------------------------- git

def git_subcommand(words):
    """For a git command, return (subcommand, its arguments), skipping
    git's global options. As in guard-lint.py."""
    i = 1
    while i < len(words) and words[i].startswith("-"):
        if words[i] in ("-c", "-C", "--git-dir", "--work-tree",
                        "--namespace", "--exec-path") and i + 1 < len(words):
            i += 2
        else:
            i += 1
    sub = words[i] if i < len(words) else ""
    return sub, words[i + 1:]


PUSH_FORCE_LONG = re.compile(r"^--(?:force|force-with-lease|force-if-includes"
                             r"|mirror|all|delete|prune)(?:=|$)")
# git push options that take the next word as their value.
PUSH_VALUE_OPTS = {"-o", "--push-option", "--repo", "--receive-pack",
                   "--exec"}


def push_reason(args):
    positional, skip = [], False
    for a in args:
        if skip:
            skip = False
            continue
        if a in PUSH_VALUE_OPTS:
            skip = True
        elif PUSH_FORCE_LONG.match(a):
            return f"uses git push {a}, which forces or deletes"
        elif a.startswith("-") and not a.startswith("--"):
            # A cluster of short options, such as -uf. -o takes the rest
            # of the word as its value.
            for ch in a[1:]:
                if ch == "o":
                    break
                if ch in "fd":
                    return f"uses git push {a}, which forces or deletes"
        elif not a.startswith("-"):
            positional.append(a)
    refspecs = positional[1:]  # the first one is the remote
    for r in refspecs:
        if r.startswith(("+", ":")):
            return f"pushes {r}, which forces or deletes"
        dst = r.split(":", 1)[-1]
        if dst in (MAIN, f"refs/heads/{MAIN}"):
            return f"pushes to {MAIN}"
        if dst in ("HEAD", "@") and current_branch() == MAIN:
            return f"pushes HEAD, which is {MAIN}"
    if not refspecs and current_branch() == MAIN:
        return f"pushes with no branch named while {MAIN} is checked out"
    return None


COMMITS_ON_MAIN = {"commit", "merge", "cherry-pick", "revert", "am",
                   "rebase"}


def git_reason(words):
    sub, args = git_subcommand(words)
    if sub == "push":
        reason = push_reason(args)
        if reason:
            return (f"{reason}. Agents push only their own claude/<topic> "
                    "branch, without forcing, and Zach merges into main "
                    "(D44).")
    if sub in COMMITS_ON_MAIN and current_branch() == MAIN:
        return (f"runs git {sub} with {MAIN} checked out. Create a branch "
                "first (git switch -c claude/<topic>); only Zach changes "
                "main, by merging a pull request (D44).")
    return None


# -------------------------------------------------------------------- gh

def gh_api_write(args):
    for i, a in enumerate(args):
        if a in ("-f", "-F", "--field", "--raw-field", "--input") \
                or re.match(r"^(?:--field=|--raw-field=|--input=|-[fF].)", a):
            return True
        method = None
        if a in ("-X", "--method") and i + 1 < len(args):
            method = args[i + 1]
        elif a.startswith("--method="):
            method = a.split("=", 1)[1]
        elif a.startswith("-X") and len(a) > 2:
            method = a[2:]
        if method is not None and method.upper() != "GET":
            return True
    return False


GH_DENY = {
    "repo": {"edit", "delete", "rename", "archive"},
    "secret": {"set", "delete", "remove"},
    "variable": {"set", "delete", "remove"},
    "auth": {"token", "login", "logout", "refresh", "switch"},
}


def gh_reason(args):
    plain = [a for a in args if not a.startswith("-")]
    group = plain[0] if plain else ""
    sub = plain[1] if len(plain) > 1 else ""
    what = None
    if group == "pr" and sub == "merge":
        what = "gh pr merge"
    elif group == "pr" and sub == "review" \
            and any(a in ("--approve", "-a") for a in args):
        what = "gh pr review --approve"
    elif group == "api" and gh_api_write(args[1:]):
        what = "gh api with a write"
    elif sub in GH_DENY.get(group, ()):
        what = f"gh {group} {sub}"
    if what:
        return (f"runs {what}. Agents open and update pull requests; "
                "merging, approving and changing the repository, its "
                "secrets or the login are Zach's (D44).")
    return None


# ------------------------------------------------------------------ main

def check(cmd, depth=0):
    """Return the deny reasons for a command line."""
    deny = []
    for raw in subcommands(cmd):
        words = unwrap(raw)
        if not words:
            continue
        name = os.path.basename(words[0])
        args = words[1:]
        if name in SHELLS and "-c" in args and depth < 3:
            i = args.index("-c")
            if i + 1 < len(args):
                deny += check(args[i + 1], depth + 1)
            continue
        reason = None
        if name == "git":
            reason = git_reason(words)
        elif name == "gh":
            reason = gh_reason(args)
        if reason:
            deny.append(reason)
    return deny


def main():
    data = json.load(sys.stdin)
    if data.get("tool_name") != "Bash":
        return
    cmd = (data.get("tool_input") or {}).get("command", "")
    try:
        deny = check(cmd)
    except ValueError:
        # Unbalanced quotes: we can't tell what it runs, so refuse.
        deny = ["can't be parsed reliably (unbalanced quotes); rewrite it."]
    if deny:
        print(f"Git guard: this command {deny[0]}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
