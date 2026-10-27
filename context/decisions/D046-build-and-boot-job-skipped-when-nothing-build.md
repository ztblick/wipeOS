---
id: D46
title: "Build and boot job, skipped when nothing build-relevant changed"
status: superseded
date: 2026-10-26
decided_in: docs/plans/build-and-boot-ci.md
superseded_by: D56
---

# D46: Build and boot job, skipped when nothing build-relevant changed

**Decision.**

- **Placement.** A second job in `.github/workflows/ci.yml`, id `build`, named **`build and boot`**. It runs on the `ubuntu-24.04` runner itself, not in a container: it matches the cluster's Ubuntu 24.04, and the boots need `/dev/kvm`. Same triggers as the lint job, plus `workflow_dispatch` so Zach can run it by hand.
- **The skip.** The job always runs, because a required check that never runs leaves a pull request unmergeable. Its first step decides whether to build, with `scripts/ci-changes.sh`:
  - **Build** when any changed file matches: `src/**`, `package/**`, `configs/**`, `external.desc`, `external.mk`, `Config.in`, `scripts/run.sh`, `scripts/ci-changes.sh`, `.github/workflows/**`.
  - **Skip** otherwise: every later step is skipped, the job passes, and the summary says "No build-relevant changes; build and boot skipped", followed by the changed paths.
  - **What "changed" means:** for pull requests, the diff from the merge base with the base branch; for pushes to `main`, the diff from the previous head (`github.event.before`); for `workflow_dispatch`, a new branch, or a base that can't be found, always build.
- **No third-party actions.** Only GitHub's own `actions/checkout`, `actions/cache` and `actions/upload-artifact`, pinned to a major version.
- **Protection.** `scripts/ci-changes.sh` decides whether a build runs at all, so the lint guard protects it like `.github/workflows/` (D34, D43).

**Rationale.** A change that needs a boot can be verified without the cluster, on every pull request, while a documentation change still gets its required check in seconds.

**Alternatives considered.** The `paths:` filter on the workflow (a skipped required check blocks merging); a third-party paths-filter action (supply-chain risk for a protected workflow); building on every pull request (40+ minutes for a README edit).
