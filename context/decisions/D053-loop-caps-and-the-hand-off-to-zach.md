---
id: D53
title: "Loop caps and the hand-off to Zach"
status: accepted
date: 2026-10-27
decided_in: docs/plans/agents-in-github.md
---

# D53: Loop caps and the hand-off to Zach

**Decision.**

- **The cap.** Before a `fix` run, the gate counts that pull request's earlier automatic fix runs. Each `fix` run leaves a comment with the marker `<!-- agent-run: fix -->`. At three, instead of fixing, the job adds `needs-zach` and comments to `@ztblick` with a summary of what's still failing.
- **Fixes Zach asks for.** A `fix` run triggered by Zach's review doesn't count toward the cap, and Zach removing `needs-zach` resets it.
- **Stop conditions.** A builder that hits a plan stop condition follows the plan's "How to stop" steps, then adds `blocked` and `needs-zach` and comments to `@ztblick`. Zach answers with an `@claude` comment.
- **Concurrency.**
  - At most one agent run per pull request at a time. Runs queue; they don't cancel each other.
  - At most one planner run in the repository at a time.
- **Limits.** Every agent job has a timeout and a turn limit, per role.

**Rationale.** A builder and a reviewer that disagree could otherwise loop until Zach's usage runs out. A cap per pull request stops one bad pull request without stopping the others.

**Alternatives considered.** No cap (a builder and reviewer that disagree can loop until Zach's usage runs out); a cap per day (doesn't stop one bad pull request from using the whole allowance).
