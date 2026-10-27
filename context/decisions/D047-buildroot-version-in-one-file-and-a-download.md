---
id: D47
title: "Buildroot version in one file, and a download cache"
status: accepted
date: 2026-10-26
decided_in: docs/plans/build-and-boot-ci.md
---

# D47: Buildroot version in one file, and a download cache

**Decision.**

- **Version file.** The Buildroot version lives in `configs/buildroot.version`, one line: `2026.02.3`. README's build-host setup clones that version by reading the file, and CI does the same, so the two can't drift.
- **What's cached.** `buildroot/dl/` (about 1.2 GB of sources) is cached with `actions/cache`.
  - Key: `br-dl-<buildroot version>-<hash of configs/** and package/**>`.
  - Restore key: `br-dl-<buildroot version>-`, so a config change reuses most downloads. This is safe because Buildroot checks every file against its hash and fetches what's missing.
  - A new cache entry is saved whenever the exact key missed.
- **Not cached:** `output/`, which is about 9 GB, against GitHub's 10 GB cache limit per repository. ccache is not used. Every build compiles from scratch.

**Rationale.** One place for the version keeps build hosts and CI on the same Buildroot. Caching the downloads spares upstream mirrors and keeps mirror failures from looking like code failures; leaving `output/` uncached keeps every CI build a clean build from the configs.

**Alternatives considered.** Caching `output/` (too large, and a stale tree risks a build that doesn't match the configs); ccache (changes the Buildroot configuration; deferred until build time is measured); no cache (1.2 GB from upstream mirrors on every build, and mirror failures that look like code failures).
