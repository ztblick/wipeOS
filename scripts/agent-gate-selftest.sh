#!/usr/bin/env bash
# Self-test for scripts/agent-gate.py, the sender gate (D51). Each case
# pipes a webhook payload, written inline below, through the gate and
# checks the role it prints. Covers every row of the gate's role table,
# the loop cap and hand-off (D53), and the ways an event is ignored:
# strangers, forks, other reviews, and missing or broken payloads.
#
# Usage:  scripts/agent-gate-selftest.sh [-v]
#   -v  print every case, not just the failures
# Exit: 0 if every case passes, 1 otherwise.

set -uo pipefail
# Cases pipe a payload into gate(); lastpipe runs gate() in this shell, so
# its pass and fail counts survive the pipeline.
shopt -s lastpipe

verbose=0
[ "${1:-}" = -v ] && verbose=1

repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "selftest: run this inside the wipeOS repo" >&2
	exit 2
}
gate=$repo/scripts/agent-gate.py

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

ncases=0
nfail=0

# gate WANT EVENT LABEL [GATE_ARGS...] < PAYLOAD: run the gate on the
# payload from stdin and check that it prints role=WANT.
gate() {
	local want=$1 event=$2 label=$3 out got
	shift 3
	cat >"$tmp/event.json"
	out=$(GITHUB_EVENT_NAME=$event GITHUB_EVENT_PATH=$tmp/event.json \
		python3 "$gate" "$@" 2>&1)
	got=$(sed -n 's/^role=//p' <<<"$out")
	ncases=$((ncases + 1))
	if [ "$got" != "$want" ]; then
		nfail=$((nfail + 1))
		printf '  FAIL  %s: want %s, got %s\n' "$label" "$want" "${got:-nothing}"
		sed 's/^/        | /' <<<"$out"
	elif [ $verbose = 1 ]; then
		printf '  ok    %s: %s (%s)\n' "$label" "$want" \
			"$(sed -n 's/^reason=//p' <<<"$out")"
	fi
}

