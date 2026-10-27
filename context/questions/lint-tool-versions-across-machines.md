---
title: "Lint tool versions across machines"
status: open
group: design
---

# Lint tool versions across machines

D42 gets the laptop and CI the same lint tools by running both on Ubuntu 26.04: the laptop's `x86_64-linux-gnu-gcc` and CI's `gcc` are both 15.2.0-16ubuntu1, and both have cppcheck 2.19.0 (checked 2026-10-26 in the first CI run). That holds only while both track the same Ubuntu updates. A point release can land on one machine before the other, and the CI container image (`ubuntu:26.04`) moves under a fixed tag. Build hosts on the cluster lint with whatever gcc and cppcheck they have. `lint.sh` prints its tool versions, so drift is visible in logs, but nothing stops it.

Options known so far: pin the container image by digest and the apt package versions in the workflow, and check the laptop against them in `lint.sh`; build a lint container image that the laptop runs too (exact match, but Docker in WSL); accept drift and treat CI as the only authority.

**Added 2026-10-27 (`docs/plans/agents-in-github.md`).** Agent jobs in GitHub (D50) run on the `ubuntu-24.04` runner itself, not in the `ubuntu:26.04` container, and install cppcheck from the runner's archive. So the builder's pre-push lint uses Ubuntu 24.04's gcc and cppcheck (gcc 13 and cppcheck 2.13 in that release, not checked on a runner yet), older than the laptop's and CI's. A finding only the newer tools report reaches the agent as a failed **`lint and self-tests`** check and comes back as a fix run, so CI stays the authority; running agent jobs in the `ubuntu:26.04` container would remove the gap, but the action's setup in a container is untested.
