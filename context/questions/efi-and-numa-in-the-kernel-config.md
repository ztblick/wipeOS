---
title: "EFI and NUMA in the kernel config"
status: deferred
---

# EFI and NUMA in the kernel config

`CONFIG_EFI`, `CONFIG_NUMA`, `CONFIG_ACPI_NUMA` and `CONFIG_X86_64_ACPI_NUMA` are currently off. They are needed on real hardware from tier T1 onward:
- EFI, so a kernel entered through kexec reads the UEFI memory map correctly.
- ACPI SRAT, for the per-socket memory ranges used by inventory (D4) and by NUMA-local fill threads.

They do nothing in a plain QEMU VM and grow the image, so they are tabled until the step up to T1. When they are enabled, report `bzImage` size before and after.
