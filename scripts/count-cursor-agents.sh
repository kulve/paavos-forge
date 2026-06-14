#!/usr/bin/env bash
# Best-effort count of active Cursor agents/subagents via transcript files.
# Not official Cursor API — heuristic based on observed behavior.
set -euo pipefail

PROJ="${1:-$HOME/.cursor/projects/home-kulve-projects-paavo-rts-1/agent-transcripts}"
RECENT_MIN="${2:-10}"   # consider "recently touched" within N minutes
GROW_SEC="${3:-4}"      # bytes grown over this window => "actively writing"

if [[ ! -d "$PROJ" ]]; then
  echo "No transcript dir: $PROJ" >&2
  exit 1
fi

tmp1=$(mktemp)
tmp2=$(mktemp)
find "$PROJ" -name '*.jsonl' -printf '%s\t%p\n' | sort -k2 >"$tmp1"
sleep "$GROW_SEC"
find "$PROJ" -name '*.jsonl' -printf '%s\t%p\n' | sort -k2 >"$tmp2"

agent_type() {
  local f="$1"
  if [[ "$f" == */subagents/* ]]; then
    echo "subagent"
  else
    echo "main"
  fi
}

last_status() {
  local f="$1"
  if grep -q '"type":"turn_ended"' "$f" 2>/dev/null; then
    local st
    st=$(grep '"type":"turn_ended"' "$f" | tail -1 | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
    echo "ended:${st:-unknown}"
  else
    echo "no_turn_ended"
  fi
}

guess_role() {
  local f="$1"
  local hint

  hint=$(head -1 "$f" 2>/dev/null | grep -oE 'You are the [a-z-]+ agent' | head -1 | sed 's/You are the //;s/ agent//')
  if [[ -n "$hint" ]]; then
    echo "$hint"
    return
  fi

  for role in integration-test-write integration-test-review integration-test-plan integration-test-plan-review \
              requirements-write requirements-review requirements-plan requirements-plan-review \
              architecture-write architecture-review architecture-plan architecture-plan-review \
              implementation-write implementation-review implementation-plan implementation-plan-review \
              project-manager coordinator cursor-guide explore generalPurpose fixer; do
    if head -1 "$f" 2>/dev/null | grep -q "$role"; then
      echo "$role"
      return
    fi
  done

  echo "unknown"
}

echo "=== Cursor agent activity heuristic ==="
echo "Project transcripts: $PROJ"
echo "Recent window: ${RECENT_MIN}m | Growth window: ${GROW_SEC}s"
echo

growing=()
recent_open=()

while IFS=$'\t' read -r s1 p; do
  s2=$(awk -F'\t' -v p="$p" '$2==p{print $1; exit}' "$tmp2")
  [[ -z "${s2:-}" ]] && continue
  delta=$((s2 - s1))
  kind=$(agent_type "$p")
  id=$(basename "$p" .jsonl)
  parent=$(basename "$(dirname "$p")")
  [[ "$parent" == "subagents" ]] && parent=$(basename "$(dirname "$(dirname "$p")")")
  status=$(last_status "$p")
  role=$(guess_role "$p")
  mmin=$(find "$p" -mmin "-$RECENT_MIN" -printf 'yes' 2>/dev/null || true)

  if (( delta > 0 )); then
    growing+=("$kind|$id|$parent|$delta|$status|$role|$p")
  elif [[ "$mmin" == "yes" && "$status" == "no_turn_ended" ]]; then
    recent_open+=("$kind|$id|$parent|0|$status|$role|$p")
  fi
done <"$tmp1"

count_growing=${#growing[@]}
count_recent_open=${#recent_open[@]}

echo "--- Actively growing transcripts (+${GROW_SEC}s): $count_growing ---"
if (( count_growing > 0 )); then
  printf '%s\n' "${growing[@]}" | sort -t'|' -k4 -nr | while IFS='|' read -r kind id parent delta status role path; do
    printf '  %-9s %-36s parent=%-36s +%6sB  %-15s  role=%s\n' "$kind" "$id" "$parent" "$delta" "$status" "$role"
  done
else
  echo "  (none)"
fi

echo
echo "--- Recently touched but not ended (last ${RECENT_MIN}m, no turn_ended): $count_recent_open ---"
if (( count_recent_open > 0 )); then
  printf '%s\n' "${recent_open[@]}" | while IFS='|' read -r kind id parent delta status role path; do
    printf '  %-9s %-36s parent=%-36s  %-15s  role=%s\n' "$kind" "$id" "$parent" "$status" "$role"
  done
else
  echo "  (none)"
fi

echo
echo "--- Summary ---"
echo "  Growing now (strongest signal):     $count_growing"
echo "  Recent + no turn_ended (weaker):    $count_recent_open"
echo "  Combined unique heuristic total:    $(( count_growing + count_recent_open ))"
echo
echo "Note: main chats and subagents are counted separately."
echo "      ps/pgrep cannot see these; only transcript growth/status."

rm -f "$tmp1" "$tmp2"
