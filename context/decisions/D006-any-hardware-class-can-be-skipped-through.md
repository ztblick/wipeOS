---
id: D6
title: "Any hardware class can be skipped through configuration"
status: accepted
date: null
---

# D6: Any hardware class can be skipped through configuration

**Decision.** Any hardware class can be skipped through configuration. Memory-only mode skips local NVMe. In production, every skip requires authentication and an explicit confirmation that names what will not be erased ("Are you sure you don't want to erase NVMe?").

**Rationale.** Lets us test and profile each wiper on its own, and run without the disk wipe if disks leave the pod. A skipped device is not erased, so the certificate must list it, and its capacity is charged to R unless the auditor manifest excludes it from the pod.

**Alternatives considered.** Always wipe everything: simpler, but blocks per-component testing and forces disk wipes even if storage is removed.

