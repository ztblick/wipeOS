---
id: D30
title: "Boot result reported through the boot log"
status: accepted
date: 2026-10-20
---

# D30: Boot result reported through the boot log

**Decision.** `scripts/run.sh` determines the outcome from the boot log and exits 0 for `WIPEOS RESULT=SUCCESS`, 1 for `WIPEOS RESULT=FAIL`, 2 when there is no RESULT line (crash, hang, timeout or kernel panic), and 3 for bad arguments to `run.sh`. The stub powers off after reporting, which ends QEMU under `-no-reboot`. A run only passes if the stub reports SUCCESS and the VM then shuts down cleanly; anything else is exit 2, except a FAIL followed by a clean shutdown, which stays exit 1. No QEMU debug-exit device is used.

**Rationale.** Process 1 contains no port I/O and no architecture-specific code (D17), and nothing in it has to be kept off real hardware.

**Alternatives considered.** QEMU's isa-debug-exit device: an independent exit code, but x86-specific port I/O in process 1, a guard flag to keep it off real hardware, and awkward exit-code mapping.

