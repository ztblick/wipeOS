---
id: D10
title: "Benchmark on Lucid's DGX H100 node"
status: accepted
date: null
---

# D10: Benchmark on Lucid's DGX H100 node

**Decision.** Benchmark on Lucid's DGX H100 node (h100-sxm-8-0), wiping a subset of its GPUs rather than everything.

**Rationale.** It is available now, the cluster has a network tap, and one node exercises the DRAM, HBM and NVMe wipers. Per-device throughput can be measured without wiping the full node.

**Alternatives considered.** Wait for Vera Rubin NVL72 hardware.

