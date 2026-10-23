---
id: D31
title: "The repo is a Buildroot external tree"
status: accepted
date: 2026-10-20
---

# D31: The repo is a Buildroot external tree

**Decision.** The repo root is a Buildroot external tree named `WIPEOS`: `external.desc`, `Config.in` and `external.mk` at the top, the package in `package/wipeos-stub/`, the stub source in `src/stub/`, the launcher in `scripts/run.sh`, boot logs in `logs/` (gitignored), alongside the existing `configs/`, `docs/` and gitignored `buildroot/`. Paths inside config files use `$(BR2_EXTERNAL_WIPEOS_PATH)`, never `../` or a home-folder path. Commands pass the external tree relatively from `~/wipeOS/buildroot`: `make BR2_EXTERNAL=.. wipeOS_x86_64_defconfig`. There is no rootfs overlay, since the package installs the stub, and no `arch/` folder until something needs one.

**Rationale.** Buildroot remembers the external tree for later builds in that checkout and finds the defconfig by name in the external tree's `configs/`, so `configs/` stays where D21 put it. Config paths no longer depend on where Buildroot is checked out.

**Alternatives considered.** A separate `br2-external/` folder: tidier top level, but no defconfig discovery unless `configs/` moves inside it.

