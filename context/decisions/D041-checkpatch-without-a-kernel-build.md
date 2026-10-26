---
id: D41
title: "checkpatch without a kernel build"
status: accepted
date: 2026-10-26
decided_in: docs/plans/portable-build-host-and-fast-CI.md
---

# D41: checkpatch without a kernel build

**Decision.**

- **Fetch script.** `scripts/fetch-checkpatch.sh` downloads `checkpatch.pl`, `spelling.txt` and `const_structs.checkpatch` for the kernel version pinned in `configs/wipeOS_x86_64_defconfig` (`BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`). The source is kernel.org's stable tree at tag `v<version>`, and the files go into `.cache/checkpatch/<version>/`, which is gitignored. The script prints the absolute path of `checkpatch.pl`, and downloads nothing if the files are already there.
- **Lookup in `lint.sh`.** `CHECKPATCH` if set, otherwise the cache for the pinned version. The Buildroot tree is no longer searched, so every host runs the same file. If the cached file is missing, the error message names `scripts/fetch-checkpatch.sh`.
- **Protection.** The fetch script is protected like `scripts/lint.sh`: in the lint guard's protected paths and runnable scripts, and in `.claude/settings.json`'s `ask` list.

**Rationale.** Lint (D33) needed a Buildroot kernel tree only to find `checkpatch.pl`, so it couldn't run in CI or on a machine that never builds (D38). The fetched files are the kernel tree's own, at the pinned tag, so D33's "the kernel tree's checkpatch.pl" stays true.

**Alternatives considered.** Vendoring `checkpatch.pl` in the repo (a GPL-2.0 file to keep in sync by hand); a system checkpatch package (its version drifts from our kernel); downloading the whole kernel tarball every run (about 150 MB for three files); keeping the Buildroot tree first in the lookup (after a kernel bump, a stale tree on the laptop would lint with an older checkpatch than CI).
