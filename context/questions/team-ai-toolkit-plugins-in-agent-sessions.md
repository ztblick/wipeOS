---
title: "Team-ai-toolkit plugins in agent sessions"
status: open
group: design
---

# Team-ai-toolkit plugins in agent sessions

Whether, and when, to load the team-ai-toolkit marketplace's plugins in the agents' GitHub sessions. `docs/plans/agents-in-github.md` left them out of scope. `claude-code-action` can install plugins and marketplaces per run (its `plugins` and `plugin_marketplaces` inputs, at the pinned v1.0.262), so the mechanism exists.

What it affects: a plugin adds instructions, skills and possibly hooks or MCP servers to sessions that hold the Claude app's token. It would sit outside the repository, so it wouldn't get the protection the skills have (D34, D52), and a plugin update would change what agents do without a commit here. Options known so far: never load plugins in agent sessions; load named plugins pinned to a marketplace commit, listed in `agents.yml` (protected, reviewed); vendor the useful parts into `.claude/skills/`.
