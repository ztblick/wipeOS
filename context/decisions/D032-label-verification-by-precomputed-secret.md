---
id: D32
title: "Label verification by precomputed secret challenges"
status: accepted
date: 2026-10-21
supersedes: [D18]
---

# D32: Label verification by precomputed secret challenges

**Decision.** Labels are generated on the node with Amodo's PoSE-DB code (D5, D14). Ahead of each erasure event, the auditor precomputes a database of single-use challenges, offline and on any auditor hardware. Each entry holds:

- a fresh secret χ;
- secret sample positions (chunks, and label ranks within each chunk);
- the expected answer for each position, stored as a hash rather than the label itself.

At the event, the challenge server takes an unused entry, sends its χ at SEED, queries the stored positions at QUERY, and checks each answer by hashing it and comparing. The entry is then discarded.

This supersedes D18 and refines D16: labels are still generated on the node, and the challenge server still doesn't recompute labels during the event. The only recomputation happens offline, before the event, on auditor hardware.

**Requirements.**

- χ stays secret until SEED, and the sample positions until QUERY. Both matter: knowing the positions alone would let a node store only those labels.
- Entries are single-use.
- Expected answers are stored as hashes, so a leak reveals no label values.
- Entries are tied to the pod's memory layout from the auditor manifest (D4), so a hardware change invalidates them.
- The response deadline still applies.

**Rationale.**

- Verification at event time is a lookup, so one challenge server keeps up with all 18 nodes in parallel.
- It's the simplest option to stand up, and reuses Amodo's code unchanged.
- Live recompute on a CPU-only server is limited by the fill window (about 1,300 sampled chunks per tray on 32 cores), and gets worse as GPUs get faster.
- D18's streamed fingerprints don't work on PoSE-DB: every stored label's parent is a discarded scaffold node, and 32-byte labels would make a per-label fingerprint stream about half the size of memory.

The evidence is in `docs/research/amodo-study.md` (§3.1, §3.4) and `docs/research/label-verification.md`.

**Alternatives considered.**

- Live recompute on the challenge server: limited by the window, and scales poorly with parallel nodes.
- Deferred verification, checking answers after the event: no secret database, but cheating is detected hours later.
- Commit-and-check proofs of space: see the Deferred item "Commit-and-check proofs of space as the successor to precomputation".
- D18, streamed fingerprints: incompatible with PoSE-DB.

