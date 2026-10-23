---
title: "NVMe cache"
status: open
group: design
---

# NVMe cache

WipeOS supports NVMe wipes either way (D6, D7). The open question is whether production pods keep local NVMe, shrink it, or exclude it as the paper suggests. Drive endurance also matters: each full fill is one drive write, so daily wipes alone would use roughly the whole 5-year rating of a ~1 DWPD drive (approximate; check the actual drive). Over-provisioned NAND has to be counted in R either way.
