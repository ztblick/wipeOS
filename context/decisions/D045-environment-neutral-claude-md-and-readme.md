---
id: D45
title: "Environment-neutral CLAUDE.md and README"
status: accepted
date: 2026-10-26
decided_in: docs/plans/portable-build-host-and-fast-CI.md
---

# D45: Environment-neutral CLAUDE.md and README

**Decision.**

- **CLAUDE.md "Development environment"** is a short table of the three machines (laptop, GitHub runners, cluster) and what each is for, followed by laptop rules (WSL2 on aarch64; Windows interop off; never `/mnt/c`; no builds or boots, D40; lint with the x86_64 cross compiler, D42) and build-host rules (builds are expensive; never `make clean`, `make distclean` or delete `output/` without asking; narrowest rebuild target; KVM only through `run.sh --accel auto`, D39; ask before installing system packages).
- **CLAUDE.md "Commands"** marks `scripts/run.sh` and `make` as build-host commands.
- **CLAUDE.md "Verifying changes"**: on the laptop, run lint and the self-tests, push the branch and read CI on the pull request. A change that needs a boot or a `bzImage` size is verified in CI once plan 2 lands, or by Zach on the cluster, and the report says which.
- **CLAUDE.md "Git"** is D44's workflow and its "never" list.
- **README.md** splits running and setup into workstation (laptop) and build-host parts, and describes how changes reach `main`.

**Rationale.** Agents read CLAUDE.md as fact about their host. With builds moving off the laptop (D38), and sessions on more than one kind of machine, a single-host description would mislead every session that isn't on the laptop.

**Alternatives considered.** A separate CLAUDE.md per environment (three files to keep consistent); leaving the laptop details and adding CI notes (agents in CI would read false facts about their host).
