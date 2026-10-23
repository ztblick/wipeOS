---
id: D8
title: "Pod-wide barrier protocol"
status: accepted
date: null
---

# D8: Pod-wide barrier protocol

**Decision.** Run each erasure event as a pod-wide barrier protocol driven by the challenge server: READY, SEED, FILLED, QUERY, RESPONSE, VERDICT, RELEASE. All 18 nodes fill at once, the seed χ is the start signal, and all nodes are queried simultaneously.

**Rationale.** With every memory in the pod filling at once, state moved between nodes has nowhere unfilled to land. Using χ as the start signal makes the first barrier cryptographic, because no meaningful fill can start before it. Simultaneous queries stop a node that has already answered from lending its memory to one still being queried.

**Alternatives considered.** Stagger the node wipes and rely on gateway policy alone to block node-to-node restore traffic, the paper's other option.

