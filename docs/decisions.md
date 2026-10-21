# WipeOS: Decision log and open questions

Every design decision, with its reasoning and the alternatives considered, plus the queue of undecided questions. The architecture these decisions produce is described in `docs/design.md`.

D1 follows from the threat model, and D2, D5 and D6 to D22 were settled in design discussion; all of these are Accepted. D3 and D4 are proposals from our first read of the Pod-PoComp paper and are open for discussion.

## How this log works

- Each decision is a section with an ID, a short title, a status, the decision, the rationale and the alternatives considered. New decisions take the next free number, are appended at the end of the log, and record the date they were added.
- A decision starts as **Proposed** and moves to **Accepted** once I agree to it. A reversed decision is marked **Superseded by Dn** and keeps its original text. Decisions are never deleted and their reasoning is never rewritten.
- Anything unresolved goes in Open questions. When a question is answered, it becomes a decision, and the question moves to Resolved with a pointer to that decision.
- **Claude Code** may add decisions with status Proposed and add open questions it runs into. It changes a decision's status only when I have said so in that session ("accept D23"), and it never edits or removes an existing decision's text.

Template for a new decision:

```markdown
### D23: Short title

**Status:** Proposed

**Date:** YYYY-MM-DD

**Decision.** ...

**Rationale.** ...

**Alternatives considered.** ...
```

## Decisions

### D1: No reliance on hardware attestation

**Status:** Accepted

**Decision.** Do not rely on hardware attestation. Mutable firmware, recovery and configuration state is either overwritten and checked, or charged to R.

**Rationale.** Attestation is untrusted, or unavailable, under the threat model.

**Alternatives considered.** The paper's option of attesting such state as fixed and including it in I0.

### D2: Enter WipeOS through a kexec handoff

**Status:** Accepted

**Decision.** Enter WipeOS from the production OS through a kexec-style handoff.

**Rationale.** WipeOS can then overwrite the memory the production OS occupied, without firmware running in between (paper, Appendix C.2).

**Alternatives considered.** A full firmware reboot into WipeOS: slower, and firmware touches memory. Wiping in place from the production OS: cannot overwrite its own footprint.

### D3: Minimal, itemized resident footprint

**Status:** Accepted

**Decision.** Keep WipeOS's resident footprint minimal and itemize every resident byte in the residual ledger.

**Rationale.** The kernel, drivers and recovery state are charged to R unless fixed by I0. A smaller WipeOS means a smaller R.

**Alternatives considered.** A stock distribution kernel and initramfs: much larger and harder to account for.

### D4: Erasure target from an auditor manifest, cross-checked by discovery

**Status:** Accepted

**Decision.** Build the erasure target from an auditor-held pod manifest, cross-checked against live discovery inside WipeOS. Any mismatch aborts the event.

**Rationale.** The paper derives W from an audited inventory, and the host's self-report is untrusted.

**Alternatives considered.** Discovery only. This is fine for test configurations and becomes the dev mode.

### D5: Fill with Amodo's PoSE labels

**Status:** Accepted

**Decision.** Generate the fill with Amodo's PoSE label construction.

**Rationale.** It reuses existing open-source code, and memory-hard labels block answering by recomputation.

**Alternatives considered.** Stream the full fill from the challenge server: simpler, but limited by link bandwidth.

### D6: Any hardware class can be skipped through configuration

**Status:** Accepted

**Decision.** Any hardware class can be skipped through configuration. Memory-only mode skips local NVMe. In production, every skip requires authentication and an explicit confirmation that names what will not be erased ("Are you sure you don't want to erase NVMe?").

**Rationale.** Lets us test and profile each wiper on its own, and run without the disk wipe if disks leave the pod. A skipped device is not erased, so the certificate must list it, and its capacity is charged to R unless the auditor manifest excludes it from the pod.

**Alternatives considered.** Always wipe everything: simpler, but blocks per-component testing and forces disk wipes even if storage is removed.

### D7: Keep a full NVMe wipe path

**Status:** Accepted

**Decision.** Keep a full NVMe wipe path in WipeOS, even while we look for a way to avoid wiping disks.

