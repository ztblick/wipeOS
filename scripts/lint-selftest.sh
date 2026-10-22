#!/usr/bin/env bash
# Self-test for scripts/lint.sh and the pre-commit hook. Everything runs
# in a temporary directory; the repo and its history are not touched.
#
# Part 1 feeds lint.sh small C programs, each with one planted defect,
# and checks that the expected tool reports it. One clean program must
# pass, which shows the checks aren't simply failing everything.
#
# Part 2 builds a throwaway git repo with the hook installed and checks
# when a commit is allowed and when it is refused.
#
# Usage:  scripts/lint-selftest.sh [-v]
#   -v  print lint's (or git's) output under each case
# Exit: 0 if every case passes, 1 otherwise.

set -uo pipefail

verbose=0
[ "${1:-}" = -v ] && verbose=1

repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "selftest: run this inside the wipeOS repo" >&2
	exit 2
}
lint=$repo/scripts/lint.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

npass=0
nfail=0

result() { # result OK TOOL NAME OUTPUT
	if [ "$1" = 1 ]; then
		printf '  PASS  %-9s %s\n' "$2" "$3"
		npass=$((npass + 1))
	else
		printf '  FAIL  %-9s %s\n' "$2" "$3"
		nfail=$((nfail + 1))
	fi
	if [ $verbose = 1 ] || [ "$1" != 1 ]; then
		echo "$4" | grep -v -e '^$' -e '^== ' -e '^lint: ' | sed 's/^/        | /'
	fi
}

# lint_case TOOL NAME EXPECT, with the program on stdin. lint.sh must
# exit 1 and its output must contain EXPECT. An empty EXPECT means the
# program is clean and lint.sh must exit 0.
lint_case() {
	local tool=$1 name=$2 expect=$3 f out rc ok=0
	f=$tmp/$(echo "$name" | tr -c 'a-zA-Z0-9\n' '_').c
	cat > "$f"
	out=$("$lint" "$f" 2>&1)
	rc=$?
	if [ -z "$expect" ]; then
		[ $rc -eq 0 ] && ok=1
	elif [ $rc -eq 1 ] && grep -qF -- "$expect" <<<"$out"; then
		ok=1
	fi
	result $ok "$tool" "$name" "$out"
}

echo "Part 1: each check catches its planted defect"

lint_case clean "a clean program passes every check" "" <<'EOF'
#include <stdio.h>

static int twice(int n)
{
	return 2 * n;
}

int main(void)
{
	printf("%d\n", twice(21));
	return 0;
}
EOF

# ---- checkpatch: Linux kernel style ----

lint_case style "indent with spaces, not tabs" "CODE_INDENT" <<'EOF'
int main(void)
{
        return 0;
}
EOF

lint_case style "function brace on its own line" "OPEN_BRACE" <<'EOF'
int main(void) {
	return 0;
}
EOF

lint_case style "line longer than 80 columns" "LONG_LINE" <<'EOF'
int main(void)
{
	int a_rather_long_variable_name_for_this_test = 1, another_one_here_too = 2;

	return a_rather_long_variable_name_for_this_test + another_one_here_too;
}
EOF

lint_case style "trailing whitespace" "TRAILING_WHITESPACE" <<'EOF'
int main(void)
{	
	return 0;
}
EOF

lint_case style "assignment inside if" "ASSIGN_IN_IF" <<'EOF'
#include <stdio.h>

int main(void)
{
	int c;

	if ((c = getchar()) == EOF)
		return 1;
	return c == 'y';
}
EOF

lint_case style "statement on the same line as if" "TRAILING_STATEMENTS" <<'EOF'
int main(int argc, char **argv)
{
	(void)argv;
	if (argc > 1) return 1;
	return 0;
}
EOF

lint_case style "new typedef" "NEW_TYPEDEFS" <<'EOF'
typedef struct {
	int x;
} point_t;

