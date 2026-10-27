---
id: D56
title: "Build and boot only for inputs that haven't passed"
status: accepted
date: 2026-10-27
supersedes: [D46]
---

# D56: Build and boot only for inputs that haven't passed

Proposed by Claude Code and accepted by Zach in chat on 2026-10-27, after every push to pull request #6 rebuilt the image (35–40 minutes each) though none after the first changed a build input, and the push to `main` after pull request #4 rebuilt a tree #4 had just passed. Zach's rule: the 30-minute-plus build runs on a runner only when it is necessary. This restates D46 with two changes.

**Decision.**

- **Placement (from D46).** A second job in `.github/workflows/ci.yml`, id `build`, named **`build and boot`**, on the `ubuntu-24.04` runner itself, not in a container. Same triggers as the lint job, plus `workflow_dispatch`.
- **The job always runs (from D46),** because a required check that never runs leaves a pull request unmergeable. Its first step decides whether the rest runs, and anything but a clear skip builds.
- **Skip 1, no build-relevant change (from D46, with a narrower list).** `scripts/ci-changes.sh` compares the commit under test with its base: for a pull request, the diff from the merge base with the base branch; for a push to `main`, the diff from the previous head; for `workflow_dispatch`, a new branch or a base that can't be found, always build. It builds when any changed file matches `src/**`, `package/**`, `configs/**`, `external.desc`, `external.mk`, `Config.in`, `scripts/run.sh`, `scripts/ci-changes.sh` or **`.github/workflows/ci.yml`**. Other workflows, such as `agents.yml`, can't change the image or the boot, so they no longer count.
- **Skip 2, these inputs already passed (new).**
  - **Fingerprint.** `scripts/ci-changes.sh --fingerprint <commit>` prints a SHA-256 of `git ls-tree` over the build paths above: the mode and content hash of every input, and nothing else. Two commits with identical build inputs have the same fingerprint, whatever else differs.
  - **Pass marker.** When the build and all four boots pass, the job uploads a small artifact named `build-and-boot-passed-<fingerprint>` (the fingerprint, commit and run), kept 14 days like the other artifacts (D49).
  - **Lookup.** When skip 1 says build, the decide step computes the fingerprint of the commit being tested (the merge commit, for a pull request) and looks for an unexpired marker with that name from a run whose head repository is this repository. Markers from forks don't count. If one exists, the job skips and its summary links the run that passed. The lookup needs `actions: read` for the job's token.
  - **Manual runs always build.** `workflow_dispatch` never looks for a marker.
  - **Fails closed.** A failed fingerprint or lookup means build.
- **No third-party actions (from D46).** Only GitHub's own `actions/checkout`, `actions/cache` and `actions/upload-artifact`, pinned to a major version.
- **Protection (from D46).** `scripts/ci-changes.sh` and `ci.yml` are protected like the lint scripts (D34, D43).

**Rationale.** A build proves something about its inputs, not about a commit, so a pass is reused wherever the inputs are the same: later documentation commits on a pull request, and the merge of a pull request whose tree was already built. Keying on content rather than on "the previous push" keeps a failed or cancelled build from being skipped past. The cost is that the runner image and QEMU, which aren't in the fingerprint, can change under a reused pass for up to the 14 days a marker is kept.

**Alternatives considered.** Diffing only the new commits on each push (simpler, but a docs-only push after a failed or cancelled build would skip with no passing build behind it); a label or manual trigger for builds (easy to forget, for Zach and for agents); building only after merge (nothing verified before merge); caching `output/` to make builds faster instead of fewer (about 9 GB against the 10 GB cache limit, as D47 found).
