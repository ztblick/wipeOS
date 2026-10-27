---
id: D49
title: "What CI leaves behind"
status: accepted
date: 2026-10-26
decided_in: docs/plans/build-and-boot-ci.md
---

# D49: What CI leaves behind

**Decision.**

- **Artifacts:**
  - `boot-logs`: the four boot logs, and the last 200 lines of the build log. Uploaded whenever the job got past the skip decision, including on failure.
  - `bzImage`: the image. Uploaded when the build succeeded.
  - Both kept for 14 days. The repository is public, so so are the artifacts.
- **Job summary:** build time, `bzImage` size in bytes, and a table of the four cases with accelerator, exit code and pass or fail.
- **Who uses them.** Agents read failures with `gh run download <run-id> -n boot-logs`. Zach can boot a CI-built image on the cluster with `gh run download <run-id> -n bzImage`, placing it at `buildroot/output/images/bzImage` and running `scripts/run.sh --no-build`, instead of building there.

**Rationale.** Footprint is a security quantity (D3, D20), so every build reports the `bzImage` size where reviewers, people or agents, see it. Logs as files let agents read a failure directly.

**Alternatives considered.** Logs only in the job log (agents would parse long logs instead of reading files); keeping artifacts for 90 days (the default; they take storage, and the image is rebuilt on demand).
