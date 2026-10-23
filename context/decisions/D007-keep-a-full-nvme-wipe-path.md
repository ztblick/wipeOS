---
id: D7
title: "Keep a full NVMe wipe path"
status: accepted
date: null
---

# D7: Keep a full NVMe wipe path

**Decision.** Keep a full NVMe wipe path in WipeOS, even while we look for a way to avoid wiping disks.

**Rationale.** If no way to avoid disk wipes is found, the capability is already built. Disk wipe time will be reduced later through testing and optimization.

**Alternatives considered.** Build the disk path only once disks are confirmed to stay in the pod.

