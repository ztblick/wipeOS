---
id: D51
title: "The sender gate"
status: accepted
date: 2026-10-27
decided_in: docs/plans/agents-in-github.md
---

# D51: The sender gate

**Decision.** Every agent run starts with a `gate` job that runs `scripts/agent-gate.py`.

- **Input and output.** It reads the event name and payload (`GITHUB_EVENT_NAME`, `GITHUB_EVENT_PATH`) and prints one role, or `ignore` with a reason. Role jobs run only for a role. An ignored event ends the run, with the reason in the job summary, and the token is never used.
- **Rules that apply to every event:**
  - The event's `sender` is `ztblick` or `claude[bot]`.
  - For pull request events, the head branch is in `ztblick/wipeOS`, never a fork.
  - A pull request labeled `needs-zach` starts nothing automatically. Only Zach's `@claude` comments act on it.
- **The roles:**

  | Event | Condition | Role |
  | --- | --- | --- |
  | `pull_request` closed | merged, `merged_by` is `ztblick`, labeled `build` | `plan` |
  | `pull_request` closed | merged, `merged_by` is `ztblick`, labeled `spec` | `build` |
  | `pull_request_review` submitted | by `ztblick`, state `changes_requested`, labeled `spec` | `revise` |
  | `pull_request_review` submitted | by `ztblick`, state `changes_requested`, labeled `build` | `fix` |
  | `pull_request_review` submitted | by `claude[bot]`, labeled `build`, body's first line is `Verdict: changes needed` | `fix` |
  | `pull_request` labeled | label `needs-respec`, added by `ztblick`, on a `build` pull request | `respec` |
  | `pull_request` opened, synchronize, reopened, or labeled `build` | author `claude[bot]`, labeled `build`, sender `ztblick` or `claude[bot]` | `review` |
  | `workflow_run` completed | workflow `ci`, conclusion `failure`, branch `claude/build-*` in this repo, triggered by `ztblick` or `claude[bot]` | `fix` |
  | `issue_comment` or `pull_request_review_comment` created | by `ztblick`, body starts with `@claude plan-next` | `plan` |
  | `issue_comment` or `pull_request_review_comment` created | by `ztblick`, body contains `@claude` | `mention` |
  | anything else | | `ignore` |

- **One extra condition for `plan`:** no open pull request is labeled `spec`. Otherwise it's ignored, because a proposal is already waiting.
- **Labels.** `spec`, `build`, `needs-respec`, `needs-zach` and `blocked` exist in the repository. The agents create them if they're missing.

**Rationale.** A script with a self-test is easier to check than workflow expressions, and it covers what the action's own write-access check doesn't: merges, labels and CI events.

**Alternatives considered.** `if:` expressions in the workflow only (hard to test, easy to get subtly wrong); the action's own write-access check alone (it doesn't cover merges, labels or CI events, and depends on the action's defaults).
