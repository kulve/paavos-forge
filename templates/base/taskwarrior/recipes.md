# Taskwarrior Command Recipes

Reference for agents interacting with Taskwarrior. See `ai-framework/LOGIC.md` for the full workflow specification.

## Create Story Tasks

Create four phase tasks with dependencies for a story. Replace `XXXXX` with the story ID.

```bash
REQ_ID=$(task add "Story XXXXX: Requirements" aiphase:req aistate:plan aistory:XXXXX 2>&1 | grep -oP 'Created task \K[0-9]+')
ARCH_ID=$(task add "Story XXXXX: Architecture" aiphase:arch aistate:blocked aistory:XXXXX depends:$REQ_ID 2>&1 | grep -oP 'Created task \K[0-9]+')
TEST_ID=$(task add "Story XXXXX: Integration Tests" aiphase:test aistate:blocked aistory:XXXXX depends:$ARCH_ID 2>&1 | grep -oP 'Created task \K[0-9]+')
task add "Story XXXXX: Implementation" aiphase:impl aistate:blocked aistory:XXXXX depends:$TEST_ID
```

## Query Tasks

Find the next actionable task for a story:
```bash
task aistory:XXXXX status:pending +READY export
```

Show all tasks for a story:
```bash
task aistory:XXXXX export
```

Use the custom report:
```bash
task ainext
```

## State Transitions

Advance from plan to write:
```bash
task <id> modify aistate:write
```

Advance from write to review:
```bash
task <id> modify aistate:review
```

Approve (review passed):
```bash
task <id> modify aistate:done
task <id> done
```

Reject (review failed, back to write):
```bash
task <id> modify aistate:write
```

## Annotations

Link a plan file:
```bash
task <id> annotate "Plan: plan/requirement-plans/XXXXX-auth.md"
```

Link an artifact:
```bash
task <id> annotate "Artifact: plan/requirements/core/XXXXX-auth.md"
```

Approve a review:
```bash
task <id> annotate "Review: approved"
```

Link review feedback:
```bash
task <id> annotate "Feedback: plan/requirements-review/XXXXX-feedback.md"
```

## Escalation

Block a task and link the escalation report:
```bash
task <id> modify +blocked
task <id> annotate "Escalation: plan/escalations/XXXXX-req-auth.md"
```

Reopen an upstream phase after escalation:
```bash
task <upstream-id> modify aistate:write
task <upstream-id> annotate "Escalation context: plan/escalations/XXXXX-req-auth.md"
```
