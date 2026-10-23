# Question records

One file per question, named `<slug>.md` from the title: lowercase, words joined by hyphens, at most 50 characters. `context/INDEX.md` lists them all; rerun `scripts/context_index.py` after any change here.

**Rules.**

- **Status** is `open`, `deferred` (tabled on purpose, with the reason in the body) or `resolved`.
- **Group**, for open questions only: `proposal` if it blocks the team proposal, otherwise `design`.
- **Resolving.** A question is answered by a decision. Set `status: resolved`, drop `group`, add `resolved_by: [Dnn]`, and add one closing line to the body naming the decision. Leave the rest of the body as it was.
- Claude Code may add open questions it runs into, extend the body of an open question with what it learns, and resolve a question once an accepted decision answers it. Moving a question to `deferred` is Zach's choice.

**Template.** Copy everything inside the fence.

```markdown
---
title: "Short question title"
status: open
group: design
---

# Short question title

What is undecided, why it matters, and the options known so far.
```
