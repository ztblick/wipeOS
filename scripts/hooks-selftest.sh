#!/usr/bin/env bash
# Self-test for the Claude Code hooks in .claude/hooks/ (D37). Each case
# feeds a hook the JSON Claude Code would send and checks what the hook
# decides: block, ask or pass. The repo is not touched; the index check
# runs against a temporary copy of context/.
#
# Part 1: guard-lint.py, the lint bypass guard (D34).
# Part 2: guard-build.py, the build-safety guard (D35).
# Part 3: check-index.py, the Stop hook for context/INDEX.md (D36).
# lint-c.sh has its own cases in scripts/lint-selftest.sh.
#
# Usage:  scripts/hooks-selftest.sh [-v]
#   -v  print every case, not just the failures
# Exit: 0 if every case passes, 1 otherwise.

set -uo pipefail

verbose=0
[ "${1:-}" = -v ] && verbose=1

repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "selftest: run this inside the wipeOS repo" >&2
	exit 2
}
# From buildroot/, git finds Buildroot's checkout instead.
[ -f "$repo/.claude/hooks/guard-build.py" ] ||
	repo=$(git -C "$repo/.." rev-parse --show-toplevel 2>/dev/null)
[ -f "$repo/.claude/hooks/guard-build.py" ] || {
	echo "selftest: can't find the wipeOS repo" >&2
	exit 2
}
hooks=$repo/.claude/hooks

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

# The KVM rule checks this device. Absent by default, so results don't
# depend on the host; the KVM-present cases point it at a real file.
no_kvm=$tmp/no-kvm
touch "$tmp/kvm"

ncases=0
nfail=0

# outcome RC STDOUT: block, ask, pass, or what went wrong.
outcome() {
	if [ "$1" = 2 ]; then
		echo block
	elif [ "$1" = 0 ] && [ -z "$2" ]; then
		echo pass
	elif [ "$1" = 0 ] && grep -q '"permissionDecision": "ask"' <<<"$2"; then
		echo ask
	elif [ "$1" = 0 ] && grep -q '"systemMessage"' <<<"$2"; then
		echo warn
	else
		echo "error (exit $1)"
	fi
}

report() { # report WANT GOT LABEL OUTPUT
	ncases=$((ncases + 1))
	if [ "$1" != "$2" ]; then
		nfail=$((nfail + 1))
		printf '  FAIL  %s: want %s, got %s\n' "$3" "$1" "$2"
		[ -n "$4" ] && sed 's/^/        | /' <<<"$4"
	elif [ $verbose = 1 ]; then
		printf '  ok    %s: %s\n' "$3" "$1"
	fi
}

# hook WANT HOOK LABEL JSON [ENV=VALUE...]: pipe JSON into HOOK, with the
# extra environment, and check it decides WANT.
hook() {
	local want=$1 h=$2 label=$3 json=$4 out err rc got
	shift 4
	out=$(env CLAUDE_PROJECT_DIR="$repo" GUARD_BUILD_KVM_DEVICE="$no_kvm" \
		"$@" python3 "$hooks/$h" <<<"$json" 2>"$tmp/err")
	rc=$?
	err=$(cat "$tmp/err")
	got=$(outcome $rc "$out")
	report "$want" "$got" "$h: $label" "$out$err"
}

bash_json() {
	python3 -c 'import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$1"
}

lint() { hook "$1" guard-lint.py "$2" "$(bash_json "$2")"; }
build() { hook "$1" guard-build.py "$2" "$(bash_json "$2")" "${@:3}"; }
both() { lint "$1" "$2"; build "$1" "$2"; }

# edit_json TOOL FILE OLD NEW: the JSON for an Edit, MultiEdit or Write.
edit_json() {
	python3 -c 'import json, sys
tool, path, old, new = sys.argv[1:]
ti = {"file_path": path}
if tool == "Edit":
    ti.update(old_string=old, new_string=new)
elif tool == "MultiEdit":
    ti["edits"] = [{"old_string": "x", "new_string": "y"},
                   {"old_string": old, "new_string": new}]
else:
    ti["content"] = new
print(json.dumps({"tool_name": tool, "tool_input": ti}))' "$@"
}

# ---- Part 1: guard-lint.py ----

echo "Part 1: lint guard"