**Rationale.** If no way to avoid disk wipes is found, the capability is already built. Disk wipe time will be reduced later through testing and optimization.

**Alternatives considered.** Build the disk path only once disks are confirmed to stay in the pod.

### D8: Pod-wide barrier protocol

**Status:** Accepted

**Decision.** Run each erasure event as a pod-wide barrier protocol driven by the challenge server: READY, SEED, FILLED, QUERY, RESPONSE, VERDICT, RELEASE. All 18 nodes fill at once, the seed χ is the start signal, and all nodes are queried simultaneously.

**Rationale.** With every memory in the pod filling at once, state moved between nodes has nowhere unfilled to land. Using χ as the start signal makes the first barrier cryptographic, because no meaningful fill can start before it. Simultaneous queries stop a node that has already answered from lending its memory to one still being queried.

**Alternatives considered.** Stagger the node wipes and rely on gateway policy alone to block node-to-node restore traffic, the paper's other option.

### D9: A node that misses a barrier fails the event

**Status:** Accepted

**Decision.** A node that does not reach READY or FILLED before its timeout is treated as adversarial. The pod fails the erasure event, and the case is escalated to a human verifier.

**Rationale.** A missing node cannot be told apart from one hiding state, so failing is the safe default. A human verifier handles the exceptions, including honest hardware faults.

**Alternatives considered.** Retry the node or exclude it automatically.

### D10: Benchmark on Lucid's DGX H100 node

**Status:** Accepted

**Decision.** Benchmark on Lucid's DGX H100 node (h100-sxm-8-0), wiping a subset of its GPUs rather than everything.

**Rationale.** It is available now, the cluster has a network tap, and one node exercises the DRAM, HBM and NVMe wipers. Per-device throughput can be measured without wiping the full node.

**Alternatives considered.** Wait for Vera Rubin NVL72 hardware.

### D11: Three-stage benchmark scale-up

**Status:** Accepted

**Decision.** Scale benchmarks up in three stages: (1) individual components, meaning chunks of DRAM, GPU memory and NVMe; (2) whole GPUs plus chunks of DRAM and disk at the same time; (3) a full-node wipe, if the cluster managers approve. Start with one reserved GPU, ask for a dedicated NVMe allocation so other users' data is never touched, and reserve overnight time for full DRAM and GPU wipes.

**Rationale.** The cluster serves other users, so testing has to cause minimal disruption. Each stage is tested before the next.

**Alternatives considered.** A full-node wipe from the start.

### D12: Three-rung test ladder

**Status:** Accepted

**Decision.** Test ladder: (1) local wiping, launching WipeOS directly on the node with no host-OS handoff, starting in Linux emulation on a laptop; (2) the tap and the DGX node together emulating the auditor and host; (3) the DGX node split into two nodes for multi-node barrier tests.

**Rationale.** Each rung adds one new piece: the wipers, then the auditor side, then cross-node coordination.

**Alternatives considered.** Build the full kexec and multi-node flow first.

### D13: Challenge server on a CPU-only cluster server

**Status:** Accepted

**Decision.** Run the challenge server on one of the cluster's CPU-only servers, where the network tap is currently emulated.

**Rationale.** It is available, and like the real auditor side it has far less compute than the nodes it challenges.

**Alternatives considered.** Run it on the DGX node itself.

### D14: Our contribution versus Amodo's

**Status:** Accepted

**Decision.** Our contribution is the WipeOS image, the wiping process and the challenge server. From Amodo we clone only their open-source GPU disk-label generation code.

**Rationale.** The label-generation code is all Amodo makes public; the rest has to be built.

**Alternatives considered.** A gap analysis of Amodo's full system first: not possible, since it is not public.

### D15: Success is a working end-to-end prototype

**Status:** Accepted

**Decision.** Success for now is a prototype that works end to end. Coverage fraction and R-ledger size are not targets yet, but WipeOS logs everything a full Pod-PoComp certificate would have to report.

**Rationale.** A working prototype comes first; logging the certificate fields from day one means optimization later has a baseline.

**Alternatives considered.** Set coverage and residual targets now.

### D16: Labels are generated on the node

**Status:** Accepted

