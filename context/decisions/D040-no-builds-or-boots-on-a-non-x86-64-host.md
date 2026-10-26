---
id: D40
title: "No builds or boots on a non-x86_64 host"
status: accepted
date: 2026-10-26
decided_in: docs/plans/portable-build-host-and-fast-CI.md
---

# D40: No builds or boots on a non-x86_64 host

**Decision.** `.claude/hooks/guard-build.py` denies, on a host whose machine type (`platform.machine()`, or `GUARD_BUILD_HOST_ARCH` if set, for the self-test) isn't `x86_64`:

- any `make` or `gmake`. Nothing on the laptop needs make: the stub is built by Buildroot (D26), and lint doesn't use make.
- `scripts/run.sh`, run directly or as the script argument of `bash` or `sh`, unless one of its arguments is `-h` or `--help`;
- `qemu-system-x86_64`.

The reason tells Claude to verify through CI or ask Zach to run it on the cluster. On x86_64 hosts, nothing changes.

This amends D35. D35's pass list includes `make`, `scripts/run.sh` with any options, and `qemu-system-x86_64` without KVM flags; on a non-x86_64 host these are now denied. The rest of D35 is unchanged.

**Rationale.** D38 makes the laptop a workstation. A forgotten `make` there would start a 40-minute build that the workflow no longer needs, and a deny gives Claude the right route (CI or the cluster) at once.

**Alternatives considered.** A CLAUDE.md rule only (one forgotten `make` costs 40 minutes and fails anyway); asking instead of denying (there's no legitimate build on the laptop any more); denying `make` only in `buildroot/` (the hook would have to guess the shell's directory from `cd` and `-C`, for no gain, since nothing else on the laptop needs make).