int main(void)
{
	point_t p = { 0 };

	return p.x;
}
EOF

lint_case style "strcpy" "STRCPY" <<'EOF'
#include <stdio.h>
#include <string.h>

int main(void)
{
	char buf[8];

	strcpy(buf, "hi");
	puts(buf);
	return 0;
}
EOF

# ---- gcc warnings (-O2 pass) ----

lint_case gcc "unused variable" "=unused-variable]" <<'EOF'
int main(void)
{
	int unused;

	return 0;
}
EOF

lint_case gcc "variable shadows another" "=shadow]" <<'EOF'
int main(int argc, char **argv)
{
	(void)argv;
	for (int i = 0; i < argc; i++) {
		int argc = i;

		(void)argc;
	}
	return 0;
}
EOF

lint_case gcc "non-static function without a prototype" \
	"=missing-prototypes]" <<'EOF'
int helper(void)
{
	return 1;
}

int main(void)
{
	return helper();
}
EOF

lint_case gcc "printf format doesn't match argument" "=format=]" <<'EOF'
#include <stdio.h>

int main(void)
{
	long n = 5;

	printf("%d\n", n);
	return 0;
}
EOF

lint_case gcc "variable-length array" "=vla]" <<'EOF'
#include <stdio.h>

int main(int argc, char **argv)
{
	char buf[argc];

	(void)argv;
	buf[0] = 0;
	printf("%d\n", buf[0]);
	return 0;
}
EOF

# ---- gcc -fanalyzer (-O0 pass): memory and resource errors ----

# The leak cases sit in a helper, not main(): neither analyzer reports
# memory still held when main returns, since process exit frees it.
lint_case analyzer "memory leak" "analyzer-malloc-leak" <<'EOF'
#include <stdio.h>
#include <stdlib.h>

static int answer(void)
{
	int *p = malloc(sizeof(*p));

	if (!p)
		return -1;
	*p = 42;
	return *p;
}

int main(void)
{
	printf("%d\n", answer());
	return 0;
}
EOF

lint_case analyzer "use after free" "analyzer-use-after-free" <<'EOF'
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
	int *p = malloc(sizeof(*p));

	if (!p)
		return 1;
	*p = 1;
	free(p);
	printf("%d\n", *p);
	return 0;
}
EOF

lint_case analyzer "double free" "analyzer-double-free" <<'EOF'
#include <stdlib.h>

int main(void)
{
	int *p = malloc(sizeof(*p));

	free(p);
	free(p);
	return 0;
}
EOF

lint_case analyzer "malloc result used without a NULL check" \
	"analyzer-possible-null-dereference" <<'EOF'
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
	int *p = malloc(sizeof(*p));

	*p = 1;
	printf("%d\n", *p);
	free(p);
	return 0;
}
EOF

lint_case analyzer "file descriptor leak" "analyzer-fd-leak" <<'EOF'
#include <fcntl.h>
#include <unistd.h>

static int first_byte(void)
{
	char c;
	int fd = open("/etc/hostname", O_RDONLY);

	if (fd < 0)
		return -1;
	return read(fd, &c, 1) == 1 ? c : -1;
}

int main(void)
{
	return first_byte() < 0;
}
EOF

lint_case analyzer "FILE* never closed" "analyzer-file-leak" <<'EOF'
#include <stdio.h>

static int first_char(void)
{
	FILE *f = fopen("/etc/hostname", "r");

	if (!f)
		return EOF;
	return fgetc(f);
}

int main(void)
{
	return first_char() == EOF;
}
EOF

# ---- cppcheck ----

lint_case cppcheck "array index out of bounds" "arrayIndexOutOfBounds" <<'EOF'
#include <stdio.h>

int main(void)
{
	int a[4] = { 0 };

	for (int i = 0; i <= 4; i++)
		a[i] = i;
	printf("%d\n", a[0]);
	return 0;
}
EOF


