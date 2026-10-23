---
title: "WipeOS allowance"
status: open
group: design
---

# WipeOS allowance

The auditor cannot verify that a node runs genuine WipeOS, so its footprint cannot be self-declared. What fixed allowance is agreed in advance, and is the image built reproducibly so its hash can be committed in I0? The kernel also keeps about 64 bytes of bookkeeping per 4 KB page, about 1.6% of RAM: roughly 16 MB in a 1 GiB VM, but around 32 GB on a 2 TiB host. Can WipeOS boot with the kernel managing only a small slice of RAM, so the wipe agent writes the rest directly and it needs no bookkeeping? Two options to explore: (1) wipeOS manages most physical memory itself, outside the kernel's page allocator, so that memory carries no per-page bookkeeping; (2) default to huge pages, which give a better bookkeeping-to-memory ratio. Huge pages only shrink the per-page bookkeeping if the kernel's HugeTLB vmemmap optimization is turned on; it frees about 7/8 of it for 2 MB pages and nearly all of it for 1 GB pages. Huge pages also cut the page-table overhead of the wipers' own mappings. Option 2 is adopted as D22; option 1 is tabled as a fallback (see Deferred).
