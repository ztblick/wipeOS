---
id: D29
title: "Stub report format"
status: accepted
date: 2026-10-20
---

# D29: Stub report format

**Decision.** The stub writes only lines of the form `WIPEOS key=value` to the console, each with a single `write()`. The first line is `WIPEOS BEGIN format=1 version=<git commit>`; the last is `WIPEOS RESULT=SUCCESS` or `WIPEOS RESULT=FAIL reason=<token>`, and a missing RESULT line means the stub crashed or hung. Keys are lowercase, grouped by dotted prefix (`mem.`, `iomem.`, `hugetlb.`, `pci.`, `check.`), with units in the key name (`_kb`, `_bytes`, `_pages`, `_ms`). Addresses are hex with `0x`; values contain no spaces, or are wrapped in double quotes.

**Rationale.** One `write()` per line means a kernel message can't land inside a line, and line-based output stays parseable if it is cut off. This is the seed of the WipeOS log format (D15, D20); it is easy to change and the stakes are low, so it is kept simple.

**Alternatives considered.** Free text: fragile to parse. A final JSON object: invalid if output is cut off. Text plus key=value lines: two formats that can drift.

