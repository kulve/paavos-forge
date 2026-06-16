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

The Coordinator must ensure at most one phase task is `+ACTIVE` at any time. The `-AI_LOCK` filter excludes PM/Coordinator lock tasks so they do not interfere with this check:

```bash
# Check no phase subagent is currently active (must be 0 before starting a subagent)
taskwarrior/tw +ACTIVE -AI_LOCK count

# Mark a phase task active (call before invoking a subagent)
taskwarrior/tw <id> start

# Clear active status (call after subagent completes or is stopped)
taskwarrior/tw <id> stop
```

## Top-Level Role Locks

PM and Coordinator are singleton agents. Each has a permanent `+AI_LOCK` Taskwarrior task (created by `taskwarrior/setup.sh`) that is `start`ed when the agent begins and `stop`ped when it exits.

Check whether a top-level agent is currently running:
```bash
taskwarrior/tw +AI_LOCK +ACTIVE export
```

Acquire PM lock (call at PM session start, before any reads or writes):
```bash
taskwarrior/tw +AI_LOCK airole:pm +ACTIVE count    # must be 0
taskwarrior/tw +AI_LOCK airole:pm start
```

Release PM lock (call when PM is intentionally done or stopped):
```bash
taskwarrior/tw +AI_LOCK airole:pm stop
```

Acquire Coordinator lock (call before creating tasks, touching git, or invoking subagents):
```bash
taskwarrior/tw +AI_LOCK airole:coordinator +ACTIVE count    # must be 0
taskwarrior/tw +AI_LOCK airole:coordinator start
```

Release Coordinator lock (call on story completion, escalation halt, or clean exit):
```bash
taskwarrior/tw +AI_LOCK airole:coordinator stop
```

View all lock tasks and their active status:
```bash
taskwarrior/tw ailocks
```

View active phase tasks (excludes lock tasks):
```bash
taskwarrior/tw aiactive
```

Manual stale-lock and orphaned-active recovery (user only, after confirming no Cursor agents/subagents are running for this workspace):
```bash
ccmd bash taskwarrior/cleanup-ai-state.sh
ccmd bash taskwarrior/cleanup-ai-state.sh --apply
```

The cleanup script defaults to dry-run. In apply mode it stops active PM/Coordinator lock tasks and active phase tasks, optionally scoped with `--story XXXXX` or limited to locks with `--locks-only`. It does not mark tasks done, modify `aistate`, delete tasks, or touch git. Agents must not run this automatically; they may only point the user to it after reporting read-only status.

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

## Discoveries

Discoveries are filesystem-only records under `plan/discoveries/`; they are not Taskwarrior tasks and should not be annotated on phase tasks. Subagents may only create new discovery files and must not inspect existing ones.
