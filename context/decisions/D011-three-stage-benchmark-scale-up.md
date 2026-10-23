---
id: D11
title: "Three-stage benchmark scale-up"
status: accepted
date: null
---

# D11: Three-stage benchmark scale-up

**Decision.** Scale benchmarks up in three stages: (1) individual components, meaning chunks of DRAM, GPU memory and NVMe; (2) whole GPUs plus chunks of DRAM and disk at the same time; (3) a full-node wipe, if the cluster managers approve. Start with one reserved GPU, ask for a dedicated NVMe allocation so other users' data is never touched, and reserve overnight time for full DRAM and GPU wipes.

**Rationale.** The cluster serves other users, so testing has to cause minimal disruption. Each stage is tested before the next.

**Alternatives considered.** A full-node wipe from the start.