**Decision.** Labels are generated on the node's hardware. The challenge server issues challenges and checks responses but should not have to recompute labels. D18 chooses how.

**Rationale.** The challenge server will always be far less computationally capable than the pod it challenges.

**Alternatives considered.** The challenge server recomputes each sampled label: simple, but its cost grows with the sample count.

### D17: x86_64 first, architecture code behind an abstraction

**Status:** Accepted

**Decision.** Build x86_64 first. Keep architecture-specific code behind an abstraction layer so an Arm (aarch64) port is easy later, but do not implement the Arm side yet.

**Rationale.** The DGX test node is x86_64, while the Vera target is Arm. Isolating architecture-specific code now keeps the eventual port cheap without slowing the prototype.

**Alternatives considered.** Build both from the start: slower. x86_64 only, with no abstraction: makes the port expensive.

### D18: Verify labels with streamed fingerprints (candidate C)

**Status:** Accepted

**Decision.** Verify labels with candidate C. During the fill, the node streams a fingerprint of every label; the challenge server secretly keeps a sample, in neighborhoods, and checks queried labels against it. The scheme sits behind its own interface so a better one can replace it later.

**Rationale.** B's bandwidth is prohibitive and A needs too much extra memory. C keeps server work to one or two hashes per query, with about 290 GB of ingest per Vera Rubin NVL72. Confidence is about 85%, which is enough to proceed because this is one replaceable part of the system.

**Alternatives considered.** A, Merkle commitment. B, streamed full labels. Streaming one in N labels (rejected: the node could store only those).

### D19: Image delivery and kexec trigger

**Status:** Accepted

**Decision.** The challenge server stores the WipeOS image and starts each erasure event with a trigger message to a small agent on the production OS. The agent downloads the image over the erasure channel, checks its hash against I0, stages it with kexec -l, and jumps into it with kexec -e.

**Rationale.** The auditor controls which build every node gets, and the image is ingress already committed in I0. The hash check protects the developer from a wrong or tampered image. Staging with kexec -l takes the download off the critical path. A kexec deadline adds no security, because the fill and the timed challenge cover any stashed state, so liveness is handled by the D9 READY timeout, measured in seconds.

**Alternatives considered.** A hardware interrupt from the challenge server: not possible over the network. A millisecond kexec deadline: adds no security and is too short to quiesce. WipeOS kept on the node: mutable, so it would have to be wiped or charged to R.

### D20: Residual ledger

**Status:** Accepted

**Decision.** WipeOS keeps a residual ledger: one entry for every region it does not erase, with location, size, reason and category. Two categories to start: committed binaries that could be attested and included in I0 (such as the WipeOS kernel and initramfs), and unaccounted unerased memory, which is tallied into R. The schema is open-ended, so new categories and fields can be added without changing the wipers.

**Rationale.** Committing binaries in I0 would need attestation, which is not solved yet, and the Pod-PoComp accounting is not a crucial part of the prototype. Logging what is left and why now means the accounting can be tightened later without redesign.

**Alternatives considered.** Charge everything unerased to R with no categories: simpler, but loses the distinction needed later. Solve attestation first: blocks the prototype.

### D21: Build with Buildroot and glibc

**Status:** Accepted

**Decision.** Build WipeOS with Buildroot, using a glibc toolchain and a pared-down kernel config, with the initramfs linked into the kernel image. The kernel config is kept in our own repository, not in Buildroot's board files.

**Rationale.** One tool builds the kernel, the initramfs and the toolchain; it has ready-made QEMU configs for x86_64 and aarch64 (D17) and a reproducible-build option. glibc is required by NVIDIA's userspace. First boot in QEMU: about 15 MB of kernel code and data, about 53 MB of a 1 GiB VM not free.

**Alternatives considered.** A mainline kernel from tinyconfig with a hand-built initramfs: smallest, but the most manual. A LinuxBoot-style kernel with a u-root initramfs: built-in kexec and netboot, but Go userspace and less turnkey.

### D22: Fill with 1 GB huge pages

**Status:** Accepted

