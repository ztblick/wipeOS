#!/usr/bin/env python3
"""Claude Code PreToolUse hook: the build and environment rules in CLAUDE.md.

Registered in .claude/settings.json for Bash (D35). What CLAUDE.md says
never to do is denied; what it says to do only after asking goes to Zach
as a permission prompt.

Denies (exit 2, reason on stderr, which Claude sees):
  1. KVM flags when /dev/kvm is absent: -enable-kvm, -accel kvm,
     -accel=kvm, accel=kvm in -machine, -cpu host. There is no KVM for
     x86 guests on the laptop; on a host that has it, the rule lifts.
  2. Windows executables: a command ending in .exe, powershell, pwsh.
  3. The Windows filesystem: any word under /mnt/<drive letter>/.
  4. Builds and boots on a host that isn't x86_64 (D40, amending D35):
     make or gmake; scripts/run.sh, run directly or through bash or sh,
     unless an argument is -h or --help; qemu-system-x86_64. Builds and
     boots run on x86_64 hosts only (D38): CI and the cluster.
     The same commands are denied in an agent session in GitHub, where
     agents.yml sets WIPEOS_AGENT_CI=1, whatever the host (D54): agents
     verify through the build and boot check instead.

Asks Zach (permission "ask", with the reason in the prompt):
  5. make clean, make distclean, make <pkg>-dirclean;
  6. a toolchain rebuild: -rebuild, -reconfigure or -reinstall of
     toolchain*, host-gcc*, host-binutils*, glibc or linux-headers;
  7. rm of build output: a path whose last part is output (or a glob
     that matches it), a path containing output/, or the buildroot
     checkout;
  8. system packages: apt, apt-get, aptitude, dpkg -i, snap install,
     pip install, python -m pip install, npm install -g;
  9. sudo, for anything.

Everything else passes. On an x86_64 host that includes make, make
linux-rebuild, make <pkg>-rebuild, scripts/run.sh, and qemu-system-x86_64
without KVM flags.

Each simple command is checked on its own, so cd buildroot && make clean
is caught, and so are commands run through timeout, env, nice, sudo or
bash -c. A toolchain rebuild caused by a changed defconfig can't be seen
from the command line; that stays a CLAUDE.md rule. The checks match
words, so they stop the obvious and the accidental, not a determined
attempt (a script written to a file and then run, say).

Exit 0, no output: no objection; the normal permission flow applies.
Exit 0, JSON on stdout: ask Zach.
Exit 2: denied; stderr tells Claude why. A command that can't be parsed
is denied too. Any crash also blocks, because the hook is registered with
onFailure "block".

The KVM device checked is /dev/kvm, or GUARD_BUILD_KVM_DEVICE if set in
the hook's own environment, and the host architecture is
platform.machine(), or GUARD_BUILD_HOST_ARCH if set. Both overrides are
for scripts/hooks-selftest.sh; a Bash command can't set them, since
Claude Code starts the hook, not the shell.

Test without Claude Code by piping in the JSON it would send:
  echo '{"tool_name":"Bash","tool_input":{"command":"make clean"}}' |
    python3 .claude/hooks/guard-build.py; echo "exit $?"
"""

import fnmatch
import json
import os
import platform
import re
import shlex
import sys

SEPARATORS = {";", "&&", "||", "|", "&", "|&", "(", ")", "\n"}
ASSIGNMENT = re.compile(r"^[A-Za-z_]\w*=")

# Commands that run the command after them. Their options are skipped;
# timeout also takes a duration.
WRAPPERS = {"env", "timeout", "nice", "nohup", "exec", "command", "time",
            "stdbuf", "xargs", "sudo"}
SHELLS = {"bash", "sh", "dash", "zsh"}

# Read once: the machine doesn't change during a call.
HOST_ARCH = os.environ.get("GUARD_BUILD_HOST_ARCH") or platform.machine()
# Set by agents.yml in every agent job (D54). Like the overrides above, it
# is in the hook's own environment, which a Bash command can't change.
AGENT_CI = os.environ.get("WIPEOS_AGENT_CI") == "1"


