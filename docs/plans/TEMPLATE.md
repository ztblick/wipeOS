# Plan: <short title> (<key results>)

<!--
How to use this template; delete this comment in a real plan.
- A plan is written in a chat design discussion with Zach and committed
  before Claude Code starts. Committing it is the approval: Claude Code works
  through every step without stopping for review, and stops only for a stop
  condition below.
- Keep it as short as the task allows. A section that doesn't apply says
  "None."
- Everything above "Outcome" is fixed once work starts. Claude Code writes
  only in Outcome.
-->

Implementation plan for <one line>. Written <YYYY-MM-DD> from a design discussion with Zach.

Read this whole file before starting, together with `CLAUDE.md` and the records it points to in `context/INDEX.md`. Then do step 0, the preflight, before changing anything.

## Goal

<What exists when this is done, in two or three sentences, and which key results it covers.>

**Out of scope:** <...>

## Constraints from existing decisions

- **Dn:** <what it means for this task>

## Decisions made for this plan

Settled with Zach in chat. In the last step, record each one in `context/decisions/` as `accepted`, with `decided_in` set to this file's path.

### 1. <Short title>

<The decision.>

*Alternatives considered:* <...>

## Delegated to Claude Code

Choices Claude Code makes itself, without stopping. List every one in Outcome, one line each with the reason.

- <for example: names of internal functions and files inside the component>
- <for example: how the tests are organized>

## Stop conditions

Everything on CLAUDE.md's "Design decisions are mine" list is reserved, unless this plan settles it above or delegates it. Stop when any of these comes up:

- a reserved choice the plan doesn't settle;
- <task-specific conditions, for example: "the interface in Decision 2 needs a field it doesn't list">;
- a step can't pass its acceptance test without changing something outside this plan;
- the plan contradicts an accepted decision, or the code contradicts the plan.

**How to stop.**

1. Write the question as a `proposed` decision in `context/decisions/`, with your recommendation as the decision and two or three alternatives with their tradeoffs.
2. Set Outcome's status to `blocked`, naming the decision, and rerun `scripts/context_index.py`.
3. End your turn with a short message naming the decision, and wait.

Don't continue with work that depends on the answer, and don't guess.

## Component specs

<Per file or component: what it does, its interfaces, formats and rules. Exact enough that two implementations would agree on everything visible from outside.>

## Steps

Work through the steps in order without stopping for review. For every step that changes the image, note `bzImage` size before and after in Outcome.

0. **Preflight.** Check this plan against `context/INDEX.md`, the records the plan cites, and the current code. If anything conflicts or is missing, stop as above, before writing any code.
1. <...>
2. **Record.**
   - Write each decision from "Decisions made for this plan" to `context/decisions/`.
   - Add any open question you ran into to `context/questions/`.
   - Tick the key results this plan completes in `docs/okrs.md`, each with a one-line note of the evidence.
   - Update `README.md` if a command or path changed.
   - Rerun `scripts/context_index.py`.
   - Fill in Outcome.

## Acceptance tests

Commands Zach can run himself. Each one states its expected result.

1. `<command>` exits 0, and <what the log or output shows>.

## Outcome

Written by Claude Code when it finishes or stops.

- **Status:** not started | blocked on Dnn | done
- **Changed:** <each file, one line>
- **Verified:** <the commands run and their results; anything not verified, said plainly>
- **Image size:** <bzImage before and after, or "not affected">
- **Choices made within delegated scope:** <one line each, with the reason>
- **Records written:** <decisions, questions, OKR ticks, README>
- **Suggested design.md changes:** <the exact text, for Zach to rewrite or drop>
- **Noticed, not touched:** <...>
- **Suggested commit message:** <one line>
