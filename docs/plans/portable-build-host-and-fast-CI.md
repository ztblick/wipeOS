# Plan: Portable build hosts, fast CI and the agent git workflow (supports KR1.3)

Implementation plan for moving builds and boots off the laptop onto x86_64 Linux hosts (GitHub-hosted runners and the cluster), giving the laptop and CI the same lint tools, adding a fast CI check on every pull request, and letting agents work through branches and pull requests that only Zach merges. Written 2026-10-26 from a design discussion with Zach.

Read this whole file before starting, together with `CLAUDE.md` and the records it points to in `context/INDEX.md`. Then do step 0, the preflight, before changing anything.

## Goal

Every build and boot runs on an x86_64 Linux host: a GitHub-hosted runner or the cluster. The laptop is for editing, driving Claude Code, linting, git and SSH, and the build guard enforces that. `scripts/run.sh` uses KVM when the host has it, so boots are fast where they can be. Lint no longer needs a kernel build, always targets x86_64, and uses the same tool versions on the laptop and in CI. A GitHub Actions workflow runs lint, both self-tests and the index check on every pull request to `main` and every push to `main`. Agents develop on a branch, push it and open a pull request; only Zach merges into `main`, and a guard stops agents from merging, approving or pushing to `main`. This supports KR1.3 (the harness) but completes no key result.

**Out of scope:** building the image or booting it in CI (plan 2); agents running in GitHub; self-hosted runners (the repo is public, D38); a separate GitHub identity for agents (D44); changes to the stub, the image, the kernel config or the Buildroot defconfig.

## Before handing this over

Zach does these before Claude Code starts; the preflight checks them. The lint guard blocks Claude from items 3 and 4.

1. **The stub passes whole-tree lint.** On 2026-10-26, `scripts/lint.sh` on `main` exits 1 with 38 checkpatch findings in `src/stub/` (28 `LINE_SPACING`, 6 long lines, 2 `ASSIGN_IN_IF`, 1 `STRCPY`, 1 `UNSPECIFIED_INT`). They predate the pre-commit hook, which checks only changed lines. CI lints the whole tree (D43), so these are fixed first, in a separate change.
2. **The x86_64 cross compiler is on the laptop** (D42): `sudo apt install gcc-x86-64-linux-gnu libc6-dev-amd64-cross`. `x86_64-linux-gnu-gcc --version` shows 15.2.
3. **`scripts/hooks-selftest.sh` is executable in git.** It is mode 100644 today, so CI can't run it by path: `chmod +x scripts/hooks-selftest.sh && git update-index --chmod=+x scripts/hooks-selftest.sh`.
4. **This plan, item 3 and the `ask` entries in `.claude/settings.json` are committed to `main` and pushed.** The `ask` entries for `scripts/fetch-checkpatch.sh` and `.github/workflows/` were added on 2026-10-26.

## Constraints from existing decisions

- **D12:** the test ladder's first rung says "Linux emulation on a laptop". D38 supersedes D12 and keeps rungs 2 and 3 as written.
- **D17:** lint compiles for x86_64 on every host (D42), so x86-only code lints the same on the laptop and in CI.
- **D23:** `run.sh` uses the distribution's `qemu-system-x86_64`. Unchanged; only the accelerator changes.
- **D30:** `run.sh` exit codes 0/1/2/3 keep their meaning.
- **D33:** D41 and D42 change where checkpatch and the compiler come from, not which checks run. "The kernel tree's checkpatch.pl" stays true: the fetched file is the kernel tree's, at the pinned tag.
- **D33, D34:** lint applies the same checks everywhere, and every route around it stays closed. The new fetch script and the CI workflow are lint infrastructure, so they get the same protection as `scripts/lint.sh`.
- **D35:** D40 amends D35's pass list: on a non-x86_64 host, `make`, `scripts/run.sh` and `qemu-system-x86_64` are denied, where D35 lets them pass. The rest of D35 is unchanged, D35 stays accepted, and its body stays as written; D40's body states the amendment. The KVM rule is already conditional on `/dev/kvm` and needs no change.
- **D37:** the new git guard follows D37's conventions. Guard changes need self-test cases in `scripts/hooks-selftest.sh`, and the self-test pins the host architecture so its results don't depend on the machine.
- **D3, D20:** nothing in this plan changes the image. `bzImage` size is unaffected and doesn't need reporting.

## Decisions made for this plan

Settled with Zach in chat. In the last step, record each one in `context/decisions/` as `accepted`, with `decided_in` set to this file's path. Numbers are the next free ones as of writing; if preflight finds them taken, use the next free numbers and note it in Outcome.

### 1. D38: Build and test hosts

Builds and QEMU boots run only on x86_64 Linux hosts: GitHub-hosted runners (CI) and the cluster (by hand, over SSH). The laptop (Windows on Arm, WSL2) is a workstation: editing, Claude Code sessions, lint, the pre-commit hook, git and `gh`, and SSH to the cluster. No builds or boots there. While the repo is public, CI uses GitHub-hosted runners only, never self-hosted, because a pull request from anyone could run code on a self-hosted machine. When the repo goes private, the cluster may become a self-hosted runner without script changes.

