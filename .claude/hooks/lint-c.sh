#!/usr/bin/env bash
# Claude Code PostToolUse hook (registered in .claude/settings.json):
# after Claude edits or writes a C file under src/, lint what changed in
# it with scripts/lint.sh, the same checks the pre-commit hook enforces,
# and hand any findings back to Claude.
#
# Exit 0: not a C file under src/, or lint is clean. Claude sees nothing.
# Exit 2: lint found problems, or couldn't run. Claude Code shows stderr
#         to Claude. The edit has already happened; this shapes Claude's
#         next step rather than undoing anything.
#
# Test without Claude Code by piping in the JSON it would send:
#   echo '{"tool_input":{"file_path":"'"$PWD"'/src/stub/util.c"}}' |
#     CLAUDE_PROJECT_DIR=$PWD .claude/hooks/lint-c.sh; echo "exit $?"

set -uo pipefail

repo=${CLAUDE_PROJECT_DIR:-}
if [ -z "$repo" ]; then
	echo "Lint hook: CLAUDE_PROJECT_DIR is not set, so this edit" \
	     "was not linted." >&2
	exit 2
fi

# The edited file's path, from the JSON Claude Code sends on stdin. perl
# and its JSON::PP module are already here for checkpatch, so this adds
# no dependency.
file=$(perl -MJSON::PP -0777 -ne \
	'my $d = decode_json($_); print $d->{tool_input}{file_path} // ""') || {
	echo "Lint hook: could not read the hook input, so this edit" \
	     "was not linted." >&2
	exit 2
}

case $file in
"$repo"/src/*.c | "$repo"/src/*.h) ;;
*) exit 0 ;;
esac
[ -f "$file" ] || exit 0

rel=${file#"$repo"/}
# Hooks run in the shell's current directory. lint.sh finds the repo with
# git rev-parse, which from buildroot/ (a separate git repo) finds
# Buildroot's checkout instead, so start from the project root.
cd "$repo" || {
	echo "Lint hook: could not cd to $repo, so the change to $rel" \
	     "was not linted." >&2
	exit 2
}
out=$("$repo/scripts/lint.sh" --changed "$file" 2>&1)
rc=$?
case $rc in
0)
	exit 0
	;;
1)
	{
		echo "scripts/lint.sh found problems in the uncommitted" \
		     "changes to $rel. The pre-commit hook will refuse a" \
		     "commit until they are fixed, or suppressed in the code" \
		     "with a comment giving the reason."
		echo "$out"
	} >&2
	exit 2
	;;
*)
	{
		echo "scripts/lint.sh could not run (exit $rc), so the change" \
		     "to $rel is unchecked:"
		echo "$out"
	} >&2
	exit 2
	;;
esac
