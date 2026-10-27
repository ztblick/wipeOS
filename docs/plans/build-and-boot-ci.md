# Plan: Build and boot in CI (supports KR1.3)

Implementation plan for building the image and running the boot tests on GitHub-hosted runners, so a change that needs a boot can be verified without the cluster. Written 2026-10-26 from a design discussion with Zach.

Read this whole file before starting, together with `CLAUDE.md` and the records it points to in `context/INDEX.md`. Then do step 0, the preflight, before changing anything.

## Goal

Every pull request to `main`, and every push to `main`, gets a second check, **`build and boot`**:

- **When nothing build-relevant changed** (a README edit, say), the check passes in seconds without building.
- **Otherwise,** it builds the image with Buildroot on the runner and boots it with `scripts/run.sh` in four cases, under KVM and TCG.
- **Outputs:** the boot logs and the `bzImage` are uploaded as artifacts, and the job summary reports the image size.
- **Cache:** downloaded sources are cached between runs.

This closes the open `accel=kvm` check from `docs/plans/portable-build-host-and-fast-CI.md`. It supports KR1.3 but completes no key result.

**Out of scope:**

- ccache, a prebuilt or reused toolchain, and any other build-speed work beyond the download cache. Decided with Zach: measure first, and address bottlenecks in a later plan.
- Comparing image size against `main` automatically.
- Agents in GitHub.
- Changes to the stub, the image, the kernel config or the Buildroot defconfig.

## Constraints from existing decisions

- **D3, D20:** footprint is a security quantity. CI reports `bzImage` size on every build, so reviewers (people or agents) can see changes.
- **D23:** QEMU is the distribution's `qemu-system-x86_64`, from Ubuntu's packages on the runner.
- **D30:** `run.sh` exit codes are the boot test's pass and fail signal.
- **D38:** GitHub-hosted runners only while the repo is public.
- **D39:** `--accel auto|kvm|tcg`. CI forces each mode explicitly rather than relying on `auto`, so a broken KVM setup fails loudly instead of quietly falling back to TCG.
- **D43:** the existing **`lint and self-tests`** job stays as it is, in the `ubuntu:26.04` container.
- **D34:** `.github/workflows/` is protected. The new change-detection script decides whether a build runs at all, so it gets the same protection.
- **D44:** agents verify through pull requests and CI, and the ruleset on `main` lists the required checks.
- **"Fail closed, never skip silently":** a skipped build says so in the job summary. A build or boot that can't run fails the check.

## Decisions made for this plan

Settled with Zach in chat. In the last step, record each one in `context/decisions/` as `accepted`, with `decided_in` set to this file's path. Numbers are the next free ones as of writing; if preflight finds them taken, use the next free numbers and note it in Outcome.

### 1. D46: Build and boot job, skipped when nothing build-relevant changed

- **Placement.** A second job in `.github/workflows/ci.yml`, id `build`, named **`build and boot`**. It runs on the `ubuntu-24.04` runner itself, not in a container: it matches the cluster's Ubuntu 24.04, and the boots need `/dev/kvm`. Same triggers as the lint job, plus `workflow_dispatch` so Zach can run it by hand.
- **The skip.** The job always runs, because a required check that never runs leaves a pull request unmergeable. Its first step decides whether to build, with `scripts/ci-changes.sh`:
  - **Build** when any changed file matches: `src/**`, `package/**`, `configs/**`, `external.desc`, `external.mk`, `Config.in`, `scripts/run.sh`, `scripts/ci-changes.sh`, `.github/workflows/**`.
  - **Skip** otherwise: every later step is skipped, the job passes, and the summary says "No build-relevant changes; build and boot skipped", followed by the changed paths.
  - **What "changed" means:**
    - pull requests: the diff from the merge base with the base branch;
    - pushes to `main`: the diff from the previous head (`github.event.before`);
    - `workflow_dispatch`, a new branch, or a base that can't be found: always build.
