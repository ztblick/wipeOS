# Decision records

One file per decision, named `Dnnn-<slug>.md`: the number zero-padded to three digits, the slug from the title, lowercase, words joined by hyphens, at most 50 characters. A new decision takes the next free number. `context/INDEX.md` lists them all; rerun `scripts/context_index.py` after any change here.

**Rules.**

- **Status.** A decision is `proposed` until Zach agrees to it, then `accepted`. A decision written down from a plan Zach handed over (its "Decisions made for this plan") is `accepted` from the start, with `decided_in` naming the plan. Claude Code never accepts a decision on its own: anything else it writes starts as `proposed`.
- **The body is fixed.** Once a decision is accepted, everything below the frontmatter stays as written. Only `status`, `superseded_by` and `supersedes` change.
- **Superseding.** A reversed decision is never edited or deleted. Write a new decision with `supersedes: [Dnn]`, then set the old one's `status: superseded` and `superseded_by: Dmm`, in the same change and only once the new one is accepted.
- **Proposed decisions** may be rewritten freely until accepted. Write your recommendation as the decision and two or three other options, with their tradeoffs, as the alternatives.
- **Frontmatter values** are `null`, a bare word, a double-quoted string, or a list in brackets. No comments in the frontmatter.

**Template.** Copy everything inside the fence. Leave out `decided_in` and `supersedes` when they don't apply.

```markdown
---
id: Dnn
title: "Short title"
status: proposed
date: YYYY-MM-DD
decided_in: docs/plans/<plan>.md
supersedes: [Dnn]
---

# Dnn: Short title

**Decision.** ...

**Rationale.** ...

**Alternatives considered.** ...
```
