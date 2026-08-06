# Escalation: Story XXXXX, Phase [phase]

## Blocked Task

[Taskwarrior task ID]

## Failure Description

[What went wrong, with exact error messages or contradictions]

## Reproduction

[Steps to see the failure]

## Root Cause Analysis

[Which upstream artifact is believed to be wrong and why]

## Proposed Recovery

[Which artifacts to edit in place and what should change. Completed phase tasks stay completed -- do not ask to reopen a `done` task. Inline escalation-recovery applies the fix and the Coordinator continues the current phase.]

## Domain Disposition

[Include this section only for architecture-plan domain-vocabulary mismatches. Omit otherwise.]

- [proposed-domain] → [surviving-domain]

Rationale: [why the proposed domain cannot be committed as its own DAG node]

Refile:

- plan/requirements/[proposed]/XXXXX-name.md → plan/requirements/[surviving]/XXXXX-name.md (`## Domain`: [surviving])
