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
