---
description: "Show pipeline status: epics, stories, phases, and merge gate"
---

# AI Status

Show the current status of the AI execution framework pipeline.

## Instructions

Run the following commands and present the results in a readable table format:

### Epic-Level Status (run from main tree)

```bash
ccmd bash taskwarrior/epic-status
ccmd bash taskwarrior/epic-gate-status
```

### Per-Worktree Story Status

For each active epic worktree listed by `epic-status`, run from within that worktree:

```bash
ccmd bash taskwarrior/tw status:pending aistory.any: export
ccmd bash taskwarrior/tw status:completed aistory.any: export
```

### Present Results As

1. **Milestone progress** (if a milestone file exists in `plan/milestones/`)
2. **Epic table**: epic ID, slug, state (active/merge-ready/merged/conflict), worktree path
3. **Merge gate**: FREE or HELD (with details)
4. **Per-epic story table**: story ID, phase progress (req/arch/test/impl), current state, blocked/escalated items
5. **Summary**: total stories pending vs completed across all epics

Highlight any blocked tasks or escalations. If `plan/escalations/` has files, list them.
