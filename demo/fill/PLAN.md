# Temporary demo: fill and verify free DRAM

A throwaway demo for Zach's team meeting. It shows WipeOS booting, then writing and verifying nearly all free RAM, and reporting what it couldn't reach. It is **not** PoSE: no challenge, no labels, no fingerprints. Delete it after the meeting.

Place this file at `demo/fill/PLAN.md`. Everything the demo needs lives in `demo/fill/`, so removing it is `git rm -r demo/`.

## The one hard rule: zero changes outside `demo/fill/`

Don't touch `package/`, `configs/`, `src/stub/`, `scripts/run.sh`, `README.md`, `.gitignore` or anything in `docs/`. No Buildroot or kernel config changes, and no image rebuild.

Zach approves `demo/` as a temporary folder, so don't log a decision for it. If something seems to need a change outside `demo/fill/`, stop and ask.

## How it gets into the VM without changing the image

The demo binary is shipped as a second, tiny initramfs passed to QEMU with `-initrd`. The kernel unpacks its built-in initramfs and then the external one on top, so the demo appears in the running system while `bzImage` stays untouched. `CONFIG_BLK_DEV_INITRD` is already on.

Prerequisite: stub-plan Step 3 is done (dev mode gives a shell), and `buildroot/output/images/bzImage` has been built.

## Files

```
demo/fill/
├── PLAN.md          # this file
├── fill-demo.c      # the demo program
├── run-demo.sh      # builds the demo, packs the cpio, boots QEMU
├── .gitignore       # ignores build/
└── build/           # generated: fill-demo binary and demo.cpio
```

## `fill-demo.c`

C17, statically linked, compiled with Buildroot's cross-compiler (`buildroot/output/host/bin/x86_64-buildroot-linux-gnu-gcc`) using `-std=c17 -O2 -Wall -Wextra -Werror -static`.

**Arguments:** `--seed N` (default 1, so runs are repeatable) and `--margin-mb N` (default 64).

**Steps:**

1. **Guard and announce.** Refuse to run as process 1. Print `WIPEOS demo.note="not PoSE: plain pattern fill, no challenge"`.
2. **Measure.** Read `MemTotal`, `MemAvailable`, `HugePages_Free` and `Hugepagesize` from `/proc/meminfo`. Read the machine's RAM size as the sum of the top-level `System RAM` ranges in `/proc/iomem`.
   - Print `demo.ram_bytes`, `demo.mem_available_kb`, `demo.hugepages_free` and the target in bytes.
   - The target is the free huge pages plus (`MemAvailable` − margin). Huge pages aren't counted in `MemAvailable`, so the two pools add up.
3. **Allocate.**
   - First, map all free 1 GB huge pages: `mmap` with `MAP_ANONYMOUS | MAP_PRIVATE | MAP_HUGETLB | MAP_HUGE_1GB`.
   - Then map ordinary memory in 64 MB chunks, with `MAP_POPULATE` so it's backed immediately, until the target is reached.
   - If an `mmap` fails, stop allocating and continue with what was mapped. Print how much was obtained from each pool.
4. **Fill.** For every 8-byte word, write `splitmix64(seed + i)`, where `i` is the word's index across all mapped regions in order.
   - Don't write zeros. Linux already hands out zeroed memory, so zeros would prove nothing.
   - Print progress at every 10%: percent, bytes, elapsed time, MB/s.
5. **Verify.** Recompute every word and compare, with the same progress lines. Count mismatches.
6. **Summarize.**
   - Print `demo.filled_bytes`, `demo.filled_hugetlb_bytes`, `demo.filled_4k_bytes`, `demo.unfilled_bytes` (RAM minus filled), `demo.margin_bytes`, `demo.coverage_pct` (one decimal place), `demo.fill_mb_per_s`, `demo.verify_mb_per_s`, `demo.verify_mismatches`, and `demo.result=PASS` or `FAIL`.
   - Then print one plain-English line for the audience, for example: `Filled and verified 2.95 GiB of 3.00 GiB (98.3%). 52 MB untouched: kernel, initramfs, page bookkeeping, shell, and the 64 MB safety margin.`
7. **Exit.** The memory is released on exit.

**Output rules:**

- Use `WIPEOS demo.key=value` lines, one `write()` per line, plus the one plain-English summary line.
- Never print a `RESULT=` line; that token belongs to the stub.

**Why the margin:** if the demo exhausted memory, the kernel's out-of-memory handler would kill it, or worse. Stopping 64 MB short avoids that.

## `run-demo.sh`

Usage: `demo/fill/run-demo.sh [--mem N]`, where N is in GiB and defaults to 3.

1. **Resolve paths** relative to the script's own location. Use `set -euo pipefail`.
2. **Build.** Compile `fill-demo.c` into `build/fill-demo`. If the cross-compiler or `bzImage` is missing, stop with a message saying to build the main image first.
3. **Pack.** Create `build/demo.cpio` (newc format) containing the `sbin/` directory and `sbin/wipeos-fill-demo`, mode 0755.
4. **Boot.**

   ```
   qemu-system-x86_64 -m <N>G -vga none -nographic -no-reboot [-cpu max] \
     -kernel buildroot/output/images/bzImage -initrd demo/fill/build/demo.cpio \
     -append "console=ttyS0 panic=-1 wipeos.mode=dev [default_hugepagesz=1G hugepagesz=1G hugepages=<N-2>]"
   ```

   Add `-cpu max` and the huge-page options only when N ≥ 3.
5. **Before booting, print one hint:** "At the shell prompt, run /sbin/wipeos-fill-demo. Type exit to power off."

Never use `-enable-kvm`, `-accel kvm` or `-cpu host`.

## Verify

- `demo/fill/run-demo.sh --mem 3` boots to the stub's report and the dev shell. There, `/sbin/wipeos-fill-demo` fills about 1 GiB of huge pages plus the ordinary memory, verifies with zero mismatches, and prints `demo.result=PASS` and the summary line. `exit` powers the VM off.
- `demo/fill/run-demo.sh --mem 2` works too, with `demo.filled_hugetlb_bytes=0`.
- `git status` shows changes only under `demo/fill/`.

Report the commands you ran, the summary lines from both runs, and the fill and verify throughput. Note that throughput under emulation isn't representative of real hardware.

## Removal

`git rm -r demo/` and commit. Nothing else changes.
