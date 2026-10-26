---
id: D43
title: "Fast CI on pull requests and on main"
status: accepted
date: 2026-10-26
decided_in: docs/plans/portable-build-host-and-fast-CI.md
---

# D43: Fast CI on pull requests and on main

**Decision.** `.github/workflows/ci.yml` runs on `pull_request` targeting `main` and on `push` to `main`, on a GitHub-hosted `ubuntu-24.04` runner (pinned, not `ubuntu-latest`), with the job inside the `ubuntu:26.04` container (D42).

- **Steps:** install the tools with `apt-get` before checkout, so the checkout is a real git clone; check out; configure git (the workspace as a safe directory, `core.hooksPath .githooks`); `scripts/fetch-checkpatch.sh`; `scripts/lint.sh`; `scripts/lint-selftest.sh`; `scripts/hooks-selftest.sh`; `scripts/context_index.py --check`.
- **Settings:** `permissions: contents: read`, and no secrets, so pull requests from forks are safe.
- **Concurrency:** one group per pull request (or per ref, for pushes). A newer push cancels an older run on the same pull request; runs on `main` always finish.
- **Protection:** `.github/workflows/` is protected like the lint scripts: lint guard paths plus the `ask` list. A weakened workflow is a way around the lint (D34).
- **Enforcement:** a ruleset on `main` requires the check (D44).
- Actions are pinned to a major version.

**Rationale.** D33 named CI as the enforced gate to add later; agents now push branches (D44), so every change needs an automatic check before Zach merges it. Lint and the self-tests take about a minute, so the check is cheap enough to run on every pull request.

**Alternatives considered.** `ubuntu-latest` (tools change under us without a commit); running on every push to every branch (each push to a pull request runs twice); running only on pull requests (merges into `main` go unchecked).