def subcommands(cmd):
    """Split a command line into its simple commands, as word lists.
    The same split as guard-lint.py."""
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
    """Return (the words from the real command on, whether sudo was seen).
    Leading VAR=value assignments and wrappers such as timeout are
    skipped."""
    sudo = False
    i = 0
    while True:
        while i < len(words) and ASSIGNMENT.match(words[i]):
            i += 1
        if i >= len(words):
            return [], sudo
        name = os.path.basename(words[i])
        if name not in WRAPPERS:
            return words[i:], sudo
        sudo = sudo or name == "sudo"
        i += 1
        while i < len(words) and words[i].startswith("-"):
            i += 1
        if name == "timeout" and i < len(words) and words[i][:1].isdigit():
            i += 1


# ------------------------------------------------------------------ deny

def kvm_available():
    return os.path.exists(os.environ.get("GUARD_BUILD_KVM_DEVICE",
                                         "/dev/kvm"))


MACHINE_KVM = re.compile(r"(?:^|,)accel=(?:[^,]*:)?kvm(?::|,|$)")
WINDOWS_PATH = re.compile(r"(?:^|[=:])/mnt/[A-Za-z](?:/|$)")
WINDOWS_PROGRAMS = {"powershell", "pwsh", "cmd.exe", "wsl.exe"}


def first_part(word):
    return word.split(",", 1)[0]


def kvm_flag(words):
    """The KVM flag in a command's words, or None."""
    for i, w in enumerate(words):
        nxt = words[i + 1] if i + 1 < len(words) else ""
        if w in ("-enable-kvm", "--enable-kvm"):
            return w
        if w in ("-accel", "--accel") and first_part(nxt) == "kvm":
            return f"{w} {nxt}"
        if re.match(r"^--?accel=kvm(?:,|$)", w):
            return w
        if MACHINE_KVM.search(w):
            return w
        if w in ("-cpu", "--cpu") and first_part(nxt) == "host":
            return f"{w} {nxt}"
    return None


def runs_launcher(name, args):
    """True if the command runs scripts/run.sh to build or boot, directly
    or as the script given to bash or sh. --help only prints usage."""
    if name in SHELLS:
        if not args or args[0].startswith("-"):
            return False
        name, args = os.path.basename(args[0]), args[1:]
    return name == "run.sh" and not any(a in ("-h", "--help")
                                         for a in args)


def arch_reason(name, args):
    """D40: no builds or boots on a host that isn't x86_64. D54: none in
    an agent session in GitHub either."""
    if HOST_ARCH == "x86_64" and not AGENT_CI:
        return None
    what = None
    if name in ("make", "gmake", "qemu-system-x86_64"):
        what = name
    elif runs_launcher(name, args):
        what = "scripts/run.sh"
    if what and AGENT_CI:
        return (f"runs {what} in an agent session in GitHub. Agents don't "
                "build or boot (D54): push, then read the build and boot "
                "check's summary (gh run view) and its boot-logs artifact "
                "(gh run download <run-id> -n boot-logs).")
    if what:
        return (f"runs {what} on this {HOST_ARCH} host. Builds and boots "
                "run only on x86_64 hosts (D38, D40): verify through CI, "
                "or ask Zach to run it on the cluster.")
    return None


def deny_reason(words):
    if not kvm_available():
        flag = kvm_flag(words)
        if flag:
            return (f"uses {flag}, but this host has no KVM for x86 guests. "
                    "QEMU runs under TCG here; drop the flag (CLAUDE.md, "
                    "Development environment).")
    name = os.path.basename(words[0]).lower()
    if name.endswith(".exe") or name in WINDOWS_PROGRAMS:
        return (f"runs {words[0]}, a Windows program. Windows interop is "
                "off in this WSL; do it from Linux, or ask Zach.")
    for w in words:
        if WINDOWS_PATH.search(w):
            return (f"touches {w}, on the Windows filesystem. Buildroot "
                    "breaks there; work under ~/wipeOS.")
    return arch_reason(name, words[1:])


# ------------------------------------------------------------------- ask

# make options that take the next word as their value.
MAKE_VALUE_OPTS = {"-C", "-f", "-I", "-o", "-W", "--directory", "--file",
                   "--makefile", "--include-dir", "--old-file",
                   "--assume-old", "--new-file", "--assume-new", "--what-if"}
