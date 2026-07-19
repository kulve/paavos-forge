#!/bin/bash
# Manual AI state cleanup for the execution framework.
# Run this after confirming no Cursor agents or subagents are active.
#
# Usage:
#   cleanup-ai-state.sh [OPTIONS]
#
# Options:
#   --apply              Actually perform changes (default is dry-run)
#   --yes                Skip confirmation prompt
#   --story ID           Scope cleanup to a specific story
#   --epic ID            Scope cleanup to a specific epic
#   --locks-only         Only clean up lock state
#   --clear-escalations  Also clear escalation state on blocked tasks
#   --release-gate       Also release a stuck merge gate
#   -h, --help           Show this help
#
# What it does:
#   Main tree (run from project root):
#   - Stops active PM lock
#   - Stops active merge gate (with --release-gate)
#   - Resets epic state from 'merging' to 'merge-ready' (with --release-gate)
#
#   Worktree (auto-detected or specified via --epic):
#   - Stops active Coordinator lock
#   - Stops active phase tasks
#   - Optionally clears escalation state (with --clear-escalations)
#
# NEVER run this while agents are still active. Always confirm first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

PROJECT_ROOT="${SCRIPT_DIR}/.."

APPLY=false
YES=false
STORY=""
EPIC=""
LOCKS_ONLY=false
CLEAR_ESCALATIONS=false
RELEASE_GATE=false

usage() {
    head -27 "$0" | tail -25
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --apply) APPLY=true ;;
        --yes) YES=true ;;
        --story) STORY="$2"; shift ;;
        --epic) EPIC="$2"; shift ;;
        --locks-only) LOCKS_ONLY=true ;;
        --clear-escalations) CLEAR_ESCALATIONS=true ;;
        --release-gate) RELEASE_GATE=true ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
    shift
done

echo "=== AI State Cleanup ==="
echo "Mode: $([ "$APPLY" = true ] && echo 'APPLY' || echo 'DRY-RUN')"
echo ""

# --- Main tree checks ---
echo "--- Main Tree ($(pwd)) ---"

# PM Lock
PM_ACTIVE=$(task +AI_LOCK airole:pm +ACTIVE count 2>/dev/null || echo "0")
if [ "$PM_ACTIVE" -gt 0 ]; then
    PM_ID=$(task +AI_LOCK airole:pm +ACTIVE ids 2>/dev/null | awk '{print $1}')
    echo "  PM lock ACTIVE (task $PM_ID) -- will stop"
    if [ "$APPLY" = true ]; then
        task "$PM_ID" stop
        echo "    -> stopped"
    fi
else
    echo "  PM lock: free"
fi

# Merge gate
GATE_ACTIVE=$(task +MERGE_GATE +ACTIVE count 2>/dev/null || echo "0")
if [ "$GATE_ACTIVE" -gt 0 ]; then
    GATE_ID=$(task +MERGE_GATE +ACTIVE ids 2>/dev/null | awk '{print $1}')
    echo "  Merge gate ACTIVE (task $GATE_ID)"
    if [ "$RELEASE_GATE" = true ]; then
        echo "    -- will release (--release-gate specified)"
        if [ "$APPLY" = true ]; then
            task "$GATE_ID" stop
            # Reset any epic stuck in 'merging'
            task "epicstate:merging" modify "epicstate:merge-ready" 2>/dev/null || true
            echo "    -> released"
        fi
    else
        echo "    -- skipping (use --release-gate to release)"
    fi
else
    echo "  Merge gate: free"
fi

# Epic state report
echo ""
echo "  Epics:"
task aiepic.any: export 2>/dev/null | python3 -c "
import sys, json
tasks = json.load(sys.stdin)
if not tasks:
    print('    (none)')
