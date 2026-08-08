#!/bin/bash
# Sourced by every Forge script. Resolves the project tree root from this file's
# own location, makes Taskwarrior state absolute, and enforces execution context.
#
# Because the root is derived from ${BASH_SOURCE[0]} and this file cds into it,
# a script invoked by absolute path always operates on its own tree regardless of
# the caller's working directory.
AI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AI_ROOT
# shellcheck source=env.sh
source "${AI_ROOT}/taskwarrior/env.sh"
cd "$AI_ROOT"

# Print the execution context of AI_ROOT: main | worktree | unknown.
# A git worktree has .git as a regular file (a gitdir pointer); the main tree has
# it as a directory. No git invocation required.
ai_context() {
    if [ -f "${AI_ROOT}/.git" ]; then echo worktree
    elif [ -d "${AI_ROOT}/.git" ]; then echo main
    else echo unknown
    fi
}

# require_context main|worktree
# Exits 2 when the resolved root is not the required kind of tree.
require_context() {
    local want="$1" have
    have="$(ai_context)"
    if [ "$have" != "$want" ]; then
        echo "ERROR: $(basename "$0") must run in the ${want} tree. Resolved root: ${AI_ROOT} (detected: ${have})." >&2
        exit 2
    fi
    if [ "$want" = worktree ] && [[ "$AI_ROOT" != */.worktrees/epic-* ]]; then
        echo "ERROR: $(basename "$0") resolved root ${AI_ROOT} is not an epic worktree." >&2
        exit 2
    fi
}

# expected_epic_branch
# Echo the epic/* branch that belongs to this worktree, derived from AI_ROOT's
# directory name (.worktrees/epic-ID-slug → epic/ID-slug). Do not guess from git
# decorations or branch listing order: parallel epics forked from the same tip
# share decorations, and head -1 is non-deterministic.
# Exits 2 if AI_ROOT is not an epic worktree path or the branch ref is missing.
expected_epic_branch() {
    local base branch
    if [[ "$AI_ROOT" != */.worktrees/epic-* ]]; then
        echo "ERROR: expected_epic_branch: not an epic worktree: ${AI_ROOT}" >&2
        exit 2
    fi
    base="$(basename "$AI_ROOT")"
    if [[ ! "$base" =~ ^epic-(.+)$ ]]; then
        echo "ERROR: expected_epic_branch: cannot derive epic branch from: ${AI_ROOT}" >&2
        exit 2
    fi
    branch="epic/${BASH_REMATCH[1]}"
    if ! git rev-parse --verify --quiet "$branch" >/dev/null; then
        echo "ERROR: Expected epic branch '${branch}' does not exist." >&2
        exit 2
    fi
    echo "$branch"
}

# ai_heartbeat <event> [key=value ...]
# Record Coordinator progress. Never fails the caller, so lifecycle scripts can
# emit telemetry unconditionally.
ai_heartbeat() {
    bash "${AI_ROOT}/taskwarrior/coordinator-heartbeat" "$@" || true
}

# ai_task_fields <task-id>
# Echo "story=<aistory> phase=<aiphase> state=<aistate>" for use as heartbeat args.
ai_task_fields() {
    task "$1" export 2>/dev/null | python3 -c "
import sys, json
try:
    tasks = json.load(sys.stdin)
except Exception:
    tasks = []
t = tasks[0] if tasks else {}
print('story=%s phase=%s state=%s' % (t.get('aistory', ''), t.get('aiphase', ''), t.get('aistate', '')))
" 2>/dev/null || true
}
