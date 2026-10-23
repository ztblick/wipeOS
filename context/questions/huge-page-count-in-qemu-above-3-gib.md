---
title: "Huge-page count in QEMU above 3 GiB"
status: deferred
---

# Huge-page count in QEMU above 3 GiB

`run.sh` requests N−2 pages of 1 GB for `--mem N`, which assumes guest RAM is one unbroken block. Up to 3 GiB it is, but QEMU's `pc` machine moves RAM above 3 GiB to start at 4 GiB, and the 2–3 GiB gigabyte ends in a reserved region (`0xbffe0000–0xbfffffff`). With `--mem 4`, only two aligned gigabytes are free (1–2 GiB and 4–5 GiB), and early boot allocations, probably the per-page bookkeeping, took one: 2 requested, 1 reserved (`logs/run-20261020-225626.log`). `run.sh` warns and the result is unaffected. Options: match the formula to QEMU's layout, have the stub report which gigabytes the pages came from, or accept the warning, since real hardware has a different memory map. Tabled until we know whether QEMU stays relevant beyond tier T0.