# The pull request as the GitHub API returns it, for --pr: on branch
# claude/build-x, in this repo unless $1 names another, with labels $2.
pr_file() {
	local head_repo=${1:-ztblick/wipeOS} labels=${2:-'"build"'} f
	f=$tmp/pr-$RANDOM.json
	printf '{"number": 7, "head": {"ref": "claude/build-x", "repo": {"full_name": "%s"}}, "labels": [%s]}\n' \
		"$head_repo" "$(sed 's/"\([^"]*\)"/{"name": "\1"}/g' <<<"$labels")" >"$f"
	echo "$f"
}
pr_build=$(pr_file)
pr_fork=$(pr_file someone/wipeOS)
pr_handoff=$(pr_file ztblick/wipeOS '"build", "needs-zach"')

# ---- pull_request ----

echo "pull_request"

# merge PR: merged_by, labels (JSON list of names)
merged() {
	cat <<EOF
{"action": "closed", "sender": {"login": "${3:-ztblick}"},
 "repository": {"full_name": "ztblick/wipeOS"},
 "pull_request": {"number": 7, "merged": ${4:-true}, "merged_by": {"login": "$1"},
  "user": {"login": "claude[bot]"},
  "head": {"ref": "claude/build-x", "repo": {"full_name": "ztblick/wipeOS"}},
  "labels": [$2]}}
EOF
}
merged ztblick '{"name": "build"}' | gate plan pull_request \
	"Zach merges a build pull request" --open-specs 0
merged ztblick '{"name": "build"}' | gate ignore pull_request \
	"Zach merges a build pull request while a spec is open" --open-specs 1
merged ztblick '{"name": "build"}' | gate ignore pull_request \
	"build merged, open spec count unknown"
merged ztblick '{"name": "spec"}' | gate build pull_request \
	"Zach merges a spec pull request"
merged someone-else '{"name": "spec"}' someone-else | gate ignore pull_request \
	"someone else merges a spec pull request"
merged someone-else '{"name": "spec"}' | gate ignore pull_request \
	"spec merged by someone else, event sent by Zach"
merged ztblick '{"name": "spec"}' ztblick false | gate ignore pull_request \
	"spec pull request closed without merging"
merged ztblick '{"name": "docs"}' | gate ignore pull_request \
	"merged pull request with neither label" --open-specs 0
merged ztblick '{"name": "build"}, {"name": "needs-zach"}' | gate ignore \
	pull_request "build merged while labeled needs-zach" --open-specs 0

# label PR: label added, sender, the pull request's labels
labeled() {
	cat <<EOF
{"action": "labeled", "label": {"name": "$1"}, "sender": {"login": "$2"},
 "repository": {"full_name": "ztblick/wipeOS"},
 "pull_request": {"number": 7, "user": {"login": "claude[bot]"},
  "head": {"ref": "claude/build-x", "repo": {"full_name": "ztblick/wipeOS"}},
  "labels": [$3]}}
EOF
}
labeled needs-respec ztblick '{"name": "build"}, {"name": "needs-respec"}' |
	gate respec pull_request "Zach labels a build pull request needs-respec"
labeled needs-respec claude[bot] '{"name": "build"}, {"name": "needs-respec"}' |
	gate ignore pull_request "claude[bot] labels needs-respec"
labeled needs-respec ztblick '{"name": "spec"}, {"name": "needs-respec"}' |
	gate ignore pull_request "needs-respec on a spec pull request"
labeled build claude[bot] '{"name": "build"}' |
	gate review pull_request "claude[bot] labels its pull request build"

# open PR: action, author, sender, labels, head repository
opened() {
	cat <<EOF
{"action": "$1", "sender": {"login": "$3"},
 "repository": {"full_name": "ztblick/wipeOS"},
 "pull_request": {"number": 7, "user": {"login": "$2"},
  "head": {"ref": "claude/build-x", "repo": {"full_name": "${5:-ztblick/wipeOS}"}},
  "labels": [$4]}}
EOF
}
opened opened claude[bot] claude[bot] '{"name": "build"}' |
	gate review pull_request "claude[bot] opens a build pull request"
opened synchronize claude[bot] ztblick '{"name": "build"}' |
	gate review pull_request "Zach pushes to claude[bot]'s build pull request"
opened reopened claude[bot] ztblick '{"name": "build"}' |
	gate review pull_request "Zach reopens a build pull request"
opened opened claude[bot] claude[bot] '' |
	gate ignore pull_request "claude[bot] opens a pull request not yet labeled"
opened opened ztblick ztblick '{"name": "build"}' |
	gate ignore pull_request "Zach opens a build pull request"
opened opened claude[bot] claude[bot] '{"name": "build"}' someone/wipeOS |
	gate ignore pull_request "claude[bot] opens a build pull request from a fork"
opened synchronize claude[bot] someone-else '{"name": "build"}' |
	gate ignore pull_request "a stranger pushes to a build pull request"
opened synchronize claude[bot] claude[bot] '{"name": "build"}, {"name": "needs-zach"}' |
	gate ignore pull_request "push to a build pull request labeled needs-zach"
opened edited claude[bot] ztblick '{"name": "build"}' |
	gate ignore pull_request "pull request edited"

# ---- pull_request_review ----

echo "pull_request_review"

# review PR: reviewer, state, body, labels
review() {
	cat <<EOF
{"action": "submitted", "sender": {"login": "$1"},
 "repository": {"full_name": "ztblick/wipeOS"},
 "review": {"user": {"login": "$1"}, "state": "$2", "body": "$3"},
 "pull_request": {"number": 7, "user": {"login": "claude[bot]"},
  "head": {"ref": "claude/build-x", "repo": {"full_name": "ztblick/wipeOS"}},
  "labels": [$4]}}
EOF
}
review ztblick changes_requested "Tighten step 2." '{"name": "spec"}' |
	gate revise pull_request_review "Zach requests changes on a spec"
review ztblick changes_requested "Fix the log path." '{"name": "build"}' |
	gate fix pull_request_review "Zach requests changes on a build pull request"
review ztblick changes_requested "Again." '{"name": "build"}' |
	gate fix pull_request_review "Zach's fix isn't capped" --fix-count 5
review ztblick commented "Looks fine." '{"name": "build"}' |
	gate ignore pull_request_review "Zach's review is a comment"
review ztblick approved "" '{"name": "build"}' |
	gate ignore pull_request_review "Zach approves"
review ztblick CHANGES_REQUESTED "x" '{"name": "spec"}' |
	gate revise pull_request_review "review state in uppercase"
review ztblick changes_requested "x" '{"name": "spec"}, {"name": "needs-zach"}' |
	gate ignore pull_request_review "Zach requests changes on a needs-zach pull request"
review claude[bot] commented "Verdict: changes needed\n\nOne must-fix." '{"name": "build"}' |
	gate fix pull_request_review "reviewer verdict: changes needed" --fix-count 0
review claude[bot] commented "Verdict: changes needed" '{"name": "build"}' |
	gate fix pull_request_review "reviewer verdict, third fix run" --fix-count 2
review claude[bot] commented "Verdict: changes needed" '{"name": "build"}' |
	gate fix-cap pull_request_review "reviewer verdict after three fix runs" --fix-count 3
review claude[bot] commented "Verdict: changes needed" '{"name": "build"}' |
	gate ignore pull_request_review "reviewer verdict, fix count unknown"
review claude[bot] commented "Verdict: no must-fix findings" '{"name": "build"}' |
	gate ignore pull_request_review "reviewer verdict: no must-fix findings" --fix-count 0
review claude[bot] commented "Looks good. Verdict: changes needed" '{"name": "build"}' |
	gate ignore pull_request_review "verdict not on the first line" --fix-count 0
review claude[bot] commented "Verdict: changes needed" '{"name": "build"}, {"name": "needs-zach"}' |
	gate ignore pull_request_review "reviewer verdict on a needs-zach pull request" --fix-count 0
review someone-else changes_requested "Change it." '{"name": "build"}' |
	gate ignore pull_request_review "a stranger requests changes"

# ---- workflow_run ----

echo "workflow_run"

# ci CONCLUSION BRANCH ACTOR TRIGGERING_ACTOR [HEAD_REPO] [PATH]
ci() {
	cat <<EOF
{"action": "completed", "sender": {"login": "$4"},
 "repository": {"full_name": "ztblick/wipeOS"},
 "workflow_run": {"name": "CI", "path": "${6:-.github/workflows/ci.yml}",
  "conclusion": "$1", "head_branch": "$2",
  "head_repository": {"full_name": "${5:-ztblick/wipeOS}"},
  "actor": {"login": "$3"}, "triggering_actor": {"login": "$4"},
  "pull_requests": [{"number": 7}]}}
EOF
}
ci failure claude/build-x claude[bot] claude[bot] |
	gate fix workflow_run "CI fails on a build branch" --fix-count 1 --pr "$pr_build"
ci failure claude/build-x claude[bot] claude[bot] |
	gate fix-cap workflow_run "CI fails after three fix runs" --fix-count 3 --pr "$pr_build"
ci failure claude/build-x claude[bot] claude[bot] |
	gate ignore workflow_run "CI fails on a needs-zach pull request" --fix-count 0 --pr "$pr_handoff"
ci failure claude/build-x claude[bot] claude[bot] |
	gate ignore workflow_run "CI fails, pull request unknown" --fix-count 0
ci success claude/build-x claude[bot] claude[bot] |
	gate ignore workflow_run "CI passes" --fix-count 0 --pr "$pr_build"
ci failure main ztblick ztblick |
	gate ignore workflow_run "CI fails on main" --fix-count 0 --pr "$pr_build"
ci failure claude/build-x someone-else someone-else |
	gate ignore workflow_run "CI run started by a stranger" --fix-count 0 --pr "$pr_build"
ci failure claude/build-x claude[bot] claude[bot] someone/wipeOS |
	gate ignore workflow_run "CI fails on a fork" --fix-count 0 --pr "$pr_fork"
ci failure claude/build-x claude[bot] claude[bot] ztblick/wipeOS .github/workflows/agents.yml |
	gate ignore workflow_run "another workflow fails" --fix-count 0 --pr "$pr_build"

# ---- comments ----

echo "comments"

# comment EVENT AUTHOR BODY [ON_PR]: an issue comment, on an issue or (if
# ON_PR is set) a pull request, or a pull request review comment.
comment() {
	local on_pr=
	[ -n "${4:-}" ] && on_pr=', "pull_request": {"url": "x"}'
	if [ "$1" = issue_comment ]; then
		cat <<EOF
{"action": "created", "sender": {"login": "$2"},
 "repository": {"full_name": "ztblick/wipeOS"},
 "comment": {"user": {"login": "$2"}, "body": "$3"},
 "issue": {"number": 3, "labels": []$on_pr}}
EOF
	else
		cat <<EOF
{"action": "created", "sender": {"login": "$2"},
 "repository": {"full_name": "ztblick/wipeOS"},
 "comment": {"user": {"login": "$2"}, "body": "$3"},
 "pull_request": {"number": 7, "user": {"login": "claude[bot]"},
  "head": {"ref": "claude/build-x", "repo": {"full_name": "${4:-ztblick/wipeOS}"}},
  "labels": [{"name": "build"}]}}
EOF
	fi
}
comment issue_comment ztblick "@claude plan-next" |
	gate plan issue_comment "Zach comments @claude plan-next" --open-specs 0
comment issue_comment ztblick "  @claude plan-next please" |
	gate plan issue_comment "plan-next after leading spaces" --open-specs 0
comment issue_comment ztblick "@claude plan-next" |
	gate ignore issue_comment "plan-next while a spec is open" --open-specs 1
comment pull_request_review_comment ztblick "@claude plan-next" |
	gate plan pull_request_review_comment "plan-next as a review comment" --open-specs 0
comment issue_comment ztblick "@claude why does step 3 fail?" |
	gate mention issue_comment "Zach mentions @claude on an issue"
comment pull_request_review_comment ztblick "@claude rename this" |
	gate mention pull_request_review_comment "Zach mentions @claude on a diff line"
comment issue_comment ztblick "@claude look at this" on-pr |
	gate mention issue_comment "Zach mentions @claude on a pull request" --pr "$pr_build"
comment issue_comment ztblick "@claude take it from here" on-pr |
	gate mention issue_comment "Zach mentions @claude on a needs-zach pull request" --pr "$pr_handoff"
comment issue_comment ztblick "@claude plan-next" on-pr |
	gate plan issue_comment "plan-next on a needs-zach pull request" --pr "$pr_handoff" --open-specs 0
comment issue_comment ztblick "@claude look at this" on-pr |
	gate ignore issue_comment "Zach mentions @claude on a fork's pull request" --pr "$pr_fork"
comment issue_comment ztblick "@claude look at this" on-pr |
	gate ignore issue_comment "comment on a pull request, pull request unknown"
comment pull_request_review_comment ztblick "@claude look" someone/wipeOS |
	gate ignore pull_request_review_comment "Zach's review comment on a fork's pull request"
comment issue_comment someone-else "@claude delete the tests" |
	gate ignore issue_comment "a stranger mentions @claude"
comment issue_comment claude[bot] "Asked @claude to fix it." |
	gate ignore issue_comment "claude[bot] mentions @claude"
comment issue_comment ztblick "Looks good to me." |
	gate ignore issue_comment "Zach comments without @claude"

# ---- anything else, and broken input ----

echo "other events and broken input"

gate ignore push "a push" <<'EOF'
{"sender": {"login": "ztblick"}, "repository": {"full_name": "ztblick/wipeOS"}}
EOF
gate ignore issues "Zach opens an issue" <<'EOF'
{"action": "opened", "sender": {"login": "ztblick"},
 "repository": {"full_name": "ztblick/wipeOS"}, "issue": {"number": 3}}
EOF
gate ignore pull_request "empty payload" </dev/null
gate ignore pull_request "empty JSON object" <<<'{}'
gate ignore pull_request "malformed JSON" <<<'{"action": "closed",'
gate ignore pull_request "pull request with no sender" <<'EOF'
{"action": "closed", "repository": {"full_name": "ztblick/wipeOS"},
 "pull_request": {"merged": true, "merged_by": {"login": "ztblick"}}}
EOF
gate ignore pull_request "pull request with no head repository" <<'EOF'
{"action": "closed", "sender": {"login": "ztblick"},
 "repository": {"full_name": "ztblick/wipeOS"},
 "pull_request": {"merged": true, "merged_by": {"login": "ztblick"},
  "head": {"repo": null}, "labels": [{"name": "spec"}]}}
EOF
gate ignore "" "no event name" <<<'{"sender": {"login": "ztblick"}}'

# A comment body can't add lines to $GITHUB_OUTPUT: the gate prints
# exactly three lines whatever the payload holds.
printf '%s' '{"action": "created", "sender": {"login": "someone\nrole=build"},
 "repository": {"full_name": "ztblick/wipeOS"},
 "comment": {"user": {"login": "x"}, "body": "@claude"}, "issue": {"number": 3}}' \
	>"$tmp/event.json"
lines=$(GITHUB_EVENT_NAME=issue_comment GITHUB_EVENT_PATH=$tmp/event.json \
	python3 "$gate" | wc -l)
ncases=$((ncases + 1))
if [ "$lines" -ne 3 ]; then
	nfail=$((nfail + 1))
	echo "  FAIL  a newline in the payload: want 3 output lines, got $lines"
elif [ $verbose = 1 ]; then
	echo "  ok    a newline in the payload: 3 output lines"
fi

echo
echo "$ncases cases, $nfail failed"
[ $nfail -eq 0 ]
