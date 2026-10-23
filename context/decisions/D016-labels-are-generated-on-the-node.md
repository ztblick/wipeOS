---
id: D16
title: "Labels are generated on the node"
status: accepted
date: null
---

# D16: Labels are generated on the node

**Decision.** Labels are generated on the node's hardware. The challenge server issues challenges and checks responses but should not have to recompute labels. D18 chooses how.

**Rationale.** The challenge server will always be far less computationally capable than the pod it challenges.

**Alternatives considered.** The challenge server recomputes each sampled label: simple, but its cost grows with the sample count.

