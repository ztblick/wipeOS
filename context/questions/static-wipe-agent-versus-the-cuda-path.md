---
title: "Static wipe agent versus the CUDA path"
status: deferred
---

# Static wipe agent versus the CUDA path

The userspace candidate is a single static binary, but NVIDIA ships its user-mode CUDA driver (`libcuda.so`) only as a shared library built against glibc (D21). The CUDA runtime can be linked statically, but it still loads `libcuda.so` at run time, which needs a dynamically linked glibc. If the HBM fill runs through CUDA, either the agent is dynamically linked, or a separate dynamically linked GPU helper runs alongside a static agent that covers DRAM and NVMe. Tabled until the GPU wiper is built for tier T1.