lint_case cppcheck "memcpy past the end of a buffer" "bufferAccessOutOfBounds" <<'EOF'
#include <stdio.h>
#include <string.h>

int main(void)
{
	char b[4];

	memcpy(b, "hello", 6);
	puts(b);
	return 0;
}
EOF

lint_case cppcheck "value assigned and never read" "redundantAssignment" <<'EOF'
#include <stdio.h>

int main(void)
{
	int x = 1;

	x = 2;
	x = 3;
	printf("%d\n", x);
	return 0;
}
EOF

# ---- Part 2: the pre-commit hook ----

echo
echo "Part 2: when the pre-commit hook allows or refuses a commit"

h=$tmp/hookrepo
mkdir -p "$h/scripts" "$h/src"
cp "$repo/scripts/lint.sh" "$h/scripts/"
cp -r "$repo/.githooks" "$repo/.checkpatch.conf" "$h/"
# lint.sh finds checkpatch and the cross gcc under buildroot/, so point
# the throwaway repo at the real one.
[ -e "$repo/buildroot" ] && ln -s "$repo/buildroot" "$h/buildroot"
echo buildroot > "$h/.gitignore"

good='#include <stdio.h>

static int twice(int n)
{
	return 2 * n;
}

int main(void)
{
	printf("%d\n", twice(21));
	return 0;
}'
bad='#include <stdio.h>
#include <stdlib.h>

static int twice(int n)
{
	int *p = malloc(sizeof(*p));

	if (!p)
		return -1;
	*p = 2 * n;
	return *p;
}

int main(void)
{
	printf("%d\n", twice(21));
	return 0;
}'
echo "$good" > "$h/src/demo.c"

g() { git -C "$h" "$@"; }
g init -q
g config user.name selftest
g config user.email selftest@localhost
g config core.hooksPath .githooks
g add -A
g commit -q --no-verify -m base

# hook_case NAME WANT [ENV=VALUE] -- commit-args. WANT is allowed or
# refused; a refused commit must also leave HEAD where it was.
hook_case() {
	local name=$1 want=$2 before out rc ok=0
	shift 2
	before=$(g rev-parse HEAD)
	out=$(cd "$h" && env "$@" 2>&1)
	rc=$?
	if [ "$want" = allowed ] && [ $rc -eq 0 ]; then
		ok=1
	elif [ "$want" = refused ] && [ $rc -ne 0 ] &&
	     [ "$(g rev-parse HEAD)" = "$before" ]; then
		ok=1
	fi
	result $ok hook "$name -> $want" "$out"
	g reset -q --hard
}

echo notes > "$h/notes.txt"
g add notes.txt
hook_case "commit with no C changes skips lint" allowed \
	git commit -m notes

echo "// a harmless comment" >> "$h/src/demo.c"
g add src/demo.c
hook_case "clean C change" allowed git commit -m clean

echo "$bad" > "$h/src/demo.c"
g add src/demo.c
hook_case "C change with a memory leak" refused git commit -m bad

echo "$bad" > "$h/src/demo.c"
g add src/demo.c
echo "$good" > "$h/src/demo.c"
hook_case "bad code staged, fixed only on disk" refused \
	git commit -m bad-staged

echo "$good" > "$h/src/demo.c"
echo "// staged and clean" >> "$h/src/demo.c"
g add src/demo.c
echo "$bad" > "$h/src/demo.c"
hook_case "clean code staged, bad only on disk" allowed \
	git commit -m good-staged

echo "// another comment" >> "$h/src/demo.c"
g add src/demo.c
hook_case "a lint tool is missing (fails closed)" refused \
	CHECKPATCH=/nonexistent/checkpatch.pl git commit -m no-tool

echo "$bad" > "$h/src/demo.c"
g add src/demo.c
hook_case "--no-verify bypasses the hook" allowed \
	git commit --no-verify -m bypass

echo
echo "$npass passed, $nfail failed"
[ $nfail -eq 0 ]