Supersedes D12, restating the test ladder: (1) local wiping, launching WipeOS directly on the node with no host-OS handoff, starting in QEMU on GitHub-hosted runners and the cluster; (2) the tap and the DGX node together emulating the auditor and host; (3) the DGX node split into two nodes for multi-node barrier tests.

*Alternatives considered:* keeping the laptop as a supported build host (slow TCG boots, a 40-minute build, and an aarch64 host that differs from every other environment); the cluster only, no CI (no automatic check on every change, which the agent pipeline needs).

### 2. D39: QEMU accelerator in run.sh

`scripts/run.sh` takes `--accel auto|kvm|tcg`, default `auto`.

- **`auto`:** uses KVM when the host is x86_64 and `/dev/kvm` is readable and writable by the user; otherwise TCG.
- **`kvm`:** forces KVM. If it isn't usable, `run.sh` exits 2 with the reason, before building anything.
- **`tcg`:** forces software emulation.
- The chosen accelerator is passed as `-accel kvm` or `-accel tcg`, and recorded in the `RUN` header as `accel=<kvm|tcg>`, next to `mode=`.
- `-cpu max` for 1 GB pages stays as it is; it works under both accelerators.

*Alternatives considered:* always KVM on x86_64 (fails on runners without `/dev/kvm` access instead of degrading); a separate CI-only launcher (two code paths that can drift apart).

### 3. D40: No builds or boots on a non-x86_64 host

`.claude/hooks/guard-build.py` denies, on a host whose machine type (`platform.machine()`, or `GUARD_BUILD_HOST_ARCH` if set, for the self-test) isn't `x86_64`:

- any `make` or `gmake`. Nothing on the laptop needs make: the stub is built by Buildroot (D26), and lint doesn't use make.
- `scripts/run.sh`, whether run directly by any path ending in `scripts/run.sh` or as the script argument of `bash` or `sh`, unless one of its arguments is `-h` or `--help`;
- `qemu-system-x86_64`.

The reason tells Claude to verify through CI or ask Zach to run it on the cluster. On x86_64 hosts, nothing changes.

This amends D35. D35's pass list includes `make`, `scripts/run.sh` with any options, and `qemu-system-x86_64` without KVM flags; on a non-x86_64 host these are now denied. The rest of D35 is unchanged.

*Alternatives considered:* a CLAUDE.md rule only (one forgotten `make` costs 40 minutes and fails anyway); asking instead of denying (there's no legitimate build on the laptop any more); denying `make` only in `buildroot/` (the hook would have to guess the shell's directory from `cd` and `-C`, for no gain, since nothing else on the laptop needs make).

### 4. D41: checkpatch without a kernel build

- **New script.** `scripts/fetch-checkpatch.sh` downloads `checkpatch.pl`, `spelling.txt` and `const_structs.checkpatch` for the kernel version pinned in `configs/wipeOS_x86_64_defconfig` (`BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`, 6.18.7 today). The source is kernel.org's stable tree at tag `v<version>`, and the files go into `.cache/checkpatch/<version>/`, which is gitignored. The script prints the absolute path of `checkpatch.pl`, and does nothing else if the files are already there.
- **Lookup in `lint.sh`.** `CHECKPATCH` if set, otherwise the cache for the pinned version. The Buildroot tree is no longer searched, so every host runs the same file. If the cached file is missing, the error message names `scripts/fetch-checkpatch.sh`.
- **Protection.** The fetch script is protected like `scripts/lint.sh`: in the lint guard's protected paths and runnable scripts, and in `.claude/settings.json`'s `ask` list, which Zach edits (see "Done by Zach").

*Alternatives considered:* vendoring `checkpatch.pl` in the repo (GPL-2.0 file to keep in sync by hand); a system checkpatch package (version drifts from our kernel); downloading the whole kernel tarball every run (about 150 MB for three files); keeping the Buildroot tree first in the lookup (after a kernel bump, a stale tree on the laptop would lint with an older checkpatch than CI).

### 5. D42: The same lint tools on the laptop and in CI

- **One distribution release.** The laptop and CI both run Ubuntu 26.04, so gcc (15.2) and cppcheck (2.19) come from the same packages. CI runs its job in the `ubuntu:26.04` container on a GitHub-hosted runner (D43). Build hosts lint with whatever tools they have; CI is the gate.
- **Compiler, always for x86_64 (D17).** `LINT_CC` if set; on an x86_64 host, `gcc`; otherwise `x86_64-linux-gnu-gcc` (Ubuntu's `gcc-x86-64-linux-gnu`, the same gcc release as the host's). If that compiler is missing or has no `-fanalyzer`, `lint.sh` exits 2 and names the package. There is no fallback to another compiler, and Buildroot's cross gcc is no longer used.
- **Versions in the output.** `lint.sh` prints a `tools` section first, with the compiler's and cppcheck's `--version` lines and the checkpatch path, so a difference between the laptop and CI shows in the logs.

