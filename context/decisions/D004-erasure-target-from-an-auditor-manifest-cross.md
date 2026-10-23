---
id: D4
title: "Erasure target from an auditor manifest, cross-checked by discovery"
status: accepted
date: null
---

# D4: Erasure target from an auditor manifest, cross-checked by discovery

**Decision.** Build the erasure target from an auditor-held pod manifest, cross-checked against live discovery inside WipeOS. Any mismatch aborts the event.

**Rationale.** The paper derives W from an audited inventory, and the host's self-report is untrusted.

**Alternatives considered.** Discovery only. This is fine for test configurations and becomes the dev mode.

