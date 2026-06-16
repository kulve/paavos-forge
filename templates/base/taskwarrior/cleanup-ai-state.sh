#!/usr/bin/env bash
set -euo pipefail

# Manual recovery for stale AI framework Taskwarrior active state.
# Only run this after confirming there are no active Cursor agents/subagents
# for this workspace. This does not recover or roll back git changes. It
# clears Taskwarrior start state on AI lock and phase tasks, and removes
# duplicate singleton lock tasks (keeping the lowest task ID per role).
# After cleanup, ask the PM to analyze status before launching a fresh Coordinator.

usage() {
  cat <<'USAGE'
Usage: taskwarrior/cleanup-ai-state.sh [--apply] [--yes] [--story XXXXX] [--locks-only] [--clear-escalations]

Default mode is a dry run: print current state and proposed cleanup actions.

Options:
  --apply               Stop active PM/Coordinator lock tasks and active phase tasks.
  --yes                 Skip confirmation prompt. Valid only with --apply.
  --story ID            Limit cleanup/reporting to one story ID.
  --locks-only          Stop PM/Coordinator locks and dedupe lock tasks only.
  --clear-escalations   Remove escalation annotations, +blocked tags, and
                        escalation files; restore aistate on escalated tasks.
  -h, --help            Show this help.

Safety:
  Only run this after confirming no Cursor agents/subagents are active here.
  By default this does not modify git, mark tasks done, or modify aistate.
  --clear-escalations deletes plan/escalations/ files and resets escalated
  phase tasks so the PM can resume the story. Duplicate +AI_LOCK tasks for the
  same airole are deleted (lowest ID kept).
USAGE
}

apply=false
yes=false
story=""
locks_only=false
clear_escalations=false

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
    --clear-escalations)
      clear_escalations=true
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

lock_ids_for_role() {
  local role="$1"
  run_tw status:pending +AI_LOCK "airole:$role" ids 2>/dev/null \
    | tr ' ' '\n' \
    | grep -E '^[0-9]+$' \
    | sort -n \
    || true
}

report_duplicate_locks() {
  local role
  for role in pm coordinator; do
    local ids
    ids="$(lock_ids_for_role "$role")"
    local count=0
    if [[ -n "$ids" ]]; then
      count="$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d ' ')"
    fi
    if [[ "$count" -gt 1 ]]; then
      local canonical
      canonical="$(printf '%s\n' "$ids" | head -n 1)"
      echo "- Duplicate $role lock tasks detected: $(printf '%s\n' "$ids" | tr '\n' ' ' | sed 's/ $//')"
      echo "  Keep canonical task $canonical; delete the rest"
    elif [[ "$count" -eq 1 ]]; then
      echo "- $role lock task: $(printf '%s\n' "$ids" | head -n 1) (ok)"
    else
      echo "- $role lock task: missing (run taskwarrior/setup.sh to create)"
    fi
  done
}

escalation_plan_tsv() {
  REPO_ROOT="$repo_root" python3 - "$story" <<'PY'
import glob
import json
import os
import subprocess
import sys

story = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else ""
repo_root = os.environ["REPO_ROOT"]
tw = os.path.join(repo_root, "taskwarrior", "tw")

cmd = [tw, "status:pending"]
if story:
    cmd.append(f"aistory:{story}")
else:
    cmd.append("aistory.any:")
cmd.append("export")

result = subprocess.run(cmd, capture_output=True, text=True, check=True)
lines = [line for line in result.stdout.splitlines() if not line.startswith("TASKRC")]
tasks = json.loads("\n".join(lines))
tasks = [
    task
    for task in tasks
    if task.get("aiphase") and "AI_LOCK" not in (task.get("tags") or [])
]


def infer_resume_aistate(annotations):
    descriptions = [entry.get("description", "") for entry in (annotations or [])]
    if any(desc.startswith("Artifact:") for desc in descriptions):
        return "write"
    if any(desc.startswith("Feedback:") for desc in descriptions):
        return "write"
    if any(desc.startswith("Plan-review: approved") for desc in descriptions):
        return "write"
    if any(desc.startswith("Plan:") for desc in descriptions):
        return "plan-review"
    return "plan"


escalation_dir = os.path.join(repo_root, "plan", "escalations")
files = set()
if story:
    files.update(glob.glob(os.path.join(escalation_dir, f"{story}-*.md")))
else:
    files.update(glob.glob(os.path.join(escalation_dir, "*.md")))

for task in tasks:
    task_id = str(task["id"])
    annotations = task.get("annotations") or []
    escalation_paths = []
    for entry in annotations:
        description = entry.get("description", "")
        if description.startswith("Escalation: "):
            path = description.removeprefix("Escalation: ").strip()
            escalation_paths.append(path)
            if path:
                files.add(os.path.join(repo_root, path))

    if not escalation_paths:
        continue

    resume = infer_resume_aistate(annotations)
    print(
        "\t".join(
            [
                "task",
                task_id,
                resume,
                ",".join(escalation_paths),
            ]
        )
    )

for path in sorted(files):
    rel = os.path.relpath(path, repo_root)
    print("\t".join(["file", rel]))
PY
}