**Decision.** After kexec, fill memory using the largest pages possible: 1 GB pages, reserved at boot on the kernel command line, with the HugeTLB vmemmap optimization on. Unaligned edges and the regions around memory holes fall back to 2 MB and then 4 KB pages.

**Rationale.** The wipe agent is the only userspace process, so small pages' fairness and overcommit controls buy nothing. 1 GB pages nearly eliminate per-page bookkeeping and page-table overhead, and the fill also runs faster with fewer TLB misses. Reserving at boot avoids fragmentation, because WipeOS controls its own command line.

**Alternatives considered.** Default 4 KB pages: about 1.6% of RAM in bookkeeping. 2 MB pages only: about 0.2%. WipeOS managing physical memory outside the page allocator: tabled as a fallback in case huge pages leave too much overhead.

### D23: System QEMU is the canonical test VM

**Status:** Accepted

**Date:** 2026-10-20

**Decision.** Boot test images with the distribution's `qemu-system-x86_64`, not a Buildroot-built QEMU. Remove `BR2_PACKAGE_HOST_QEMU` and `BR2_PACKAGE_HOST_E2FSPROGS` from the defconfig. The launch script records the QEMU version in every boot log.

**Rationale.** QEMU is test tooling and never part of the image, so pinning it adds build time without affecting the footprint or R. Logging the version covers the risk of behavior differing between machines.

**Alternatives considered.** Buildroot's QEMU: identical version everywhere, but a long extra compile on every fresh build. Keeping both: two copies that can silently disagree.

### D24: No address randomization, kernel or userspace

**Status:** Accepted

**Date:** 2026-10-20

**Decision.** KASLR is off (`CONFIG_RANDOMIZE_BASE`, which also turns off `RANDOMIZE_MEMORY`). Userspace randomization is off via a built-in kernel command line, `CONFIG_CMDLINE="norandmaps"`, which adds to boot-loader arguments rather than overriding them. The kernel always loads at `PHYSICAL_START` (16 MB). `PHYSICAL_ALIGN` stays at its 2 MB minimum.

**Rationale.**

- Determinism is the top priority: identical memory layout on every boot makes footprint, fill coverage and timings reproducible.
- Randomization defends against exploits by untrusted code. WipeOS runs none, and the host is already untrusted.
- Building both into the image means it doesn't depend on whoever builds the command line (QEMU's `-append`, or the D19 agent's `kexec --append`).
- `norandmaps` rather than having the stub write `/proc/sys/kernel/randomize_va_space`: the stub is process 1, so its own layout would already be randomized by then.
- With KASLR off, the kernel sits inside the first gigabyte, which can't be a 1 GB huge page anyway (D22).

**Alternatives considered.** The `nokaslr` boot option: depends on the command line. The stub writing `randomize_va_space`: misses process 1. Keeping randomization: layout changes on every boot, with little security value here.

### D25: The stub is process 1

**Status:** Accepted

**Date:** 2026-10-20

**Decision.** Our stub, `/sbin/wipeos-init`, runs as process 1 and is the only userspace process. It is named by `rdinit=/sbin/wipeos-init` in the built-in kernel command line, alongside `norandmaps` (D24), so the full built-in string is `norandmaps rdinit=/sbin/wipeos-init`. Buildroot's init system is None and `/dev` management is devtmpfs. BusyBox stays in the image only to provide `/bin/sh` for dev mode (D28); nothing in the boot path uses it. The QEMU post-build script (`board/qemu/x86_64/post-build.sh`) is removed. A boot-time `rdinit=` still overrides the built-in one, so `rdinit=/bin/sh` remains a rescue shell.

**Rationale.** With no BusyBox init, scripts, gettys or daemons, nothing else is resident or running beside the stub (D3, D20). Naming the stub in the built-in command line keeps the image independent of whoever builds the command line, as in D24. The post-build script only added a tty1 login prompt to an `inittab` that no longer exists.

**Alternatives considered.** The stub as `/init`: collides with the small `/init` script Buildroot installs in initramfs images. The stub as `/sbin/init` behind Buildroot's `/init` script: puts a shell script that needs BusyBox in front of process 1.

### D26: The stub is built as a Buildroot package

**Status:** Accepted

**Date:** 2026-10-20

