---
id: D25
title: "The stub is process 1"
status: accepted
date: 2026-10-20
---

# D25: The stub is process 1

**Decision.** Our stub, `/sbin/wipeos-init`, runs as process 1 and is the only userspace process. It is named by `rdinit=/sbin/wipeos-init` in the built-in kernel command line, alongside `norandmaps` (D24), so the full built-in string is `norandmaps rdinit=/sbin/wipeos-init`. Buildroot's init system is None and `/dev` management is devtmpfs. BusyBox stays in the image only to provide `/bin/sh` for dev mode (D28); nothing in the boot path uses it. The QEMU post-build script (`board/qemu/x86_64/post-build.sh`) is removed. A boot-time `rdinit=` still overrides the built-in one, so `rdinit=/bin/sh` remains a rescue shell.

**Rationale.** With no BusyBox init, scripts, gettys or daemons, nothing else is resident or running beside the stub (D3, D20). Naming the stub in the built-in command line keeps the image independent of whoever builds the command line, as in D24. The post-build script only added a tty1 login prompt to an `inittab` that no longer exists.

**Alternatives considered.** The stub as `/init`: collides with the small `/init` script Buildroot installs in initramfs images. The stub as `/sbin/init` behind Buildroot's `/init` script: puts a shell script that needs BusyBox in front of process 1.

