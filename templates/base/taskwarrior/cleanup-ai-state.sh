#!/usr/bin/env bash
set -euo pipefail

# Manual recovery for stale AI framework Taskwarrior active state.
# Only run this after confirming there are no active Cursor agents/subagents
# for this workspace. This does not recover or roll back git changes. It only
# clears Taskwarrior start state on AI lock and phase tasks. After cleanup, ask
# the PM to analyze status before launching a fresh Coordinator.

usage() {
  cat <<'USAGE'
Usage: taskwarrior/cleanup-ai-state.sh [--apply] [--yes] [--story XXXXX] [--locks-only]

Default mode is a dry run: print current state and proposed cleanup actions.

Options:
  --apply       Stop active PM/Coordinator lock tasks and active phase tasks.
  --yes         Skip confirmation prompt. Valid only with --apply.
  --story ID    Limit phase-task cleanup/reporting to one story ID.
  --locks-only  Stop PM/Coordinator locks only; leave phase tasks active.
  -h, --help    Show this help.

Safety:
  Only run this after confirming no Cursor agents/subagents are active here.
  This does not modify git, mark tasks done, modify aistate, or delete tasks.
USAGE
}

apply=false
yes=false
story=""
locks_only=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      apply=true
      ;;
    --yes)
      yes=true
      ;;
    --story)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --story requires a story ID" >&2
        exit 2
      fi
      story="$2"
      shift
      ;;
    --locks-only)
      locks_only=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$yes" == true && "$apply" != true ]]; then
  echo "error: --yes is only valid with --apply" >&2
  exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
tw="$repo_root/taskwarrior/tw"

if [[ ! -x "$tw" ]]; then
  echo "error: expected executable wrapper at $tw" >&2
  exit 1
fi

phase_filter=(+ACTIVE -AI_LOCK)
if [[ -n "$story" ]]; then
  phase_filter+=("aistory:$story")
fi

run_tw() {
  "$tw" "$@"
}

section() {
  printf '\n== %s ==\n' "$1"
}

section "Safety"
cat <<'SAFETY'
Only continue if you have confirmed there are no active Cursor agents/subagents
for this workspace. This script only clears Taskwarrior active state. It does
not modify git, mark tasks done, modify aistate, or delete tasks.
SAFETY

section "Current Active AI Locks"
run_tw +AI_LOCK +ACTIVE export || true

section "Current Active Phase Tasks"
run_tw "${phase_filter[@]}" export || true

section "Pending Story Tasks"
if [[ -n "$story" ]]; then
  run_tw status:pending "aistory:$story" export || true
else
  run_tw status:pending aistory.any: export || true
fi

section "Next Actionable Task"
run_tw ainext || true

section "Proposed Actions"
echo "- Stop active Coordinator lock tasks: taskwarrior/tw +AI_LOCK airole:coordinator +ACTIVE stop"
echo "- Stop active PM lock tasks: taskwarrior/tw +AI_LOCK airole:pm +ACTIVE stop"
if [[ "$locks_only" == true ]]; then
  echo "- Leave active phase tasks unchanged because --locks-only was supplied"
elif [[ -n "$story" ]]; then
  echo "- Stop active phase tasks for story $story: taskwarrior/tw +ACTIVE -AI_LOCK aistory:$story stop"
else
  echo "- Stop all active phase tasks: taskwarrior/tw +ACTIVE -AI_LOCK stop"
fi

if [[ "$apply" != true ]]; then
  cat <<'DRYRUN'

Dry run only. To apply these actions after confirming no agents/subagents are
running, run:
  ccmd bash taskwarrior/cleanup-ai-state.sh --apply
DRYRUN
  exit 0
fi

if [[ "$yes" != true ]]; then
  printf '\nType "cleanup" to apply these Taskwarrior stop actions: '
  read -r answer
  if [[ "$answer" != "cleanup" ]]; then
    echo "aborted"
    exit 1
  fi
fi

section "Applying Cleanup"
run_tw +AI_LOCK airole:coordinator +ACTIVE stop || true
run_tw +AI_LOCK airole:pm +ACTIVE stop || true
if [[ "$locks_only" != true ]]; then
  run_tw "${phase_filter[@]}" stop || true
fi

section "Post-Cleanup Active AI Locks"
run_tw +AI_LOCK +ACTIVE export || true

section "Post-Cleanup Active Phase Tasks"
run_tw "${phase_filter[@]}" export || true

cat <<'DONE'

Cleanup complete. Ask the PM to analyze status before launching a fresh
Coordinator.
DONE