**Decision.** The repo is a Buildroot external tree (D31), and `package/wipeos-stub/` builds `src/stub/` with Buildroot's toolchain and installs the binary.

**Rationale.** One `make` produces the whole image, the build is reproducible from the repo, and Buildroot stays an untouched upstream checkout.

**Alternatives considered.** Compiling separately and copying the binary in: risks a stale binary, and the image is no longer reproducible from the repo alone.

### D27: The stub is C17, statically linked against glibc

**Status:** Accepted

**Date:** 2026-10-20

**Decision.** Compile with Buildroot's toolchain using `-std=c17 -O2 -Wall -Wextra -Werror`, link with `-static`, and add `-ffile-prefix-map=<src>=.` so the binary contains no host paths. The stub uses no DNS; when networking arrives, endpoints are IP addresses taken from the command line.

**Rationale.** The stub needs no shared libraries at run time. Static glibc can't do host-name lookups properly, hence no DNS. The prefix map keeps builds reproducible. A static binary can't load CUDA's shared libraries, so the future GPU wiper will either make the agent dynamically linked or run as a separate, dynamically linked worker started by process 1. The current lean is the worker; that choice is not needed now (see Deferred: "Static wipe agent versus the CUDA path").

**Alternatives considered.** C++: no benefit for the stub. Rust: adds a long toolchain build and a second language next to CUDA. Go: its runtime and garbage collector undermine determinism.

### D28: Mode flag on the kernel command line

**Status:** Accepted

**Date:** 2026-10-20

**Decision.** `wipeos.mode=dev|prod` on the kernel command line. If the flag appears more than once, the last occurrence wins. If it is absent, the stub runs in prod mode; an unknown value is a FAIL. Both modes collect the same report and produce the same result, and run the same checks except `check.shell`, which runs in dev mode only because it tests dev mode's own ending. They differ only in how the run ends: prod powers off; dev starts `/bin/sh` on the console as a child process, waits for it, and powers off when it exits. If `/bin/sh` is missing in dev mode, the stub reports `FAIL reason=no_shell` and powers off.

**Rationale.** The mode is operational, not a security control: a shell on a node can't fake the timed challenge. Defaulting to prod means a forgotten flag never leaves a production node at a shell.

**Alternatives considered.** Default to dev: a forgotten flag in production would leave a node at a shell. Require the flag: burdens every manual and test boot.

### D29: Stub report format

**Status:** Accepted

**Date:** 2026-10-20

**Decision.** The stub writes only lines of the form `WIPEOS key=value` to the console, each with a single `write()`. The first line is `WIPEOS BEGIN format=1 version=<git commit>`; the last is `WIPEOS RESULT=SUCCESS` or `WIPEOS RESULT=FAIL reason=<token>`, and a missing RESULT line means the stub crashed or hung. Keys are lowercase, grouped by dotted prefix (`mem.`, `iomem.`, `hugetlb.`, `pci.`, `check.`), with units in the key name (`_kb`, `_bytes`, `_pages`, `_ms`). Addresses are hex with `0x`; values contain no spaces, or are wrapped in double quotes.

**Rationale.** One `write()` per line means a kernel message can't land inside a line, and line-based output stays parseable if it is cut off. This is the seed of the WipeOS log format (D15, D20); it is easy to change and the stakes are low, so it is kept simple.

**Alternatives considered.** Free text: fragile to parse. A final JSON object: invalid if output is cut off. Text plus key=value lines: two formats that can drift.

### D30: Boot result reported through the boot log

**Status:** Accepted

**Date:** 2026-10-20

**Decision.** `scripts/run.sh` determines the outcome from the boot log and exits 0 for `WIPEOS RESULT=SUCCESS`, 1 for `WIPEOS RESULT=FAIL`, 2 when there is no RESULT line (crash, hang, timeout or kernel panic), and 3 for bad arguments to `run.sh`. The stub powers off after reporting, which ends QEMU under `-no-reboot`. A run only passes if the stub reports SUCCESS and the VM then shuts down cleanly; anything else is exit 2, except a FAIL followed by a clean shutdown, which stays exit 1. No QEMU debug-exit device is used.

