---
id: D24
title: "No address randomization, kernel or userspace"
status: accepted
date: 2026-10-20
---

# D24: No address randomization, kernel or userspace

**Decision.** KASLR is off (`CONFIG_RANDOMIZE_BASE`, which also turns off `RANDOMIZE_MEMORY`). Userspace randomization is off via a built-in kernel command line, `CONFIG_CMDLINE="norandmaps"`, which adds to boot-loader arguments rather than overriding them. The kernel always loads at `PHYSICAL_START` (16 MB). `PHYSICAL_ALIGN` stays at its 2 MB minimum.

**Rationale.**

- Determinism is the top priority: identical memory layout on every boot makes footprint, fill coverage and timings reproducible.
- Randomization defends against exploits by untrusted code. WipeOS runs none, and the host is already untrusted.
- Building both into the image means it doesn't depend on whoever builds the command line (QEMU's `-append`, or the D19 agent's `kexec --append`).
- `norandmaps` rather than having the stub write `/proc/sys/kernel/randomize_va_space`: the stub is process 1, so its own layout would already be randomized by then.
- With KASLR off, the kernel sits inside the first gigabyte, which can't be a 1 GB huge page anyway (D22).

**Alternatives considered.** The `nokaslr` boot option: depends on the command line. The stub writing `randomize_va_space`: misses process 1. Keeping randomization: layout changes on every boot, with little security value here.

