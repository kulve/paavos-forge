# Taskwarrior Command Recipes

All commands use `taskwarrior/tw` -- the project-local wrapper that ensures per-project database isolation via `.taskrc` and `.task/`. Never use bare `task` directly. See `taskwarrior/env.sh` for details.

Reference for agents interacting with Taskwarrior. See `ai-framework/LOGIC.md` for the full workflow specification.

## Create Story Tasks

Create four phase tasks with dependencies for a story. Replace `XXXXX` with the story ID.

```bash
REQ_ID=$(taskwarrior/tw add "Story XXXXX: Requirements" aiphase:req aistate:plan aistory:XXXXX 2>&1 | grep -oP 'Created task \K[0-9]+')
ARCH_ID=$(taskwarrior/tw add "Story XXXXX: Architecture" aiphase:arch aistate:blocked aistory:XXXXX depends:$REQ_ID 2>&1 | grep -oP 'Created task \K[0-9]+')
TEST_ID=$(taskwarrior/tw add "Story XXXXX: Integration Tests" aiphase:test aistate:blocked aistory:XXXXX depends:$ARCH_ID 2>&1 | grep -oP 'Created task \K[0-9]+')
taskwarrior/tw add "Story XXXXX: Implementation" aiphase:impl aistate:blocked aistory:XXXXX depends:$TEST_ID
```

## Query Tasks

Find the next actionable task for a story:
```bash
taskwarrior/tw aistory:XXXXX status:pending +READY export
```

Show all tasks for a story:
```bash
taskwarrior/tw aistory:XXXXX export
```

Use the custom report:
```bash
taskwarrior/tw ainext
```

## Active Task Guard

The Coordinator must ensure at most one task is `+ACTIVE` at any time. Use these commands around every subagent invocation:

```bash
# Check nothing is currently active (must be 0 before starting a subagent)
taskwarrior/tw +ACTIVE count

# Mark a task active (call before invoking a subagent)
taskwarrior/tw <id> start

# Clear active status (call after subagent completes or is stopped)
taskwarrior/tw <id> stop
```

## State Transitions

Advance from plan to plan-review:
```bash
taskwarrior/tw <id> modify aistate:plan-review
```

Approve plan (plan-review passed, advance to write):
```bash
taskwarrior/tw <id> modify aistate:write
```

Reject plan (plan-review failed, back to plan):
```bash
taskwarrior/tw <id> modify aistate:plan
```

Advance from write to review:
```bash
taskwarrior/tw <id> modify aistate:review
```

Approve (review passed):
```bash
taskwarrior/tw <id> modify aistate:done
taskwarrior/tw <id> done
```

Reject (review failed, back to write):
```bash
taskwarrior/tw <id> modify aistate:write
```

## Annotations

Link a plan file:
```bash
taskwarrior/tw <id> annotate "Plan: plan/requirement-plans/XXXXX-auth.md"
```

Link an artifact:
```bash
taskwarrior/tw <id> annotate "Artifact: plan/requirements/core/XXXXX-auth.md"
```

Approve a plan review:
```bash
taskwarrior/tw <id> annotate "Plan-review: approved"
```

Link plan review feedback:
```bash
taskwarrior/tw <id> annotate "Plan-feedback: plan/requirement-plan-review/XXXXX-feedback.md"
```

Approve a review:
```bash
taskwarrior/tw <id> annotate "Review: approved"
```

Link review feedback:
```bash
taskwarrior/tw <id> annotate "Feedback: plan/requirements-review/XXXXX-feedback.md"
```

## Escalation

Halt execution and return control to the PM. No automatic recovery.

```bash
taskwarrior/tw <id> stop
taskwarrior/tw <id> modify +blocked
taskwarrior/tw <id> annotate "Escalation: plan/escalations/XXXXX-req-auth.md"
```
