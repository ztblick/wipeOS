---
id: D26
title: "The stub is built as a Buildroot package"
status: accepted
date: 2026-10-20
---

# D26: The stub is built as a Buildroot package

**Decision.** The repo is a Buildroot external tree (D31), and `package/wipeos-stub/` builds `src/stub/` with Buildroot's toolchain and installs the binary.

**Rationale.** One `make` produces the whole image, the build is reproducible from the repo, and Buildroot stays an untouched upstream checkout.

**Alternatives considered.** Compiling separately and copying the binary in: risks a stale binary, and the image is no longer reproducible from the repo alone.

