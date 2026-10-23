# Plan: build-safety guard and index check (no key result; tooling)

Implementation plan for two Claude Code hooks: a PreToolUse guard that enforces CLAUDE.md's build and environment rules, and a Stop hook that keeps `context/INDEX.md` current. Written 2026-10-23 from a design discussion with Zach.

Read this whole file before starting, together with `CLAUDE.md` and the records it points to in `context/INDEX.md`. Then do step 0, the preflight, before changing anything.

## Goal

The rules in CLAUDE.md's "Development environment" section are enforced by a hook instead of relying on Claude to remember them. Plan mode removed Zach's approval prompts, so a forgotten `make clean` would cost a toolchain rebuild with nobody watching. A second hook stops a turn from ending while `context/INDEX.md` is stale, because every session imports it. A self-test lets Zach rerun every hook check with one command. The lint guard Zach added on 2026-10-23 (`.claude/hooks/guard-lint.py`) is recorded as a decision.

**Out of scope:** CI, the record-rules checker, the design-gate subagent, the context sweep, any change to `scripts/lint.sh`, and any rule not listed in Decision 2.

## Constraints from existing decisions

- **D33:** C lint runs through `scripts/lint.sh`; the pre-commit hook and `.claude/hooks/lint-c.sh` call it. Nothing here weakens it.
- **D23:** tests use the system `qemu-system-x86_64`; `scripts/run.sh` must keep working unchanged.
- **D3:** hooks are dev tooling only. Nothing is added to the image; `bzImage` is not affected.
- **The lint guard:** it blocks shell commands that change files under `.claude/`, and the Edit tool must ask before touching `.claude/hooks/**` and `.claude/settings.json`. That shapes Decision 4 below.

## Decisions made for this plan

Settled with Zach in chat. In the last step, record each one in `context/decisions/` as `accepted`, with `decided_in` set to this file's path. They take the next free numbers, D34 onward, in the order below.

### 1. Lint bypass guard (already built; record only)

`.claude/hooks/guard-lint.py`, a PreToolUse hook on Bash and on Edit, Write and MultiEdit, keeps every route around the lint closed. It extends D33.

- **Bash, blocked (exit 2):**
  - `--no-verify` and any abbreviation git accepts, and `-n` on `git commit`;
  - `core.hooksPath` set to anything but `.githooks`, or unset, through `git config`, `git -c` or `GIT_CONFIG_*` variables;
  - `disableAllHooks`;
  - shell commands that change `.githooks/`, `scripts/lint*.sh`, `.checkpatch.conf`, `.claude/`, `.git/config` or `.git/hooks/`. Reading these files, running the lint scripts, and `git add` or `git commit` stay allowed.
- **Edits to C files under `src/` that add a suppression** (a `cppcheck-suppress` comment, or a GCC or clang diagnostic pragma): the hook returns "ask", so Zach sees each one.
- **Fails closed:** registered with `onFailure: "block"`, so a crashing guard blocks the call.

*Alternatives considered:* allowing suppressions automatically when they carry a reason comment (no prompt, but no human sees the call either); relying on the pre-commit hook alone (one `--no-verify` skips it).

### 2. Build-safety guard

A new PreToolUse hook on Bash, `.claude/hooks/guard-build.py`, separate from the lint guard so each script has one purpose. It enforces the "Development environment" rules in CLAUDE.md. The split follows the wording of those rules: what CLAUDE.md says "never" is denied, and what it says to do "only after asking" goes to Zach as an "ask".

**Deny (exit 2, reason to Claude):**

| Rule | Matches |
| --- | --- |
| KVM flags on a host without KVM | `-enable-kvm`, `-accel kvm`, `-accel=kvm`, `accel=kvm` in `-machine`, `-cpu host`, but only when `/dev/kvm` is absent. On the laptop it always is; on a future x86 host with KVM the rule lifts by itself |
| Windows executables | a command word ending in `.exe`, and `powershell`, `pwsh`, `cmd.exe`, `wsl.exe` |
| Windows filesystem | any word under `/mnt/<drive letter>/` |

**Ask Zach (JSON `permissionDecision: "ask"`, with the reason):**

