---
description: "Show or run the next pipeline step for an epic"
---

# AI Next

Show the next actionable pipeline step, optionally scoped to a specific epic.

## Instructions

### If epic ID or worktree path is provided in the prompt

Run from within that epic's worktree:

```bash
ccmd bash taskwarrior/story-next <story-id>
```

Or if no specific story is given, find the active story:

```bash
ccmd bash taskwarrior/tw status:pending +READY -AI_LOCK aistory.any: export
```

### If no epic specified

Run from the main tree to show all active epics:

```bash
ccmd bash taskwarrior/epic-status
```

Then for each active worktree, show the next task.

### Present Results As

1. **Epic**: which epic this task belongs to
2. **Story**: story ID and slug
3. **Phase**: req/arch/test/impl
4. **State**: plan/plan-review/write/review
5. **Subagent**: which agent would handle this (from the Coordinator mapping)
6. **Context files**: relevant annotation paths (Plan, Feedback, etc.)
7. **Coordinator lock status**: whether the Coordinator lock is held in that worktree

### Optional: Invoke

If the user explicitly asks to "run" the next step, and the Coordinator lock is NOT held:
- Ask confirmation before proceeding
- Reference the Coordinator procedure in `ai-framework/LOGIC.md` section 5
- Do NOT invoke if the Coordinator lock is held (tell the user a Coordinator is already running)
