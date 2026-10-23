---
id: D3
title: "Minimal, itemized resident footprint"
status: accepted
date: null
---

# D3: Minimal, itemized resident footprint

**Decision.** Keep WipeOS's resident footprint minimal and itemize every resident byte in the residual ledger.

**Rationale.** The kernel, drivers and recovery state are charged to R unless fixed by I0. A smaller WipeOS means a smaller R.

**Alternatives considered.** A stock distribution kernel and initramfs: much larger and harder to account for.

