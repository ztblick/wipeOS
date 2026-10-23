---
id: D21
title: "Build with Buildroot and glibc"
status: accepted
date: null
---

# D21: Build with Buildroot and glibc

**Decision.** Build WipeOS with Buildroot, using a glibc toolchain and a pared-down kernel config, with the initramfs linked into the kernel image. The kernel config is kept in our own repository, not in Buildroot's board files.

**Rationale.** One tool builds the kernel, the initramfs and the toolchain; it has ready-made QEMU configs for x86_64 and aarch64 (D17) and a reproducible-build option. glibc is required by NVIDIA's userspace. First boot in QEMU: about 15 MB of kernel code and data, about 53 MB of a 1 GiB VM not free.

**Alternatives considered.** A mainline kernel from tinyconfig with a hand-built initramfs: smallest, but the most manual. A LinuxBoot-style kernel with a u-root initramfs: built-in kexec and netboot, but Go userspace and less turnkey.

