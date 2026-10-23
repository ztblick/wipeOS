---
id: D36
title: "Index check at Stop"
status: accepted
date: 2026-10-23
decided_in: docs/plans/build-gaurd-and-index-check.md
---

# D36: Index check at Stop

**Decision.** A Claude Code Stop hook, `.claude/hooks/check-index.py`, runs `scripts/context_index.py --check` from the project root at the end of every turn.

- **Index stale:** the hook exits 2 with "context/INDEX.md is out of date; run scripts/context_index.py", so Claude regenerates it before the turn ends.
- **Still stale on the retry** (`stop_hook_active` is true): the hook lets the turn end and shows Zach a warning through `systemMessage`, so a broken index can't loop the session.
- **The check can't run** (exit 2 from `context_index.py`, a missing script, bad input): treated like a stale index, but the message says the check failed.

**Rationale.** Every session imports `context/INDEX.md` through CLAUDE.md, so a record changed without regenerating the index misleads the next session from its first message.

**Alternatives considered.** A pre-commit check instead (catches staleness only at commit time, after sessions have already imported the stale index); regenerating the index inside the hook itself (hides from Claude that it changed `context/` without updating the index).
