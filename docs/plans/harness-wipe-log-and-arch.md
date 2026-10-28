# Plan: Harness design, part 2: the wipe log and the architecture boundary (KR1.3)

Implementation plan for the two parts of the harness design KR1.3 still lacks: how wipe logs are captured, and where architecture-specific code sits (D17). Written 2026-10-28 by the planner agent, as a proposal for Zach.

Read this whole file before starting, together with `CLAUDE.md` and the records it points to in `context/INDEX.md`. Then do step 0, the preflight, before changing anything.

## Goal

KR1.3 asks for a harness design covering three things. The first, launching a VM with configurable guest RAM and capturing the boot log, is done (`scripts/run.sh`, D30, D39). This plan settles the other two, so that the fill code (KR4.1 onward) has a place to log to and a place for its architecture-specific parts:

- **Wipe log.** The wipe reports through the stub's `WIPEOS key=value` lines (D29) on the serial console, as the report does today. `run.sh` also writes those lines, with its own `RUN` header, to a separate report file next to the boot log, so the wipe's output can be read without kernel messages.
- **Architecture boundary.** Architecture-specific code goes under `src/stub/arch/<arch>/`, behind one header, `src/stub/arch.h`. The first thing behind it is the fill's page-size ladder from D22 (1 GB, 2 MB, 4 KB on x86_64), which the stub reports and checks against the running kernel.

When this is done, KR1.3 is complete.

**Out of scope:**

- The fill, label generation and the verifier (KR4.1 to KR4.3).
- The residual ledger's line format and its first entries (D20; KR4.4 and the leftover from KR1.2). This plan only reserves the `ledger.` prefix.
- Which per-phase timings and throughputs are logged (the open question "Observability"); each wipe phase's plan picks its keys.
- Any aarch64 code (D17).
- Changes to the kernel config, the Buildroot defconfig, `.github/workflows/` or the lint scripts.

## Constraints from existing decisions

- **D17:** x86_64 only; architecture code behind an abstraction so an aarch64 port is cheap. This plan defines that abstraction for the stub, and writes no aarch64 code.
- **D22:** the fill uses 1 GB pages, then 2 MB, then 4 KB for edges and holes. That ladder is the first architecture-specific fact.
- **D25–D27:** the stub is process 1, a static C17 binary built by its own Makefile through the Buildroot package. The arch layer is part of the same binary.
- **D29:** report lines are `WIPEOS key=value`, one `write()` each, lowercase dotted keys, units in the key name, no spaces in values. New keys follow it.
- **D30:** `run.sh` decides the result from the boot log. That logic doesn't change; the report file is an extra output, never an input to the result.
- **D3, D20:** the stub grows by a few hundred bytes. Report `bzImage` size before and after from the **`build and boot`** check.
- **D40, D54:** the builder doesn't build or boot. CI's **`build and boot`** check builds and boots (D56: a change under `src/` or to `scripts/run.sh` means a build).
- **"Fail closed":** a value the new report lines need and can't read marks the report incomplete (`check.report` fails), as `report.c` does today.

## Decisions made for this plan

Proposed by the planner; merging this plan accepts them. In the last step, record each one in `context/decisions/` as `accepted`, with `decided_in` set to this file's path. Numbers are the next free ones as of writing; if preflight finds them taken, use the next free numbers and note it in Outcome.

### 1. D57: The wipe log is the report, on the console, also kept in a report file

- **Channel.** Proposed: every wipe phase logs through `report()` (D29) on the serial console, the same channel as today's report. There is no second log channel, in the VM or on real hardware.
- **Key prefixes.** Proposed: these prefixes are reserved for the wipe, so later plans don't collide with the report's: `phase.` (per-phase timings and status), `fill.` (the fill), `label.` (label generation), `verify.` (the challenge and its answers), `ledger.` (the residual ledger, D20). Each plan that adds keys under one of them defines its own keys there.
- **Report file.** Proposed: after every boot, `run.sh` writes `<log without .log>-report.log`, next to the boot log and the `-build.log`. It holds the boot log's `RUN` lines and its lines starting with `WIPEOS `, in order, with carriage returns removed, and nothing else. It is written in both modes and whatever the result, including when there is no RESULT line. CI's boot-log artifact picks it up without a workflow change, because CI passes `--log logs/ci/<case>.log` and uploads `logs/ci/*.log`.

