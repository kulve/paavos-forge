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

# Custom report: shows the next actionable AI task
task config report.ainext.description "Next actionable AI task"
task config report.ainext.columns "id,aistory,aiphase,aistate,description"
task config report.ainext.filter "status:pending +READY"
task config report.ainext.sort "aistory+,aiphase+"

# Custom report: shows all AI tasks for a story
task config report.aistory.description "All AI tasks for a story"
task config report.aistory.columns "id,aiphase,aistate,description,depends"
task config report.aistory.filter "status:pending or status:completed"
task config report.aistory.sort "aiphase+"

echo "Done. Verify with: taskwarrior/tw _udas | grep -E 'aiphase|aistate|aistory'"