| Rule | Matches |
| --- | --- |
| Cleaning the build | `make` with a target `clean`, `distclean` or `<pkg>-dirclean` |
| Toolchain rebuild | `make` with a `-rebuild`, `-reconfigure` or `-reinstall` target for `toolchain*`, `host-gcc*`, `host-binutils*`, `glibc` or `linux-headers` |
| Deleting build output | `rm` with any argument whose path ends in `output`, contains `output/`, or names the `buildroot` checkout |
| System packages | `apt`, `apt-get`, `aptitude`, `dpkg -i`, `snap install`, `pip`/`pip3 install`, `python -m pip install`, `npm install -g`/`--global`, `npm i -g` |
| Root | any `sudo` |

`sudo` extends CLAUDE.md, which doesn't mention it. Every system change goes through it, and Claude has no reason to need it here.

Everything else passes untouched. That includes `make`, `make <pkg>-rebuild`, `make linux-rebuild`, `make wipeos-stub-rebuild`, `scripts/run.sh` with any options, and plain `qemu-system-x86_64` without KVM flags. A toolchain rebuild caused indirectly, by a changed defconfig, can't be seen from the command line. That case stays a CLAUDE.md rule.

*Alternatives considered:* one combined guard script (shorter settings, but lint and build rules change for different reasons); deny everything (a legitimate `make clean` would need Zach to run it himself); ask for everything (the KVM and Windows rules have no legitimate exception on this host).

### 3. Index check at Stop

A Stop hook, `.claude/hooks/check-index.py`, runs `scripts/context_index.py --check` from the project root.

- **Index stale:** the hook exits 2 with "context/INDEX.md is out of date; run scripts/context_index.py", so Claude regenerates it before the turn ends.
- **Index still stale on the retry** (`stop_hook_active` is true): the hook lets the turn end and shows Zach a warning through `systemMessage`, so a broken index can't loop the session.
- **The check can't run** (exit 2 from `context_index.py`, a missing script, bad input): treated like a stale index, but the message says the check failed.

*Alternatives considered:* a pre-commit check instead (catches staleness only at commit time, after sessions have already imported the stale index); regenerating the index inside the hook itself (hides from Claude that it changed `context/` without updating the index).

### 4. Conventions for our hooks

- **Registration.** New hooks are Python, registered in exec form as `"command": "python3", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.py"]`. They need no executable bit, which Claude can't set inside `.claude/` because the lint guard blocks `chmod` there. PreToolUse hooks also set `"onFailure": "block"`.
- **Project root.** Every hook works from `$CLAUDE_PROJECT_DIR`, never from the current directory. Claude often `cd`s into `buildroot/`, which is a separate git repository, so anything that calls `git rev-parse` from there finds the wrong repo.
- **Self-test.** `scripts/hooks-selftest.sh` feeds each hook the JSON Claude Code would send, for a fixed table of cases, and exits 0 only if every case gives the expected result: block, ask or pass. It joins the lint guard's protected paths and its list of runnable scripts, and the `ask` list in `.claude/settings.json`.
- **Running hooks by hand.** The lint guard currently blocks `python3 .claude/hooks/<name>.py`, because `python3` isn't on its list of read-only commands. Running a hook script is not changing it, so the guard allows `python3` (or `python`) when the only protected word in the command is a script under `.claude/hooks/` in the first argument position. `python3 -c`, redirects into `.claude/`, and every other write stay blocked.

*Alternatives considered:* bash hooks registered by path (needs the executable bit); registering with `"command"` pointing at the script (same); a test harness in Python (fine either way; see Delegated).

## Delegated to Claude Code

List every choice you make in Outcome, one line each with the reason.

- Internal structure, function names and message wording of the new hook scripts.
- Whether `scripts/hooks-selftest.sh` is bash or calls a small Python helper, and how its case table is laid out.
- The exact test cases, beyond the ones required in Steps and Acceptance tests.
- How the KVM rule is made testable without real KVM. For example, an environment variable naming the device to check, read from the hook's own environment, which a Bash command can't set for the hook.

## Stop conditions

