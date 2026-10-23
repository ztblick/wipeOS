---
id: D1
title: "No reliance on hardware attestation"
status: accepted
date: null
---

# D1: No reliance on hardware attestation

**Decision.** Do not rely on hardware attestation. Mutable firmware, recovery and configuration state is either overwritten and checked, or charged to R.

**Rationale.** Attestation is untrusted, or unavailable, under the threat model.

**Alternatives considered.** The paper's option of attesting such state as fixed and including it in I0.

