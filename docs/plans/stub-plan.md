# Plan: the stub as process 1 (KR1.2, KR1.4)

Implementation plan for booting WipeOS in QEMU with one command, running our own stub as the only userspace process. Written 2026-10-20 from a design discussion with Zach. The seven decisions below were approved by Zach in that discussion. Record them in `docs/decisions.md` as described in Step 1.

Read this whole file before starting, together with `CLAUDE.md`, `docs/design.md`, `docs/decisions.md` and `docs/okrs.md`. Work in the steps listed at the end, propose each step before doing it, and stop for review between steps.

## Goal

One command, `scripts/run.sh`, builds the image if needed, boots WipeOS in QEMU, and exits with a code that says whether the boot succeeded. During boot the kernel starts our stub, `/sbin/wipeos-init`, as process 1. The stub mounts the virtual filesystems, prints a report as `WIPEOS key=value` lines, runs a few checks, prints a final `RESULT` line, and then either powers off (prod) or hands the console to a shell (dev). Nothing else runs in userspace: no BusyBox init, no daemons, no login prompts.

This covers KR1.2 (boot to a userspace stub that prints the memory map; the kernel and initramfs sizes appear in its report) and KR1.4 (one command launches the image and collects its boot log).

**Out of scope:** the fill and label code (O4), networking, the residual-ledger schema, production-image trimming (dropping BusyBox and glibc), EFI and NUMA (deferred to T1), a KVM flag for the cloud VM, and anything aarch64.

## Constraints from existing decisions

- **D3, D20:** footprint is a security quantity. Report `bzImage` size before and after every step that changes the image.
- **D17:** x86_64 only. Keep architecture-specific code behind its own boundary. This plan needs none, so don't create an empty `arch/` folder.
- **D21:** Buildroot with glibc; kernel and Buildroot configs live in `configs/`.
- **D22:** huge pages are reserved at boot, which `run.sh` does for 3 GiB and above.
- **D23:** use the system `qemu-system-x86_64` and log its version.
- **No address randomization:** KASLR is off and `norandmaps` is in the built-in command line. The stub checks this.
- **Development host:** the laptop is aarch64 with no KVM for x86 guests. Never use `-enable-kvm`, `-accel kvm` or `-cpu host`. `-cpu max` is fine.
- **Interactive menus:** you can't drive `make menuconfig` or `make linux-menuconfig`. For every config change, list the exact symbols and values; Zach makes the change and saves the configs.

## Decisions

### 1. The stub is process 1

The stub is installed at `/sbin/wipeos-init`. It is named as process 1 by `rdinit=/sbin/wipeos-init` in the built-in kernel command line, alongside `norandmaps`, so the full built-in string becomes `norandmaps rdinit=/sbin/wipeos-init`.

- Buildroot's init system is **None**, and `/dev` management is **devtmpfs**.
- BusyBox remains in the image only to provide `/bin/sh` for dev mode. Nothing in the boot path uses it.
- The QEMU post-build script (`board/qemu/x86_64/post-build.sh`) is removed. It only added a tty1 login prompt to an `inittab` that no longer exists.
- A boot-time `rdinit=` still overrides the built-in one. `rdinit=/bin/sh` remains a rescue shell.

*Alternatives considered:* the stub as `/init` (collides with the small `/init` script Buildroot installs in initramfs images); the stub as `/sbin/init` behind Buildroot's `/init` script (puts a shell script that needs BusyBox in front of process 1).

### 2. The stub is built as a Buildroot package

The repo is a Buildroot external tree (see Decision 7), and `package/wipeos-stub/` builds `src/stub/` with Buildroot's toolchain and installs the binary. One `make` produces the whole image, the build is reproducible from the repo, and Buildroot stays an untouched upstream checkout.

*Alternative considered:* compiling separately and copying the binary in (risks a stale binary, and the image is no longer reproducible from the repo alone).

### 3. C17, statically linked against glibc