Everything on CLAUDE.md's "Design decisions are mine" list is reserved, unless this plan settles it above or delegates it. Stop when any of these comes up:

- a reserved choice the plan doesn't settle;
- a rule in Decision 2 can't be written without blocking or asking on a command that Acceptance test 5 requires to pass;
- `claude --version` is older than 2.1.295, the first version that honors `onFailure`;
- Claude Code doesn't pass `stop_hook_active` to Stop hooks in this version, or runs hooks somewhere other than described in Decision 4;
- a step can't pass its acceptance test without changing something outside this plan;
- the plan contradicts an accepted decision, or the code contradicts the plan.

**How to stop.**

1. Write the question as a `proposed` decision in `context/decisions/`, with your recommendation as the decision and two or three alternatives with their tradeoffs.
2. Set Outcome's status to `blocked`, naming the decision, and rerun `scripts/context_index.py`.
3. End your turn with a short message naming the decision, and wait.

Don't continue with work that depends on the answer, and don't guess.

**Expected permission prompts.** These files are protected, so Claude Code will ask Zach before changing them:

- creating `.claude/hooks/guard-build.py` and `.claude/hooks/check-index.py`;
- editing `.claude/hooks/guard-lint.py` and `.claude/settings.json`;
- editing `.claude/hooks/lint-c.sh`, if step 1 finds it needs the fix.

That is intended: these are guardrails. Any other prompt during this plan means something is off; mention it in Outcome.

## Component specs

### `.claude/hooks/guard-build.py`

- Reads the PreToolUse JSON from stdin. Acts only on `tool_name` `Bash`; anything else exits 0.
- Splits the command into simple commands the way `guard-lint.py` does, with `shlex` and punctuation characters, stripping leading `VAR=value` assignments. Matches `make` targets and `rm` arguments per simple command, so `cd buildroot && make clean` is caught.
- **Deny:** exit 2, with a one-line reason on stderr beginning `Build guard:`.
- **Ask:** print one JSON object, `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "Build guard: ..."}}`, then exit 0.
- **Pass:** exit 0 with no output.
- Unparseable commands (unbalanced quotes) are denied, as in the lint guard.
- A docstring at the top in the same style as `guard-lint.py`: what it checks, exit codes, how to test it by hand, and its limits. It matches text, so it stops the obvious and the accidental, not a determined workaround.

### `.claude/hooks/check-index.py`

- Reads the Stop JSON from stdin, changes to `$CLAUDE_PROJECT_DIR`, and runs `python3 scripts/context_index.py --check`.
- Behaves as in Decision 3. When the turn is allowed to end with a warning, it prints one JSON object with `systemMessage` and exits 0.
- Fast: no network, nothing beyond the one check.

### `.claude/hooks/guard-lint.py` (change)

- Allow `python3`/`python` running a script under `.claude/hooks/`, per Decision 4.
- Add `scripts/hooks-selftest.sh` to the protected paths and to the runnable scripts.
- No other change. The cases in its docstring and all existing behavior stay as they are.

### `.claude/settings.json` (change)

- PreToolUse on `Bash`: add `guard-build.py` next to the existing `guard-lint.py` entry, in the exec form from Decision 4, with `timeout` 10, `onFailure` `"block"` and a status message.
- Stop: a new entry for `check-index.py`, in exec form, with `timeout` 30. `onFailure` doesn't apply to Stop hooks.
- `ask`: add `Edit(/scripts/hooks-selftest.sh)`.
- Leave the existing `guard-lint.py` and `lint-c.sh` registrations as they are.

### `scripts/hooks-selftest.sh`

- Runs from anywhere in the repo: it resolves the repo root and works from there.
- For each case, pipes the JSON into the hook with `CLAUDE_PROJECT_DIR` set, and compares the result (exit code, and whether stdout holds an "ask" decision) with the expected one.
- Prints one line per failed case, then `N cases, M failed`, and exits 1 if any failed.
- Covers, at least:
  - **guard-lint:** the block and allow cases from Decision 1, including `git commit -m "Fix -n handling"` (allow), `git config core.hooksPath .githooks` (allow), `python3 .claude/hooks/guard-build.py` (allow) and `python3 -c x > .claude/x` (block); and the suppression "ask" for Edit, MultiEdit and Write.
  - **guard-build:** every row of both tables in Decision 2, the KVM rule with the device present and absent, and the pass list in Acceptance test 5.
  - **check-index:** fresh index (pass), stale index (block), stale with `stop_hook_active` (pass with a `systemMessage`). Use a temporary copy of the repo's `context/` and scripts so the real index is never touched.

