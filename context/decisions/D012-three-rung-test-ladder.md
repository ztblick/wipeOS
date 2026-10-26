---
id: D12
title: "Three-rung test ladder"
status: superseded
superseded_by: D38
date: null
---

# D12: Three-rung test ladder

**Decision.** Test ladder: (1) local wiping, launching WipeOS directly on the node with no host-OS handoff, starting in Linux emulation on a laptop; (2) the tap and the DGX node together emulating the auditor and host; (3) the DGX node split into two nodes for multi-node barrier tests.

**Rationale.** Each rung adds one new piece: the wipers, then the auditor side, then cross-node coordination.

**Alternatives considered.** Build the full kexec and multi-node flow first.

