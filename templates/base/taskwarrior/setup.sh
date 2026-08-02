#!/bin/bash
# Idempotent Taskwarrior UDA setup for the AI execution framework.
# Two modes:
#   setup.sh --main      : Configure PM-level state (run once on project root)
#   setup.sh --worktree  : Configure Coordinator/phase-level state (run per epic worktree)
#
# Uses per-project .taskrc and .task/ (not ~/.taskrc).
set -euo pipefail

# No require_context call: this script validates the context against its own flag.
# shellcheck source=guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/guard.sh"

MODE="${1:-}"
if [ "$MODE" != "--main" ] && [ "$MODE" != "--worktree" ]; then
    echo "Usage: setup.sh --main | --worktree"
    echo "  --main      : PM-level setup (project root, epic tracking, merge gate)"
    echo "  --worktree  : Worktree-level setup (Coordinator lock, phase UDAs)"
    exit 2
fi

# The mode must match the kind of tree this script resolved to, or the wrong
# database gets the wrong UDAs (the original worktree-isolation failure).
EXPECTED_CONTEXT="main"
[ "$MODE" = "--worktree" ] && EXPECTED_CONTEXT="worktree"
ACTUAL_CONTEXT="$(ai_context)"
if [ "$ACTUAL_CONTEXT" != "$EXPECTED_CONTEXT" ]; then
    echo "ERROR: setup.sh ${MODE} requires the ${EXPECTED_CONTEXT} tree."
    echo "  Resolved root: ${AI_ROOT} (detected: ${ACTUAL_CONTEXT})"
    exit 2
fi
if [ "$MODE" = "--worktree" ] && [[ "$AI_ROOT" != */.worktrees/epic-* ]]; then
    echo "ERROR: setup.sh --worktree resolved root ${AI_ROOT} is not an epic worktree."
    exit 2
fi

# Generate .taskrc if absent. It is gitignored and mode-specific, so it must be
# generated per tree rather than inherited through git from the main tree.
if [ ! -f "${TASKRC}" ]; then
    TEMPLATE="${AI_ROOT}/taskwarrior/taskrc.template"
    if [ ! -f "$TEMPLATE" ]; then
        echo "ERROR: Missing ${TEMPLATE}. Cannot generate .taskrc."
        exit 2
    fi
    cp "$TEMPLATE" "${TASKRC}"
    echo "data.location=${AI_ROOT}/.task" >> "${TASKRC}"
    echo "Generated ${TASKRC}"
fi

echo "Configuring AI execution framework (TASKRC=${TASKRC}, mode=${MODE})..."

# Suppress the per-setting "Config file ... modified." chatter; errors still surface.
tw_config() {
    task config "$@" >/dev/null
}

if [ "$MODE" = "--main" ]; then
    # === PM-level UDAs ===

    # Epic ID: links task to an epic
    tw_config uda.aiepic.type string
    tw_config uda.aiepic.label "AI Epic ID"

    # Epic state: lifecycle of an epic
    tw_config uda.epicstate.type string
    tw_config uda.epicstate.label "Epic State"
    tw_config uda.epicstate.values "active,merge-ready,merging,merged,conflict,cancelled"

    # Role lock UDA (PM only in main tree)
    tw_config uda.airole.type string
    tw_config uda.airole.label "AI Role Lock"
    tw_config uda.airole.values "pm"

    # Custom reports
    tw_config report.aiepics.description "All AI epics"
    tw_config report.aiepics.columns "id,aiepic,epicstate,description"
    tw_config report.aiepics.filter "aiepic.any:"
    tw_config report.aiepics.sort "aiepic+"

    tw_config report.ailocks.description "AI role lock status"
    tw_config report.ailocks.columns "id,airole,start,description"
    tw_config report.ailocks.filter "+AI_LOCK"
    tw_config report.ailocks.sort "airole+"

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
    tw_config uda.aiphase.type string
    tw_config uda.aiphase.label "AI Phase"
    tw_config uda.aiphase.values "req,arch,test,impl"

    # State: current progress within a phase
    tw_config uda.aistate.type string
    tw_config uda.aistate.label "AI State"
    tw_config uda.aistate.values "blocked,plan,write,review,done"

    # Story ID: links task to its parent story
    tw_config uda.aistory.type string
    tw_config uda.aistory.label "AI Story ID"

    # Role lock UDA (Coordinator only in worktree)
    tw_config uda.airole.type string
    tw_config uda.airole.label "AI Role Lock"
    tw_config uda.airole.values "coordinator"

    # Custom reports
    tw_config report.ainext.description "Next actionable AI task"
    tw_config report.ainext.columns "id,aistory,aiphase,aistate,description"
    tw_config report.ainext.filter "status:pending +READY -AI_LOCK"
    tw_config report.ainext.sort "aistory+,aiphase+"

    tw_config report.aistory.description "All AI tasks for a story"
    tw_config report.aistory.columns "id,aiphase,aistate,description,depends"
    tw_config report.aistory.filter "status:pending or status:completed"
    tw_config report.aistory.sort "aiphase+"

    tw_config report.ailocks.description "AI role lock status"
    tw_config report.ailocks.columns "id,airole,start,description"
    tw_config report.ailocks.filter "+AI_LOCK"
    tw_config report.ailocks.sort "airole+"

    tw_config report.aiactive.description "Active phase subagent tasks"
    tw_config report.aiactive.columns "id,aistory,aiphase,aistate,description"
    tw_config report.aiactive.filter "+ACTIVE -AI_LOCK"
    tw_config report.aiactive.sort "aistory+,aiphase+"

    # Coordinator lock task
    COORD_LOCK_COUNT=$(task status:pending +AI_LOCK airole:coordinator count 2>/dev/null || echo "0")
    if [ "$COORD_LOCK_COUNT" -eq 0 ]; then
        task add "AI Framework Lock: Coordinator" +AI_LOCK airole:coordinator
        echo "Created Coordinator lock task."
    fi

    echo "Done (worktree). Verify with: taskwarrior/tw _udas | grep -E 'aiphase|aistate|aistory'"
    echo "  Lock tasks: taskwarrior/tw ailocks"
fi
