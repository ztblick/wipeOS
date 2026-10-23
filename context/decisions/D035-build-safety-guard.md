---
id: D35
title: "Build-safety guard"
status: accepted
date: 2026-10-23
decided_in: docs/plans/build-gaurd-and-index-check.md
---

# D35: Build-safety guard

**Decision.** `.claude/hooks/guard-build.py`, a Claude Code PreToolUse hook on Bash separate from the lint guard (D34), enforces the "Development environment" rules in CLAUDE.md. What CLAUDE.md says "never" is denied (exit 2, reason to Claude); what it says to do only after asking goes to Zach as a permission "ask".

- **Deny:** KVM flags (`-enable-kvm`, `-accel kvm`, `-accel=kvm`, `accel=kvm` in `-machine`, `-cpu host`), but only when `/dev/kvm` is absent; Windows executables (a command word ending in `.exe`, and `powershell`, `pwsh`, `cmd.exe`, `wsl.exe`); any word under `/mnt/<drive letter>/`.
- **Ask:** `make` with a target `clean`, `distclean` or `<pkg>-dirclean`; `make` with a `-rebuild`, `-reconfigure` or `-reinstall` target for `toolchain*`, `host-gcc*`, `host-binutils*`, `glibc` or `linux-headers`; `rm` of a path ending in `output`, containing `output/`, or naming the `buildroot` checkout; system packages (`apt`, `apt-get`, `aptitude`, `dpkg -i`, `snap install`, `pip`/`pip3 install`, `python -m pip install`, `npm install -g`/`--global`, `npm i -g`); any `sudo`. `sudo` extends CLAUDE.md, since every system change goes through it and Claude has no reason to need it here.

Everything else passes untouched, including `make`, `make <pkg>-rebuild`, `make linux-rebuild`, `scripts/run.sh` with any options, and `qemu-system-x86_64` without KVM flags. A toolchain rebuild caused indirectly, by a changed defconfig, can't be seen from the command line and stays a CLAUDE.md rule. Dev tooling only; nothing is added to the image.

**Rationale.** Plan mode removed Zach's approval prompts, so a forgotten `make clean` would cost a 40-minute toolchain rebuild with nobody watching. Following CLAUDE.md's own wording keeps the split predictable: the KVM and Windows rules have no legitimate exception on this host, while a clean or an install sometimes is the right call and only needs Zach's OK.

**Alternatives considered.** One combined guard script with the lint guard (shorter settings, but lint and build rules change for different reasons); deny everything (a legitimate `make clean` would need Zach to run it himself); ask for everything (the KVM and Windows rules have no legitimate exception on this host).
