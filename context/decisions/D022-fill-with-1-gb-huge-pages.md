---
id: D22
title: "Fill with 1 GB huge pages"
status: accepted
date: null
---

# D22: Fill with 1 GB huge pages

**Decision.** After kexec, fill memory using the largest pages possible: 1 GB pages, reserved at boot on the kernel command line, with the HugeTLB vmemmap optimization on. Unaligned edges and the regions around memory holes fall back to 2 MB and then 4 KB pages.

**Rationale.** The wipe agent is the only userspace process, so small pages' fairness and overcommit controls buy nothing. 1 GB pages nearly eliminate per-page bookkeeping and page-table overhead, and the fill also runs faster with fewer TLB misses. Reserving at boot avoids fragmentation, because WipeOS controls its own command line.

**Alternatives considered.** Default 4 KB pages: about 1.6% of RAM in bookkeeping. 2 MB pages only: about 0.2%. WipeOS managing physical memory outside the page allocator: tabled as a fallback in case huge pages leave too much overhead.