**Rationale.** Process 1 contains no port I/O and no architecture-specific code (D17), and nothing in it has to be kept off real hardware.

**Alternatives considered.** QEMU's isa-debug-exit device: an independent exit code, but x86-specific port I/O in process 1, a guard flag to keep it off real hardware, and awkward exit-code mapping.

### D31: The repo is a Buildroot external tree

**Status:** Accepted

**Date:** 2026-10-20

**Decision.** The repo root is a Buildroot external tree named `WIPEOS`: `external.desc`, `Config.in` and `external.mk` at the top, the package in `package/wipeos-stub/`, the stub source in `src/stub/`, the launcher in `scripts/run.sh`, boot logs in `logs/` (gitignored), alongside the existing `configs/`, `docs/` and gitignored `buildroot/`. Paths inside config files use `$(BR2_EXTERNAL_WIPEOS_PATH)`, never `../` or a home-folder path. Commands pass the external tree relatively from `~/wipeOS/buildroot`: `make BR2_EXTERNAL=.. wipeOS_x86_64_defconfig`. There is no rootfs overlay, since the package installs the stub, and no `arch/` folder until something needs one.

**Rationale.** Buildroot remembers the external tree for later builds in that checkout and finds the defconfig by name in the external tree's `configs/`, so `configs/` stays where D21 put it. Config paths no longer depend on where Buildroot is checked out.

**Alternatives considered.** A separate `br2-external/` folder: tidier top level, but no defconfig discovery unless `configs/` moves inside it.

## Open questions

Undecided items are grouped by when they block us. The first group has to be settled for the team proposal; the second can be worked out as we build.

**Needed for the team proposal.**

Nothing outstanding. Label verification is resolved by D18.

**Design questions.**

- [ ] **NVMe cache.** WipeOS supports NVMe wipes either way (D6, D7). The open question is whether production pods keep local NVMe, shrink it, or exclude it as the paper suggests. Drive endurance also matters: each full fill is one drive write, so daily wipes alone would use roughly the whole 5-year rating of a ~1 DWPD drive (approximate; check the actual drive). Over-provisioned NAND has to be counted in R either way.
- [ ] **Boot drive.** Each tray's E1.S boot drive is mutable. Is it wiped and reimaged at every event, or charged to R?
- [ ] **Reload path and downtime.** If the boot drive is wiped, nodes netboot through the tap and reload model weights through it. How long does that take, and does it count toward the erasure window?
- [ ] **WipeOS allowance.** The auditor cannot verify that a node runs genuine WipeOS, so its footprint cannot be self-declared. What fixed allowance is agreed in advance, and is the image built reproducibly so its hash can be committed in I0? The kernel also keeps about 64 bytes of bookkeeping per 4 KB page, about 1.6% of RAM: roughly 16 MB in a 1 GiB VM, but around 32 GB on a 2 TiB host. Can WipeOS boot with the kernel managing only a small slice of RAM, so the wipe agent writes the rest directly and it needs no bookkeeping? Two options to explore: (1) wipeOS manages most physical memory itself, outside the kernel's page allocator, so that memory carries no per-page bookkeeping; (2) default to huge pages, which give a better bookkeeping-to-memory ratio. Huge pages only shrink the per-page bookkeeping if the kernel's HugeTLB vmemmap optimization is turned on; it frees about 7/8 of it for 2 MB pages and nearly all of it for 1 GB pages. Huge pages also cut the page-table overhead of the wipers' own mappings. Option 2 is adopted as D22; option 1 is tabled as a fallback (see Deferred).
- [ ] **All writable stores.** How do we account for every writable memory store in the pod: firmware, DPU and NIC memory, SRAM, device queues, and the BMC?
- [ ] **Remaining external links.** With the east-west links unplugged, which link carries challenge traffic and the WipeOS image download (D19)? Most likely the BlueField-4's management Ethernet, which would mean WipeOS needs a driver for it. Is the BMC out-of-band network tapped, or also disconnected?
- [ ] **Barrier timeouts.** How long may a node take to reach READY and FILLED before D9 applies? The READY timeout now covers the image download, quiescing and kexec (D19). The FILLED timeout depends on the slowest device.
- [ ] **Honest failure and recovery.** What is the operational recovery path, alongside D9, for a crash mid-fill, a failed RELEASE, or a reboot loop?
- [ ] **Device abstraction.** Should wipers be plug-ins behind one interface (discover, fill, open, report), selected by the manifest?
- [ ] **Observability.** Which per-phase timings, per-device throughputs and logs are built in from the start?
- [ ] **Deadline and sample count.** How are the response deadline and sample count calibrated? Best measured once the challenge server exists.
- [ ] **NVLink switch trays (lower priority).** The switch trays have their own buffers and management processors. Must their state be wiped, or can it be bounded and charged to R?
- [ ] **GPU driver in WipeOS.** How much of its footprint can be committed in I0, and how much has to be charged to R?
- [ ] **kexec on Vera.** What state survives the handoff, and what does firmware still touch?
- [ ] **Manifest format.** What is its schema, who signs it, and how is it versioned?

