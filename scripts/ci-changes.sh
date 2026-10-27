#!/usr/bin/env bash
# Decide how much of CI's build and boot job a change needs (D56). Lists
# the files that differ between two commits and says:
#   build  something that goes into the image changed: build it, boot it
#   boot   only the boot test changed (run.sh, ci.yml): the image an
#          earlier run built and passed can be booted again instead
#   skip   neither changed
# With --fingerprint, prints a hash of the image's inputs and one of the
# boot test's, so CI can match a commit to an earlier pass.
#
# Usage:
#   scripts/ci-changes.sh BASE HEAD
#     BASE  the commit to compare against: the pull request's base
#           branch (the diff starts at the merge base, as GitHub shows
#           it), or the previous head of main. Empty, or all zeros (a
#           new branch), means there is nothing to compare against.
#     HEAD  the commit under test
#   scripts/ci-changes.sh --fingerprint REV
#     REV   the commit whose inputs to hash
#
# Output: "build", "boot" or "skip" on the first line, then the changed
# paths, one per line. With --fingerprint, one line: the image
# fingerprint and the boot fingerprint, separated by a space. Each is the
# same for any two commits whose inputs of that kind are identical,
# whatever else differs.
#
# Exit: 0 on success; 2 on bad arguments or a git error. Either way the
# first line is still "build": when the answer is in doubt, CI builds.
# A failed --fingerprint prints nothing, so CI can't match a pass.

set -uo pipefail

# What goes into the image (D56). A path matches when it equals an entry
# or, for an entry ending in /, lies under it.
IMAGE_PATHS=(
	src/
	package/
	configs/
	external.desc
	external.mk
	Config.in
)
# What the boot test is: how QEMU is launched and judged, and the boot
# cases and build steps in ci.yml. Changing these needs a boot, not a
# new image. This script itself is in neither list: it only decides,
# and every CI run executes it.
BOOT_PATHS=(
	scripts/run.sh
	.github/workflows/ci.yml
)

usage() {
	sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//' >&2
}

# Fail safe: say "build", explain on stderr, exit 2.
fail() {
	echo build
	echo "ci-changes: $1" >&2
	exit 2
}

# fingerprint REV PATH...: ls-tree gives each path's mode and content
# hash (a whole tree's for a directory), so the hash changes with any
# byte, file or executable bit under the paths, and with nothing else.
fingerprint() {
	local rev=$1 listing
	shift
	listing=$(git ls-tree "$rev" -- "${@%/}") || return 1
	sha256sum <<<"$listing" | cut -c1-32
}

if [ "${1:-}" = --fingerprint ]; then
	if [ $# -ne 2 ] || [ -z "$2" ]; then
		usage
		exit 2
	fi
	git rev-parse --verify --quiet "$2^{commit}" >/dev/null || {
		echo "ci-changes: '$2' is not a commit" >&2
		exit 2
	}
	image=$(fingerprint "$2" "${IMAGE_PATHS[@]}") &&
		boot=$(fingerprint "$2" "${BOOT_PATHS[@]}") || {
		echo "ci-changes: git ls-tree $2 failed" >&2
		exit 2
	}
	echo "$image $boot"
	exit 0
fi

if [ $# -ne 2 ] || [ -z "$2" ]; then
	echo build
	usage
	exit 2
fi
base=$1 head=$2

if [ -z "$base" ] || [[ $base =~ ^0+$ ]]; then
	echo build
	echo "ci-changes: no base commit; building" >&2
	exit 0
fi

git rev-parse --verify --quiet "$head^{commit}" >/dev/null ||
	fail "head '$head' is not a commit"
git rev-parse --verify --quiet "$base^{commit}" >/dev/null ||
	fail "base '$base' is not a commit"

# Three dots: from the merge base of BASE and HEAD, so changes on the
# base branch since the pull request started don't count. --no-renames
# lists both sides of a rename, so moving a file out of src/ counts as a
# change to src/.
changed=$(git diff --name-only --no-renames "$base...$head") ||
	fail "git diff $base...$head failed"

# matches FILE PATH...: true if FILE is one of the paths or under one.
matches() {
	local f=$1 p
	shift
	for p in "$@"; do
		case $p in
		*/) [[ $f == "$p"* ]] && return 0 ;;
		*) [[ $f == "$p" ]] && return 0 ;;
		esac
	done
	return 1
}

verdict=skip
while IFS= read -r f; do
	[ -n "$f" ] || continue
	if matches "$f" "${IMAGE_PATHS[@]}"; then
		verdict=build
	elif matches "$f" "${BOOT_PATHS[@]}" && [ $verdict = skip ]; then
		verdict=boot
	fi
done <<<"$changed"

echo "$verdict"
[ -n "$changed" ] && echo "$changed"
exit 0
