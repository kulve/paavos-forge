# Taskwarrior Script Recipes

Command reference for AI agents using the execution framework. All state mutations go through scripts. Read-only queries may use `taskwarrior/tw` directly.

## Important: Script-Only Mutations

Agents must NEVER call `taskwarrior/tw` directly for: `modify`, `add`, `done`, `start`, `stop`, `annotate`, `denotate`, or `delete`. Use the provided scripts instead. Read-only operations (`export`, `count`, `list`, custom reports) are fine with `taskwarrior/tw`.

## Important: Invoke Scripts by Absolute Path

Every script sources `taskwarrior/guard.sh`, which resolves its tree from the script's own location, exports an absolute `TASKDATA`, and enforces the execution context. Because subagents cannot be given a working directory, agents must invoke scripts by absolute path:

```bash
bash /abs/path/to/project/taskwarrior/epic-status                                  # main tree
bash /abs/path/to/project/.worktrees/epic-E0001-slug/taskwarrior/story-next 00001   # worktree
```

The command lines in this document are written relative for readability. Substitute the tree root you mean. A relative invocation from the wrong directory targets the wrong tree, which is exactly the failure the guard prevents.

## Context Guard

- Main-tree-only scripts (`epic-*`, `pm-*`, `doctor`, `coordinator-status`, `cleanup-ai-state.sh`) exit 2 with an explanatory message when run against a worktree.
- Worktree-only scripts (`coordinator-*`, `story-*`, `phase-*`) exit 2 when run against the main tree.
- Exit 2 from a guard means *wrong context*, not a transient problem. Re-running it cannot help; fix the path.
- `tw`, `env.sh`, and `setup.sh` work in both trees; `setup.sh` validates the tree against its own `--main` / `--worktree` flag.

## Generated Configuration

`.taskrc` is generated per tree by `setup.sh` from `taskwarrior/taskrc.template`, with an absolute `data.location`. It is gitignored: a worktree's `.taskrc` carries Coordinator-mode UDAs and must never reach `main` through a merge.

## Exit Code Convention

All scripts follow:
- **Exit 0**: success
- **Exit 1**: precondition not met (retry later)
- **Exit 2**: error (invalid args, illegal state, wrong context, conflict)

---

## PM Scripts (run from main project tree)

### Acquire/Release PM Lock

```bash
bash taskwarrior/pm-lock-acquire    # exit 1 if already held
bash taskwarrior/pm-lock-release
```

### Preflight Check

```bash
bash taskwarrior/pm-preflight       # read-only status across all worktrees
```

### Epic Lifecycle

```bash
# Fork a new epic (creates worktree, initializes TW, registers epic)
bash taskwarrior/epic-fork EXXXX slug       # exit 1 if gate held

# Check status of all epics
bash taskwarrior/epic-status

# Mark epic ready for merge (after Coordinator completes)
bash taskwarrior/epic-mark-ready EXXXX      # exit 2 if not 'active'

# Merge epic to main (acquires gate, squash-merges, cleans up)
bash taskwarrior/epic-merge EXXXX           # exit 1 if gate held, exit 2 if conflict

# Rebase epic branch on latest main
bash taskwarrior/epic-rebase EXXXX          # exit 2 if conflict

# Merge gate inspection
bash taskwarrior/epic-gate-status
bash taskwarrior/epic-gate-release --force  # manual recovery only
```

### Coordinator Supervision

```bash
# Liveness and progress for every epic worktree.
# Exit 0: all OK/DONE. Exit 1: something STALE. Exit 2: DEAD, NO-HEARTBEAT, or escalation.
bash taskwarrior/coordinator-status
bash taskwarrior/coordinator-status --epic E0001
bash taskwarrior/coordinator-status --json

# Thresholds (seconds), overridable per project:
#   AI_HEARTBEAT_STALE_SECONDS  default 1800
#   AI_HEARTBEAT_DEAD_SECONDS   default 5400
```

Liveness values: `OK`, `STALE`, `DEAD`, `NO-HEARTBEAT` (Coordinator never started), `DONE` (stopped with the lock free). Never infer Coordinator progress from agent transcripts.

### Diagnostics

```bash
# Check framework invariants D01-D12. Dry-run: changes nothing.
bash taskwarrior/doctor
bash taskwarrior/doctor --json

# Apply only the repairs marked `fixable`. Refuses while an AI lock is ACTIVE.
bash taskwarrior/doctor --fix

# Exit 0: all clear. Exit 1: only fixable failures remain. Exit 2: a failure needs a human.
```

`--fix` is reserved for the `environment-recovery` agent and the user. Manual-only checks (D07, D09, D10, D11, D12) are never auto-repaired; they involve tracked config, orphaned active tasks, held locks, missing worktrees, and escalation bookkeeping.

---

## Coordinator Scripts (worktree tree)

