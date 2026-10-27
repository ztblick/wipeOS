---
id: D54
title: "Agents in GitHub don't build or boot"
status: accepted
date: 2026-10-27
decided_in: docs/plans/agents-in-github.md
---

# D54: Agents in GitHub don't build or boot

**Decision.**

- **The rule.** `agents.yml` sets `WIPEOS_AGENT_CI=1` for every agent session. When it's set, `guard-build.py` denies the same commands D40 denies on non-x86_64 hosts: Buildroot `make`, `scripts/run.sh` except `--help`, and `qemu-system-x86_64`.
- **How agents verify instead.** The builder reads the **`build and boot`** check, and a failure comes back to it as a `fix` run.
- **Lint stays allowed.** Lint, the self-tests and `scripts/ci-changes.sh` keep working. The builder runs lint before every push, as on the laptop.

**Rationale.** CI already builds and boots every build-relevant change (D46–D49); an agent building too would spend an hour of runner and session time per attempt for the same check.

**Alternatives considered.** Letting agents build (an hour of runner and session time per attempt, for a check CI already runs); a CLAUDE.md rule only (D40's reasoning applies).