*Alternatives considered:* the `ubuntu-26.04` runner image instead of a container (simpler, but in public preview as of October 2026; switch when it is generally available); Buildroot's cross gcc (gcc 14.3, exists only where a build has run, and differs from CI); the laptop's host gcc (targets aarch64, so x86-only code won't compile there); running lint in a container on the laptop too (an exact match, but Docker in WSL for every commit).

### 6. D43: Fast CI on pull requests and on main

`.github/workflows/ci.yml` runs on `pull_request` targeting `main` and on `push` to `main`, on a GitHub-hosted `ubuntu-24.04` runner (pinned, not `ubuntu-latest`), with the job inside the `ubuntu:26.04` container (D42).

- **Steps:** install the tools with `apt-get` (git, gcc, libc6-dev, cppcheck, perl, python3, curl, ca-certificates), before checkout, so the checkout is a real git clone; check out; `git config core.hooksPath .githooks` (`lint-selftest.sh` checks it); `scripts/fetch-checkpatch.sh`; `scripts/lint.sh`; `scripts/lint-selftest.sh`; `scripts/hooks-selftest.sh`; `scripts/context_index.py --check`.
- **Settings:** `permissions: contents: read`, and no secrets, so pull requests from forks are safe.
- **Concurrency:** one group per pull request (or per ref, for pushes). A newer push cancels an older run on the same pull request; runs on `main` always finish.
- **Protection:** `.github/workflows/` is protected like the lint scripts: lint guard paths plus the `ask` list. A weakened workflow is a way around the lint (D34).
- **Enforcement:** a ruleset on `main` that requires the check, set by Zach in GitHub (D44, "Done by Zach").

*Alternatives considered:* `ubuntu-latest` (tools change under us without a commit); running on every push to every branch (each push to a pull request runs twice); running only on pull requests (merges into `main` go unchecked).

### 7. D44: Agents work through branches and pull requests; only Zach merges

- **Workflow.** An agent starts from an up-to-date `main` (`git switch main && git pull --ff-only`), creates a branch `claude/<short-topic>`, and commits on it as the work goes; the pre-commit lint applies to every commit. It pushes with `git push -u origin <branch>` and opens a pull request to `main` with `gh pr create`. Later commits pushed to the same branch update the pull request. It reads CI with `gh pr checks` and `gh run view`.
- **Never.** Agents never commit on `main`, push to `main`, force-push, delete a remote branch, merge or approve a pull request, change repository settings, rulesets, secrets or variables, write through `gh api`, or print the `gh` token.
- **Enforced on GitHub.** A ruleset on `main` (Zach sets it): require a pull request, require the CI check, block force pushes, restrict deletion, and leave the bypass list empty. No required approvals: agents push as Zach's GitHub account, and GitHub doesn't let an account approve its own pull request, so a required approval would block every merge. Zach's merge is the approval.
- **Enforced locally.** A new hook, `.claude/hooks/guard-git.py`, denies the "never" list before it reaches GitHub. Like D34 and D35, it stops the obvious and the accidental, not a determined attempt: an agent holding Zach's token could still reach the API another way.

*Alternatives considered:* a separate GitHub account for agents, with CODEOWNERS and a required review from Zach (GitHub itself enforces that only Zach approves, but it needs a second account, SSH key and `gh` login on the laptop; revisit when agents run unattended or in GitHub); Claude Code permission deny rules only (prefix matching misses `git -C . push`, wrappers and `bash -c`); agents never push and Zach pushes every branch (Zach becomes the bottleneck for every CI run).

### 8. D45: Environment-neutral CLAUDE.md and README

- **CLAUDE.md "Development environment".** Rewritten as a short table of the three machines (laptop, GitHub runners, cluster) and what each is for, followed by:
  - **Laptop rules:** WSL2 on aarch64; Windows interop off; never `/mnt/c`; no builds or boots (D40); lint compiles for x86_64 with the cross compiler (D42).
  - **Build-host rules:** builds are expensive; never `make clean`, `make distclean` or delete `output/` without asking; narrowest rebuild target; KVM through `run.sh`'s `--accel auto` (D39) and never by hand; ask before installing system packages.
- **CLAUDE.md "Commands".** `scripts/run.sh` and `make` are build-host commands; on the laptop, boots are verified in CI (plan 2) or by Zach on the cluster.
- **CLAUDE.md "Verifying changes".** On the laptop: run lint and the self-tests locally, push the branch, and read the CI result on the pull request (`gh pr checks`, or `gh run view --log-failed` on failure). A change that needs a boot, or a `bzImage` size, is verified in CI once plan 2 lands or by Zach on the cluster; say which in the report. On a build host, the existing rules apply.
- **CLAUDE.md "Git".** Replaced by D44's workflow and its "never" list. The suggested commit message becomes the actual message; the end-of-task report links the pull request.
- **README.md.** "Running wipeOS" and "Set up on a new machine" split into "Workstation (laptop)" (clone, `git config core.hooksPath .githooks`, the cross compiler and lint tools, `scripts/fetch-checkpatch.sh`, `gh auth login`, the WSL notes) and "Build host (cluster or any x86_64 Linux)" (today's Buildroot, launch, boot-by-hand and rebuild steps, plus `--accel`). A short "How changes reach main" section describes D44's flow. The "current as of" note updates to this plan's date.

*Alternatives considered:* a separate CLAUDE.md per environment (three files to keep consistent); leaving the laptop details and adding CI notes (agents in CI read false facts about their host).

## Delegated to Claude Code

Choices Claude Code makes itself, without stopping. List every one in Outcome, one line each with the reason.

- the exact wording of the rewritten CLAUDE.md and README sections, within Decision 8
- how `fetch-checkpatch.sh` downloads: `curl` or `wget`, and the exact kernel.org URL form (the stable tree's `plain/` endpoint is the expected one). Verify it fetches the three files for v6.18.7.
- how `run.sh` tests that `/dev/kvm` is usable, and where in the script the accelerator is chosen, as long as `--accel kvm` fails before any build
- the internal structure of `guard-git.py`, and how it reads the current branch, as long as `GUARD_GIT_BRANCH` overrides it
- the new self-test cases' names and order
- workflow job and step names, one job or several, and the exact apt package list; report the name of the check Zach must require
- the `actions/checkout` major version: `@v5`, or a newer major if its releases page lists one
- this plan's branch name, under `claude/`, and how the work splits into commits

## Stop conditions

Everything on CLAUDE.md's "Design decisions are mine" list is reserved, unless this plan settles it above or delegates it. Stop when any of these comes up:

- a reserved choice the plan doesn't settle;
- an item in "Before handing this over" isn't done;
- kernel.org doesn't serve the three checkpatch files for the pinned version in any reasonable form;
- a fetched file differs from its copy in `buildroot/output/build/linux-6.18.7/scripts/` (that would mean the two sources differ);
- lint reports findings in `src/` with the new tools that it didn't with the old ones (fixing the stub is out of scope);
- an existing self-test case would need to change. The harness changes listed in Component specs are allowed;
- CI fails on the pull request for a reason this plan didn't introduce;
- a step can't pass its acceptance test without changing something outside this plan;
- the plan contradicts an accepted decision, or the code contradicts the plan.

**How to stop.**

1. Write the question as a `proposed` decision in `context/decisions/`, with your recommendation as the decision and two or three alternatives with their tradeoffs.
2. Set Outcome's status to `blocked`, naming the decision, and rerun `scripts/context_index.py`.
3. End your turn with a short message naming the decision, and wait.

Don't continue with work that depends on the answer, and don't guess.

## Component specs

**`scripts/fetch-checkpatch.sh`.**

- **Version.** Reads the version from the defconfig. Fails with exit 2 if the line is missing.
- **Output.** Writes to `$repo/.cache/checkpatch/<version>/` and prints the absolute path of `checkpatch.pl` on success.
- **Re-runs.** If all three files exist, it exits 0 without network access.
- **Failures.** A failed download leaves no partial files (download to a temp path, then move), and the script exits 2.
- **Style.** Bash, same conventions as `scripts/lint.sh`: `set -uo pipefail`, path from `git rev-parse --show-toplevel`, a usage comment.

**`scripts/lint.sh`.** The checkpatch lookup (D41), the compiler choice (D42) and the `tools` section change, with the header comment and error messages to match. The checks, their flags and the exit codes don't change.

**`scripts/lint-selftest.sh`.** Harness only; no case changes.

- After the preflight, if `CHECKPATCH` is unset, export it from `scripts/fetch-checkpatch.sh` (exit 2 if that fails), so `lint.sh` inside the throwaway repo, which has no defconfig or cache, finds the same file.
- Remove the `buildroot` symlink and the throwaway repo's `.gitignore` line (lines 411–414 today), and their comment; the throwaway repo no longer needs Buildroot.

**`scripts/run.sh`.**

- New `--accel` option in `usage()`, the argument loop and validation; a bad value exits 3.
- The accelerator is chosen after argument parsing and before the build.
- The `RUN` header gains `accel=`.

**`.claude/hooks/guard-build.py`.** Decision 3. The host arch is read once, and `GUARD_BUILD_HOST_ARCH` overrides it, like `GUARD_BUILD_KVM_DEVICE`. The docstring's pass list and rule list describe the amendment.

**`.claude/hooks/guard-lint.py`.** Add `scripts/fetch-checkpatch.sh` and `.github/workflows/` to `PROTECTED`, and `scripts/fetch-checkpatch.sh` to `RUNNABLE`, so running it (directly or with `bash`) stays allowed, like `lint.sh`. Update the docstring's list.

**`.claude/hooks/guard-git.py`** (new, D44). A PreToolUse hook on Bash, following D37: Python, works from `$CLAUDE_PROJECT_DIR`, registered in exec form with `onFailure: "block"`. It splits commands like the other guards, including wrappers and `bash -c`. It denies (exit 2, reason on stderr):

1. `git push` with `-f`, `--force`, `--force-with-lease`, `--force-if-includes`, `--mirror`, `--all`, `--delete`, `-d` or `--prune`, or a refspec starting with `+` or `:`;
2. `git push` whose destination is `main`: a refspec `main` or `refs/heads/main`, a `<src>:main` or `<src>:refs/heads/main` refspec, `HEAD` while the current branch is `main`, or no refspec while the current branch is `main`;
3. while the current branch is `main`: `git commit`, `merge`, `cherry-pick`, `revert`, `am` or `rebase` (`git pull --ff-only` stays allowed);
4. `gh pr merge`, and `gh pr review` with `--approve` or `-a`;
5. `gh api` with `-X` or `--method` other than `GET`, or with `-f`, `-F`, `--field`, `--raw-field` or `--input`;
6. `gh repo edit`, `delete`, `rename` or `archive`; `gh secret` and `gh variable` `set` or `delete`; `gh auth token`, `login`, `logout`, `refresh` or `switch`.

Everything else passes, including `git push -u origin claude/<topic>`, `gh pr create`, `gh pr view`, `gh pr checks` and `gh run view`. The current branch comes from the project's own repo; `GUARD_GIT_BRANCH` overrides it for the self-test. A detached HEAD counts as not `main`.

**`scripts/hooks-selftest.sh`.** Harness changes, then new cases only.

- **Harness.** `hook()` sets `GUARD_BUILD_HOST_ARCH=x86_64` and `GUARD_GIT_BRANCH=claude/selftest` by default, next to `GUARD_BUILD_KVM_DEVICE`, so results don't depend on the host. The header lists a Part 4 for `guard-git.py`.
- **guard-build with `GUARD_BUILD_HOST_ARCH=aarch64`:** deny `make`, `make -C buildroot`, `cd buildroot && make`, `make -C src/stub`, `scripts/run.sh`, `./scripts/run.sh`, `bash scripts/run.sh --no-build`, `~/wipeOS/scripts/run.sh`, `qemu-system-x86_64 -m 1G` and `timeout 600 qemu-system-x86_64 -m 1G`; pass `scripts/run.sh --help`, `scripts/run.sh -h`, `scripts/lint.sh` and `scripts/fetch-checkpatch.sh`. The existing cases already cover the same commands passing on x86_64.
- **guard-lint:** block a shell write to `.github/workflows/ci.yml` and to `scripts/fetch-checkpatch.sh`; pass reading them, running the fetch script and `bash scripts/fetch-checkpatch.sh`.
- **guard-git (Part 4):** every item in its deny list, and the pass list above. With `GUARD_GIT_BRANCH=main`: deny `git commit -m x`, `git push`, `git push origin HEAD` and `git merge x`; pass `git pull --ff-only` and `git switch -c claude/x`.

**`.gitignore`.** Add `.cache/`.

**`.github/workflows/ci.yml`.** Decision 6. Pin actions to a major version.

## Steps

Work through the steps in order without stopping for review. You are on the laptop, so per D40 you don't build or boot; verification is lint, the self-tests and CI. Commit on this plan's branch as you go (D44); never merge.

0. **Preflight.** Check this plan against `context/INDEX.md`, D12, D17, D23, D26, D30 and D33 to D37, and the current code. Confirm the decision numbers are free and every item in "Before handing this over" is done (`scripts/lint.sh` exits 0 on `main`, `x86_64-linux-gnu-gcc --version` shows 15.2, `git ls-files -s scripts/hooks-selftest.sh` shows 100755, this plan is on `origin/main`). If anything conflicts or is missing, stop as above, before writing any code. Then create this plan's branch from an up-to-date `main`.
1. **checkpatch and lint tools.** Add `scripts/fetch-checkpatch.sh`, add `.cache/` to `.gitignore`, change `lint.sh` (D41, D42) and the `lint-selftest.sh` harness. Editing `lint.sh` and `lint-selftest.sh` brings up a permission prompt for Zach.
   - *Acceptance:* `scripts/fetch-checkpatch.sh` prints the cache path, and a second run exits 0 without downloading. `cmp` shows each fetched file identical to its copy in `buildroot/output/build/linux-6.18.7/scripts/`. In a fresh `git worktree` of the branch, which has no `buildroot/` (what CI sees), `scripts/fetch-checkpatch.sh`, `scripts/lint.sh` and `scripts/lint-selftest.sh` exit 0, and lint's `tools` section shows `x86_64-linux-gnu-gcc` 15.2 and cppcheck 2.19. The same three pass in the main checkout. Remove the worktree afterwards.
2. **Accelerator in run.sh.** Decision 2.
   - *Acceptance:* `bash -n scripts/run.sh` passes; `scripts/run.sh --help` shows `--accel` (allowed on the laptop under D40); `shellcheck scripts/run.sh` if shellcheck is installed, with no new findings. Booting is tested by Zach on the cluster (see "Done by Zach") and by CI in plan 2.
3. **Guards.** Decision 3 in `guard-build.py`, the new paths in `guard-lint.py`, the new `guard-git.py` (Decision 7), and the harness change and new cases in `scripts/hooks-selftest.sh`. Each edit brings up a permission prompt for Zach. `guard-git.py` isn't registered yet (Zach does it after this step), so test it through the self-test only.
   - *Acceptance:* `scripts/hooks-selftest.sh` exits 0 with the new cases included, and `scripts/lint-selftest.sh` still exits 0.
4. **CI workflow and pull request.** Add `.github/workflows/ci.yml` (Decision 6). Push the branch and open a pull request to `main` with `gh pr create`, its body summarizing this plan and pointing to it.
   - *Acceptance:* the workflow runs on the pull request and passes. Read the log with `gh run view --log` and confirm each step ran, not just that the job is green, and that the `tools` section matches the laptop's versions.
5. **Docs.** Decision 8: CLAUDE.md's "Development environment", "Commands", "Verifying changes" and "Git" sections, the project layout table rows for the new files, and README's "Running wipeOS" and setup sections. Push.
   - *Acceptance:* no remaining instruction tells an agent it's on WSL or aarch64 outside the laptop rules, or to build or boot on the laptop; every command in README's workstation section works on the laptop.
6. **Record.**
   - Write D38 to D45 to `context/decisions/` as `accepted`, with `decided_in` set to this file. D38 gets `supersedes: [D12]`; set D12's `status: superseded` and `superseded_by: D38`, in the same change.
   - Add an open question to `context/questions/`: the laptop and the CI container get the same tools only while both track Ubuntu 26.04's updates, and build hosts lint with their own tools; should the versions be pinned, and how?
   - Under KR1.3 in `docs/okrs.md`, add a progress note: `run.sh` chooses the accelerator (D39), and fast CI runs on every pull request (D43).
   - Update `README.md` if a command or path changed beyond step 5.
   - Rerun `scripts/context_index.py`.
   - Fill in Outcome, including the suggested `docs/design.md` text for the test ladder and tier T0 (D38), and the "Done by Zach" checklist below, unticked. Commit and push, so the pull request holds everything. Don't merge it.

## Done by Zach

Claude Code can't do these. List them in Outcome as a checklist.

1. **Edit `.claude/settings.json` on the pull request branch, after step 3.** The `ask` entries are already in place (see "Before handing this over").
   - Register the git guard in `PreToolUse`, in the `Bash` matcher's `hooks` list, after `guard-build.py`. Only once `guard-git.py` exists: with `onFailure: "block"`, a missing script blocks every Bash call.

     ```json
     {
       "type": "command",
       "command": "python3",
       "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/guard-git.py"],
       "timeout": 10,
       "onFailure": "block",
       "statusMessage": "Checking the git workflow rules"
     }
     ```

   - Rerun `scripts/hooks-selftest.sh`.
2. **Protect `main` in GitHub, after CI has run once on the pull request.** Settings → Rules → Rulesets → New branch ruleset. Target the default branch, enforcement Active, bypass list empty. Turn on: Restrict deletions; Block force pushes; Require a pull request before merging, with 0 required approvals (D44); Require status checks to pass, selecting the check named in Outcome.
3. **Boot on the cluster.** Clone the branch, follow README's build-host setup, and run:
   - `scripts/run.sh`: the `RUN` line shows `accel=kvm`, and the run exits 0.
   - `scripts/run.sh --no-build --accel tcg`: `accel=tcg`, exits 0.
   - `scripts/run.sh --no-build --test-fail`: exits 1.
   - `scripts/run.sh --no-build --mem 4`: exits 0 with 1 GB pages reserved.

   Add the results to Outcome, or tell Claude Code to.
4. **Review and merge the pull request.**

## Outcome

- **Status:** done. The work is on branch `claude/portable-build-hosts-ci`, in pull request [#1](https://github.com/ztblick/wipeOS/pull/1); "Done by Zach" below is still open. Step 3 was briefly blocked by a user-level Ruff plugin that reformatted whole Python files on every edit. Zach turned the plugin off, so the proposed D46 was dropped and `guard-build.py` was rewritten from its committed version.
- **Commits:** `dece286` (step 1), `9ceb372` (step 2), `7bedcca` (step 3), `ea2daaa` (step 4), `e0ff679` (step 5), and the records commit (step 6).
- **Changed:**
  - `scripts/fetch-checkpatch.sh` (new): fetches checkpatch for the pinned kernel into `.cache/checkpatch/<version>/` (D41).
  - `.gitignore`: adds `.cache/`.
  - `scripts/lint.sh`:
    - checkpatch now comes from `CHECKPATCH` or the cache only (D41).
    - The compiler is `gcc` on x86_64 and `x86_64-linux-gnu-gcc` elsewhere, with no fallback (D42).
    - It prints a `tools` section first.
  - `scripts/lint-selftest.sh` (harness only): exports `CHECKPATCH` from the fetch script, and drops the `buildroot` symlink in the throwaway repo.
  - `scripts/run.sh`: `--accel auto|kvm|tcg`; `-accel` is passed to QEMU, and the `RUN` header gains `accel=` (D39).
  - `.claude/hooks/guard-build.py`: D40's deny rule for non-x86_64 hosts, with `GUARD_BUILD_HOST_ARCH`. The docstring is renumbered and states the amendment to D35.
  - `.claude/hooks/guard-lint.py`: protects `scripts/fetch-checkpatch.sh` and `.github/workflows/`, and lets the fetch script be run.
  - `.claude/hooks/guard-git.py` (new): the D44 git and `gh` guard. It isn't registered yet; see "Done by Zach".
  - `scripts/hooks-selftest.sh`:
    - The harness defaults to `GUARD_BUILD_HOST_ARCH=x86_64` and `GUARD_GIT_BRANCH=claude/selftest`.
    - New cases: D40 on aarch64, the new lint paths, and Part 4 for the git guard.
  - `.github/workflows/ci.yml` (new): D43.
  - `CLAUDE.md`: "Development environment", the layout table, "Commands", "Verifying changes" and "Git" (D45).
  - `README.md`: "Running wipeOS" and setup split into build host and workstation, plus a section on how changes reach `main` (D45).
  - Records: see "Records written".
- **Verified:**
  - **Step 0.** Preflight checks passed: `scripts/lint.sh` exits 0 on `main`; `x86_64-linux-gnu-gcc` 15.2.0; `scripts/hooks-selftest.sh` is mode 100755; the plan is on `origin/main`; D38–D45 were free.
  - **Step 1, fetch script.** It fetches all three files for v6.18.7 from `git.kernel.org/.../stable/linux.git/plain/scripts/<file>?h=v6.18.7`, and `cmp` shows each is identical to `buildroot/output/build/linux-6.18.7/scripts/`. With the network blocked (a dead proxy), a re-run exits 0, and a fresh fetch exits 2 and leaves no partial files.
  - **Step 1, lint.**
    - In the main checkout and in a fresh `git worktree` with no `buildroot/`: `scripts/lint.sh` exits 0, and `scripts/lint-selftest.sh` passes 35, fails 0.
    - Tools: `x86_64-linux-gnu-gcc` 15.2.0-16ubuntu1 and cppcheck 2.19.0.
    - `LINT_CC=no-such-gcc scripts/lint.sh` exits 2.
  - **Step 2.**
    - `bash -n scripts/run.sh` passes, `--help` shows `--accel`, and `--accel bogus` and a bare `--accel` exit 3.
    - Not run: shellcheck (not installed).
    - Not verified: `--accel kvm` exiting 2 before the build. D35's KVM rule denies the words `--accel kvm` on any command on this host, so Claude can't run it here. It's covered by Zach's cluster boots below.
  - **Step 3.**
    - `scripts/hooks-selftest.sh`: 219 cases, 0 failed. `scripts/lint-selftest.sh`: 35 passed, 0 failed.
    - Run directly, without overrides: `guard-build.py` denies `make` on this aarch64 host (exit 2), and `guard-git.py` allows `git push origin HEAD` on this branch (exit 0).
  - **Step 4.** CI run [40373392912](https://github.com/ztblick/wipeOS/actions/runs/40373392912) on pull request #1 passed in 56 s, and its log shows every step ran:
    - The fetch printed the cache path.
    - The `tools` section shows `gcc (Ubuntu 15.2.0-16ubuntu1) 15.2.0` and `Cppcheck 2.19.0`, the same releases as the laptop. Lint ended `lint: clean`.
    - Lint self-test: 35 passed, 0 failed. Hooks self-test: 218 cases, 0 failed (the "run from `buildroot/`" index case is skipped where there's no Buildroot checkout). The index check passed.
  - **Step 5.**
    - `grep` finds WSL and aarch64 only in the laptop rows and rules of `CLAUDE.md` and `README.md`.
    - The README workstation commands work on the laptop: `core.hooksPath` is `.githooks`; the six packages are installed (checked with `dpkg -s`); fetch, lint and both self-tests pass; `gh` is logged in. Not re-run: the clone itself and `apt install`.
  - **Not run by Claude:** any build or boot. Per D40 they happen on the cluster ("Done by Zach").
  - **Cluster (Zach, Oct 26, on h100-sxm-8-0, Ubuntu 24.04, image built from `main` with the README's build-host steps; boots at `d4a374d`):**
    - No `sudo`, so the README's `apt install` couldn't run, and QEMU wasn't installed. Rootless podman failed (no `/etc/subuid` range). QEMU 8.2.2 from Ubuntu's own packages, unpacked into `~/opt` behind a wrapper, worked; the recipe is now in the README ("QEMU without root").
    - No KVM: the node is bare metal, but `vmx` is absent from `/proc/cpuinfo` (virtualization off in the firmware) and there is no `/dev/kvm`. `--accel auto` chose TCG, as D39 intends.
    - `run.sh --no-build`: `accel=tcg`, SUCCESS, exit 0, boot 1.9 s (`logs/run-20261026-215307.log`).
    - `run.sh --no-build --accel tcg`: SUCCESS, exit 0, 1.6 s.
    - `run.sh --no-build --test-fail`: `FAIL reason=test_fail`, exit 1.
    - `run.sh --no-build --mem 4`: SUCCESS, exit 0; 2 huge pages requested, 1 reserved, with the warning. This matches the deferred question "Huge-page count in QEMU above 3 GiB" (same result on Oct 20).
    - Not tested on the cluster: `run.sh`'s own build step (`make wipeos-stub-rebuild && make`), `accel=kvm`, and `--accel kvm` exiting 2 without KVM.
- **Image size:** not affected; nothing in the image changed.
- **Choices made within delegated scope:**
  - **Fetch:** `curl -fsSL --retry 3` from the stable tree's `plain/` endpoint. Files download into a temporary directory beside the cache and are renamed into place, so a set is never half there. It also checks that `checkpatch.pl` starts with `#!`, so an HTML error or bot-check page isn't accepted as the script.
  - **KVM test in `run.sh`:** a `kvm_usable` function (`uname -m` is x86_64, and `/dev/kvm` is readable and writable), run straight after argument validation, before the QEMU check and the build.
  - **`guard-build.py`:** matches the launcher by its basename, `run.sh`, a little broader than "a path ending in `scripts/run.sh`", so `./run.sh` from inside `scripts/` is caught too. It's the only `run.sh` in the repo.
  - **`guard-git.py`:**
    - It copies the other guards' command splitting, as they already copy each other's.
    - It reads the branch lazily with `git symbolic-ref` in `$CLAUDE_PROJECT_DIR` (D37).
    - It also denies `gh secret remove` and `gh variable remove`, aliases of `delete`.
    - It reads `-o` in a short-option cluster as taking the rest of the word, so `-oci.skip` isn't read as `-d`.
  - **`lint.sh`:** the `-fanalyzer` check now applies to any compiler, `LINT_CC` included, so a compiler without the analyzer always fails closed.
  - **Self-test cases:**
    - The D40 cases come after Part 2's existing cases, through a small `arm()` helper.
    - The lint path cases come after Part 1's.
    - The git guard is a new Part 4, with `gitg()` and `onmain()` helpers.
  - **Workflow:**
    - One job, id `checks`, named **`lint and self-tests`**: the check to require on `main`.
    - Step names as in the file, a 15-minute timeout, and apt packages `git gcc libc6-dev cppcheck perl python3 curl ca-certificates`.
    - It adds the workspace as a git safe directory, because the container runs as root over a checkout owned by the runner's user.
  - **`actions/checkout@v7`:** the newest major (v7.0.1, July 2026) per the GitHub releases API.
  - **Branch and commits:** branch `claude/portable-build-hosts-ci`, one commit per step.
- **Records written:**
  - **Decisions:** D38–D45, `accepted`, with `decided_in` this plan. D38 has `supersedes: [D12]`, and D12 is `superseded` with `superseded_by: D38`.
  - **Open question:** "Lint tool versions across machines" (D42: drift between the laptop, the CI container and build hosts).
  - **OKRs:** a progress note under KR1.3 in `docs/okrs.md`; no key result ticked.
  - **Docs:** README and CLAUDE.md, as above.
  - **Index:** `context/INDEX.md` regenerated.
- **Suggested `docs/design.md` changes** (Test environment, for D38 superseding D12):
  - Replace "**Test ladder (D12).**" with "**Test ladder (D38).**", and its first item with: "Local wiping: WipeOS launched directly on the node, with no host-OS handoff. This starts in QEMU on GitHub-hosted runners and the cluster."
  - In the tiered test plan, replace T0's "Where" cell with "x86_64 VM in QEMU, on a GitHub-hosted runner or a cluster CPU-only server, with KVM where available" and its "Needs from the cluster" cell with "Nothing for CI, or a CPU-only server".
  - In "Codebase design", after the sentence on `scripts/run.sh`, add: "CI (`.github/workflows/ci.yml`) runs lint, the self-tests and the index check on every pull request to `main` (D43), and changes reach `main` only through pull requests Zach merges (D44)."
- **Noticed, not touched:**
  - D35's KVM rule matches `--accel kvm` as words on any command, not only QEMU, so `scripts/run.sh --accel kvm` is denied on a host without `/dev/kvm`. That's harmless (D40 denies `run.sh` there anyway, and `run.sh` would exit 2), but it explains the untested step 2 case.
  - `context/questions/test-ladder.md` still says `resolved_by: [D12]`, which is now superseded; D38 restates the ladder.
  - `docs/design.md`'s header still points to `docs/decisions.md`, and so does KR2.3's progress note in `docs/okrs.md`. The decisions now live in `context/decisions/`.
  - `demo/fill/fill-demo.c` is tracked C outside `src/`, so lint (`C_DIRS=(src)`) and CI don't check it.
  - For plan 2: GitHub-hosted runners have `/dev/kvm`, but the runner user can't open it without a udev rule, so `--accel auto` will choose TCG there until the workflow grants access.
  - The `Write(/.github/workflows/**)` entry in the `ask` list is redundant: an `Edit(...)` rule covers every tool that edits files. It's harmless.
  - The cluster node used has no KVM (see "Verified"), but D38's rationale and CLAUDE.md's machine table say cluster boots run "with KVM". Boots work under TCG; the wording overstates what this node gives us. Whether another cluster node has KVM is unknown.
  - `run.sh` names its log by the second, so runs that start in the same second write the same log, and the last one wins. Seen on the cluster when four runs failed instantly.
  - `run.sh` doesn't pass `-nic none`, so every test VM gets QEMU's default e1000 network card (and needs its boot ROM).
- **Done by Zach:**
  - [x] Register `guard-git.py` in `.claude/settings.json` (the JSON in "Done by Zach" above), on this branch, then rerun `scripts/hooks-selftest.sh`. Commit `d6a001d`.
  - [x] Add the ruleset on `main`: require the check **`lint and self-tests`**, 0 approvals, block force pushes, restrict deletions, empty bypass list. CI has already run once on pull request #1, so the check can be selected.
  - [ ] Boot on the cluster: `scripts/run.sh` (`accel=kvm`, exit 0); `scripts/run.sh --no-build --accel tcg` (`accel=tcg`, exit 0); `scripts/run.sh --no-build --test-fail` (exit 1); `scripts/run.sh --no-build --mem 4` (exit 0, 1 GB pages reserved). The three `--no-build` boots pass under TCG (see "Verified"); `run.sh` with its build step, and `accel=kvm`, are still open, the second blocked on a node with KVM.
  - [ ] Review and merge pull request #1.
