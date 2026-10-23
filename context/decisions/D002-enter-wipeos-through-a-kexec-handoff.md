---
id: D2
title: "Enter WipeOS through a kexec handoff"
status: accepted
date: null
---

# D2: Enter WipeOS through a kexec handoff

**Decision.** Enter WipeOS from the production OS through a kexec-style handoff.

**Rationale.** WipeOS can then overwrite the memory the production OS occupied, without firmware running in between (paper, Appendix C.2).

**Alternatives considered.** A full firmware reboot into WipeOS: slower, and firmware touches memory. Wiping in place from the production OS: cannot overwrite its own footprint.

