#!/usr/bin/env bash
# Lint WipeOS C code. One entry point for every place lint runs: by hand,
# the git pre-commit hook (.githooks/pre-commit), and later a Claude Code
# hook, so all three apply exactly the same checks.
#
# Three tools, each catching what the others miss:
#   checkpatch  Linux kernel coding style (the kernel's own checker,
#               configured by .checkpatch.conf)
#   gcc         strict warnings plus -fanalyzer, GCC's path-sensitive
#               analyzer: leaks, use-after-free, double free, NULL
#               dereference, fd leaks, uninitialized reads
#   cppcheck    a second, independent analyzer: buffer overruns,
#               unused variables and functions, style
#
# Usage:
#   scripts/lint.sh             every .c/.h under the C directories
#   scripts/lint.sh FILE...     just these files
#   scripts/lint.sh --staged    what is staged for commit (used by the hook)
#
# Exit: 0 clean, 1 findings, 2 a tool is missing or the arguments are bad.
# A missing tool fails the run rather than skipping its checks.
#
# Overrides: CHECKPATCH=/path/to/checkpatch.pl, LINT_CC=/path/to/gcc

set -uo pipefail

repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "lint: not inside the wipeOS git repo" >&2
	exit 2
}
cd "$repo" || exit 2

# Directories holding WipeOS C code. Add new ones here.
C_DIRS=(src)

# Stricter than the build's -Wall -Wextra (src/stub/Makefile), on purpose:
# lint may be pickier than the build without breaking the image.
CFLAGS_LINT=(-std=c17 -Wall -Wextra -Werror
	-Wshadow -Wformat=2 -Wundef -Wstrict-prototypes
	-Wmissing-prototypes -Wpointer-arith -Wvla
	-fdiagnostics-plain-output -fno-diagnostics-show-caret
	-fdiagnostics-path-format=none)
# gcc runs twice per file. Some warnings (-Wmaybe-uninitialized) need
# the optimizer's data flow, so they run at -O2 like the build. The
# analyzer runs at -O0, where it sees the code as written: optimization
# can hide real paths from it.
GCC_PASSES=("-O2" "-O0 -fanalyzer")

CPPCHECK_ARGS=(--std=c17 --quiet --inline-suppr --error-exitcode=1
	--check-level=exhaustive
	--suppress=missingIncludeSystem --suppress=checkersReport
	--template='{file}:{line}: {severity}: {message} [{id}]')

