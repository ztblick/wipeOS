---
id: D56
title: "Build only when the image changes; reuse passed images"
status: accepted
date: 2026-10-27
supersedes: [D46]
---

# D56: Build only when the image changes; reuse passed images

Proposed by Claude Code and accepted by Zach in chat on 2026-10-27, after every push to pull request #6 rebuilt the image (35–40 minutes each) though none changed it, and the push to `main` after pull request #4 rebuilt a tree #4 had just passed. Zach's rule: the image is built on a runner only when the image itself changes. Revised the same day, before merging, so that a change to the boot test reuses the image instead of rebuilding it. This restates D46 with those changes.

**Decision.**

- **Placement (from D46).** A second job in `.github/workflows/ci.yml`, id `build`, named **`build and boot`**, on the `ubuntu-24.04` runner itself, not in a container. Same triggers as the lint job, plus `workflow_dispatch`.
- **The job always runs (from D46),** because a required check that never runs leaves a pull request unmergeable. Its first step picks one of three modes: `skip`, `boot` or `build`. Anything in doubt builds.
- **Two kinds of input.** `scripts/ci-changes.sh` keeps two lists:
  - **image inputs:** `src/**`, `package/**`, `configs/**`, `external.desc`, `external.mk`, `Config.in`, what goes into the image;
  - **boot test:** `scripts/run.sh` and `.github/workflows/ci.yml`, how the image is built and booted and how the result is judged.

  `scripts/ci-changes.sh` itself and every other file, other workflows included, are in neither list.
- **Change detection (from D46, three-way).** `scripts/ci-changes.sh BASE HEAD` compares the commit under test with its base. For a pull request, the base is the merge base with the base branch; for a push to `main`, the previous head. It says `build` if an image input changed, `boot` if only the boot test changed, and `skip` otherwise. A manual run, a new branch or a base that can't be found always gives `build`.
- **Fingerprints and pass markers (new).**
  - **Fingerprints.** `scripts/ci-changes.sh --fingerprint <commit>` prints two hashes of `git ls-tree` output: one over the image inputs and one over the boot test, each the mode and content hash of every input, and nothing else.
  - **Pass markers.** When the image and all four boots pass, the job uploads a small artifact named `build-and-boot-passed-<image fingerprint>-<boot fingerprint>`, kept 14 days like the other artifacts (D49). It also uploads the image it booted as the `bzImage` artifact, in every mode that boots.
  - **Lookup.** Unless the change detection said `skip` or this is a manual run, the decide step fingerprints the commit being tested (the merge commit, for a pull request). It then looks for unexpired markers for that image fingerprint from runs whose head repository is this repository. Markers from forks don't count.
    - A marker with the same boot fingerprint: **`skip`**. This image and boot test already passed.
    - A marker with another boot fingerprint: **`boot`**. Download that run's `bzImage` and run the four boots on it, without building.
    - No marker: **`build`**.
  - **Fails closed.** A failed fingerprint or lookup means `build`.
- **The tradeoff, accepted by Zach.** A change to the build steps in `ci.yml` runs only the boots until the next change to the image's inputs builds. A build-step change that breaks the build shows up then, or in a manual run, which always builds. The runner image and QEMU aren't fingerprinted, so a reused image can be up to 14 days past its build; in `boot` mode the re-upload carries it forward.
- **No third-party actions (from D46).** Only GitHub's own `actions/checkout`, `actions/cache` and `actions/upload-artifact`, pinned to a major version.
- **Protection (from D46).** `scripts/ci-changes.sh` and `ci.yml` are protected like the lint scripts (D34, D43).

**Rationale.** A build proves something about the image's inputs, not about a commit: a pass is reused wherever those inputs are the same, including later documentation commits on a pull request and the merge of a pull request whose image was already built. A change to the boot test needs a boot, not a 35–40 minute build: booting an image that already passed takes minutes. Keying on content rather than on "the previous push" keeps a failed or cancelled build from being skipped past.

**Alternatives considered.** Counting the boot test as an image input (the first draft of this decision: every `ci.yml` or `run.sh` change rebuilt an unchanged image); diffing only the new commits on each push (a docs-only push after a failed or cancelled build would skip with no passing build behind it); a label or manual trigger for builds (easy to forget, for Zach and for agents); building only after merge (nothing verified before merge); caching `output/` to make builds faster instead of fewer (about 9 GB against the 10 GB cache limit, as D47 found).
