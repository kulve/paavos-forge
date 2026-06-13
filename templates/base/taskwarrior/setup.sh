#!/bin/bash
# Idempotent Taskwarrior UDA setup for the AI execution framework.
# Run this once after deploying the framework into a project.
# Safe to re-run -- task config overwrites existing values.
# Uses per-project .taskrc and .task/ (not ~/.taskrc).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

echo "Configuring AI execution framework UDAs (TASKRC=${TASKRC})..."

# Phase: which pipeline stage this task belongs to
task config uda.aiphase.type string
task config uda.aiphase.label "AI Phase"
task config uda.aiphase.values "req,arch,test,impl"

# State: current progress within a phase
task config uda.aistate.type string
task config uda.aistate.label "AI State"
task config uda.aistate.values "blocked,plan,plan-review,write,review,done"

# Story ID: links task to its parent story
task config uda.aistory.type string
task config uda.aistory.label "AI Story ID"

# Role lock: identifies PM/Coordinator singleton lock tasks (+AI_LOCK)
task config uda.airole.type string
task config uda.airole.label "AI Role Lock"
task config uda.airole.values "pm,coordinator"

# Custom report: shows the next actionable AI task
task config report.ainext.description "Next actionable AI task"
task config report.ainext.columns "id,aistory,aiphase,aistate,description"
task config report.ainext.filter "status:pending +READY -AI_LOCK"
task config report.ainext.sort "aistory+,aiphase+"

# Custom report: shows all AI tasks for a story
task config report.aistory.description "All AI tasks for a story"
task config report.aistory.columns "id,aiphase,aistate,description,depends"
task config report.aistory.filter "status:pending or status:completed"
task config report.aistory.sort "aiphase+"

# Custom report: shows PM and Coordinator lock tasks and their active status
task config report.ailocks.description "AI role lock status"
task config report.ailocks.columns "id,airole,start,description"
task config report.ailocks.filter "+AI_LOCK"
task config report.ailocks.sort "airole+"

# Custom report: shows active phase tasks (excludes lock tasks)
task config report.aiactive.description "Active phase subagent tasks"
task config report.aiactive.columns "id,aistory,aiphase,aistate,description"
task config report.aiactive.filter "+ACTIVE -AI_LOCK"
task config report.aiactive.sort "aistory+,aiphase+"

# Create singleton lock tasks if they don't already exist.
# These are permanent tasks that are never completed -- they are started/stopped
# to indicate that a PM or Coordinator agent is running.
PM_LOCK_COUNT=$(task +AI_LOCK airole:pm count 2>/dev/null || echo "0")
if [ "$PM_LOCK_COUNT" -eq 0 ]; then
    task add "AI Framework Lock: Project Manager" +AI_LOCK airole:pm
    echo "Created PM lock task."
fi

COORD_LOCK_COUNT=$(task +AI_LOCK airole:coordinator count 2>/dev/null || echo "0")
if [ "$COORD_LOCK_COUNT" -eq 0 ]; then
    task add "AI Framework Lock: Coordinator" +AI_LOCK airole:coordinator
    echo "Created Coordinator lock task."
fi

echo "Done. Verify with: taskwarrior/tw _udas | grep -E 'aiphase|aistate|aistory|airole'"
echo "      Lock tasks:  taskwarrior/tw ailocks"