lint block 'git commit --no-verify -m x'
lint block 'git commit --no-veri -m x'
lint block 'git push --no-v'
lint block 'git commit -n -m x'
lint block 'git commit -anm x'
lint block 'git config core.hooksPath /tmp/hooks'
lint block 'git config --unset core.hooksPath'
lint block 'git -c core.hooksPath=/dev/null commit -m x'
lint block 'GIT_CONFIG_COUNT=1 git commit -m x'
lint block 'echo "{\"disableAllHooks\": true}" > x.json'
lint block 'rm .githooks/pre-commit'
lint block 'echo x > scripts/lint.sh'
lint block 'cp x .checkpatch.conf'
lint block 'chmod +x .claude/hooks/guard-build.py'
lint block 'sed -i s/a/b/ .git/config'
lint block 'rm .git/hooks/pre-commit'
lint block 'echo x >> scripts/hooks-selftest.sh'
lint block 'python3 -c x > .claude/x'
lint block 'python3 -c "open(1)" .claude/hooks/guard-build.py'
lint block 'python3 .claude/hooks/guard-build.py .claude/settings.json'
lint block 'echo "unbalanced'

lint pass 'git commit -m "Fix -n handling"'
lint pass 'git commit -mn'
lint pass 'git config core.hooksPath .githooks'
lint pass 'git config core.hooksPath'
lint pass 'python3 .claude/hooks/guard-build.py'
lint pass 'python .claude/hooks/check-index.py'
lint pass 'cat .claude/settings.json'
lint pass 'git add .claude/settings.json scripts/hooks-selftest.sh'
lint pass 'scripts/lint.sh'
lint pass 'bash scripts/lint-selftest.sh'
lint pass 'scripts/hooks-selftest.sh'
lint pass 'bash scripts/hooks-selftest.sh -v'

src=$repo/src/stub/util.c
supp='// cppcheck-suppress nullPointer ; checked above'
prag='#pragma GCC diagnostic ignored "-Wformat"'
hook ask guard-lint.py "Edit adds a cppcheck-suppress" \
	"$(edit_json Edit "$src" 'int x;' "$supp
int x;")"
hook ask guard-lint.py "MultiEdit adds a pragma" \
	"$(edit_json MultiEdit "$src" 'int x;' "$prag")"
hook ask guard-lint.py "Write of a new file with a pragma" \
	"$(edit_json Write "$repo/src/stub/zz-new.c" '' "$prag")"
hook pass guard-lint.py "Edit without a suppression" \
	"$(edit_json Edit "$src" 'int x;' 'int y;')"
hook pass guard-lint.py "Edit keeps an existing suppression" \
	"$(edit_json Edit "$src" "$supp" "$supp
")"
hook pass guard-lint.py "suppression outside src/ is not checked" \
	"$(edit_json Edit "$repo/docs/notes.c" 'x' "$supp")"

# ---- Part 2: guard-build.py ----

echo "Part 2: build guard"

# Deny: KVM flags, with no KVM device.
build block 'qemu-system-x86_64 -enable-kvm -m 1G'
build block 'qemu-system-x86_64 -accel kvm -m 1G'
build block 'qemu-system-x86_64 -accel=kvm -m 1G'
build block 'qemu-system-x86_64 -machine q35,accel=kvm -m 1G'
build block 'qemu-system-x86_64 -M accel=kvm:tcg -m 1G'
build block 'qemu-system-x86_64 -cpu host -m 1G'
build block 'timeout 300 qemu-system-x86_64 -cpu host,pmu=off'
# The same flags pass when the device exists.
build pass 'qemu-system-x86_64 -enable-kvm -m 1G' \
	GUARD_BUILD_KVM_DEVICE="$tmp/kvm"
build pass 'qemu-system-x86_64 -machine accel=kvm -cpu host' \
	GUARD_BUILD_KVM_DEVICE="$tmp/kvm"

# Deny: Windows programs and filesystem.
build block 'explorer.exe .'
build block '/mnt/c/Windows/System32/notepad.exe x'
build block 'powershell -c Get-Date'
build block 'pwsh'
build block 'cmd.exe /c dir'
build block 'wsl.exe --list'
build block 'timeout 5 cmd.exe /c dir'
build block 'cp report.txt /mnt/c/Users/zach/Downloads/'
build block 'cd /mnt/c'
build block 'ls /mnt/d/'
build block 'tar -cf x.tar --directory=/mnt/c/x .'
build block 'bash -c "ls /mnt/c/"'
build block 'echo "unbalanced'

# Ask: cleaning the build.
build ask 'make clean'
build ask 'cd buildroot && make clean'
build ask 'make -C buildroot clean'
build ask 'make clean all'
build ask 'make distclean'
build ask 'make linux-dirclean'
build ask 'nice make -j8 wipeos-stub-dirclean'
build ask 'bash -c "cd buildroot && make clean"'

# Ask: toolchain rebuild.
build ask 'make toolchain-rebuild'
build ask 'make toolchain-buildroot-reconfigure'
build ask 'make host-gcc-final-rebuild'
build ask 'make host-binutils-reinstall'
build ask 'make glibc-rebuild'
build ask 'make linux-headers-reconfigure'

