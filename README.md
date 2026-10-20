# WipeOS

A minimal Linux image for verifiable memory wipes. On each host in a pod, WipeOS overwrites the agreed erasure target with challenge-dependent data and answers a challenge server's queries, so that at most R bits of uncommitted state survive. It builds on Amodo's PoSE memory-wiping work and the Pod-PoComp protocol.

## Docs

| File | What it holds | Changes |
| --- | --- | --- |
| `docs/design.md` | Purpose, threat model, architecture, erasure phases, inventory, software stack, test environment | Only when an accepted decision changes the design |
| `docs/decisions.md` | Decision log (D1 onward) and open questions | Whenever a decision is proposed, accepted or superseded |
| `docs/okrs.md` | This week's OKRs and an archive of past weeks | Weekly |
| `docs/research/` | Research notes behind specific decisions | As research happens |

## Running wipeOS

Current as of Oct 19, 2026. These steps are specific to my laptop (Windows on Arm with WSL2) and will become general as wipeOS turns into a product. Update this section whenever the configuration changes.

**Launch the current image.**

1. Open the Ubuntu (WSL2) terminal from the Windows Start menu, or run `wsl` in PowerShell.
2. Go to the Buildroot folder: `cd ~/wipeOS/buildroot`
3. Boot the image in QEMU:

```bash
qemu-system-x86_64 -m 1G -vga none -kernel output/images/bzImage -append "console=ttyS0" -nographic
```

4. Log in as `root` (no password).
5. To quit, press **Ctrl-A**, then **X**.

**Useful checks inside the VM.** `free -h`, `cat /proc/iomem` and `dmesg | grep Memory:` give the footprint for the residual ledger.

**Rebuild after a change** (from `~/wipeOS/buildroot`):

- After changing the kernel config with `make linux-menuconfig`: `make linux-rebuild && make`
- After changing Buildroot settings with `make menuconfig`: `make`
- Save both configs afterwards:

```bash
make linux-update-defconfig
make savedefconfig BR2_DEFCONFIG=../configs/wipeOS_x86_64_defconfig
```

**Set up on a new machine.** This repo holds only our configs; Buildroot is not committed (it is in `.gitignore`), so each developer clones it and builds the image locally. Buildroot needs a Linux host with its standard host packages (see the "System requirements" chapter of the Buildroot manual), and the launch command above needs `qemu-system-x86_64` installed. Keep the repo off Windows filesystems and out of paths with spaces.

```bash
git clone git@github.com:ztblick/wipeOS.git ~/wipeOS
cd ~/wipeOS
git clone --branch 2026.02.3 https://gitlab.com/buildroot.org/buildroot.git buildroot
cd buildroot
make defconfig BR2_DEFCONFIG=../configs/wipeOS_x86_64_defconfig
make
```

The first `make` builds the toolchain, kernel and initramfs and takes a long time; the image lands in `buildroot/output/images/bzImage`. Config paths are relative to the `buildroot` folder, so the repo can live anywhere.

**Where things live.**

| Path | What it is |
| --- | --- |
| `~/wipeOS/buildroot` | Buildroot checkout; run every `make` from here |
| `~/wipeOS/configs/linux.config` | Pruned kernel config |
| `~/wipeOS/configs/wipeOS_x86_64_defconfig` | Buildroot settings |
| `~/wipeOS/buildroot/output/images/bzImage` | The built image: kernel with initramfs inside |

**WSL setup notes.** Windows paths are kept out of the Linux PATH (`appendWindowsPath = false` in `/etc/wsl.conf`), because Buildroot fails on paths with spaces. VS Code still opens with `code .` through an alias in `~/.bashrc`.