**Deferred.**

- [ ] **Certificate format.** How the logged fields (D15) are packaged into a Pod-PoComp certificate is tabled until the prototype works.
- [ ] **Attesting committed binaries.** Committing unerased binaries such as the WipeOS image or firmware in I0 would need some form of attestation. Tabled until the Pod-PoComp accounting matures; meanwhile the residual ledger (D20) logs them as their own category.
- [ ] **WipeOS managing physical memory itself.** A break-glass option: run most of host memory outside the kernel's page allocator so it carries no per-page bookkeeping. Tabled; huge pages (D22) come first, and we only revisit this if they leave too much overhead.
- [ ] **EFI and NUMA in the kernel config.** `CONFIG_EFI`, `CONFIG_NUMA`, `CONFIG_ACPI_NUMA` and `CONFIG_X86_64_ACPI_NUMA` are currently off. They are needed on real hardware from tier T1 onward:
  - EFI, so a kernel entered through kexec reads the UEFI memory map correctly.
  - ACPI SRAT, for the per-socket memory ranges used by inventory (D4) and by NUMA-local fill threads.

  They do nothing in a plain QEMU VM and grow the image, so they are tabled until the step up to T1. When they are enabled, report `bzImage` size before and after.
- [ ] **Static wipe agent versus the CUDA path.** The userspace candidate is a single static binary, but NVIDIA ships its user-mode CUDA driver (`libcuda.so`) only as a shared library built against glibc (D21). The CUDA runtime can be linked statically, but it still loads `libcuda.so` at run time, which needs a dynamically linked glibc. If the HBM fill runs through CUDA, either the agent is dynamically linked, or a separate dynamically linked GPU helper runs alongside a static agent that covers DRAM and NVMe. Tabled until the GPU wiper is built for tier T1.

**Resolved.**

- [x] **Label verification without recomputation.** Resolved by D18: candidate C, streamed fingerprints with secret sampling, behind an interface so it can be swapped later.
- [x] **Coordination.** Resolved by D8: a barrier protocol run by the challenge server.
- [x] **Fencing between nodes.** Resolved by D8, since all nodes fill at once, and by the physical-isolation assumption, since east-west links are unplugged. The NVLink switch trays remain open above.
- [x] **Benchmark scope.** Resolved by D11: a three-stage scale-up with minimal disruption.
- [x] **Test ladder.** Resolved by D12: local wiping, then auditor emulation, then a split DGX for multi-node tests.
- [x] **Role of the H100 NVL node.** Out of scope for now.
- [x] **Network tap in the test.** Resolved by D13: the challenge server runs on a CPU-only server where the tap is emulated.
- [x] **Amodo baseline.** Resolved by D14: we clone their label-generation code and build everything else ourselves.
- [x] **Reference challenge server.** Placement resolved by D13; verification method resolved by D18.
- [x] **Success metrics.** Resolved by D15: a working prototype that logs every certificate field.
- [x] **Two architectures.** Resolved by D17: x86_64 first, with an abstraction layer for a later Arm port.
- [x] **Cluster approvals.** Scoped as the tiered test plan in Test environment. Approvals are requested tier by tier later, not before the OKRs.