*Alternatives considered:* a second serial port or a virtio console just for the report (clean separation, but a second QEMU device, a kernel driver to keep, and a second channel to fence on real hardware); writing the log to a file in the initramfs and printing it at the end (lost when the wipe crashes or hangs, which is exactly when it's needed); sending it over the network to the challenge server (no network stack yet, D19); no separate file, and `grep '^WIPEOS'` by hand (works, but every reader repeats it and forgets the `RUN` context).

### 2. D58: Architecture code lives under `src/stub/arch/<arch>/`, behind `arch.h`

- **Layout.** Proposed: `src/stub/arch.h` declares the interface. Each architecture implements it in `src/stub/arch/<arch>/arch.c`, starting with `src/stub/arch/x86_64/arch.c`.
- **Selection.** Proposed: the stub's Makefile selects the directory with `WIPEOS_ARCH ?= x86_64`, and fails with a clear message if `arch/$(WIPEOS_ARCH)/arch.c` doesn't exist. The Buildroot package doesn't pass it yet; the aarch64 port will map `BR2_ARCH` to it. `WIPEOS_ARCH`, not `ARCH`, because `ARCH` means something to the kernel's and Buildroot's makefiles.
- **The rule.** Proposed: no file outside `src/stub/arch/` tests the architecture (`__x86_64__`, `__aarch64__` and the like) or uses architecture-specific instructions, intrinsics or constants; it calls `arch.h` instead. Each `arch.c` starts with an `#error` guard if it is compiled for the wrong architecture.

*Alternatives considered:* `#ifdef __x86_64__` blocks inside the shared files (cheapest now, but an aarch64 port then touches every file and review can't see what's architecture-specific); asking the kernel for everything at run time, with no arch layer (sysfs does list huge-page sizes, but which sizes the fill prefers is policy, and the fast store paths the fill will want later are architecture code anyway); a separate library per architecture (more build machinery than one file needs).

### 3. D59: The first arch content: the page-size ladder, reported and checked

- **Interface.** Proposed: `arch.h` declares

  ```c
  struct arch_info {
  	const char *name;                   // "x86_64"
  	const unsigned long *page_sizes_kb; // the fill's ladder (D22), largest first
  	size_t n_page_sizes;                // the last entry is the base page
  };
  const struct arch_info *arch_info(void);
  ```

  On x86_64: name `x86_64`, ladder `1048576, 2048, 4`.
- **New report lines (D29).** Proposed, in this order:
  - `WIPEOS arch.name=x86_64` and `WIPEOS arch.page_sizes_kb=1048576,2048,4`, right after `cpu.count`.
  - `WIPEOS hugetlb.sizes_kb=<list>`, right after `hugetlb.pages_free`: the huge-page sizes the running kernel offers, from the `hugepages-<n>kB` entries in `/sys/kernel/mm/hugepages/`, largest first, comma-separated; `none` if the directory is empty. If the directory can't be read, a `read_fail` line and the report is incomplete.
- **New check.** Proposed: `check.arch`, after `check.report` and before `check.test_fail`. It passes when the ladder's last entry equals the kernel's base page size (`sysconf(_SC_PAGESIZE) / 1024`), and fails with `reason=arch` otherwise. It catches a stub built with the wrong arch layer. Whether each larger ladder size is in `hugetlb.sizes_kb` is reported but not checked: QEMU's default CPU model doesn't offer 1 GB pages, so the default 1 GiB boot would fail. The fill's plan decides what happens when a ladder size is missing.

*Alternatives considered:* only `arch.name`, with the ladder left for the fill's plan (the boundary would ship holding nothing real, and nothing would check it is wired up); checking every ladder size against the kernel (fails today's default boots, since QEMU's default CPU has no 1 GB pages); no new check (a mismatched arch layer would go unnoticed until the fill).

## Delegated to Claude Code

Choices Claude Code makes itself, without stopping. List every one in Outcome, one line each with the reason.

- internal function names and the layout of the code inside `report.c`, `main.c` and `arch/x86_64/arch.c`
- how `report.c` reads `/sys/kernel/mm/hugepages/` and sorts the sizes, and the limit on how many it accepts (fail closed beyond it, as `report_pci` does)
- how `run.sh` extracts the report file (`grep -a` and `tr -d '\r'`, or equivalent), and where in the script it runs, provided every exit path after the boot has written it
- the wording of comments and of README's new lines

## Stop conditions

Everything on CLAUDE.md's "Design decisions are mine" list is reserved, unless this plan settles it above or delegates it. Stop when any of these comes up:

- a reserved choice the plan doesn't settle;
- `/sys/kernel/mm/hugepages/` is missing in the booted image, so the report would fail on every boot (the fix is a kernel option, which is Zach's);
- any of the four CI boot cases gives a different exit code from before this change;
- `scripts/lint.sh` can't lint the new `arch/x86_64/arch.c` without a change to `scripts/lint.sh` or `.checkpatch.conf`;
- the Buildroot package needs a change to build the new subdirectory;
- a step can't pass its acceptance test without changing something outside this plan;
- the plan contradicts an accepted decision, or the code contradicts the plan.

**How to stop.**

1. Write the question as a `proposed` decision in `context/decisions/`, with your recommendation as the decision and two or three alternatives with their tradeoffs.
2. Set Outcome's status to `blocked`, naming the decision, and rerun `scripts/context_index.py`.
3. End your turn with a short message naming the decision, and wait.

Don't continue with work that depends on the answer, and don't guess.

## Component specs

**`src/stub/arch.h`** (new): the interface in Decision 3, with a header comment stating the rule in Decision 2 and pointing to D17 and D58.

**`src/stub/arch/x86_64/arch.c`** (new): `#if !defined(__x86_64__)` / `#error` guard; a static ladder `{ 1048576, 2048, 4 }` with a comment pointing to D22 and saying why these three (1 GB and 2 MB are x86_64's huge-page sizes, 4 KB its base page); `arch_info()` returns a pointer to a static `struct arch_info`.

**`src/stub/Makefile`:** `WIPEOS_ARCH ?= x86_64`; `arch/$(WIPEOS_ARCH)/arch.o` added to `OBJS`; an `$(error ...)` when the arch source is missing; the objects depend on `arch.h` as they do on `wipeos.h`; `clean` removes the arch object. The arch source includes `"../../arch.h"`, so no `-I` flag is needed and `scripts/lint.sh` compiles it as it is.

**`src/stub/wipeos.h`:** `struct facts` gains whatever `main.c` needs for `check.arch` (for example the kernel's base page size in kB, 0 if unread), set by `collect_report`.

**`src/stub/report.c`:** the three new report lines from Decision 3, at the places given there. A missing or unreadable value marks the report incomplete, as elsewhere in the file.

**`src/stub/main.c`:** `check.arch` from Decision 3; the `checks[]` array grows by one.

**`scripts/run.sh`:** the report file from Decision 1. Its path is printed as a `report:` line after `log:`. The usage text mentions it under `--log`. Exit codes and result logic are unchanged.

**`README.md`:** under "Logs", one sentence on the `-report.log` file; under "The report (D29)", the new `arch.*` and `hugetlb.sizes_kb` keys and `check.arch`; in "Where things live", `src/stub/` lists `arch.h` and `arch/<arch>/`.

**`CLAUDE.md`:** none. Its layout table already covers `src/stub/`.

## Steps

Work through the steps in order without stopping for review. You don't build or boot (D54); the **`build and boot`** check does.

0. **Preflight.** Check this plan against `context/INDEX.md`, D17, D20, D22, D25–D30, D54 and D56, and the current code in `src/stub/` and `scripts/run.sh`. Confirm D57–D59 are free. If anything conflicts or is missing, stop as above, before writing any code.
1. **Arch boundary and report lines.** Add `arch.h` and `arch/x86_64/arch.c`, update the Makefile, `wipeos.h`, `report.c` and `main.c` (Decisions 2 and 3).
   - *Acceptance:* `scripts/lint.sh` exits 0. `grep -rn '__x86_64__\|__aarch64__' src/` finds matches only under `src/stub/arch/`.
2. **Report file.** Update `scripts/run.sh` (Decision 1) and `README.md`. Push the branch and open the pull request.
   - *Acceptance:* `bash -n scripts/run.sh` passes; `scripts/run.sh --help` mentions the report file.
   - *Acceptance, from the **`build and boot`** check:* all four cases pass as before. In the downloaded `boot-logs` artifact:
     - every case has a `<case>-report.log` holding only `RUN` and `WIPEOS` lines, ending with the same `WIPEOS RESULT=` line as its boot log;
     - the `kvm` and `tcg` logs show `arch.name=x86_64`, `arch.page_sizes_kb=1048576,2048,4`, `hugetlb.sizes_kb=2048` and `check.arch=pass`;
     - the `mem4` log shows `hugetlb.sizes_kb=1048576,2048` (run.sh adds `-cpu max` from 3 GiB);
     - the `test-fail` log still ends `RESULT=FAIL reason=test_fail`.
   - Record the `bzImage` size from the check's summary, and the size on `main`'s last passing run, in Outcome.
3. **Record.**
   - Write D57, D58 and D59 to `context/decisions/` as `accepted`, with `decided_in` set to this file.
   - In `context/questions/observability.md`, add that D57 fixes the channel and the prefixes, and that which timings are logged is still open. Don't resolve it.
   - Tick KR1.3 in `docs/okrs.md` with a one-line note of the evidence (D57–D59, the CI run).
   - Rerun `scripts/context_index.py`.
   - Fill in Outcome, including a suggested `docs/design.md` change for "Codebase design".

## Acceptance tests

Commands Zach can run himself. Each one states its expected result.

1. `scripts/lint.sh` exits 0 on the laptop.
2. `gh run download <run-id> -n boot-logs -D /tmp/bl && cat /tmp/bl/kvm-report.log` shows the `RUN` lines, then only `WIPEOS` lines, including `WIPEOS arch.name=x86_64`, `WIPEOS check.arch=pass` and `WIPEOS RESULT=SUCCESS`.
3. On a build host: `scripts/run.sh --mem 4` exits 0, prints a `report:` line, and that file shows `hugetlb.sizes_kb=1048576,2048`.
4. `scripts/run.sh --test-fail` exits 1, and its report file ends with `WIPEOS RESULT=FAIL reason=test_fail`.

## Outcome

Written by Claude Code when it finishes or stops.

- **Status:** not started | blocked on Dnn | done
- **Changed:** <each file, one line>
- **Verified:** <the commands run and their results; anything not verified, said plainly>
- **Image size:** <bzImage before and after, or "not affected">
- **Choices made within delegated scope:** <one line each, with the reason>
- **Records written:** <decisions, questions, OKR ticks, README>
- **Suggested design.md changes:** <the exact text, for Zach to rewrite or drop>
- **Noticed, not touched:** <...>
- **Suggested commit message:** <one line>
