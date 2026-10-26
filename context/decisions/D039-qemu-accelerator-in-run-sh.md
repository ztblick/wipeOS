---
id: D39
title: "QEMU accelerator in run.sh"
status: accepted
date: 2026-10-26
decided_in: docs/plans/portable-build-host-and-fast-CI.md
---

# D39: QEMU accelerator in run.sh

**Decision.** `scripts/run.sh` takes `--accel auto|kvm|tcg`, default `auto`.

- **`auto`:** KVM when the host is x86_64 and `/dev/kvm` is readable and writable by the user; otherwise TCG.
- **`kvm`:** forces KVM. If it isn't usable, `run.sh` exits 2 with the reason, before building anything.
- **`tcg`:** forces software emulation.
- The chosen accelerator is passed as `-accel kvm` or `-accel tcg`, and recorded in the `RUN` header as `accel=<kvm|tcg>`, next to `mode=`.
- `-cpu max` for 1 GB pages stays as it is; it works under both accelerators.

**Rationale.** One launcher serves every host (D38): fast boots where KVM exists, and a working, slower boot where it doesn't. Recording the accelerator in the log keeps timings comparable between runs (D23).

**Alternatives considered.** Always KVM on x86_64 (fails on runners without `/dev/kvm` access instead of degrading); a separate CI-only launcher (two code paths that can drift apart).
