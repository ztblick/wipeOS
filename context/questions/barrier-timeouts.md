---
title: "Barrier timeouts"
status: open
group: design
---

# Barrier timeouts

How long may a node take to reach READY and FILLED before D9 applies? The READY timeout now covers the image download, quiescing and kexec (D19). The FILLED timeout depends on the slowest device.
