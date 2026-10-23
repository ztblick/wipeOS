---
id: D18
title: "Verify labels with streamed fingerprints (candidate C)"
status: superseded
date: null
superseded_by: D32
---

# D18: Verify labels with streamed fingerprints (candidate C)

**Decision.** Verify labels with candidate C. During the fill, the node streams a fingerprint of every label; the challenge server secretly keeps a sample, in neighborhoods, and checks queried labels against it. The scheme sits behind its own interface so a better one can replace it later.

**Rationale.** B's bandwidth is prohibitive and A needs too much extra memory. C keeps server work to one or two hashes per query, with about 290 GB of ingest per Vera Rubin NVL72. Confidence is about 85%, which is enough to proceed because this is one replaceable part of the system.

**Alternatives considered.** A, Merkle commitment. B, streamed full labels. Streaming one in N labels (rejected: the node could store only those).

