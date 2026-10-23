---
title: "WipeOS managing physical memory itself"
status: deferred
---

# WipeOS managing physical memory itself

A break-glass option: run most of host memory outside the kernel's page allocator so it carries no per-page bookkeeping. Tabled; huge pages (D22) come first, and we only revisit this if they leave too much overhead.