Compile with Buildroot's toolchain using `-std=c17 -O2 -Wall -Wextra -Werror` and link with `-static`. Also add `-ffile-prefix-map=<src>=.` so the binary contains no host paths, which keeps builds reproducible.

- The stub needs no shared libraries at runtime.
- It uses no DNS. Static glibc can't do host-name lookups properly. When networking arrives, endpoints are IP addresses taken from the command line.
- *Implication for later:* a static binary can't load CUDA's shared libraries. The future GPU wiper will either make the agent dynamically linked or run as a separate, dynamically linked worker started by process 1. The current lean is the worker. That decision isn't needed now.

*Alternatives considered:* C++ (no benefit for the stub); Rust (adds a long toolchain build and a second language next to CUDA); Go (its runtime and garbage collector undermine determinism).

### 4. Mode flag

`wipeos.mode=dev|prod` on the kernel command line.

- If the flag appears more than once, the last occurrence wins.
- If it's absent, the stub runs in prod mode. An unknown value is a FAIL.
- Both modes collect the same report, run the same checks and produce the same result. They differ only in how the run ends:
  - **prod** powers off;
  - **dev** starts `/bin/sh` on the console as a child process, waits for it, and powers off when it exits.
- If `/bin/sh` is missing in dev mode, the stub reports `FAIL reason=no_shell` and powers off.

The mode is operational, not a security control: a shell on a node can't fake the timed challenge.

*Alternatives considered:* default to dev (a forgotten flag in production would leave a node at a shell); require the flag (burdens every manual and test boot).

### 5. Report format

The stub writes only lines of the form `WIPEOS key=value` to the console, each with a single `write()` so a kernel message can't land inside a line.

- **First line:** `WIPEOS BEGIN format=1 version=<git commit>`.
- **Last line:** `WIPEOS RESULT=SUCCESS` or `WIPEOS RESULT=FAIL reason=<token>`. A missing RESULT line means the stub crashed or hung.
- **Keys:** lowercase, grouped by dotted prefix (`mem.`, `iomem.`, `hugetlb.`, `pci.`, `check.`), with units in the key name (`_kb`, `_bytes`, `_pages`, `_ms`).
- **Values:** addresses are hex with `0x`. Values contain no spaces, or are wrapped in double quotes.

This is the seed of the WipeOS log format (D15, D20). It's easy to change and the stakes are low, so don't over-engineer it.

*Alternatives considered:* free text (fragile to parse); a final JSON object (invalid if output is cut off); text plus key=value lines (two formats that can drift).

### 6. Result reporting through the boot log

`run.sh` determines the outcome from the boot log, then exits with:

| Exit code | Meaning |
| --- | --- |
| 0 | `WIPEOS RESULT=SUCCESS` |
| 1 | `WIPEOS RESULT=FAIL` |
| 2 | No RESULT line: crash, hang, timeout or kernel panic |
| 3 | Bad arguments to `run.sh` |

The stub powers off after reporting, which ends QEMU under `-no-reboot`. No QEMU debug-exit device is used, so process 1 contains no port I/O and no architecture-specific code.

*Alternative considered:* QEMU's isa-debug-exit device (an independent exit code, but x86-specific port I/O in process 1, a guard flag to keep it off real hardware, and awkward exit-code mapping).

### 7. Repository layout

The repo root is a Buildroot external tree named `WIPEOS`:

```
~/wipeOS/
├── external.desc            # name: WIPEOS
├── Config.in                # sources package/wipeos-stub/Config.in
├── external.mk              # includes package/*/*.mk
├── package/
│   └── wipeos-stub/
│       ├── Config.in        # BR2_PACKAGE_WIPEOS_STUB
│       └── wipeos-stub.mk   # generic-package, local source in src/stub
├── src/stub/                # C source and Makefile
├── scripts/run.sh           # the launcher
├── configs/                 # existing: linux.config, wipeOS_x86_64_defconfig
├── docs/                    # existing
├── logs/                    # boot logs; add to .gitignore
└── buildroot/               # existing upstream checkout; gitignored
```

