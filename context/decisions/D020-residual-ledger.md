---
id: D20
title: "Residual ledger"
status: accepted
date: null
---

# D20: Residual ledger

**Decision.** WipeOS keeps a residual ledger: one entry for every region it does not erase, with location, size, reason and category. Two categories to start: committed binaries that could be attested and included in I0 (such as the WipeOS kernel and initramfs), and unaccounted unerased memory, which is tallied into R. The schema is open-ended, so new categories and fields can be added without changing the wipers.

**Rationale.** Committing binaries in I0 would need attestation, which is not solved yet, and the Pod-PoComp accounting is not a crucial part of the prototype. Logging what is left and why now means the accounting can be tightened later without redesign.

**Alternatives considered.** Charge everything unerased to R with no categories: simpler, but loses the distinction needed later. Solve attestation first: blocks the prototype.

