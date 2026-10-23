---
id: D28
title: "Mode flag on the kernel command line"
status: accepted
date: 2026-10-20
---

# D28: Mode flag on the kernel command line

**Decision.** `wipeos.mode=dev|prod` on the kernel command line. If the flag appears more than once, the last occurrence wins. If it is absent, the stub runs in prod mode; an unknown value is a FAIL. Both modes collect the same report and produce the same result, and run the same checks except `check.shell`, which runs in dev mode only because it tests dev mode's own ending. They differ only in how the run ends: prod powers off; dev starts `/bin/sh` on the console as a child process, waits for it, and powers off when it exits. If `/bin/sh` is missing in dev mode, the stub reports `FAIL reason=no_shell` and powers off.

**Rationale.** The mode is operational, not a security control: a shell on a node can't fake the timed challenge. Defaulting to prod means a forgotten flag never leaves a production node at a shell.

**Alternatives considered.** Default to dev: a forgotten flag in production would leave a node at a shell. Require the flag: burdens every manual and test boot.