- **No third-party actions.** Only GitHub's own `actions/checkout`, `actions/cache` and `actions/upload-artifact`, pinned to a major version.

*Alternatives considered:* the `paths:` filter on the workflow (a skipped required check blocks merging); a third-party paths-filter action (supply-chain risk for a protected workflow); building on every pull request (40+ minutes for a README edit).

### 2. D47: Buildroot version in one file, and a download cache

- **Version file.** The Buildroot version lives in `configs/buildroot.version`, one line: `2026.02.3`. README's build-host setup clones that version by reading the file, and CI does the same, so the two can't drift.
- **What's cached.** `buildroot/dl/` (about 1.2 GB of sources) is cached with `actions/cache`.
  - Key: `br-dl-<buildroot version>-<hash of configs/** and package/**>`.
  - Restore key: `br-dl-<buildroot version>-`, so a config change reuses most downloads. This is safe because Buildroot checks every file against its hash and fetches what's missing.
  - A new cache entry is saved whenever the exact key missed.
- **Not cached:** `output/`, which is about 9 GB, against GitHub's 10 GB cache limit per repository. ccache is not used. Every build compiles from scratch.

*Alternatives considered:* caching `output/` (too large, and a stale tree risks a build that doesn't match the configs); ccache (changes the Buildroot configuration; deferred until build time is measured); no cache (1.2 GB from upstream mirrors on every build, and mirror failures that look like code failures).

### 3. D48: KVM on runners, and the four boot cases

- **KVM access.** The job grants the runner user access to `/dev/kvm` with a udev rule, before the boots.
- **The boots.** After the build, the job runs four boots in this order, each with `--no-build` and an explicit `--log logs/ci/<case>.log`:

  | Case | Command | Expected |
  | --- | --- | --- |
  | `kvm` | `scripts/run.sh --no-build --accel kvm` | exit 0, `RUN` line has `accel=kvm` |
  | `tcg` | `scripts/run.sh --no-build --accel tcg` | exit 0, `accel=tcg` |
  | `test-fail` | `scripts/run.sh --no-build --test-fail` | exit 1, `WIPEOS RESULT=FAIL` |
  | `mem4` | `scripts/run.sh --no-build --mem 4` | exit 0 |

- **Failures.** Every case runs even if an earlier one fails, and the step fails if any case didn't match. If KVM can't be made usable, the `kvm` case fails; there is no fallback.

*Alternatives considered:* `--accel auto` only (a broken udev step would silently test TCG and pass); TCG only (matches the cluster today, but leaves D39's KVM path untested anywhere).

### 4. D49: What CI leaves behind

- **Artifacts:**
  - `boot-logs`: the four boot logs, and the last 200 lines of the build log. Uploaded whenever the job got past the skip decision, including on failure.
  - `bzImage`: the image. Uploaded when the build succeeded.
  - Both kept for 14 days. The repository is public, so so are the artifacts.
- **Job summary:** build time, `bzImage` size in bytes, and a table of the four cases with accelerator, exit code and pass or fail.
- **Who uses them.** Agents read failures with `gh run download <run-id> -n boot-logs`. Zach can boot a CI-built image on the cluster with `gh run download <run-id> -n bzImage`, placing it at `buildroot/output/images/bzImage` and running `scripts/run.sh --no-build`, instead of building there.

*Alternatives considered:* logs only in the job log (agents would parse long logs instead of reading files); keeping artifacts for 90 days (the default; they take storage, and the image is rebuilt on demand).

## Delegated to Claude Code

Choices Claude Code makes itself, without stopping. List every one in Outcome, one line each with the reason.

- how `scripts/ci-changes.sh` reads its inputs (arguments or environment) and prints its result, within Decision 1
- how the workflow frees disk space if the runner has less than 20 GB free: removing preinstalled SDKs such as `/usr/share/dotnet`, `/usr/local/lib/android` or `/opt/ghc`
- the apt package list for the build job, starting from README's build-host list
- the exact udev rule and commands for KVM access
- step names, the job's timeout (at most 150 minutes), and whether the boots are one step or four
- how the job summary is laid out, within Decision 4

## Stop conditions

Everything on CLAUDE.md's "Design decisions are mine" list is reserved, unless this plan settles it above or delegates it. Stop when any of these comes up:

- a reserved choice the plan doesn't settle;
- the build fails on the runner and the fix needs a change to the defconfig, the kernel config or Buildroot itself (an apt package or the disk step is delegated);
- the runner doesn't have enough disk for the build even after freeing space;
- `/dev/kvm` can't be made usable on the runner;
- the cold build takes longer than 150 minutes;
- a boot case gives a different result on the runner from the cluster's results in `docs/plans/portable-build-host-and-fast-CI.md`'s Outcome, other than `kvm`, which the cluster couldn't run;
- an existing self-test case would need to change, not just new cases be added;
- a step can't pass its acceptance test without changing something outside this plan;
- the plan contradicts an accepted decision, or the code contradicts the plan.

**How to stop.**

1. Write the question as a `proposed` decision in `context/decisions/`, with your recommendation as the decision and two or three alternatives with their tradeoffs.
2. Set Outcome's status to `blocked`, naming the decision, and rerun `scripts/context_index.py`.
3. End your turn with a short message naming the decision, and wait.

Don't continue with work that depends on the answer, and don't guess.

## Component specs

**`configs/buildroot.version`** (new): one line, the Buildroot release tag, `2026.02.3`.

**`scripts/ci-changes.sh`** (new).

- **Inputs:** a base and a head commit. "No base" means always build.
- **Output:** prints `build` or `skip` on the first line, then the changed paths, one per line.
- **Exit codes:** 0 on success, 2 on bad arguments or a git error. A git error means the workflow builds, because it fails safe.
- **Style:** bash, same conventions as `scripts/lint.sh`. The path list from Decision 1 sits in one array at the top, with a comment pointing to D46.

**`.github/workflows/ci.yml`.** The existing `checks` job is unchanged. Add the `build` job (Decisions 1 to 4):

1. Check out with enough history for the merge base (`fetch-depth: 0` is fine for a repo this size).
2. Decide with `scripts/ci-changes.sh`, and write the result to a step output and the summary.
3. Every later step has `if:` on that output.
4. Free disk if needed, install packages, clone Buildroot at `configs/buildroot.version` into `buildroot/`, restore the `dl/` cache, and run `make BR2_EXTERNAL=.. wipeOS_x86_64_defconfig` then `make` from `buildroot/`, with output to `logs/ci/build.log`.
5. Enable KVM, run the boots, write the summary, and upload the artifacts.

Concurrency as for the existing job: a newer push to a pull request cancels its older run. Keep the file header comment current.

**`.claude/hooks/guard-lint.py`.** Add `scripts/ci-changes.sh` to `PROTECTED`. Running it stays allowed.

**`scripts/hooks-selftest.sh`.** New cases only: block a shell write to `scripts/ci-changes.sh`; pass reading it and running it.

**`README.md`.** Build-host setup clones the version in `configs/buildroot.version`. Add a short section, "Booting an image built by CI", with the `gh run download` commands from Decision 4, and note that `gh` must be installed and logged in on the host.

**`CLAUDE.md`.**

- In "Verifying changes": a change that needs a boot or a `bzImage` size is verified by the **`build and boot`** check. Read its summary with `gh run view`, and its logs with `gh run download <run-id> -n boot-logs`. A cluster run is needed only for hardware CI can't provide; say so in the report.
- In the layout table: rows for the two new files.

## Steps

Work through the steps in order without stopping for review. You are on the laptop, so per D40 you don't build or boot; the runner does.

0. **Preflight.** Check this plan against `context/INDEX.md`, D3, D20, D23, D30, D34, D38, D39, D43 and D44, and the current code. Confirm the decision numbers are free and that `README.md`'s Buildroot version is `2026.02.3`. If anything conflicts or is missing, stop as above, before writing any code.
1. **Version file and change detection.** Add `configs/buildroot.version` and `scripts/ci-changes.sh`.
   - *Acceptance:* run the script against existing commits and record the results in Outcome.
     - `45bf148^ 45bf148` (README and a plan only) gives `skip`.
     - `dece286^ dece286` (lint scripts and `.gitignore`, nothing on the build list) gives `skip`.
     - `9ceb372^ 9ceb372` (`scripts/run.sh`) gives `build`.
     - `536091f^ 536091f` (stub source under `src/`) gives `build`.
     - `ea2daaa^ ea2daaa` (`.github/workflows/ci.yml`) gives `build`.
     - No base gives `build`.
     - A nonexistent base gives `build`, with exit 2.
2. **Guard.** Protect `scripts/ci-changes.sh` in `guard-lint.py`, and add the self-test cases. This brings up a permission prompt for Zach.
   - *Acceptance:* `scripts/hooks-selftest.sh` exits 0.
3. **Build job.** Add the `build` job to `ci.yml`, up to and including the build. Push the branch and open the pull request. The pull request touches `.github/workflows/`, so the job builds.
   - *Acceptance:* the build succeeds. Record the cold build time and the runner's free disk before and after.
4. **Boots, summary and artifacts.** Complete the job (Decisions 3 and 4) and push.
   - *Acceptance:*
     - All four cases match the table, with `accel=kvm` in the `kvm` log. The open `accel=kvm` check is now verified; say so in Outcome.
     - `gh run download` fetches both artifacts.
     - Re-run the job (`gh run rerun`) and confirm the `dl/` cache was restored. Record that run's build time as the warm time.
5. **Docs.** Update `README.md` and `CLAUDE.md` as specified.
   - *Acceptance:* the README's build-host commands read the version from the file. `grep` finds `2026.02.3` only in `configs/buildroot.version` and in records.
6. **Record.**
   - Write D46 to D49 to `context/decisions/` as `accepted`, with `decided_in` set to this file.
   - Add anything you ran into to `context/questions/`. If the cold build is over 60 minutes, add an open question, "Build time in CI", with the cold and warm numbers.
   - Under KR1.3 in `docs/okrs.md`, add a progress note: the image is built and boot-tested in CI on every build-relevant change (D46 to D49).
   - Rerun `scripts/context_index.py`.
   - Fill in Outcome, including the "Done by Zach" checklist below, unticked.

## Done by Zach

Claude Code can't do these. List them in Outcome as a checklist.

1. **Add the `ask` entry for the new script** to `.claude/settings.json`, after `Edit(/scripts/fetch-checkpatch.sh)`:

   ```json
   "Edit(/scripts/ci-changes.sh)",
   ```

2. **Require the new check.** After the check has run once on the pull request, edit the ruleset on `main` and add **`build and boot`** as a second required check, next to **`lint and self-tests`**.
3. **Review and merge** the pull request.
4. **Optional:** on the cluster, boot the `bzImage` artifact from the merged run with `scripts/run.sh --no-build`, to confirm a CI-built image behaves like one built there.

## Outcome

- **Status:** done. The work merged in pull request [#4](https://github.com/ztblick/wipeOS/pull/4) (`92adc61`). Zach merged #4 before this Outcome and a README fix were pushed, so they follow in a second pull request from `claude/build-and-boot-ci-outcome`. No stop condition came up. D46–D49 were free, as planned.
- **Commits:** `7549ab5` (the plan), `dc3520c` (step 1), `769353b` (step 2), `02b5fae` (step 3), `5c49bd6` (step 4), `4096d2b` (step 5), `b4940a9` (D46–D49), and on the follow-up branch, the README fix and OKR note plus this Outcome.
- **Changed:**
  - `configs/buildroot.version` (new): `2026.02.3` (D47).
  - `scripts/ci-changes.sh` (new): build or skip from the changed paths (D46).
  - `.claude/hooks/guard-lint.py`: `scripts/ci-changes.sh` is protected from shell writes and stays runnable, directly or with `bash`.
  - `scripts/hooks-selftest.sh`: five new Part 1 cases (two block, three pass). No existing case changed.
  - `.github/workflows/ci.yml`: the `build` job, **`build and boot`**; `workflow_dispatch`; header comment rewritten for both jobs.
  - `README.md`:
    - The build-host clone reads `configs/buildroot.version`.
    - New section "Build and boot in CI (D46–D49)" with "Booting an image built by CI".
    - Rows for the two new files.
    - "Where things run" mentions the new check.
    - "How changes reach main" says "the CI checks".
  - `CLAUDE.md`:
    - "Verifying changes" as the plan specifies, and layout rows for the two new files.
    - Beyond the spec, so they don't contradict it: three lines that said boots come "once plan 2 lands" or described CI as lint only (the runner row of the machine table, the `ci.yml` layout row, and "Commands").
  - `docs/okrs.md`: a progress note under KR1.3.
  - Records: D46–D49.
- **Verified:**
  - **Step 0.** D46–D49 free; README pinned `2026.02.3`; the five commits the acceptance test names touch the files the plan says; no conflict with D3, D20, D23, D30, D34, D38, D39, D43 or D44.
  - **Step 1.** `scripts/ci-changes.sh`:

    | Arguments | First line | Exit |
    | --- | --- | --- |
    | `45bf148^ 45bf148` (README, plan) | `skip` | 0 |
    | `dece286^ dece286` (lint scripts, `.gitignore`) | `skip` | 0 |
    | `9ceb372^ 9ceb372` (`scripts/run.sh`) | `build` | 0 |
    | `536091f^ 536091f` (`src/stub/*.c`) | `build` | 0 |
    | `ea2daaa^ ea2daaa` (`ci.yml`) | `build` | 0 |
    | `'' HEAD` (no base) | `build` | 0 |
    | all-zeros base (new branch) | `build` | 0 |
    | `deadbeefdeadbeef HEAD` (nonexistent base) | `build` | 2 |
    | `HEAD` only (bad arguments) | `build` | 2 |
    | `HEAD HEAD` | `skip`, no paths | 0 |

  - **Step 2.** `scripts/hooks-selftest.sh`: 224 cases, 0 failed.
  - **Step 3.** CI run [40423302997](https://github.com/ztblick/wipeOS/actions/runs/40423302997), the build job only. The decision was `build` (the workflow changed).
    - Disk: 86 GB free on `/` at the start, so nothing was removed; 76 GB free after the build.
    - Cache miss, as expected for a first run, and a new entry was saved under `br-dl-2026.02.3-0594…0904`.
    - **Cold build: 2273 s (37 min 53 s)**, exit 0. QEMU 8.2.2 (`1:8.2.2+ds-0ubuntu1.18`), the same version as the cluster.
    - `bzImage` 8,569,856 bytes.
  - **Step 4.** CI run [40438641765](https://github.com/ztblick/wipeOS/actions/runs/40438641765), the whole job:
    - Download cache: exact hit. Build: 1333 s. 87 GB free at the start.
    - After the udev rule, `/dev/kvm` was `crw-rw-rw- root kvm`.
    - Boots:

      | Case | Accelerator | Exit (expected) | Log | Result |
      | --- | --- | --- | --- | --- |
      | `kvm` | kvm | 0 (0) | `RUN … accel=kvm`, `RESULT=SUCCESS`, `Power down` | pass |
      | `tcg` | tcg | 0 (0) | `RUN … accel=tcg`, `RESULT=SUCCESS` | pass |
      | `test-fail` | kvm | 1 (1) | `RESULT=FAIL reason=test_fail`, `Power down` | pass |
      | `mem4` | kvm | 0 (0) | `pages=1g hugepages_requested=2`, `hugetlb.pages_total=1`, `RESULT=SUCCESS` | pass |

    - **The open `accel=kvm` check from `docs/plans/portable-build-host-and-fast-CI.md` is now verified:** `run.sh --accel kvm` boots under KVM on the runner. The `tcg`, `test-fail` and `mem4` results match the cluster's, including `mem4`'s 1 of 2 huge pages, the deferred question "Huge-page count in QEMU above 3 GiB".
    - `gh run download 40438641765 -n boot-logs` fetched the four boot logs and `build-tail.log`. `-n bzImage` fetched an 8,569,856-byte file that `file` identifies as a Linux 6.18.7 x86 bzImage.
    - `gh run download` refuses to overwrite an existing file ("file exists"), so the README's download commands now create the directory and `rm -f` the old image first. Run as written, that sequence downloads the image.
    - Re-run of the job (`gh run rerun --job`, attempt 2): download cache restored from the exact key, **warm build 2185 s (36 min 25 s)**, all four boots pass as above.
  - **Step 5.** README's build-host commands clone `"$(cat configs/buildroot.version)"`. `grep` finds `2026.02.3` only in `configs/buildroot.version` and this plan.
  - **Not verified:**
    - The skip path on a real CI run: every run on #4 built, because the pull request touches the workflow. The skip logic is covered by the step 1 cases.
    - The disk cleanup branch: the runner had 86–87 GB free, so it never ran.
    - The `push` to `main` path (`github.event.before`) after the merge: not read yet.
    - `actionlint` and `shellcheck` aren't installed. Instead, the YAML was parsed with Python, each inline script passed `bash -n`, and the Boot and Summary scripts were run against a fake `run.sh` in the scratchpad, with KVM working and not.
- **Build time.** Cold 2273 s; warm 1333 s and 2185 s. The cold build is under 60 minutes, so no "Build time in CI" question was added. Warm and cold differ by less than the two warm runs differ from each other. The download cache saves little next to compile time and the variation between runners.
- **Image size:** not affected; nothing in the image changed. CI's first recorded `bzImage` size is 8,569,856 bytes, the reference for later changes.
- **Choices made within delegated scope:**
  - **`ci-changes.sh` interface:** two positional arguments, `BASE HEAD`. An empty or all-zeros base means "no base". Any error prints `build` first, then exits 2.
  - **`ci-changes.sh` diff:** a three-dot `git diff`, so the diff starts at the merge base. `--no-renames` makes a file moved out of `src/` count as a change to `src/`.
  - **Workflow inputs to the script:**
    - Pull requests pass `pull_request.base.sha` and `head.sha`, so the diff is the one GitHub shows, not the merge commit's.
    - Pushes pass `github.event.before` and `GITHUB_SHA`; manual runs pass no base.
    - The workflow builds unless the script prints `skip` and exits 0.
  - **Disk:** free space is measured on `/`. Below 20 GB, the step removes `/usr/share/dotnet`, `/usr/local/lib/android`, `/opt/ghc` and `/usr/local/.ghcup`, and fails if there's still less than 20 GB.
  - **apt:**
    - README's list without `libncurses-dev` (only for menuconfig).
    - Plus `seabios` and `ipxe-qemu` named explicitly: the BIOS and the default NIC's boot ROM. With `--no-install-recommends`, they're listed in case they're only recommends.
  - **KVM:** `/etc/udev/rules.d/99-kvm4all.rules` with `KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"`, then `udevadm control --reload-rules` and `udevadm trigger --name-match=kvm`. The step doesn't check the result itself; the `kvm` case is the test, with no fallback, as D48 says.
  - **Job:**
    - Timeout 150 minutes.
    - `defaults.run.shell: bash`, so every step runs with `-eo pipefail`.
    - One Boot step: a `boot()` function per case, with results in `$RUNNER_TEMP/boots.tsv` for the summary.
    - The boots and the uploads run with `!cancelled()`, so a failed KVM step or one failed case doesn't skip the rest.
  - **Summary:**
    - The decide step writes the verdict and the changed paths, with base and head.
    - The Summary step writes a Build table (outcome and time, `bzImage` bytes, download cache: exact, partial or miss, and free disk at three points) and the Boots table (case, accelerator, exit, expected, result).
  - **Cache, split into `actions/cache/restore@v6` and `actions/cache/save@v6`:**
    - The save runs only after a successful build. A save after an early failure would store a near-empty `dl/` under the exact key, which later runs would hit and never replace.
    - This narrows D47's "saved whenever the exact key missed". Zach, say if you want it the other way.
  - **Action versions:** `actions/checkout@v7`, `actions/cache@v6` and `actions/upload-artifact@v7`, the latest majors per the GitHub releases API.
  - **Clone:** CI clones Buildroot with `--depth 1`; the build needs no history.
  - **Build log tail:** written inside the Build step on success and failure, as `logs/ci/build-tail.log`.
  - **`workflow_dispatch`:** sits at the workflow level, so a manual run also runs the lint job. Its definition is unchanged.
  - **Accelerator for the last two cases:** `test-fail` and `mem4` use `run.sh`'s default `--accel auto`, which chose KVM on the runner. The plan's table doesn't set an accelerator for them.
  - **Branch:** `claude/build-and-boot-ci`, one commit per step.
- **Records written:**
  - **Decisions:** D46–D49, `accepted`, with `decided_in` this plan.
  - **Open questions:** none; the cold build is under 60 minutes.
  - **OKRs:** a progress note under KR1.3; no key result ticked.
  - **Index:** `context/INDEX.md` regenerated.
- **Suggested `docs/design.md` change** ("Codebase design", after the sentence on `scripts/run.sh`): "On every change that can affect the image, CI builds it on a GitHub-hosted runner, boots it four times under KVM and TCG, and reports the `bzImage` size (D46–D49)."
- **Noticed, not touched:**
  - The skip compares the pull request's whole diff, so once a pull request touches a build-relevant file, every later push to it rebuilds (22–38 min), docs-only pushes included. That is D46 as written.
  - Right after both runs ended, `gh run view <id> --log` printed nothing and exited 0. `gh api repos/ztblick/wipeOS/actions/jobs/<job-id>/logs` (a read) returned the log. CLAUDE.md's `gh run view --log-failed` may hit the same gap.
  - The README's `rm -f buildroot/output/images/bzImage` brings up the build guard's "ask" prompt for an agent on a build host (D35), as CLAUDE.md intends for deleting build output.
  - Zach's uncommitted change to `.claude/settings.json` (dropping the redundant `Write(/.github/workflows/**)`) is still in the working tree, uncommitted. "Done by Zach" 1 below edits the same file.
  - `test-fail` and `mem4` boot under KVM on the runner, so CI no longer runs those two cases under TCG.
- **Done by Zach:**
  - [ ] Add `"Edit(/scripts/ci-changes.sh)",` to the `ask` list in `.claude/settings.json`, after `Edit(/scripts/fetch-checkpatch.sh)`.
  - [ ] Add **`build and boot`** as a second required check on `main`'s ruleset. As of this Outcome, `protect-main` requires only **`lint and self-tests`**.
  - [x] Review and merge the pull request: #4 merged as `92adc61`. The follow-up pull request with this Outcome is still open.
  - [ ] Optional: on the cluster, boot the `bzImage` artifact from the merged run with `scripts/run.sh --no-build`, using the README's download commands.