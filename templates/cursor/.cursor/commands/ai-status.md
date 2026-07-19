---
description: "Show pipeline status: project roadmap, epics, stories, phases, and merge gate"
---

# AI Status

Show the current status of the AI execution framework pipeline.

## Instructions

Run the following commands and present the results in a readable table format:

### Project Roadmap

Read `plan/project.md` (if present) and summarize:

1. **Paavo Notes binding**: project name/id and pinned closed version
2. **Roadmap**: ordered milestones with Status (Done / In Progress / TODO)
3. **Current milestone**: the In Progress entry and its file under `plan/milestones/` if created
4. **Product Definition of Done**: whether the product appears complete

If `plan/project.md` is missing, report that project init (via `roadmap-planner`) is required before execution.

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

1. **Project / roadmap** (from `plan/project.md`)
2. **Milestone progress** (Status from milestone files and roadmap)
3. **Epic table**: epic ID, slug, state (active/merge-ready/merged/conflict), worktree path
4. **Merge gate**: FREE or HELD (with details)
5. **Per-epic story table**: story ID, phase progress (req/arch/test/impl), current state, blocked/escalated items
6. **Summary**: total stories pending vs completed across all epics

Highlight any blocked tasks or escalations. If `plan/escalations/` has files, list them.