else:
    for t in tasks:
        print(f\"    {t.get('aiepic','?')}: {t.get('epicstate','?')} - {t.get('description','')}\")
" 2>/dev/null || echo "    (error reading)"

# --- Worktree checks ---
echo ""
echo "--- Worktrees ---"

cleanup_worktree() {
    local wt_path="$1"
    local wt_name=$(basename "$wt_path")
    
    if [ ! -f "${wt_path}/taskwarrior/tw" ]; then
        echo "  $wt_name: no taskwarrior/tw (skipping)"
        return
    fi
    
    echo "  $wt_name:"
    
    # Coordinator lock
    local coord_active
    coord_active=$(cd "$wt_path" && bash taskwarrior/tw +AI_LOCK airole:coordinator +ACTIVE count 2>/dev/null || echo "0")
    if [ "$coord_active" -gt 0 ]; then
        local coord_id
        coord_id=$(cd "$wt_path" && bash taskwarrior/tw +AI_LOCK airole:coordinator +ACTIVE ids 2>/dev/null | awk '{print $1}')
        echo "    Coordinator lock ACTIVE (task $coord_id) -- will stop"
        if [ "$APPLY" = true ]; then
            (cd "$wt_path" && bash taskwarrior/tw "$coord_id" stop)
            echo "      -> stopped"
        fi
    else
        echo "    Coordinator lock: free"
    fi
    
    if [ "$LOCKS_ONLY" = true ]; then
        return
    fi
    
    # Active phase tasks
    local phase_active
    phase_active=$(cd "$wt_path" && bash taskwarrior/tw +ACTIVE -AI_LOCK count 2>/dev/null || echo "0")
    if [ "$phase_active" -gt 0 ]; then
        echo "    Active phase tasks: $phase_active -- will stop"
        if [ "$APPLY" = true ]; then
            local task_ids
            task_ids=$(cd "$wt_path" && bash taskwarrior/tw +ACTIVE -AI_LOCK ids 2>/dev/null)
            for tid in $task_ids; do
                (cd "$wt_path" && bash taskwarrior/tw "$tid" stop)
                echo "      -> stopped task $tid"
            done
        fi
    else
        echo "    Active phase tasks: none"
    fi
    
    # Escalation cleanup
    if [ "$CLEAR_ESCALATIONS" = true ]; then
        local blocked
        blocked=$(cd "$wt_path" && bash taskwarrior/tw +blocked status:pending count 2>/dev/null || echo "0")
        if [ "$blocked" -gt 0 ]; then
            echo "    Blocked tasks with escalations: $blocked -- will clear"
            if [ "$APPLY" = true ]; then
                (cd "$wt_path" && bash taskwarrior/tw +blocked status:pending export 2>/dev/null | python3 -c "
import sys, json, subprocess, os
os.chdir('$wt_path')
tasks = json.load(sys.stdin)
for t in tasks:
    tid = str(t['id'])
    annotations = t.get('annotations', [])
    for ann in annotations:
        desc = ann.get('description', '')
        if desc.startswith('Escalation:'):
            subprocess.run(['bash', 'taskwarrior/tw', tid, 'denotate', desc], check=True)
            esc_path = desc.split('Escalation: ', 1)[1].strip()
            if os.path.exists(esc_path):
                os.remove(esc_path)
                print(f'      -> removed {esc_path}')
    # Infer resume state from annotations
    resume = 'plan'
    for ann in annotations:
        desc = ann.get('description', '')
        if desc.startswith('Review: approved'): resume = 'done'
        elif desc.startswith('Feedback:'): resume = 'write'
        elif desc.startswith('Plan-review: approved'): resume = 'write'
        elif desc.startswith('Plan-feedback:'): resume = 'plan'
        elif desc.startswith('Plan:'): resume = 'plan-review'
    subprocess.run(['bash', 'taskwarrior/tw', tid, 'modify', '-blocked', f'aistate:{resume}'], check=True)
    print(f'      -> task {tid} unblocked, aistate:{resume}')
" 2>/dev/null)
            fi
        fi
    fi
}

if [ -n "$EPIC" ]; then
    # Find specific epic worktree
    for wt in "${PROJECT_ROOT}/.worktrees"/epic-${EPIC}-*/; do
        if [ -d "$wt" ]; then
            cleanup_worktree "$wt"
        fi
    done
elif [ -d "${PROJECT_ROOT}/.worktrees" ]; then
    for wt in "${PROJECT_ROOT}/.worktrees"/*/; do
        if [ -d "$wt" ]; then
            cleanup_worktree "$wt"
        fi
    done
else
    echo "  No worktrees found."
fi

echo ""
if [ "$APPLY" = true ]; then
    echo "=== Cleanup applied ==="
else
    echo "=== Dry run complete. Use --apply to execute changes. ==="
fi
