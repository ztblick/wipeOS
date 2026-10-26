---
id: D44
title: "Agents work through branches and pull requests; only Zach merges"
status: accepted
date: 2026-10-26
decided_in: docs/plans/portable-build-host-and-fast-CI.md
---

# D44: Agents work through branches and pull requests; only Zach merges

**Decision.**

- **Workflow.** An agent starts from an up-to-date `main` (`git switch main && git pull --ff-only`), creates a branch `claude/<short-topic>`, and commits on it as the work goes; the pre-commit lint applies to every commit. It pushes with `git push -u origin <branch>` and opens a pull request to `main` with `gh pr create`. Later commits pushed to the same branch update the pull request. It reads CI with `gh pr checks` and `gh run view`.
- **Never.** Agents never commit on `main`, push to `main`, force-push, delete a remote branch, merge or approve a pull request, change repository settings, rulesets, secrets or variables, write through `gh api`, or print the `gh` token.
- **Enforced on GitHub.** A ruleset on `main`, set by Zach, requires a pull request and the CI check, blocks force pushes, restricts deletion, and has an empty bypass list. There are no required approvals: agents push as Zach's GitHub account, and GitHub doesn't let an account approve its own pull request, so a required approval would block every merge. Zach's merge is the approval.
- **Enforced locally.** `.claude/hooks/guard-git.py` denies the "never" list before it reaches GitHub. Like D34 and D35, it stops the obvious and the accidental, not a determined attempt: an agent holding Zach's token could still reach the API another way.

**Rationale.** Agents need to do real development with git, and Zach needs to review every change to `main`. Branches and pull requests give both, with CI (D43) on every change.

**Alternatives considered.** A separate GitHub account for agents, with CODEOWNERS and a required review from Zach (GitHub itself would enforce that only Zach approves, but it needs a second account, SSH key and `gh` login on the laptop; revisit when agents run unattended or in GitHub); Claude Code permission deny rules only (prefix matching misses `git -C . push`, wrappers and `bash -c`); agents never push and Zach pushes every branch (Zach becomes the bottleneck for every CI run).
