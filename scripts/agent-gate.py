#!/usr/bin/env python3
"""Decide which agent, if any, a GitHub event starts (D51).

The first job of .github/workflows/agents.yml runs this before any agent
token is used. It reads the event and prints one role, or "ignore" with a
reason. Only Zach (ztblick) and the Claude app's bot (claude[bot]) can
start an agent; events from anyone else, and pull requests from forks,
are ignored.

  Event                        Condition                              Role
  pull_request closed          merged by ztblick, labeled build       plan
  pull_request closed          merged by ztblick, labeled spec        build
  pull_request_review          by ztblick, changes_requested, spec    revise
  pull_request_review          by ztblick, changes_requested, build   fix
  pull_request_review          by claude[bot], build, first line      fix
                               "Verdict: changes needed"
  pull_request labeled         needs-respec, by ztblick, on build     respec
  pull_request opened,         author claude[bot], labeled build      review
    synchronize, reopened,
    or labeled build
  workflow_run completed       CI failed on claude/build-* in this    fix
                               repo, run by ztblick or claude[bot]
  issue_comment or             by ztblick, starts "@claude plan-next" plan
    pull_request_review_comment
  issue_comment or             by ztblick, contains "@claude"         mention
    pull_request_review_comment
  anything else                                                       ignore

Also:
  - plan is ignored while a pull request labeled spec is open;
  - a pull request labeled needs-zach starts nothing but Zach's @claude
    comments (mention, and plan-next);
  - an automatic fix (the reviewer's verdict, or CI) after three earlier
    automatic fix runs becomes fix-cap: the workflow labels the pull
    request needs-zach and hands it to Zach instead of fixing (D53). A fix
    Zach asks for by review isn't counted or capped.

Usage:
  scripts/agent-gate.py [--fix-count N] [--open-specs N] [--pr FILE]

  The event comes from GITHUB_EVENT_NAME and GITHUB_EVENT_PATH, as in a
  workflow. The workflow reads the rest from the GitHub API, so this
  script never touches the network:
    --fix-count   automatic fix runs on the pull request since Zach last
                  removed needs-zach
    --open-specs  open pull requests labeled spec
    --pr          the pull request as GET /repos/{repo}/pulls/{n} returns
                  it, for events whose payload lacks its head repository
                  or labels (comments on a pull request, workflow_run)

Output, for $GITHUB_OUTPUT:
  role=<plan|build|revise|fix|fix-cap|respec|review|mention|ignore>
  trigger=<what started it, for the job summary>
  reason=<why, in one line>

Fails closed: an unreadable payload, an unknown event or a missing field
gives role=ignore and exit 0. A crash exits non-zero, and the workflow
treats that as ignore too. Standard library only.
"""

import argparse
import json
import os
import sys

ZACH = "ztblick"
BOT = "claude[bot]"
TRUSTED = {ZACH, BOT}
CI_WORKFLOW = ".github/workflows/ci.yml"
FIX_CAP = 3


class Ignore(Exception):
    """The event starts nothing; the message says why."""


def get(obj, path):
    """obj["a"]["b"]... for path "a.b...", or raise Ignore if any part is
    missing: a payload without a field the gate needs starts nothing."""
    for key in path.split("."):
        if not isinstance(obj, dict) or obj.get(key) is None:
            raise Ignore(f"payload has no {path}")
        obj = obj[key]
    return obj


def labels(pr):
    return {lb.get("name") for lb in get(pr, "labels")
            if isinstance(lb, dict)}


def require_same_repo(ev, pr):
    """The pull request's head branch is in this repository, not a fork."""
    if get(pr, "head.repo.full_name") != get(ev, "repository.full_name"):
        raise Ignore("pull request is from a fork")


def require_no_handoff(pr_labels):
    if "needs-zach" in pr_labels:
        raise Ignore("pull request is labeled needs-zach; only Zach's "
                     "@claude comments act on it")


def plan_role(args, trigger):
    if args.open_specs is None:
        raise Ignore("open spec count unknown")
    if args.open_specs > 0:
        raise Ignore("a spec pull request is already open")
    return "plan", trigger


def auto_fix(args, trigger):
    """A fix the reviewer or CI asks for counts toward the cap (D53)."""
    if args.fix_count is None:
        raise Ignore("fix-run count unknown")
    if args.fix_count >= FIX_CAP:
        return "fix-cap", f"{trigger}; {args.fix_count} automatic fix runs"
    return "fix", trigger


def pull_request(ev, args):
    pr = get(ev, "pull_request")
    require_same_repo(ev, pr)
    have = labels(pr)
    action = get(ev, "action")

    if action == "closed":
        if not pr.get("merged"):
            raise Ignore("pull request closed without merging")
        if get(pr, "merged_by.login") != ZACH:
            raise Ignore("merged by someone other than ztblick")
        require_no_handoff(have)
        if {"build", "spec"} <= have:
            raise Ignore("labeled both build and spec")
        if "build" in have:
            return plan_role(args, "build pull request merged")
        if "spec" in have:
            return "build", "spec pull request merged"
        raise Ignore("merged pull request is labeled neither build nor spec")

    if action == "labeled" and get(ev, "label.name") == "needs-respec":
        if get(ev, "sender.login") != ZACH:
            raise Ignore("needs-respec added by someone other than ztblick")
        if "build" not in have:
            raise Ignore("needs-respec on a pull request not labeled build")
        require_no_handoff(have)
        return "respec", "needs-respec label added"

    if action in ("opened", "synchronize", "reopened") or (
            action == "labeled" and get(ev, "label.name") == "build"):
        if get(pr, "user.login") != BOT:
            raise Ignore("pull request not authored by claude[bot]")
        if "build" not in have:
            raise Ignore("pull request not labeled build")
        require_no_handoff(have)
        return "review", f"build pull request {action}"

    raise Ignore(f"pull_request {action} starts nothing")


