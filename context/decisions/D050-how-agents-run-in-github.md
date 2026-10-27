---
id: D50
title: "How agents run in GitHub"
status: accepted
date: 2026-10-27
decided_in: docs/plans/agents-in-github.md
---

# D50: How agents run in GitHub

**Decision.**

- **One workflow.** Agents run in `.github/workflows/agents.yml`, on GitHub-hosted `ubuntu-24.04` runners, using `anthropics/claude-code-action`. The action is pinned to a full commit SHA with the version in a comment, because it receives the token.
- **Credentials.** It authenticates with a `CLAUDE_CODE_OAUTH_TOKEN` repository secret, from Zach's Team-plan seat, which Zach generates with `claude setup-token` and sets himself.
- **Identity.** The Claude GitHub App is installed on `ztblick/wipeOS` only. Agents act as the app's bot account, `claude[bot]`.
- **Permissions.** Each job gets only the GitHub permissions its role needs. `id-token: write` is included where the action requires it.

**Rationale.** One workflow keeps the gate and setup in one place. A pinned SHA stops a changed action from receiving the token unreviewed. The app's bot identity makes agent events trigger workflows, so the loop can chain.

**Alternatives considered.** An API key with a spend cap (Zach chose his subscription); a workflow file per role (five copies of the gate and setup to keep consistent).
