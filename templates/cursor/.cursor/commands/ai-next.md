---
description: "Show or execute the next step in the AI execution pipeline"
---

Equivalent to one iteration of the Coordinator loop. Useful for step-by-step debugging.

## Steps

1. Query Taskwarrior for the next ready task:
   ```bash
   taskwarrior/tw status:pending +READY aistory.any: export
   ```

2. If no ready tasks, report that the pipeline is idle or all stories are complete.

3. If a ready task exists, report:
   - Task ID, story, phase, and current state
   - Which subagent would be invoked
   - What files would be passed as context (from annotations)

4. Ask the user if they want to invoke the subagent or just see the status.

5. If the user confirms, invoke the appropriate subagent as described in the Coordinator's procedure (see `ai-framework/LOGIC.md` section 5).
