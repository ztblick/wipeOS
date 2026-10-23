---
id: D27
title: "The stub is C17, statically linked against glibc"
status: accepted
date: 2026-10-20
---

# D27: The stub is C17, statically linked against glibc

**Decision.** Compile with Buildroot's toolchain using `-std=c17 -O2 -Wall -Wextra -Werror`, link with `-static`, and add `-ffile-prefix-map=<src>=.` so the binary contains no host paths. The stub uses no DNS; when networking arrives, endpoints are IP addresses taken from the command line.

**Rationale.** The stub needs no shared libraries at run time. Static glibc can't do host-name lookups properly, hence no DNS. The prefix map keeps builds reproducible. A static binary can't load CUDA's shared libraries, so the future GPU wiper will either make the agent dynamically linked or run as a separate, dynamically linked worker started by process 1. The current lean is the worker; that choice is not needed now (see Deferred: "Static wipe agent versus the CUDA path").

**Alternatives considered.** C++: no benefit for the stub. Rust: adds a long toolchain build and a second language next to CUDA. Go: its runtime and garbage collector undermine determinism.