usage() {
	sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

# ---- Find the tools --------------------------------------------------

# checkpatch.pl: Buildroot already unpacked the kernel we build, so use
# that tree's copy; it then matches our kernel version.
checkpatch=${CHECKPATCH:-}
if [ -z "$checkpatch" ]; then
	checkpatch=$(ls -d "$repo"/buildroot/output/build/linux-*/scripts/checkpatch.pl \
		2>/dev/null | sort -V | tail -n 1)
fi
if [ -z "$checkpatch" ] || [ ! -f "$checkpatch" ]; then
	echo "lint: checkpatch.pl not found. Build the kernel once (make in" \
	     "buildroot/), or set CHECKPATCH=/path/to/checkpatch.pl" >&2
	exit 2
fi

# The compiler: prefer Buildroot's x86_64 cross gcc, so the analyzer sees
# the same headers and target as the image (D17); x86-only code won't
# compile with the aarch64 host gcc. Fall back to host gcc if the cross
# gcc is missing or was built without the analyzer.
cc=${LINT_CC:-}
if [ -z "$cc" ]; then
	# Absolute path: the staged mode runs gcc from a temporary directory.
	cc=$(ls "$repo"/buildroot/output/host/bin/*-buildroot-linux-gnu-gcc \
		2>/dev/null | head -n 1)
	if [ -n "$cc" ] && ! echo 'int x;' |
	   "$cc" -fanalyzer -x c -c -o /dev/null - 2>/dev/null; then
		echo "lint: $cc has no -fanalyzer; using host gcc" >&2
		cc=
	fi
	cc=${cc:-gcc}
fi
for tool in "$cc" cppcheck perl; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "lint: '$tool' not found (see scripts/lint.sh header)" >&2
		exit 2
	}
done

# ---- Decide what to lint ---------------------------------------------

mode=tree
case "${1:-}" in
--staged) mode=staged; shift ;;
-h | --help) usage ;;
-*) usage ;;
esac
[ "$mode" = staged ] && [ $# -gt 0 ] && usage

# All C sources and headers under C_DIRS, from git so that untracked
# scratch files and build output are left out.
all_c_files() { git ls-files -- "${C_DIRS[@]/%//*.c}" "${C_DIRS[@]/%//*.h}"; }

workdir=$repo
if [ "$mode" = staged ]; then
	# Lint the index, not the working tree: the commit contains what is
	# staged, which can differ from what is on disk.
	mapfile -t changed < <(git diff --cached --name-only --diff-filter=ACMR \
		-- "${C_DIRS[@]/%//*.c}" "${C_DIRS[@]/%//*.h}")
	[ ${#changed[@]} -eq 0 ] && exit 0

	workdir=$(mktemp -d) || exit 2
	trap 'rm -rf "$workdir"' EXIT
	git checkout-index --all --prefix="$workdir/" || exit 2
	mapfile -t files < <(all_c_files)
elif [ $# -gt 0 ]; then
	files=("$@")
	for f in "${files[@]}"; do
		[ -f "$f" ] || { echo "lint: no such file: $f" >&2; exit 2; }
	done
else
	mapfile -t files < <(all_c_files)
fi

# Analyze every .c among the files. A header change can break any file
# that includes it, so if a header is in the set, analyze all sources.
sources=()
for f in "${files[@]}"; do
	case $f in *.c) sources+=("$f") ;; *.h) whole=1 ;; esac
done
if [ "${whole:-0}" = 1 ] || [ "$mode" = staged ]; then
	mapfile -t sources < <(all_c_files | grep '\.c$')
	whole=1
fi

failed=0
section() { printf '\n== %s\n' "$1"; }

# ---- 1. Style: checkpatch --------------------------------------------

# checkpatch always reads a patch, never --file: in --file mode it
# quietly downgrades some checks (long lines, spelling, fallthrough) to
# CHECK level, which it doesn't report without --strict. So the hook
# and a manual run would apply different rules.
export CHECKPATCH_CONFIG_DIR=$repo
diffopts=(--no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/)
section "style (checkpatch, Linux kernel style)"
if [ "$mode" = staged ]; then
	# Check only the lines this commit adds or changes, the way kernel
	# patches are checked, so older code doesn't block unrelated commits.
	out=$(git diff --cached "${diffopts[@]}" -- "${changed[@]}" |
		perl "$checkpatch" --quiet --no-summary - 2>&1)
else
	# Whole files: present each one as a patch that adds it.
	out=$(for f in "${files[@]}"; do
		# --no-index exits 1 when the files differ, which they always do.
		git diff --no-index "${diffopts[@]}" /dev/null "$f" || true
	done | perl "$checkpatch" --quiet --no-summary - 2>&1)
fi
rc=$?
out=$(echo "$out" | grep -v '^total: ')
if [ $rc -ne 0 ] || [ -n "$out" ]; then
	echo "$out"
	failed=1
else
	echo "ok"
fi

# ---- 2. Compiler warnings and gcc's analyzer -------------------------

section "compiler + analyzer ($(basename "$cc"))"
gcc_failed=0
for src in "${sources[@]}"; do
	out=
	for pass in "${GCC_PASSES[@]}"; do
		# $pass is unquoted on purpose: it holds several flags.
		# shellcheck disable=SC2086
		out+=$(cd "$workdir" && "$cc" "${CFLAGS_LINT[@]}" $pass \
			-I"$(dirname "$src")" -c -o /dev/null "$src" 2>&1)
		[ $? -ne 0 ] && gcc_failed=1
		out+=$'\n'
	done
	# Both passes repeat the ordinary warnings; print each line once.
	echo "$out" | grep -v -e 'all warnings being treated as errors' -e '^$' |
		awk '!seen[$0]++'
done
[ $gcc_failed = 0 ] && echo "ok"
[ $gcc_failed = 1 ] && failed=1

# ---- 3. cppcheck -----------------------------------------------------

section "cppcheck"
enable=warning,style,performance,portability
# unusedFunction is only meaningful when cppcheck sees every caller.
[ "${whole:-0}" = 1 ] || [ $# -eq 0 ] && enable+=,unusedFunction
incdirs=()
for d in $(printf '%s\n' "${sources[@]}" | xargs -r -n1 dirname | sort -u); do
	incdirs+=(-I "$d")
done
if [ ${#sources[@]} -gt 0 ]; then
	out=$(cd "$workdir" && cppcheck "${CPPCHECK_ARGS[@]}" \
		--enable="$enable" "${incdirs[@]}" "${sources[@]}" 2>&1)
	if [ $? -ne 0 ] || [ -n "$out" ]; then
		echo "$out"
		failed=1
	else
		echo "ok"
	fi
else
	echo "ok (no sources)"
fi

echo
if [ $failed = 1 ]; then
	echo "lint: FAILED. Fix the findings above, or suppress a false" \
	     "positive in the code with a comment saying why."
	exit 1
fi
echo "lint: clean"
exit 0