- Paths inside config files use `$(BR2_EXTERNAL_WIPEOS_PATH)`, never `../` or a home-folder path. For example, `BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="$(BR2_EXTERNAL_WIPEOS_PATH)/configs/linux.config"`.
- Commands pass the external tree relatively, from `~/wipeOS/buildroot`: `make BR2_EXTERNAL=.. wipeOS_x86_64_defconfig`. Buildroot remembers it for later builds in that checkout, and finds the defconfig by name in the external tree's `configs/`.
- No rootfs overlay: the package installs the stub. No `arch/` folder until something needs one.

*Alternative considered:* a separate `br2-external/` folder (tidier top level, but no defconfig discovery unless `configs/` moves inside it).

## Component specs

### Build configuration changes

List these for Zach to apply. Don't edit the files by hand.

**Buildroot** (`make menuconfig`, then `make savedefconfig BR2_DEFCONFIG=../configs/wipeOS_x86_64_defconfig`):

| Symbol | Value | Why |
| --- | --- | --- |
| `BR2_INIT_NONE` | y | No BusyBox init, scripts, gettys or daemons |
| `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_DEVTMPFS` | y | The kernel fills `/dev`; the stub mounts it |
| `BR2_PACKAGE_WIPEOS_STUB` | y | Our package, under the external tree's menu |
| `BR2_ROOTFS_POST_BUILD_SCRIPT` | empty | The QEMU tty1-getty script is no longer needed |
| `BR2_ROOTFS_POST_SCRIPT_ARGS` | empty | No post scripts remain to pass arguments to |
| `BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE` | `$(BR2_EXTERNAL_WIPEOS_PATH)/configs/linux.config` | Not tied to where Buildroot is checked out |

**Kernel** (`make linux-menuconfig`, then `make linux-update-defconfig`):

| Symbol | Value |
| --- | --- |
| `CONFIG_CMDLINE` | `"norandmaps rdinit=/sbin/wipeos-init"` |

`CONFIG_CMDLINE_BOOL` stays on, and `CONFIG_CMDLINE_OVERRIDE` stays off.

Check the `git diff` of both config files after saving. It should contain exactly these changes.

### The package (`package/wipeos-stub/`)

- **`Config.in`:** a `BR2_PACKAGE_WIPEOS_STUB` bool with a one-line help text.
- **`wipeos-stub.mk`:** uses `generic-package` with:
  - `WIPEOS_STUB_SITE = $(BR2_EXTERNAL_WIPEOS_PATH)/src/stub` and `WIPEOS_STUB_SITE_METHOD = local`.
  - **Build:** `$(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)`. Pass the version string in, from `git -C $(BR2_EXTERNAL_WIPEOS_PATH) describe --always --dirty`, falling back to `unknown`.
  - **Install:** `install -D -m 0755 $(@D)/wipeos-init $(TARGET_DIR)/sbin/wipeos-init`.
- After editing the stub's source, `make wipeos-stub-rebuild && make` rebuilds it and repacks the image. `run.sh` does this.

### The stub (`src/stub/`)

Keep it small and readable. A few `.c` files are fine, for example `main.c` for the sequence and mode, `report.c` for collecting and printing, and `util.c` for line output and file reading. Comment the *why* on anything non-obvious. This is extra-scrutiny code under `CLAUDE.md`.

**Sequence:**