## Steps

Work through the steps in order without stopping for review. None of them changes the image.

0. **Preflight.** Check this plan against `context/INDEX.md`, D33, `CLAUDE.md` and the current hooks and settings. Run `claude --version`. Confirm from the Claude Code hooks reference that Stop hooks receive `stop_hook_active`, and where command hooks run. If anything conflicts or is missing, stop as above, before writing any code.
1. **Check the existing lint hook from `buildroot/`.**
   - With the Bash tool's working directory at `~/wipeOS/buildroot`, make a trivial whitespace-only edit to `src/stub/util.c` and see whether `lint-c.sh` lints it correctly.
   - Revert the edit.
   - If it fails because `scripts/lint.sh` resolves the buildroot repository, add a `cd "$repo"` to `lint-c.sh` before it calls `lint.sh` (Decision 4, project root), and recheck. Record the finding in Outcome either way.
2. **Build guard:** write `guard-build.py`.
3. **Index check:** write `check-index.py`.
4. **Lint guard change**, as specified.
5. **Self-test:** write `scripts/hooks-selftest.sh` and make it pass. If a case shows a bug in one of the hooks, fix the hook, not the expected result.
6. **Register** the hooks in `.claude/settings.json`, as specified.
7. **Docs.**
   - In `CLAUDE.md`:
     - add a sentence under "Development environment" saying these rules are enforced by `.claude/hooks/guard-build.py`;
     - add `.claude/hooks/` and `scripts/hooks-selftest.sh` to Project layout;
     - add `scripts/hooks-selftest.sh` to Commands.

     Change nothing else in CLAUDE.md.
   - In `README.md`, add the self-test command where the lint commands are documented, or under "Useful checks" if they aren't there.
8. **Record.**
   - Write Decisions 1–4 to `context/decisions/` as D34–D37, `accepted`, with `decided_in` set to this file.
   - Add any open question you ran into to `context/questions/`.
   - No key result covers this plan, so don't tick anything in `docs/okrs.md`.
   - Rerun `scripts/context_index.py`.
   - Fill in Outcome.

## Acceptance tests

Commands Zach can run himself, from `~/wipeOS`. Each one states its expected result.

1. `scripts/hooks-selftest.sh` exits 0 and reports 0 failed.
2. This prints a JSON "ask" decision whose reason starts `Build guard:`, and exits 0:
   ```bash
   echo '{"tool_name":"Bash","tool_input":{"command":"cd buildroot && make clean"}}' | python3 .claude/hooks/guard-build.py; echo "exit $?"
   ```
3. The same with `qemu-system-x86_64 -enable-kvm -m 1G` exits 2 on the laptop.
4. The same with `cp report.txt /mnt/c/Users/zach/Downloads/` exits 2.
5. These each exit 0 with no output from both guards:
   - `cd ~/wipeOS/buildroot && make wipeos-stub-rebuild && make`
   - `make linux-rebuild`
   - `scripts/run.sh --no-build --mem 3`
   - `git status`
   - `scripts/lint.sh`
6. `echo '{"tool_name":"Bash","tool_input":{"command":"python3 .claude/hooks/guard-build.py"}}' | .claude/hooks/guard-lint.py; echo "exit $?"` exits 0.
7. **Live, in a new Claude Code session:** ask Claude to run `make clean` in `buildroot/`. A permission prompt appears with the build guard's reason. Decline it.
8. **Live:** copy `context/questions/TEMPLATE.md`'s template into a scratch record `context/questions/zz-scratch.md`, then send Claude any message. Before the turn ends, Claude regenerates the index. Then delete the scratch file and ask Claude to regenerate the index again.
9. **Live:** with Claude's shell in `~/wipeOS/buildroot`, an edit to a C file under `src/` is still linted by `lint-c.sh`.

