---
id: D9
title: "A node that misses a barrier fails the event"
status: accepted
date: null
---

# D9: A node that misses a barrier fails the event

**Decision.** A node that does not reach READY or FILLED before its timeout is treated as adversarial. The pod fails the erasure event, and the case is escalated to a human verifier.

**Rationale.** A missing node cannot be told apart from one hiding state, so failing is the safe default. A human verifier handles the exceptions, including honest hardware faults.

**Alternatives considered.** Retry the node or exclude it automatically.

