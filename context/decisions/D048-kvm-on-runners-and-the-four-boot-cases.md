---
id: D48
title: "KVM on runners, and the four boot cases"
status: accepted
date: 2026-10-26
decided_in: docs/plans/build-and-boot-ci.md
---

# D48: KVM on runners, and the four boot cases

**Decision.**

- **KVM access.** The job grants the runner user access to `/dev/kvm` with a udev rule, before the boots.
- **The boots.** After the build, the job runs four boots in this order, each with `--no-build` and an explicit `--log logs/ci/<case>.log`:

  | Case | Command | Expected |
  | --- | --- | --- |
  | `kvm` | `scripts/run.sh --no-build --accel kvm` | exit 0, `RUN` line has `accel=kvm` |
  | `tcg` | `scripts/run.sh --no-build --accel tcg` | exit 0, `accel=tcg` |
  | `test-fail` | `scripts/run.sh --no-build --test-fail` | exit 1, `WIPEOS RESULT=FAIL` |
  | `mem4` | `scripts/run.sh --no-build --mem 4` | exit 0 |

- **Failures.** Every case runs even if an earlier one fails, and the step fails if any case didn't match. If KVM can't be made usable, the `kvm` case fails; there is no fallback.

**Rationale.** CI forces each accelerator explicitly rather than relying on `--accel auto` (D39), so a broken KVM setup fails loudly instead of quietly falling back to TCG. Exit codes are the pass and fail signal (D30).

**Alternatives considered.** `--accel auto` only (a broken udev step would silently test TCG and pass); TCG only (matches the cluster today, but leaves D39's KVM path untested anywhere).
