---
description: "Show current AI execution framework status"
---

Query Taskwarrior and summarize the current state of the AI execution pipeline.

## Steps

1. Read the current milestone from `plan/milestones/` (find the latest one).

2. Query Taskwarrior for all AI tasks:
   ```bash
   task status:pending aistory.any: export
   task status:completed aistory.any: export
   ```

3. Summarize in a table:
   - Current milestone name and progress
   - For each active story: story ID, current phase, current state, any blocked tasks
   - Count of completed stories vs total
   - Any escalations in `plan/escalations/`

4. If there are blocked tasks or escalations, highlight them and suggest next steps.

Format the output as a concise status table that a human can scan quickly.
