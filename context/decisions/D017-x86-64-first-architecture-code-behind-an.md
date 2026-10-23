---
id: D17
title: "x86_64 first, architecture code behind an abstraction"
status: accepted
date: null
---

# D17: x86_64 first, architecture code behind an abstraction

**Decision.** Build x86_64 first. Keep architecture-specific code behind an abstraction layer so an Arm (aarch64) port is easy later, but do not implement the Arm side yet.

**Rationale.** The DGX test node is x86_64, while the Vera target is Arm. Isolating architecture-specific code now keeps the eventual port cheap without slowing the prototype.

**Alternatives considered.** Build both from the start: slower. x86_64 only, with no abstraction: makes the port expensive.

