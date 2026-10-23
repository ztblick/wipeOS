---
id: D33
title: "Lint C code with checkpatch, gcc -fanalyzer and cppcheck"
status: accepted
date: 2026-10-22
---

# D33: Lint C code with checkpatch, gcc -fanalyzer and cppcheck

**Decision.** All C under `src/` is linted by `scripts/lint.sh`: kernel style via the kernel tree's checkpatch.pl (`.checkpatch.conf`), gcc warnings plus `-fanalyzer`, and cppcheck. A pre-commit hook in `.githooks/` runs it on staged changes; style is checked on changed lines, analysis on the whole program. False positives are suppressed in the code with a comment giving the reason. Dev tooling only; nothing is added to the image.

**Rationale.** Linux style matches the base we build on; two independent analyzers catch memory errors early in code where a silent bug weakens the wipe guarantee. One script keeps the hook, manual runs and agent hooks consistent.

**Alternatives considered.** clang-format (conflicts with checkpatch in places); clang-tidy (overlaps the analyzers); sparse (kernel-only annotations); CI-only checks (slower feedback; still worth adding later as the enforced gate).

