#!/usr/bin/env bash
# Fetch the kernel's checkpatch.pl for scripts/lint.sh (D41), so lint
# runs without a kernel build: on the laptop, in CI, on any host.
#
# Downloads checkpatch.pl and the two data files it reads from its own
# directory (spelling.txt, const_structs.checkpatch) for the kernel
# version our defconfig pins, from kernel.org's stable tree at tag
# v<version>, into .cache/checkpatch/<version>/ (gitignored). If they
# are already there, nothing is downloaded.
#
# Usage:
#   scripts/fetch-checkpatch.sh   fetch if needed, then print the
#                                 absolute path of checkpatch.pl
#
# Exit: 0 the files are in place, 2 the version can't be read or a
# download failed. A failed download leaves no partial files.

set -uo pipefail

repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "fetch-checkpatch: not inside the wipeOS git repo" >&2
	exit 2
}

FILES=(checkpatch.pl spelling.txt const_structs.checkpatch)
URL=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/scripts

defconfig=$repo/configs/wipeOS_x86_64_defconfig
version=$(sed -n 's/^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="\(.*\)"$/\1/p' \
	"$defconfig" 2>/dev/null)
if ! [[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
	echo "fetch-checkpatch: no kernel version" \
	     "(BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE) in $defconfig" >&2
	exit 2
fi

dest=$repo/.cache/checkpatch/$version
complete=1
for f in "${FILES[@]}"; do
	[ -f "$dest/$f" ] || complete=0
done

if [ $complete = 0 ]; then
	command -v curl >/dev/null 2>&1 || {
		echo "fetch-checkpatch: 'curl' not found" >&2
		exit 2
	}
	mkdir -p "$repo/.cache/checkpatch" || exit 2
	# Download into a temporary directory beside the destination, then
	# rename it into place, so an interrupted or failed run never leaves
	# a set that looks complete.
	tmp=$(mktemp -d "$repo/.cache/checkpatch/.$version.XXXXXX") || exit 2
	trap 'rm -rf "$tmp"' EXIT
	for f in "${FILES[@]}"; do
		if ! curl -fsSL --retry 3 -o "$tmp/$f" "$URL/$f?h=v$version"; then
			echo "fetch-checkpatch: download failed:" \
			     "$URL/$f?h=v$version" >&2
			exit 2
		fi
	done
	# A web page served in place of the script (an error or a bot
	# check) would download fine; the script starts with "#!".
	if [ "$(head -c 2 "$tmp/checkpatch.pl")" != '#!' ]; then
		echo "fetch-checkpatch: $URL/checkpatch.pl?h=v$version" \
		     "is not a script" >&2
		exit 2
	fi
	chmod 755 "$tmp" && rm -rf "$dest" && mv "$tmp" "$dest" || exit 2
fi

echo "$dest/checkpatch.pl"
