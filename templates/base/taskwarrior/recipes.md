# Taskwarrior Script Recipes

Command reference for AI agents using the execution framework. All state mutations go through scripts. Read-only queries may use `taskwarrior/tw` directly.

## Important: Script-Only Mutations

Agents must NEVER call `taskwarrior/tw` directly for: `modify`, `add`, `done`, `start`, `stop`, `annotate`, `denotate`, or `delete`. Use the provided scripts instead. Read-only operations (`export`, `count`, `list`, custom reports) are fine with `taskwarrior/tw`.

## Exit Code Convention

All scripts follow:
- **Exit 0**: success
- **Exit 1**: precondition not met (retry later)
- **Exit 2**: error (invalid args, illegal state, conflict)

---

## PM Scripts (run from main project tree)

### Acquire/Release PM Lock

```bash
ccmd bash taskwarrior/pm-lock-acquire    # exit 1 if already held
ccmd bash taskwarrior/pm-lock-release
```

### Preflight Check

```bash
ccmd bash taskwarrior/pm-preflight       # read-only status across all worktrees
```

### Epic Lifecycle

```bash
# Fork a new epic (creates worktree, initializes TW, registers epic)
ccmd bash taskwarrior/epic-fork EXXXX slug       # exit 1 if gate held

# Check status of all epics
ccmd bash taskwarrior/epic-status

# Mark epic ready for merge (after Coordinator completes)
ccmd bash taskwarrior/epic-mark-ready EXXXX      # exit 2 if not 'active'

# Merge epic to main (acquires gate, squash-merges, cleans up)
ccmd bash taskwarrior/epic-merge EXXXX           # exit 1 if gate held, exit 2 if conflict

# Rebase epic branch on latest main
ccmd bash taskwarrior/epic-rebase EXXXX          # exit 2 if conflict

# Merge gate inspection
ccmd bash taskwarrior/epic-gate-status
ccmd bash taskwarrior/epic-gate-release --force  # manual recovery only
```

---

## Coordinator Scripts (run from within epic worktree)

### Acquire/Release Coordinator Lock

```bash
ccmd bash taskwarrior/coordinator-lock-acquire   # exit 1 if already held
ccmd bash taskwarrior/coordinator-lock-release
ccmd bash taskwarrior/coordinator-lock-status    # read-only
```

### Story Lifecycle

```bash
# Initialize story (creates 4 phase tasks + git branch)
ccmd bash taskwarrior/story-init XXXXX slug

# Query next actionable task (returns JSON or "NONE")
ccmd bash taskwarrior/story-next XXXXX

# Verify all phases done, optionally run tests
ccmd bash taskwarrior/story-complete XXXXX --run-tests   # exit 1 if not done, exit 2 if tests fail

# Merge story branch into epic branch
ccmd bash taskwarrior/story-merge XXXXX slug
```

---

## Phase Scripts (run from within epic worktree)

### Task Activation

```bash
# Start a phase task (guards against other active tasks)
ccmd bash taskwarrior/phase-start <task-id>      # exit 1 if another task active

# Stop a phase task
ccmd bash taskwarrior/phase-stop <task-id>
```

### State Transitions

```bash
# Validated state change (checks transition is legal)
ccmd bash taskwarrior/phase-transition <task-id> <new-state>

# Legal transitions:
#   plan → plan-review
#   plan-review → write (approved)
#   plan-review → plan (rejected)
#   write → review
#   review → done (approved)
#   review → write (rejected)
#   blocked → plan/plan-review/write/review (recovery)
```

### Annotations

```bash
# Add a validated annotation
ccmd bash taskwarrior/phase-annotate <task-id> <prefix> <value>

# Valid prefixes:
#   Plan          - plan file path
#   Plan-review   - "approved"
#   Plan-feedback - feedback file path (plan rejected)
#   Artifact      - artifact file path
#   Deleted       - deleted artifact path
#   Test fix      - reason for test modification
#   Feedback      - review feedback file path (review rejected)
#   Review        - "approved"
#   Escalation    - escalation file path
#   Recovery      - recovery summary
```

### Completion and Blocking

```bash
# Mark phase done (sets aistate:done, completes task)
ccmd bash taskwarrior/phase-done <task-id>

# Block task with escalation
ccmd bash taskwarrior/phase-block <task-id> <escalation-path>
```

---

## Read-Only Queries (direct taskwarrior/tw usage allowed)

```bash
# Export task JSON
ccmd bash taskwarrior/tw <task-id> export

# Count tasks
ccmd bash taskwarrior/tw status:pending aistory:XXXXX count
ccmd bash taskwarrior/tw +ACTIVE -AI_LOCK count

# Custom reports
ccmd bash taskwarrior/tw ainext       # next actionable task
ccmd bash taskwarrior/tw aistory      # all story tasks
ccmd bash taskwarrior/tw ailocks      # lock status
ccmd bash taskwarrior/tw aiactive     # active phase tasks
ccmd bash taskwarrior/tw aiepics      # all epics (main tree only)
```

---

## Manual Recovery

```bash
# Cleanup stale state (dry-run first, then --apply)
ccmd bash taskwarrior/cleanup-ai-state.sh
ccmd bash taskwarrior/cleanup-ai-state.sh --apply

# Scope to specific epic
ccmd bash taskwarrior/cleanup-ai-state.sh --apply --epic EXXXX

# Clear escalations
ccmd bash taskwarrior/cleanup-ai-state.sh --apply --epic EXXXX --clear-escalations

# Release stuck merge gate
ccmd bash taskwarrior/cleanup-ai-state.sh --apply --release-gate
# or directly:
ccmd bash taskwarrior/epic-gate-release --force
```

---

## Typical Flows

### PM: Dispatch an Epic

```bash
ccmd bash taskwarrior/pm-lock-acquire
ccmd bash taskwarrior/pm-preflight
ccmd bash taskwarrior/epic-fork E0001 auth-system
# Launch Coordinator subagent pointed at .worktrees/epic-E0001-auth-system/
```

### PM: Merge a Completed Epic

```bash
ccmd bash taskwarrior/epic-mark-ready E0001
ccmd bash taskwarrior/epic-merge E0001
```

### Coordinator: Process a Story Phase

```bash
ccmd bash taskwarrior/story-next 00001
# → JSON with task_id, phase, state, annotations
ccmd bash taskwarrior/phase-start 5
# invoke subagent...
ccmd bash taskwarrior/phase-stop 5
# check outcome from annotations
```

### Phase Agent: Complete Work

```bash
# Plan agent:
ccmd bash taskwarrior/phase-annotate 5 Plan plan/requirement-plans/00001-auth.md
ccmd bash taskwarrior/phase-transition 5 plan-review

# Review agent (approve):
ccmd bash taskwarrior/phase-annotate 5 Review approved
ccmd bash taskwarrior/phase-transition 5 done

# Review agent (reject):
ccmd bash taskwarrior/phase-annotate 5 Feedback plan/requirements-review/00001-feedback.md
ccmd bash taskwarrior/phase-transition 5 write
```
