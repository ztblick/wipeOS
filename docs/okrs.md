# WipeOS: OKRs

Weekly objectives and key results. I write OKRs one week at a time; the current week is at the top and past weeks move to the archive below.

**Editing rules.** Claude Code may tick a key result it completed, adding a one-line note of the evidence, and may add progress notes under a key result. It does not add, remove or reword objectives or key results.

## Week of Oct 19, 2026

**O1. Stand up a minimal WipeOS image and VM harness.**

- [x] **KR1.1** Choose a minimal x86_64 linux kernel base and remove any unnecessary modules from it.
  - **Done.** Chose Buildroot with glibc, the initramfs linked into the kernel and the disk root filesystem off (D21), starting from Buildroot's QEMU x86_64 config. Removed graphics, sound, USB, wireless, Bluetooth and disk and network filesystems; kept serial console, PCI, virtio, NVMe, networking, kexec and module support. The kernel shrank from 14.8 MB to 13.0 MB, and memory not free in a 1 GiB VM fell from 53.2 MB to 51.3 MB. Key finding: the kernel's per-page bookkeeping is about 16 MB here, 1.6% of RAM. Later use of large (2 MB) and huge (1 GB) pages should solve this problem.
- [x] **KR1.2** The stripped-down kernel and initramfs boot in a VM to a userspace stub that prints the memory map. The kernel and initramfs sizes are recorded as the first entries in the residual ledger.
  - **Done.** `/sbin/wipeos-init` runs as process 1 (D25) and prints the memory map (`iomem.ram.*`, the kernel's sections) in its `WIPEOS` report; the kernel and initramfs sizes are report lines (`iomem.kernel_total_bytes=13360176`, `initramfs.shmem_kb=6444`), not yet ledger entries, since the ledger schema was out of scope in `docs/plans/stub-plan.md`.
- [ ] **KR1.3** Design harness. It covers how a VM is launched with configurable guest RAM, how boot and wipe logs are captured, and where architecture-specific code sits (D17).
  - **Progress.** `scripts/run.sh` covers launching with configurable guest RAM and page size, and capturing the boot log. Wipe logs and the D17 boundary for architecture-specific code are not designed yet; the stub has no architecture-specific code so far.
- [x] **KR1.4** One command launches the image in QEMU and collects its boot log.
  - **Done.** `scripts/run.sh` builds, boots, writes `logs/run-<date>-<time>.log` and exits 0/1/2/3 by the result (D30); acceptance tests 1–8 of `docs/plans/stub-plan.md` pass.

**O2. Finalize the plan for streaming labels back to the verifier (D18).**

- [x] **KR2.1** Clone Amodo's open-source GPU label-generation code. Built and run it on a single GPU. Understand the specifics of its label-generation algorithm and whether that fits with my label-streaming idea.
  - **Done.** Cloned at `fae0935`, built and run on one H100 (0.81 GB/s of stored labels); the algorithm is in `docs/research/amodo-study.md` Part 1, and §3.1 shows it doesn't fit label streaming.
- [x] **KR2.2** Answer this question: which labels in the DAG need to be streamed back to the challenge server for it to be able to theoretically challenge every node on the graph?
  - **Done.** No stored label has a stored parent (0 of 131,072 at m = 2^17), so streaming can't support neighborhood checks; see `docs/research/amodo-study.md` §3.1.
- [ ] **KR2.3** Specify streaming protocol: label size, fingerprint size, how the server picks and keeps neighborhoods, batching, and query format.
  - **Progress.** The plan changed (D32): there is no fingerprint stream; the protocol is now precomputed challenges. Its sizing is the open question "Precomputation parameters" in `docs/decisions.md`.

**O3. Share the design and get feedback.**

- [ ] **KR3.1** Walk Landy, my mentor, through the design, and the feedback is recorded in this doc.
- [ ] **KR3.2** Ask around the Lucid network for systems engineers who can review the design.
- [ ] **KR3.3** Read up on the Linux kernel internals this design depends on, such as kexec, memory management and the boot path.

**O4. Write the first erasure code: wipe a few pages of DRAM and stream back their fingerprints.**

- [ ] **KR4.1** A userspace program fills a small DRAM buffer, a few pages, with labels derived from a seed. A placeholder label function, such as a keyed hash per page, sits behind a label-generation interface so Amodo's construction can replace it later.
- [ ] **KR4.2** As each label is written, its fingerprint (D18) is streamed to stdout in batches, in a format documented in `docs/research/label-verification.md`.
  - **Progress.** The plan changed (D32): there is no fingerprint stream; the protocol is now precomputed challenges.
- [ ] **KR4.3** A verifier stub reads the fingerprint stream, keeps a random sample, queries those pages, and checks the returned labels against the kept fingerprints. Program and stub can run as two processes joined by a pipe.
- [ ] **KR4.4** The program runs as the userspace stub in the KR1.2 image, and logs per-phase timings and the pages it did not fill to the residual ledger (D20).

## Archive

No past weeks yet.