These require `require_context worktree`. The `bash taskwarrior/<script>` form below assumes the worktree is your working directory; agents launched from the main tree must instead use the absolute form `bash <worktree>/taskwarrior/<script>`.

### Acquire/Release Coordinator Lock

```bash
bash taskwarrior/coordinator-lock-acquire   # exit 1 if already held
bash taskwarrior/coordinator-lock-release
bash taskwarrior/coordinator-lock-status    # read-only
```

### Story Lifecycle

```bash
# Initialize story (creates 4 phase tasks + git branch)
bash taskwarrior/story-init XXXXX slug

# Query next actionable task (returns JSON or "NONE")
bash taskwarrior/story-next XXXXX

# Verify all phases done, optionally run tests
bash taskwarrior/story-complete XXXXX --run-tests   # exit 1 if not done, exit 2 if tests fail

# Merge story branch into epic branch
bash taskwarrior/story-merge XXXXX slug
```

---

## Phase Scripts (worktree tree)

Same rule as the Coordinator scripts: use `bash <worktree>/taskwarrior/<script>` unless the worktree is already your working directory.

### Task Activation

```bash
# Start a phase task (guards against other active tasks)
bash taskwarrior/phase-start <task-id>      # exit 1 if another task active

# Stop a phase task
bash taskwarrior/phase-stop <task-id>
```

### State Transitions

```bash
# Validated state change (checks transition is legal)
bash taskwarrior/phase-transition <task-id> <new-state>

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
bash taskwarrior/phase-annotate <task-id> <prefix> <value>

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
bash taskwarrior/phase-done <task-id>

# Block task with escalation
bash taskwarrior/phase-block <task-id> <escalation-path>
```

### Progress Telemetry (automatic)

```bash
# Called by the lifecycle scripts above. Agents never call this directly.
bash taskwarrior/coordinator-heartbeat <event> [story=..] [phase=..] [state=..] [detail=..]
```

Writes `.task/coordinator-status.json` and appends to `.task/coordinator-events.log`. It never fails its caller: a telemetry problem prints a warning and exits 0. Events: `started`, `story-init`, `phase-start`, `annotate`, `state`, `phase-stop`, `phase-done`, `escalated`, `story-verified`, `story-merged`, `stopped`.

---

## Read-Only Queries (direct taskwarrior/tw usage allowed)

```bash
# Export task JSON
bash taskwarrior/tw <task-id> export

# Count tasks
bash taskwarrior/tw status:pending aistory:XXXXX count
bash taskwarrior/tw +ACTIVE -AI_LOCK count

# Custom reports
bash taskwarrior/tw ainext       # next actionable task
bash taskwarrior/tw aistory      # all story tasks
bash taskwarrior/tw ailocks      # lock status
bash taskwarrior/tw aiactive     # active phase tasks
bash taskwarrior/tw aiepics      # all epics (main tree only)
```

---

## Manual Recovery

```bash
# Cleanup stale state (dry-run first, then --apply)
bash taskwarrior/cleanup-ai-state.sh
bash taskwarrior/cleanup-ai-state.sh --apply

# Scope to specific epic
bash taskwarrior/cleanup-ai-state.sh --apply --epic EXXXX

# Clear escalations
bash taskwarrior/cleanup-ai-state.sh --apply --epic EXXXX --clear-escalations

# Release stuck merge gate
bash taskwarrior/cleanup-ai-state.sh --apply --release-gate
# or directly:
bash taskwarrior/epic-gate-release --force
```

---

## Typical Flows

### PM: Dispatch an Epic

```bash
bash taskwarrior/pm-lock-acquire
bash taskwarrior/pm-preflight
# Commit the framework and planning files to main first: epic-fork rejects an
# uncommitted or undeployed tree, because the worktree is created from main.
bash taskwarrior/epic-fork E0001 auth-system
# Launch a background Coordinator subagent. Subagents get no working directory,
# so put the absolute worktree path in the prompt:
#   <project>/.worktrees/epic-E0001-auth-system
bash taskwarrior/coordinator-status      # supervise; act on the exit code
```

### PM: Merge a Completed Epic

```bash
bash taskwarrior/epic-mark-ready E0001
bash taskwarrior/epic-merge E0001
```

### Coordinator: Process a Story Phase

```bash
bash taskwarrior/story-next 00001
# → JSON with task_id, phase, state, annotations
bash taskwarrior/phase-start 5
# invoke subagent...
bash taskwarrior/phase-stop 5
# check outcome from annotations
```

### Phase Agent: Complete Work

```bash
# Plan agent:
bash taskwarrior/phase-annotate 5 Plan plan/requirement-plans/00001-auth.md
bash taskwarrior/phase-transition 5 plan-review

# Review agent (approve):
bash taskwarrior/phase-annotate 5 Review approved
bash taskwarrior/phase-transition 5 done

# Review agent (reject):
bash taskwarrior/phase-annotate 5 Feedback plan/requirements-review/00001-feedback.md
bash taskwarrior/phase-transition 5 write
```
