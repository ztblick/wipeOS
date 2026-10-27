---
id: D55
title: "Agent identity in GitHub"
status: accepted
date: 2026-10-27
decided_in: docs/plans/agents-in-github.md
---

# D55: Agent identity in GitHub

**Decision.**

- **What changes.** Agents in GitHub act as `claude[bot]`, through the Claude app. Agents on the laptop still push as Zach. Both work under D44's workflow and "never" list.
- **Required approvals.** Pull requests authored by the bot could take an approval, but required approvals stay off: laptop agents' pull requests are authored by Zach, and he can't approve his own.

This extends D44 without superseding it.

**Rationale.** The bot identity separates agent work in GitHub from Zach's own, and its events trigger workflows; keeping laptop agents as Zach keeps Claude Code on the laptop working as it does.

**Alternatives considered.** Requiring approvals and moving all agent work into GitHub (gives up driving Claude Code from the laptop); a separate machine account for laptop agents (another set of credentials, for little gain today).