# Ask: deleting build output.
build ask 'rm -rf output'
build ask 'rm -rf buildroot/output/'
build ask 'rm -rf output/build/linux-6.12'
build ask 'cd buildroot && rm -rf out*'
build ask 'rm -rf ~/wipeOS/buildroot'
build ask 'rm -r ../buildroot/'

# Ask: system packages.
build ask 'apt install qemu-system-x86'
build ask 'apt-get update'
build ask 'aptitude search qemu'
build ask 'dpkg -i x.deb'
build ask 'snap install jq'
build ask 'pip install requests'
build ask 'pip3 install --user requests'
build ask 'python3 -m pip install requests'
build ask 'python -m pip install requests'
build ask 'npm install -g typescript'
build ask 'npm install --global typescript'
build ask 'npm i -g typescript'

# Ask: root.
build ask 'sudo ls /root'
build ask 'sudo make install'

# Pass: what CLAUDE.md allows. Acceptance test 5 runs through both guards.
both pass 'cd ~/wipeOS/buildroot && make wipeos-stub-rebuild && make'
both pass 'make linux-rebuild'
both pass 'scripts/run.sh --no-build --mem 3'
both pass 'git status'
both pass 'scripts/lint.sh'
build pass 'make'
build pass 'make -j8 host-qemu-rebuild'
build pass 'make savedefconfig && make linux-update-defconfig'
build pass 'timeout 600 qemu-system-x86_64 -m 1G -cpu max -nographic'
build pass 'scripts/run.sh --mode dev --mem 4 --pages 4k'
build pass 'rm -f logs/run-2026-10-23-1200.log'
build pass 'rm -rf /tmp/claude-1000/scratch/x'
build pass 'ls /mnt/wsl'
build pass 'dpkg -l qemu-system-x86'
build pass 'snap list'
build pass 'pip list'
build pass 'npm install'
build pass 'grep -rn enable-kvm CLAUDE.md'
# The acceptance tests' own commands: the JSON is one quoted word.
build pass "echo '{\"command\":\"qemu-system-x86_64 -enable-kvm\"}' | python3 .claude/hooks/guard-build.py"
build pass "echo '{\"command\":\"cp a /mnt/c/x\"}' | python3 .claude/hooks/guard-build.py"
hook pass guard-build.py "ignores tools other than Bash" \
	'{"tool_name":"Edit","tool_input":{"command":"make clean"}}'

# ---- Part 3: check-index.py ----

echo "Part 3: index check"

# A throwaway repo with a copy of context/ and the index script, since
# context_index.py finds the repo root with git.
c=$tmp/ctx
mkdir -p "$c/scripts"
cp -r "$repo/context" "$c/"
cp "$repo/scripts/context_index.py" "$c/scripts/"
git -C "$c" init -q
(cd "$c" && python3 scripts/context_index.py >/dev/null)

stop() { # stop WANT LABEL ACTIVE [ENV=VALUE...]
	local want=$1 label=$2 active=$3
	shift 3
	hook "$want" check-index.py "$label" \
		"{\"hook_event_name\":\"Stop\",\"stop_hook_active\":$active}" \
		CLAUDE_PROJECT_DIR="$c" "$@"
}

stop pass "fresh index" false
stop pass "fresh index, on a retry" true

cat > "$c/context/questions/zz-scratch.md" <<'EOF'
---
title: "Scratch"
status: open
group: design
---

# Scratch
EOF
stop block "stale index" false
stop warn "stale index, on a retry" true
rm "$c/context/questions/zz-scratch.md"
stop pass "fresh again after the record is removed" false

echo "no frontmatter" > "$c/context/questions/zz-broken.md"
stop block "check can't run (bad record)" false
stop warn "check can't run, on a retry" true
rm "$c/context/questions/zz-broken.md"

stop block "CLAUDE_PROJECT_DIR not set" false CLAUDE_PROJECT_DIR=
hook block check-index.py "input is not JSON" 'not json' CLAUDE_PROJECT_DIR="$c"

# From buildroot/ (its own git repo) the hook must still check our index.
if [ -d "$repo/buildroot/.git" ]; then
	out=$(cd "$repo/buildroot" && CLAUDE_PROJECT_DIR="$c" python3 \
		"$hooks/check-index.py" <<<'{"stop_hook_active":false}' 2>&1)
	rc=$?
	report pass "$(outcome $rc "$out")" \
		"check-index.py: run from buildroot/" "$out"
fi

echo
echo "$ncases cases, $nfail failed"
[ $nfail -eq 0 ]
