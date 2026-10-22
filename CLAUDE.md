# CLAUDE.md — WipeOS

## What this project is

WipeOS is a minimal Linux image that boots on each host in a pod during a memory-erasure event. It overwrites the agreed erasure target with challenge-dependent labels and answers a challenge server's queries, so that at most R bits of uncommitted state survive. It builds on Amodo's PoSE memory-wiping work and the Pod-PoComp protocol.

Current stage: prototype. The x86_64 image boots in QEMU to our own process 1, which reports the memory layout and checks (`scripts/run.sh`). Next is the first erasure code: fill a few pages of DRAM with labels, then check them with a verifier stub that holds precomputed secret challenges (D32).

## Project docs: read them first, every session

The repo is the source of truth for the design. These files are imported here so they load with this file:

@README.md
@docs/design.md
@docs/decisions.md
@docs/okrs.md

Before starting any task, make sure you have read them. In your first reply of the session, name the decisions, open questions and key results that bear on the task. If a task touches a design question the docs don't settle, stop and ask.

Research notes in `docs/research/` are not imported. Read them when a task touches their topic (Amodo's PoSE-DB label generator is in `docs/research/amodo-study.md`; label verification, precomputed challenges and the verifier are in `docs/research/label-verification.md`).

Implementation plans live in `docs/plans/`. When a task belongs to a plan, read the whole plan first and follow its steps.

**What you may change in each doc:**

| File | You may | You may not |
| --- | --- | --- |
| `docs/okrs.md` | Tick a key result you completed, with a one-line note of the evidence; add progress notes under a key result | Add, remove or reword objectives or key results |
| `docs/decisions.md` | Add decisions with status Proposed, and add open questions you run into; change a status only when I've said so in this session ("accept D23"), and move the answered question to Resolved | Edit or delete an existing decision's text, or accept a decision on your own |
| `docs/design.md` | Propose an edit, showing me the exact change | Edit it before I approve the change |
| `README.md` | Update the commands and paths when they change, in the same step as the change | — |
| `docs/research/` | Add notes when I ask | — |

If the code contradicts the docs, or a doc looks out of date, tell me. Don't silently follow one over the other.

## Development environment

- **Host:** Windows laptop on ARM silicon. You are running inside WSL2 (Ubuntu), so the host is **aarch64**. WSL has 8 cores and 8 GB RAM.
- **Target:** **x86_64** (D17). Buildroot cross-compiles everything with its own toolchain; nothing built for the target runs natively on this host.
- **QEMU:** the image boots with `qemu-system-x86_64` under full software emulation (TCG). There is no KVM for x86 guests on this host, so never add `-enable-kvm`, `-accel kvm` or `-cpu host`. Boots are slow; keep guest RAM at 1 GiB unless a task needs more.
- **Windows interop is off** (`appendWindowsPath = false` in `/etc/wsl.conf`). Don't call Windows executables (`*.exe`, `powershell`, `cmd.exe`) and never work under `/mnt/c`: Buildroot breaks on paths with spaces and on the Windows filesystem.
- **Builds are expensive here.** Never run `make clean`, `make distclean`, delete `output/`, or trigger a toolchain rebuild without asking first. Use the narrowest rebuild target that works (`make linux-rebuild`, `make <pkg>-rebuild`).
- Don't install system packages (apt, pip, global npm) without asking. Tell me what's missing and why.

## Project layout

The project folder is `~/wipeOS`, with capital "OS". Use that exact spelling in every path and command.

| Path | What it is |
| --- | --- |
| `~/wipeOS/README.md` | What WipeOS is, map of the docs, build and run commands |
| `~/wipeOS/docs/design.md` | Architecture and design (edit only with my approval) |
| `~/wipeOS/docs/decisions.md` | Decision log and open questions |
| `~/wipeOS/docs/okrs.md` | This week's OKRs and past weeks |
| `~/wipeOS/docs/research/` | Research notes behind specific decisions |
| `~/wipeOS/.claude/settings.json` | Claude Code permissions for this project. Don't edit it. |
| `~/wipeOS/buildroot` | Upstream Buildroot checkout. Run every `make` from here. Don't edit files in it unless I ask. |
| `~/wipeOS/configs/linux.config` | Our pruned kernel config |
| `~/wipeOS/configs/wipeOS_x86_64_defconfig` | Our Buildroot settings |
| `~/wipeOS/scripts/run.sh` | The launcher: builds, boots in QEMU, logs to `logs/`, exits by the result (D30) |
| `~/wipeOS/src/stub/` | The stub, process 1 (D25): C source and Makefile |
| `~/wipeOS/package/wipeos-stub/` | Buildroot package for the stub (D26) |
| `~/wipeOS/external.desc`, `Config.in`, `external.mk` | Make the repo a Buildroot external tree (D31) |
| `~/wipeOS/logs/` | Boot and build logs from `run.sh` (gitignored) |
| `~/wipeOS/docs/plans/` | Implementation plans |
| `~/wipeOS/buildroot/output/images/bzImage` | Built image: kernel with initramfs linked in |

## Commands

Build, boot and rebuild commands are in `README.md`, imported above. Run every `make` from `~/wipeOS/buildroot`. If a command or path changes, update `README.md` in the same step and tell me.

- To boot the image yourself, use `scripts/run.sh` (add `--no-build` when the image is current). It applies a timeout and writes the log to `logs/`; tell me the log path and the exit code. For a boot `run.sh` can't express, call QEMU under `timeout`, capture serial output to a file under `/tmp`, and tell me the path.
- `make menuconfig` and `make linux-menuconfig` are interactive and you can't drive them. When a kernel or Buildroot option needs to change, list the exact symbols and values and I'll make the change.

## How I want you to work

**Keep the lens narrow.**
- Work only on the task I gave you. Don't fix, refactor, rename, reformat or "improve" anything outside it. If you notice something else worth changing, list it at the end instead of doing it.
- For anything beyond a trivial edit, propose a plan first: which files you'll touch, what changes, and how you'll verify. Wait for my OK.
- Work in small, reviewable steps. If a step would touch more than a few files or roughly 150 lines, split it and check in between.
- Read existing code and config before proposing changes. Don't guess at file contents.

**Design decisions are mine.** Stop and ask before any of these:
- new files, modules or directories, or changes to the project layout
- interfaces, data formats and protocols (for example the challenge database entry format or the residual ledger schema)
- new dependencies, Buildroot packages, kernel options or drivers, or anything else that grows the image
- the choice of algorithm, language, library or build approach
- anything that contradicts or extends a decision in the log
- error-handling policy, especially anything that would let a wipe continue after a failure

If you're unsure whether something is a design choice, assume it is. When one comes up, stop and add it to `docs/decisions.md` as a Proposed decision, using the template in that file: your recommendation as the decision, the other 2–3 options with their tradeoffs as the alternatives. Then tell me and wait for my answer before building on it.

## Rules that come from the design

These are the decisions from `docs/decisions.md` that matter most for code. If this summary and that file disagree, the file wins; point out the mismatch.

- **Footprint is a security quantity.** Every byte WipeOS keeps resident counts toward R unless it's committed in advance (D3, D20). Don't add code, packages or kernel options casually. When a change affects the image, report `bzImage` size before and after.
- **No hardware attestation** (D1). Don't design anything that depends on TPM or attestation reports.
- **x86_64 only for now** (D17). Keep architecture-specific code behind its own boundary so an aarch64 port is cheap later, but don't write aarch64 code.
- **Replaceable seams.** Label generation (a placeholder keyed hash now, Amodo's PoSE construction later; D5) and label verification (precomputed secret challenges; D32) each sit behind their own interface. Don't couple other code to the placeholder implementations.
- **Challenge secrets stay on the verifier side** (D32). χ is secret until SEED and the sample positions until QUERY; expected answers are stored only as hashes. The fill code never sees the positions before QUERY.
- **Fail closed, never skip silently.** Any region the wipe code doesn't fill is recorded in the residual ledger with location, size, reason and category (D20). A region that fails or is skipped is reported as an error, never worked around quietly.
- **Large pages for the fill** (D22). Memory is filled using 1 GB pages reserved at boot, falling back to 2 MB and then 4 KB pages only for unaligned edges and regions around holes.
- **Config lives in our repo** (D21). The kernel config and Buildroot defconfig live in `~/wipeOS/configs`, not in Buildroot's board files.

## Code that gets extra scrutiny

This covers wipe and fill paths, memory discovery, label generation, the challenge database and the verifier, and the residual ledger.

- Keep diffs especially small, and comment the *why* on anything non-obvious.
- Correctness before speed: no clever optimizations without asking.
- Never weaken, skip or edit a test to make it pass. If a test looks wrong, tell me.

## Verifying changes

- After a change, build with the narrowest target and, if relevant, boot in QEMU. Report the commands you ran and what happened.
- "It compiles" is not "it works." If you couldn't verify something, say so plainly.

## Git

Don't commit, push or rewrite history unless I ask. When a step is done, suggest a one-line commit message.

## When you finish a task, report

1. What changed (each file, one line)
2. Why
3. How you verified it (commands and results)
4. Image size delta, if the image is affected
5. Doc changes you made (OKR ticks, Proposed decisions, open questions, README) and design.md edits you're proposing
6. Decisions you need from me, and anything you noticed but didn't touch

## Help me understand

I want to understand everything that goes into this project. When you use a kernel, Buildroot or QEMU mechanism I may not know, explain it in a sentence or two. When I ask "why," give the reasoning and the alternatives you rejected.