## Outcome

Written by Claude Code when it finishes or stops.

- **Status:** done, 2026-10-23. Acceptance tests 1–6 pass. 7–9 are live tests for a new session. One follow-up for Zach: `scripts/hooks-selftest.sh` isn't executable yet (see Noticed).
- **Changed:**
  - `.claude/hooks/guard-build.py` (new): the build-safety guard (D35).
  - `.claude/hooks/check-index.py` (new): the Stop hook for `context/INDEX.md` (D36).
  - `.claude/hooks/guard-lint.py`: allows `python3`/`python` to run a script under `.claude/hooks/`; protects `scripts/hooks-selftest.sh` and lets it run; docstring item 4 updated to match.
  - `.claude/hooks/lint-c.sh`: `cd "$repo"` before calling `lint.sh` (step 1 finding).
  - `scripts/hooks-selftest.sh` (new): 131 cases across the three hooks.
  - `.claude/settings.json`: `guard-build.py` next to `guard-lint.py` on Bash; a Stop entry for `check-index.py`; `Edit(/scripts/hooks-selftest.sh)` added to `ask`.
  - `CLAUDE.md`: an enforcement sentence under Development environment, two Project layout rows and one Commands bullet.
  - `README.md`: a "Useful checks" paragraph with the self-test command.
  - `context/decisions/D034`–`D037` (new). `context/INDEX.md` regenerated.
- **Verified:**
  - **Preflight.** `claude --version` reports 2.1.309, at or above 2.1.295. The hooks reference (code.claude.com/docs/en/hooks) shows `stop_hook_active` in the Stop input. It says handlers "run in the current directory with Claude Code's environment", with `CLAUDE_PROJECT_DIR` set to the session's project root, which matches Decision 4. It also documents exec form with `${CLAUDE_PROJECT_DIR}` expanded in `args`, and `onFailure` from v2.1.295. No conflicts with D23, D33 or D3.
  - **Step 1: the lint hook failed from `buildroot/`.** With the shell in `~/wipeOS/buildroot`, a whitespace edit to `src/stub/util.c` made the hook report "scripts/lint.sh could not run (exit 2) … checkpatch.pl not found". `lint.sh` had resolved Buildroot's own repo. After the `cd "$repo"` fix, still from `buildroot/`, a planted unused variable was reported as `-Werror=unused-variable` and a clean edit passed. Both edits were reverted; `git status` shows `util.c` unchanged.
  - **AT1.** `bash scripts/hooks-selftest.sh` reports `131 cases, 0 failed` and exits 0. It is run through `bash` because the file isn't executable yet (see Noticed). A mutated copy with two wrong expectations reported exactly those two failures, so the harness can fail.
  - **AT2.** The command prints the "ask" JSON with "Build guard: this command runs make clean…" and exits 0.
  - **AT3.** Exits 2 ("uses -enable-kvm, but this host has no KVM").
  - **AT4.** Exits 2 ("touches /mnt/c/Users/zach/Downloads/").
  - **AT5.** In the self-test, all five commands pass through both guards with no output.
  - **AT6.** Exits 0.
  - **Live check in this session.** After registration, `ls /mnt/c/` was denied by `python3 ${CLAUDE_PROJECT_DIR}/.claude/hooks/guard-build.py`, so the new registration and exec form work.
  - **AT7–9.** Not run. They need a new session. AT9's behaviour was shown live in step 1.
  - **Lint self-test.** `scripts/lint-selftest.sh` reports 35 passed, 0 failed after the `lint-c.sh` change.
