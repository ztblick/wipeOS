#!/usr/bin/env bash
# Temporary demo (demo/fill/PLAN.md): build the fill demo, pack it into a
# small extra initramfs, and boot WipeOS in dev mode with it. The kernel
# unpacks its built-in initramfs and then this one on top, so the demo
# appears in the running system without rebuilding bzImage.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
CC=$REPO/buildroot/output/host/bin/x86_64-buildroot-linux-gnu-gcc
KERNEL=$REPO/buildroot/output/images/bzImage
BUILD=$HERE/build

usage() {
	echo "Usage: demo/fill/run-demo.sh [--mem N]   (N in GiB, default 3)" >&2
	exit 2
}

mem=3
while [ $# -gt 0 ]; do
	case $1 in
	--mem)
		[ $# -ge 2 ] || usage
		mem=$2
		shift 2
		;;
	*) usage ;;
	esac
done
[[ $mem =~ ^[1-9][0-9]*$ ]] || usage

for f in "$CC" "$KERNEL"; do
	if [ ! -e "$f" ]; then
		echo "run-demo.sh: $f is missing; build the main image first (see README.md)" >&2
		exit 1
	fi
done

mkdir -p "$BUILD"
"$CC" -std=c17 -O2 -Wall -Wextra -Werror -static \
	-o "$BUILD/fill-demo" "$HERE/fill-demo.c"

# A newc cpio holding sbin/ and sbin/wipeos-fill-demo, owned by root.
rm -rf "$BUILD/root"
mkdir -p "$BUILD/root/sbin"
install -m 0755 "$BUILD/fill-demo" "$BUILD/root/sbin/wipeos-fill-demo"
(cd "$BUILD/root" &&
	printf 'sbin\nsbin/wipeos-fill-demo\n' | cpio --quiet -o -H newc -R 0:0) \
	>"$BUILD/demo.cpio"

# 1 GB huge pages from 3 GiB up, N-2 of them, as in scripts/run.sh.
cpu_args=()
pages=
if [ "$mem" -ge 3 ]; then
	cpu_args=(-cpu max)
	pages=" default_hugepagesz=1G hugepagesz=1G hugepages=$((mem - 2))"
fi

echo "At the shell prompt, run /sbin/wipeos-fill-demo. Type exit to power off."
exec qemu-system-x86_64 -m "${mem}G" -vga none -nographic -no-reboot \
	"${cpu_args[@]}" -kernel "$KERNEL" -initrd "$BUILD/demo.cpio" \
	-append "console=ttyS0 panic=-1 wipeos.mode=dev$pages"
