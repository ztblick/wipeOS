---
id: D23
title: "System QEMU is the canonical test VM"
status: accepted
date: 2026-10-20
---

# D23: System QEMU is the canonical test VM

**Decision.** Boot test images with the distribution's `qemu-system-x86_64`, not a Buildroot-built QEMU. Remove `BR2_PACKAGE_HOST_QEMU` and `BR2_PACKAGE_HOST_E2FSPROGS` from the defconfig. The launch script records the QEMU version in every boot log.

**Rationale.** QEMU is test tooling and never part of the image, so pinning it adds build time without affecting the footprint or R. Logging the version covers the risk of behavior differing between machines.

**Alternatives considered.** Buildroot's QEMU: identical version everywhere, but a long extra compile on every fresh build. Keeping both: two copies that can silently disagree.

