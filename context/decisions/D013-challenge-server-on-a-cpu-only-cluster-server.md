---
id: D13
title: "Challenge server on a CPU-only cluster server"
status: accepted
date: null
---

# D13: Challenge server on a CPU-only cluster server

**Decision.** Run the challenge server on one of the cluster's CPU-only servers, where the network tap is currently emulated.

**Rationale.** It is available, and like the real auditor side it has far less compute than the nodes it challenges.

**Alternatives considered.** Run it on the DGX node itself.

