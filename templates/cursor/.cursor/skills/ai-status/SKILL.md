---
name: ai-status
description: Reports Paavo's Forge pipeline status - project roadmap, milestones, epics, stories, phases, Coordinator liveness, and the merge gate. Read-only.
disable-model-invocation: true
---

# AI Status

Show the current status of the Paavo's Forge pipeline.

This is a read-only report that sits outside the pipeline. Run it in its own chat, without the `project-manager` skill loaded. Do not mutate Taskwarrior state, do not touch git, and do not dispatch any subagent.

## Instructions

Run the following commands and present the results in a readable table format:

### Project Roadmap

Read `plan/project.md` (if present) and summarize:

1. **Paavo's Codex binding**: project name/id and pinned closed version
2. **Roadmap**: ordered milestones with Status (Done / In Progress / TODO)
3. **Current milestone**: the In Progress entry and its file under `plan/milestones/` if created
4. **Product Definition of Done**: whether the product appears complete

If `plan/project.md` is missing, report that project init (via `roadmap-planner`) is required before execution.

### Epic-Level Status (run from main tree)

```bash
bash taskwarrior/epic-status
bash taskwarrior/epic-gate-status
```

### Coordinator Liveness and Progress (run from main tree)

```bash
bash taskwarrior/coordinator-status
```

Report each worktree's lock state, liveness (`OK` / `STALE` / `DEAD` / `NO-HEARTBEAT` / `DONE`), last event with its age, active task, and progress counts. The exit code summarizes the fleet: 0 healthy, 1 something stale, 2 something dead or escalated. Never infer Coordinator progress from agent transcripts.

If liveness is anything other than `OK` or `DONE`, also run the diagnostics (read-only, never `--fix` from a status report):

```bash
bash taskwarrior/doctor
```

### Per-Worktree Story Status

For each active epic worktree listed by `epic-status`, query it by absolute path (no `cd` needed):

```bash
bash <worktree>/taskwarrior/tw status:pending aistory.any: export
bash <worktree>/taskwarrior/tw status:completed aistory.any: export
```

### Present Results As

1. **Project / roadmap** (from `plan/project.md`)
2. **Milestone progress** (Status from milestone files and roadmap)
3. **Epic table**: epic ID, slug, state (active/merge-ready/merged/conflict), worktree path
4. **Merge gate**: FREE or HELD (with details)
5. **Coordinator table**: epic, lock, liveness, last event and age, active task, progress
6. **Per-epic story table**: story ID, phase progress (req/arch/test/impl), current state, blocked/escalated items
7. **Summary**: total stories pending vs completed across all epics, plus any failing `doctor` checks

Highlight any blocked tasks or escalations. If `plan/escalations/` has files, list them.

Recovery is not your job. If something is blocked, dead, or escalated, report it and tell the user to start a `/project-manager` chat, which owns triage and recovery.