TOOLCHAIN = re.compile(r"^(?:(?:toolchain|host-gcc|host-binutils)[\w.+-]*"
                       r"|glibc|linux-headers)-(?:rebuild|reconfigure"
                       r"|reinstall)$")


def make_targets(args):
    targets, skip = [], False
    for i, a in enumerate(args):
        if skip:
            skip = False
            continue
        if a in MAKE_VALUE_OPTS:
            skip = True
        elif a in ("-j", "-l", "--jobs", "--load-average"):
            # The value is optional; take the next word only if it's a number.
            skip = i + 1 < len(args) and args[i + 1].isdigit()
        elif not a.startswith("-") and not ASSIGNMENT.match(a):
            targets.append(a)
    return targets


def make_reason(args):
    for t in make_targets(args):
        if t in ("clean", "distclean") or t.endswith("-dirclean"):
            return (f"runs make {t}, which deletes build output; rebuilding "
                    "can take about 40 minutes. CLAUDE.md asks for your OK.")
        if TOOLCHAIN.match(t):
            return (f"runs make {t}, a toolchain rebuild. CLAUDE.md asks "
                    "for your OK.")
    return None


def rm_reason(args):
    for a in args:
        if a.startswith("-"):
            continue
        path = a.rstrip("/")
        last = path.rsplit("/", 1)[-1]
        if "output/" in a or fnmatch.fnmatchcase("output", last) \
                or fnmatch.fnmatchcase("buildroot", last):
            return (f"deletes {a}, which may be Buildroot's checkout or "
                    "build output. CLAUDE.md asks for your OK.")
    return None


def first_arg(args):
    return next((a for a in args if not a.startswith("-")), "")


def package_reason(name, args):
    what = None
    if name in ("apt", "apt-get", "aptitude"):
        what = name
    elif name == "dpkg" and ("-i" in args or "--install" in args):
        what = "dpkg -i"
    elif name == "snap" and first_arg(args) == "install":
        what = "snap install"
    elif re.match(r"^pip[\d.]*$", name) and first_arg(args) == "install":
        what = f"{name} install"
    elif re.match(r"^python[\d.]*$", name) and args[:2] == ["-m", "pip"] \
            and "install" in args[2:]:
        what = f"{name} -m pip install"
    elif name == "npm" and first_arg(args) in ("install", "i", "add") \
            and any(a in ("-g", "--global", "--location=global")
                    for a in args):
        what = "npm install -g"
    if what:
        return (f"uses {what}, which changes the system's packages. "
                "CLAUDE.md asks you to say what's missing and why first.")
    return None


# ------------------------------------------------------------------ main

def check(cmd, depth=0):
    """Return (deny reasons, ask reasons) for a command line."""
    deny, ask = [], []
    for raw in subcommands(cmd):
        words, sudo = unwrap(raw)
        if sudo:
            ask.append("uses sudo. Claude has no reason to need root here.")
        if not words:
            continue
        name = os.path.basename(words[0])
        args = words[1:]
        reason = deny_reason(words)
        if reason:
            deny.append(reason)
        if name in SHELLS and "-c" in args and depth < 3:
            i = args.index("-c")
            if i + 1 < len(args):
                d, a = check(args[i + 1], depth + 1)
                deny += d
                ask += a
            continue
        for reason in (make_reason(args) if name in ("make", "gmake")
                       else None,
                       rm_reason(args) if name == "rm" else None,
                       package_reason(name, args)):
            if reason:
                ask.append(reason)
    return deny, ask


def main():
    data = json.load(sys.stdin)
    if data.get("tool_name") != "Bash":
        return
    cmd = (data.get("tool_input") or {}).get("command", "")
    try:
        deny, ask = check(cmd)
    except ValueError:
        # Unbalanced quotes: we can't tell what it runs, so refuse.
        deny, ask = ["can't be parsed reliably (unbalanced quotes); "
                     "rewrite it."], []
    if deny:
        print(f"Build guard: this command {deny[0]}", file=sys.stderr)
        sys.exit(2)
    if ask:
        # One reason per rule, even if several commands trip it.
        ask = list(dict.fromkeys(ask))
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason":
                "Build guard: this command " + " It also ".join(ask)}}))


if __name__ == "__main__":
    main()