1. **Mount** `proc` on `/proc`, `sysfs` on `/sys` and `devtmpfs` on `/dev`, creating the directories if missing. Treat "already mounted" (`EBUSY`) as success. The kernel's automatic devtmpfs mount doesn't apply to an initramfs.
2. **Make sure stdout and stderr are the console.** The kernel normally gives process 1 `/dev/console`. If not, open it.
3. **Parse `/proc/cmdline`:** `wipeos.mode` and `wipeos.test_fail`, with the last occurrence winning.
4. **Print `WIPEOS BEGIN ...`,** then `WIPEOS mode=<dev|prod>`.
5. **Collect and print the report.** Initial keys:
   - `boot.uptime_ms`, `cpu.count`, `cmdline="<full /proc/cmdline>"`
   - `mem.total_kb`, `mem.free_kb`, `mem.available_kb` (from `/proc/meminfo`)
   - `iomem.ram.<n>=0xSTART-0xEND`, one per top-level `System RAM` range
   - `iomem.kernel_code`, `iomem.kernel_rodata`, `iomem.kernel_data`, `iomem.kernel_bss` (each `0xSTART-0xEND`), and `iomem.kernel_total_bytes`
   - `initramfs.shmem_kb` (`Shmem` from `/proc/meminfo`, the unpacked initramfs)
   - `hugetlb.page_size_kb`, `hugetlb.pages_total`, `hugetlb.pages_free` (from `/proc/meminfo`), and `hugetlb.vmemmap_optimize` (from `/proc/sys/vm/hugetlb_optimize_vmemmap`, reported as `absent` if missing)
   - `aslr.randomize_va_space` (from `/proc/sys/kernel/randomize_va_space`)
   - `pci.count`, and one `pci.<slot>=<vendor>:<device>:<class>` per device in `/sys/bus/pci/devices`
6. **Run the checks,** printing each as `check.<name>=pass` or `check.<name>=fail`:
   - `check.mounts`: all three mounts succeeded.
   - `check.aslr_off`: `randomize_va_space` is `0`.
   - `check.report`: every file the report needs could be read.
   - If `wipeos.test_fail=1` is set, also emit `check.test_fail=fail`. This is the negative test.
7. **Print the result:** `WIPEOS RESULT=SUCCESS` if every check passed, otherwise `WIPEOS RESULT=FAIL reason=<first failed check>`.
8. **End by mode:**
   - **prod:** `sync()`, then `reboot(RB_POWER_OFF)`.
   - **dev:** `fork()`. In the child, call `setsid()`, open `/dev/console`, make it the controlling terminal (`TIOCSCTTY`), and `execv("/bin/sh", ...)`. The parent `wait()`s, reaping any child, and powers off when the shell exits. If `/bin/sh` is missing, print `WIPEOS RESULT=FAIL reason=no_shell` and power off.

**Process-1 rules:**

- **Never return from `main` or exit.** If process 1 exits, the kernel panics. If `reboot()` itself fails, loop on `pause()`.
- **Fail closed.** Any unexpected internal error becomes a FAIL with a reason token, then the normal ending for the mode. Never skip silently.
- **One `write()` per output line.** Format each line into a buffer first.
- **No background activity.** No threads, timers or signal-driven work. The default signal behavior of process 1 (the kernel ignores signals that have no handler) is fine.

### The launcher (`scripts/run.sh`)

**Usage:**

```
scripts/run.sh [--mode dev|prod] [--mem N] [--pages auto|4k|1g]
               [--no-build] [--timeout SECONDS] [--log PATH] [--test-fail]
```

**Defaults:** `--mode prod`, `--mem 1`, `--pages auto`, and a timeout of 300 s in prod with none in dev. The log goes to `logs/run-<YYYYmmdd-HHMMSS>.log`.

**Memory and pages**, where `--mem` is in GiB:

- `--pages auto`: N ≤ 2 uses 4 KB pages. N ≥ 3 uses 1 GB pages: add `-cpu max` and `default_hugepagesz=1G hugepagesz=1G hugepages=<N−2>`.
  - The first gigabyte is always fragmented (BIOS areas, legacy hole, kernel), and the top of guest RAM has a reserved region, so N−2 is the safe count.
- `--pages 4k`: forces ordinary pages at any size, for measuring bookkeeping cost.
- `--pages 1g` with N < 3: a usage error (exit 3).
- If the report's `hugetlb.pages_total` is less than requested, print a warning. This doesn't change the result.

**Steps:**

