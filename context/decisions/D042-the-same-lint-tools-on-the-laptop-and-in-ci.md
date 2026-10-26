---
id: D42
title: "The same lint tools on the laptop and in CI"
status: accepted
date: 2026-10-26
decided_in: docs/plans/portable-build-host-and-fast-CI.md
---

# D42: The same lint tools on the laptop and in CI

**Decision.**

- **One distribution release.** The laptop and CI both run Ubuntu 26.04, so gcc (15.2) and cppcheck (2.19) come from the same packages. CI runs its job in the `ubuntu:26.04` container on a GitHub-hosted runner (D43). Build hosts lint with whatever tools they have; CI is the gate.
- **Compiler, always for x86_64 (D17).** `LINT_CC` if set; on an x86_64 host, `gcc`; otherwise `x86_64-linux-gnu-gcc` (Ubuntu's `gcc-x86-64-linux-gnu`, the same gcc release as the host's). If that compiler is missing or has no `-fanalyzer`, `lint.sh` exits 2 and names the package. There is no fallback to another compiler, and Buildroot's cross gcc is no longer used.
- **Versions in the output.** `lint.sh` prints a `tools` section first, with the compiler's and cppcheck's `--version` lines and the checkpatch path, so a difference between the laptop and CI shows in the logs.

**Rationale.** gcc's analyzer and cppcheck report different findings across releases, so a commit that lints clean locally could fail CI, or the reverse. Before this, the laptop linted with Buildroot's cross gcc 14.3 and CI's default runner image would have used gcc 13.

**Alternatives considered.** The `ubuntu-26.04` runner image instead of a container (simpler, but in public preview as of October 2026; switch when it is generally available); Buildroot's cross gcc (gcc 14.3, exists only where a build has run, and differs from CI); the laptop's host gcc (targets aarch64, so x86-only code won't compile there); running lint in a container on the laptop too (an exact match, but Docker in WSL for every commit).
