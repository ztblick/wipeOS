---
id: D19
title: "Image delivery and kexec trigger"
status: accepted
date: null
---

# D19: Image delivery and kexec trigger

**Decision.** The challenge server stores the WipeOS image and starts each erasure event with a trigger message to a small agent on the production OS. The agent downloads the image over the erasure channel, checks its hash against I0, stages it with kexec -l, and jumps into it with kexec -e.

**Rationale.** The auditor controls which build every node gets, and the image is ingress already committed in I0. The hash check protects the developer from a wrong or tampered image. Staging with kexec -l takes the download off the critical path. A kexec deadline adds no security, because the fill and the timed challenge cover any stashed state, so liveness is handled by the D9 READY timeout, measured in seconds.

**Alternatives considered.** A hardware interrupt from the challenge server: not possible over the network. A millisecond kexec deadline: adds no security and is too short to quiesce. WipeOS kept on the node: mutable, so it would have to be wiped or charged to R.