1. **Build**, unless `--no-build`: from `~/wipeOS/buildroot`, run `make wipeos-stub-rebuild && make`. Stop with exit 2 if the build fails.
2. **Print** `qemu-system-x86_64 --version` into the log (D23).
3. **Boot:**

   ```
   qemu-system-x86_64 -m <N>G -vga none -nographic -no-reboot [-cpu max] \
     -kernel output/images/bzImage \
     -append "console=ttyS0 panic=-1 wipeos.mode=<mode> [wipeos.test_fail=1] [huge-page options]"
   ```

   `panic=-1` makes a crashing or missing stub end the run at once instead of waiting for the timeout. In prod, wrap the command in `timeout`. In dev, pass the terminal through for interactive use and only copy output to the log.
4. **Determine the result** from the log (Decision 6) and print a short summary: the result, failure reason, huge pages requested versus reserved, the log path and elapsed time. Then exit with the matching code.

**Resolve paths relative to the script's own location,** so it works from any directory and on any machine. Use `set -euo pipefail`.

## Implementation steps

Propose each step, wait for approval, and stop for review after it. For every step that changes the image, report `bzImage` size before and after. Give the usual end-of-task report from `CLAUDE.md`.

1. **Record and prepare.**
   - Add Decisions 1–7 to `docs/decisions.md` with the next free numbers and today's date. Zach approved them in design discussion; ask him to confirm "accept" in the session before marking them Accepted.
   - Add `logs/` to `.gitignore`.
2. **Skeleton boot.**
   - Create the external tree files and the package.
   - Write a minimal stub that only mounts the three filesystems, prints `WIPEOS BEGIN` and `WIPEOS RESULT=SUCCESS`, and powers off.
   - List the build configuration changes for Zach to apply.
   - Verify with a manual QEMU boot that `/sbin/wipeos-init` runs as process 1 and QEMU exits on its own.
3. **Full stub:** the report keys, checks, mode handling and the `wipeos.test_fail` hook. Verify in both modes with manual boots.
4. **The launcher:** `scripts/run.sh` as specified.
5. **Docs.**
   - Update the "Running wipeOS" section of `README.md` with the new commands, including `make BR2_EXTERNAL=.. wipeOS_x86_64_defconfig` for setup on a new machine.
   - Tick KR1.2 and KR1.4 in `docs/okrs.md`, each with a one-line note of the evidence.
   - Propose, without making, any `docs/design.md` edits. The Software stack's Userspace row is the obvious one.

## Acceptance tests

1. `scripts/run.sh --mode prod --mem 1` exits 0. The log ends with `WIPEOS RESULT=SUCCESS`, and `hugetlb.pages_total=0`.
2. `scripts/run.sh --mode prod --mem 3` exits 0, with `hugetlb.pages_total=1`, `hugetlb.page_size_kb=1048576` and `hugetlb.vmemmap_optimize=1`.
3. `scripts/run.sh --mode prod --mem 4 --pages 4k` exits 0, with `hugetlb.pages_total=0`.
4. `scripts/run.sh --mode prod --test-fail` exits 1, with `RESULT=FAIL reason=test_fail`.
5. `scripts/run.sh --mode prod --pages 1g --mem 2` exits 3 without booting.
6. `scripts/run.sh --mode dev` gives a shell. There, `ps` shows only `wipeos-init`, `sh` and kernel threads, and `exit` powers the VM off.
7. Two runs of test 1 report identical `iomem.kernel_code` ranges, confirming no randomization.
8. With the stub binary deliberately removed from the image, `run.sh` exits 2 promptly, because `panic=-1` ends the run. Do this as a one-off check, then restore the image.

Also report the change in `bzImage` size and in `mem.free_kb` compared with the BusyBox-init image. The daemons going away should show up.

## For later (not this task)

- Dropping BusyBox, and possibly glibc, from the production image when it's committed in I0.
- The GPU wiper's linking (Decision 3's implication).
- Networking to the challenge server (D19), and the BlueField driver.
- EFI and NUMA at T1 (Deferred in `docs/decisions.md`).
- A `--kvm` option in `run.sh` for the x86 cloud VM.
- Moving the stub into the O4 fill and fingerprint code.