- **Image size:** not affected. Nothing under `src/`, `configs/` or `package/` changed, and no build was run.
- **Choices made within delegated scope:**
  - **KVM testability.** The guard checks `GUARD_BUILD_KVM_DEVICE` if it is set, else `/dev/kvm`. The variable is read from the hook's own environment, which a Bash command can't set. The self-test points it at a missing path by default, so results don't depend on the host.
  - **Word-level matching.** The guard matches words, not regexes over the raw command line. The acceptance tests' own `echo '{"command":"… -enable-kvm"}' | python3 …` commands, and `grep enable-kvm`, then pass instead of tripping the guard.
  - **Wrappers.** The guard looks through `timeout`, `env`, `nice`, `nohup`, `exec`, `command`, `time`, `stdbuf`, `xargs` and `sudo`, and recurses into `bash`/`sh -c "…"`. CLAUDE.md itself tells Claude to run QEMU under `timeout`, so `timeout 300 qemu-system-x86_64 -cpu host` must be caught.
  - **"Ends in output".** Read as the last path component, not a string suffix, so `rm myoutput` passes. A glob that could match `output` or `buildroot` asks, for example `cd buildroot && rm -rf out*`. As a side effect, `rm -rf logs/*` also asks.
  - **Windows paths.** `/mnt/<letter>` is matched at the start of a word or after `=` or `:`, so `--directory=/mnt/c/x` is caught and `/mnt/wsl` passes.
  - **Precedence.** Deny wins over ask. Ask reasons from several commands are deduplicated and joined into one prompt. Small extras: `npm --location=global`, `pip3.x`, `python3.x`.
  - **check-index.py details.** It runs the check with `sys.executable` and a 20 s timeout, from `CLAUDE_PROJECT_DIR`. Bad input JSON blocks, as the plan specifies. Without input it can't detect a retry, so it relies on Claude Code's documented cap on consecutive Stop blocks.
  - **Self-test format.** Bash, like `scripts/lint-selftest.sh`, with inline `python3` one-liners that build the JSON. The index cases run against a throwaway git repo holding a copy of `context/` and `context_index.py`, because the script finds the repo root with git. One extra case runs the Stop hook from `buildroot/`.
  - **`lint-c.sh` fix.** A failed `cd` prints a reason before exiting 2, rather than failing silently.
  - **README placement.** README has no lint commands, so "Useful checks" went in as a bold-lead paragraph before "Set up on a new machine", in the README's existing style.
- **Records written:** D34 (lint bypass guard), D35 (build-safety guard), D36 (index check at Stop), D37 (conventions for our hooks). All are `accepted`, with `decided_in: docs/plans/build-gaurd-and-index-check.md`, the file's actual name. No new open questions. No OKR ticks, since no key result covers this plan. INDEX regenerated and `--check` passes.
- **Suggested design.md changes:** none required. Optional, under Codebase design, after the first paragraph: "Dev tooling lives outside the image: `scripts/lint.sh` and the pre-commit hook lint the C code (D33), and Claude Code hooks in `.claude/hooks/` guard the lint, the build environment and the context index (D34–D37)."
- **Noticed, not touched:**
  - **Self-test not executable.** `scripts/hooks-selftest.sh` was created mode 644. Step 4 protects it before step 5 creates it, so the lint guard then blocks `chmod` on it. Run `chmod +x scripts/hooks-selftest.sh` yourself, after which AT1 runs as written. Until then, `bash scripts/hooks-selftest.sh` works.
  - **Plan file name.** The file is `build-gaurd-and-index-check.md` (typo), and it was untracked when executed. Renaming it means updating `decided_in` in D34–D37 in the same change.
  - **Lint guard friction.** The lint guard blocks some read-only uses of protected files: `cd .claude/hooks`, `sed -n` on `scripts/lint.sh`, `cp <protected> elsewhere` and `python3 -m json.tool .claude/settings.json`. Piping through `cat` works around each one.
  - **`git clean` gap.** `git clean -fdx` inside `buildroot/` would delete `output/`, which Buildroot's `.gitignore` covers. D35 doesn't catch it.
  - **`settings.json` row in CLAUDE.md.** Project layout still says `.claude/settings.json` "Don't edit it", but this plan edited it. You could change the row to say edits come only from a plan.
  - **README "Where things live".** The table doesn't list `.claude/hooks/` or the lint scripts.
  - **Stale `docs/decisions.md` references.** `docs/design.md` (intro) and `docs/okrs.md` (KR2.3 progress note) still point to `docs/decisions.md`, which `context/decisions/` replaced.
- **Suggested commit message:** `Add build-safety guard and index-check hooks with self-test; record D34–D37`