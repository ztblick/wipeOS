---
id: D38
title: "Build and test hosts"
status: accepted
date: 2026-10-26
decided_in: docs/plans/portable-build-host-and-fast-CI.md
supersedes: [D12]
---

# D38: Build and test hosts

**Decision.** Builds and QEMU boots run only on x86_64 Linux hosts: GitHub-hosted runners (CI) and the cluster (by hand, over SSH). The laptop (Windows on Arm, WSL2) is a workstation: editing, Claude Code sessions, lint, the pre-commit hook, git and `gh`, and SSH to the cluster. No builds or boots there. While the repo is public, CI uses GitHub-hosted runners only, never self-hosted, because a pull request from anyone could run code on a self-hosted machine. When the repo goes private, the cluster may become a self-hosted runner without script changes.

Supersedes D12, restating the test ladder: (1) local wiping, launching WipeOS directly on the node with no host-OS handoff, starting in QEMU on GitHub-hosted runners and the cluster; (2) the tap and the DGX node together emulating the auditor and host; (3) the DGX node split into two nodes for multi-node barrier tests.

**Rationale.** The laptop is aarch64 with no KVM for x86 guests, so every boot there runs under slow software emulation and a fresh build takes about 40 minutes, on a host unlike every other environment. x86_64 hosts boot with KVM and match the target (D17).

**Alternatives considered.** Keeping the laptop as a supported build host (slow TCG boots, a 40-minute build, and an aarch64 host that differs from every other environment); the cluster only, with no CI (no automatic check on every change, which the agent pipeline needs).
