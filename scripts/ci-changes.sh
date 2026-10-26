#!/usr/bin/env bash
# Decide whether CI's build and boot job has anything to do (D46). Lists
# the files that differ between two commits and says "build" if any of
# them can change the image or how it is booted, "skip" otherwise.
#
# Usage:
#   scripts/ci-changes.sh BASE HEAD
#     BASE  the commit to compare against: the pull request's base
#           branch (the diff starts at the merge base, as GitHub shows
#           it), or the previous head of main. Empty, or all zeros (a
#           new branch), means there is nothing to compare against.
#     HEAD  the commit under test
#
# Output: "build" or "skip" on the first line, then the changed paths,
# one per line.
#
# Exit: 0 on success; 2 on bad arguments or a git error. Either way the
# first line is still "build": when the answer is in doubt, CI builds.

set -uo pipefail

# What can change the image or the boot test (D46). A path matches when
# it equals an entry or, for an entry ending in /, lies under it.
BUILD_PATHS=(
	src/
	package/
	configs/
	external.desc
	external.mk
	Config.in
	scripts/run.sh
	scripts/ci-changes.sh
	.github/workflows/
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

verdict=skip
while IFS= read -r f; do
	[ -n "$f" ] || continue
	for p in "${BUILD_PATHS[@]}"; do
		case $p in
		*/) [[ $f == "$p"* ]] && verdict=build ;;
		*) [[ $f == "$p" ]] && verdict=build ;;
		esac
	done
done <<<"$changed"

echo "$verdict"
[ -n "$changed" ] && echo "$changed"
exit 0