report_escalations() {
  local kind
  local arg1
  local arg2
  local arg3
  local had_actions=false
  while IFS=$'\t' read -r kind arg1 arg2 arg3; do
    [[ -z "$kind" ]] && continue
    had_actions=true
    case "$kind" in
      task)
        echo "- Clear escalation on task $arg1: denotate Escalation:, remove +blocked, set aistate:$arg2"
        if [[ -n "$arg3" ]]; then
          echo "  Referenced files: ${arg3//,/, }"
        fi
        ;;
      file)
        if [[ -f "$repo_root/$arg1" ]]; then
          echo "- Delete escalation file: $arg1"
        else
          echo "- Escalation file already missing: $arg1"
        fi
        ;;
    esac
  done < <(escalation_plan_tsv || true)

  if [[ "$had_actions" != true ]]; then
    if [[ -n "$story" ]]; then
      echo "- No escalation annotations or files found for story $story"
    else
      echo "- No escalation annotations or files found"
    fi
  fi
}

clear_escalations() {
  local kind
  local arg1
  local arg2
  local arg3
  local task_id
  local resume
  local rel_path
  local abs_path

  while IFS=$'\t' read -r kind arg1 arg2 arg3; do
    [[ -z "$kind" ]] && continue
    case "$kind" in
      task)
        task_id="$arg1"
        resume="$arg2"
        echo "- Clear escalation on task $task_id (resume aistate:$resume)"
        run_tw "$task_id" denotate "Escalation:" || true
        run_tw "$task_id" modify -blocked "aistate:$resume" || true
        ;;
      file)
        rel_path="$arg1"
        abs_path="$repo_root/$rel_path"
        if [[ -f "$abs_path" ]]; then
          echo "- Delete escalation file: $rel_path"
          rm -f "$abs_path"
        else
          echo "- Escalation file already missing: $rel_path"
        fi
        ;;
    esac
  done < <(escalation_plan_tsv || true)
}

dedupe_lock_tasks() {
  local role
  for role in pm coordinator; do
    local ids
    ids="$(lock_ids_for_role "$role")"
    local count=0
    if [[ -n "$ids" ]]; then
      count="$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d ' ')"
    fi
    if [[ "$count" -le 1 ]]; then
      continue
    fi

    local canonical
    canonical="$(printf '%s\n' "$ids" | head -n 1)"
    local duplicate
    while IFS= read -r duplicate; do
      [[ -z "$duplicate" ]] && continue
      echo "- Delete duplicate $role lock task $duplicate (keeping canonical task $canonical)"
      if [[ "$apply" == true ]]; then
        run_tw "$duplicate" delete || true
      fi
    done < <(printf '%s\n' "$ids" | tail -n +2)
  done
}

section "Safety"
if [[ "$clear_escalations" == true ]]; then
  cat <<'SAFETY'
Only continue if you have confirmed there are no active Cursor agents/subagents
for this workspace. This script clears Taskwarrior active state, removes
duplicate singleton lock tasks, and (with --clear-escalations) deletes
plan/escalations/ files and resets escalated phase tasks. It does not modify
git or mark phase tasks done except when clearing escalations.
SAFETY
else
  cat <<'SAFETY'
Only continue if you have confirmed there are no active Cursor agents/subagents
for this workspace. This script clears Taskwarrior active state and removes
duplicate singleton lock tasks. It does not modify git, mark phase tasks done,
or modify aistate on phase tasks.
SAFETY
fi

section "Current AI Lock Tasks"
run_tw ailocks || true

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
report_duplicate_locks
if [[ "$locks_only" == true ]]; then
  echo "- Leave active phase tasks unchanged because --locks-only was supplied"
elif [[ -n "$story" ]]; then
  echo "- Stop active phase tasks for story $story: taskwarrior/tw +ACTIVE -AI_LOCK aistory:$story stop"
else
  echo "- Stop all active phase tasks: taskwarrior/tw +ACTIVE -AI_LOCK stop"
fi

if [[ "$clear_escalations" == true ]]; then
  report_escalations
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
dedupe_lock_tasks
if [[ "$locks_only" != true ]]; then
  run_tw "${phase_filter[@]}" stop || true
fi
if [[ "$clear_escalations" == true ]]; then
  section "Clearing Escalations"
  clear_escalations
fi

section "Post-Cleanup AI Lock Tasks"
run_tw ailocks || true

section "Post-Cleanup Active AI Locks"
run_tw +AI_LOCK +ACTIVE export || true

section "Post-Cleanup Active Phase Tasks"
run_tw "${phase_filter[@]}" export || true

cat <<'DONE'

Cleanup complete. Ask the PM to analyze status before launching a fresh
Coordinator.
DONE