def pull_request_review(ev, args):
    if get(ev, "action") != "submitted":
        raise Ignore("review not submitted")
    pr = get(ev, "pull_request")
    require_same_repo(ev, pr)
    have = labels(pr)
    author = get(ev, "review.user.login")
    # Webhooks send the state in lowercase; the REST API in uppercase.
    state = get(ev, "review.state").lower()

    if author == ZACH:
        if state != "changes_requested":
            raise Ignore(f"Zach's review is {state}, not changes_requested")
        require_no_handoff(have)
        if "spec" in have:
            return "revise", "Zach requested changes on the spec"
        if "build" in have:
            # Zach asked for it, so it isn't counted or capped (D53).
            return "fix", "Zach requested changes"
        raise Ignore("reviewed pull request is labeled neither spec nor build")

    if author == BOT:
        if "build" not in have:
            raise Ignore("claude[bot] review on a pull request not labeled "
                         "build")
        body = ev["review"].get("body") or ""
        first = body.strip().splitlines()[0].strip() if body.strip() else ""
        if first != "Verdict: changes needed":
            raise Ignore("reviewer found no must-fix problems")
        require_no_handoff(have)
        return auto_fix(args, "reviewer found must-fix problems")

    raise Ignore("review by someone other than ztblick or claude[bot]")


def workflow_run(ev, args):
    run = get(ev, "workflow_run")
    if get(ev, "action") != "completed":
        raise Ignore("workflow run not completed")
    if get(run, "path") != CI_WORKFLOW:
        raise Ignore(f"workflow {run.get('path')} is not CI")
    if get(run, "conclusion") != "failure":
        raise Ignore(f"CI concluded {run.get('conclusion')}, not failure")
    if not get(run, "head_branch").startswith("claude/build-"):
        raise Ignore("CI failed on a branch that isn't claude/build-*")
    if get(run, "head_repository.full_name") != get(ev,
                                                    "repository.full_name"):
        raise Ignore("CI ran on a fork")
    for who in ("actor.login", "triggering_actor.login"):
        if get(run, who) not in TRUSTED:
            raise Ignore(f"CI run's {who.split('.')[0]} is not ztblick or "
                         "claude[bot]")
    # The payload carries no labels, so needs-zach is read from --pr.
    if args.pr is None:
        raise Ignore("pull request for the CI run unknown")
    require_same_repo(ev, args.pr)
    if get(args.pr, "head.ref") != run["head_branch"]:
        raise Ignore("pull request doesn't match the CI run's branch")
    require_no_handoff(labels(args.pr))
    return auto_fix(args, "CI failed")


def comment(ev, args):
    if get(ev, "action") != "created":
        raise Ignore("comment not created")
    if get(ev, "comment.user.login") != ZACH:
        raise Ignore("comment by someone other than ztblick")
    body = get(ev, "comment").get("body") or ""
    if "@claude" not in body:
        raise Ignore("comment doesn't mention @claude")

    # Find the pull request, if the comment is on one, to refuse forks.
    if "pull_request" in ev:
        require_same_repo(ev, ev["pull_request"])
    elif get(ev, "issue").get("pull_request"):
        if args.pr is None:
            raise Ignore("pull request for the comment unknown")
        require_same_repo(ev, args.pr)

    # needs-zach doesn't stop these: they are Zach's @claude comments.
    if body.lstrip().startswith("@claude plan-next"):
        return plan_role(args, "Zach commented @claude plan-next")
    return "mention", "Zach mentioned @claude"


HANDLERS = {
    "pull_request": pull_request,
    "pull_request_review": pull_request_review,
    "workflow_run": workflow_run,
    "issue_comment": comment,
    "pull_request_review_comment": comment,
}


def decide(name, ev, args):
    if not isinstance(ev, dict) or not ev:
        raise Ignore("empty payload")
    if name not in HANDLERS:
        raise Ignore(f"event {name or '(none)'} starts nothing")
    if get(ev, "sender.login") not in TRUSTED:
        raise Ignore(f"sent by {ev['sender']['login']}, not ztblick or "
                     "claude[bot]")
    return HANDLERS[name](ev, args)


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main():
    p = argparse.ArgumentParser(description="Decide which agent an event "
                                "starts (D51).")
    p.add_argument("--fix-count", type=int)
    p.add_argument("--open-specs", type=int)
    p.add_argument("--pr", metavar="FILE")
    args = p.parse_args()

    name = os.environ.get("GITHUB_EVENT_NAME", "")
    try:
        try:
            ev = load_json(os.environ.get("GITHUB_EVENT_PATH", ""))
        except (OSError, ValueError) as e:
            raise Ignore(f"can't read the event payload ({e.__class__.__name__})")
        if args.pr is not None:
            try:
                args.pr = load_json(args.pr)
            except (OSError, ValueError):
                args.pr = None
        role, trigger = decide(name, ev, args)
        reason = f"{trigger}: {role}"
    except Ignore as e:
        role, trigger, reason = "ignore", name or "none", str(e)

    # One line each, so a payload can't add lines to $GITHUB_OUTPUT.
    for key, value in (("role", role), ("trigger", trigger),
                       ("reason", reason)):
        print(f"{key}={' '.join(str(value).split())}")


if __name__ == "__main__":
    main()
