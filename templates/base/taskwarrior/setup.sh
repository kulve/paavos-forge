#!/bin/bash
# Idempotent Taskwarrior UDA setup for the AI execution framework.
# Two modes:
#   setup.sh --main      : Configure PM-level state (run once on project root)
#   setup.sh --worktree  : Configure Coordinator/phase-level state (run per epic worktree)
#
# Uses per-project .taskrc and .task/ (not ~/.taskrc).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

MODE="${1:-}"
if [ "$MODE" != "--main" ] && [ "$MODE" != "--worktree" ]; then
    echo "Usage: setup.sh --main | --worktree"
    echo "  --main      : PM-level setup (project root, epic tracking, merge gate)"
    echo "  --worktree  : Worktree-level setup (Coordinator lock, phase UDAs)"
    exit 2
fi

echo "Configuring AI execution framework (TASKRC=${TASKRC}, mode=${MODE})..."

if [ "$MODE" = "--main" ]; then
    # === PM-level UDAs ===

    # Epic ID: links task to an epic
    task config uda.aiepic.type string
    task config uda.aiepic.label "AI Epic ID"

    # Epic state: lifecycle of an epic
    task config uda.epicstate.type string
    task config uda.epicstate.label "Epic State"
    task config uda.epicstate.values "active,merge-ready,merging,merged,conflict,cancelled"

    # Role lock UDA (PM only in main tree)
    task config uda.airole.type string
    task config uda.airole.label "AI Role Lock"
    task config uda.airole.values "pm"

    # Custom reports
    task config report.aiepics.description "All AI epics"
    task config report.aiepics.columns "id,aiepic,epicstate,description"
    task config report.aiepics.filter "aiepic.any:"
    task config report.aiepics.sort "aiepic+"

    task config report.ailocks.description "AI role lock status"
    task config report.ailocks.columns "id,airole,start,description"
    task config report.ailocks.filter "+AI_LOCK"
    task config report.ailocks.sort "airole+"

    # Singleton lock tasks
    PM_LOCK_COUNT=$(task status:pending +AI_LOCK airole:pm count 2>/dev/null || echo "0")
    if [ "$PM_LOCK_COUNT" -eq 0 ]; then
        task add "AI Framework Lock: Project Manager" +AI_LOCK airole:pm
        echo "Created PM lock task."
    fi

    # Merge gate task
    GATE_COUNT=$(task status:pending +MERGE_GATE count 2>/dev/null || echo "0")
    if [ "$GATE_COUNT" -eq 0 ]; then
        task add "AI Framework: Merge Gate" +MERGE_GATE
        echo "Created merge gate task."
    fi

    echo "Done (main). Verify with: taskwarrior/tw aiepics"
    echo "  Lock tasks: taskwarrior/tw ailocks"

elif [ "$MODE" = "--worktree" ]; then
    # === Worktree-level UDAs ===

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

    # Role lock UDA (Coordinator only in worktree)
    task config uda.airole.type string
    task config uda.airole.label "AI Role Lock"
    task config uda.airole.values "coordinator"

    # Custom reports
    task config report.ainext.description "Next actionable AI task"
    task config report.ainext.columns "id,aistory,aiphase,aistate,description"
    task config report.ainext.filter "status:pending +READY -AI_LOCK"
    task config report.ainext.sort "aistory+,aiphase+"

    task config report.aistory.description "All AI tasks for a story"
    task config report.aistory.columns "id,aiphase,aistate,description,depends"
    task config report.aistory.filter "status:pending or status:completed"
    task config report.aistory.sort "aiphase+"

    task config report.ailocks.description "AI role lock status"
    task config report.ailocks.columns "id,airole,start,description"
    task config report.ailocks.filter "+AI_LOCK"
    task config report.ailocks.sort "airole+"

    task config report.aiactive.description "Active phase subagent tasks"
    task config report.aiactive.columns "id,aistory,aiphase,aistate,description"
    task config report.aiactive.filter "+ACTIVE -AI_LOCK"
    task config report.aiactive.sort "aistory+,aiphase+"

    # Coordinator lock task
    COORD_LOCK_COUNT=$(task status:pending +AI_LOCK airole:coordinator count 2>/dev/null || echo "0")
    if [ "$COORD_LOCK_COUNT" -eq 0 ]; then
        task add "AI Framework Lock: Coordinator" +AI_LOCK airole:coordinator
        echo "Created Coordinator lock task."
    fi

    echo "Done (worktree). Verify with: taskwarrior/tw _udas | grep -E 'aiphase|aistate|aistory'"
    echo "  Lock tasks: taskwarrior/tw ailocks"
fi
