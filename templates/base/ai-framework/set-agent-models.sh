#!/bin/bash
# Assign a model to every Cursor agent prompt according to its framework bucket.
#
# Two mappings meet here. Agent -> bucket is framework knowledge and lives in the
# BUCKET_MAP table below. Bucket -> model is your budget decision and is supplied
# on the command line. See DEPLOY.md "Choose Models for Agent Buckets".
#
# Re-runnable at any time. Upstream framework updates ship `model: inherit`, so
# re-run this after merging agent prompt changes.
set -euo pipefail

AI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_DIR="$AI_ROOT/.cursor/agents"

BUCKETS="deep critic builder checker mechanical"

# bucket:agent -- the canonical assignment. Adding an agent prompt without adding
# it here is an error, which is how a new upstream agent gets noticed.
BUCKET_MAP="
deep:roadmap-planner
deep:architecture-plan
deep:architecture-write
deep:fixer
deep:escalation-analysis
deep:escalation-recovery
deep:deploy-profile
critic:implementation-review
critic:architecture-review
critic:architecture-plan-review
critic:story-review
builder:implementation-write
builder:implementation-plan
builder:integration-test-write
builder:integration-test-plan
builder:requirements-write
builder:requirements-plan
checker:requirements-review
checker:requirements-plan-review
checker:integration-test-review
checker:integration-test-plan-review
checker:implementation-plan-review
checker:escalation-triage
mechanical:coordinator
mechanical:environment-recovery
"

MODEL_deep=""
MODEL_critic=""
MODEL_builder=""
MODEL_checker=""
MODEL_mechanical=""
DRY_RUN=0
DO_LIST=0

usage() {
    cat <<'EOF'
Usage:
  set-agent-models.sh --list
  set-agent-models.sh [--dry-run] --deep M --critic M --builder M --checker M --mechanical M

Buckets:
  deep        World knowledge and generative design. Roadmap, architecture, debugging,
              escalation recovery. Low token volume, highest leverage per token.
  critic      Adversarial review. Judges semantic correctness of work it did not write.
              Must be a different model family than both builder and deep.
  builder     Bulk write volume: implementation, tests, requirements, and their plans.
              Must be vision-capable if the project profile's UI kind is not `none`.
  checker     Bounded structural checks against a written plan. Must differ in family
              from builder.
  mechanical  Procedure following: the Coordinator state machine and environment repair.

The Project Manager has no bucket. It is a skill, not a subagent, so it runs on
whatever model the top-level chat is set to. Pick that model yourself when you
start a `/project-manager` chat.

Model syntax is a Cursor model ID with optional bracket parameters, for example
"claude-opus-5[effort=high]" or "grok-4.5[effort=low]". Use "inherit" to fall back
to the parent chat's model. Verify exact IDs in Cursor's model picker.

Options:
  --list      Show each bucket, its agents, and the model currently set on disk
  --dry-run   Report what would change without writing
EOF
}

agents_in_bucket() {
    echo "$BUCKET_MAP" | grep "^$1:" | cut -d: -f2
}

bucket_of_agent() {
    echo "$BUCKET_MAP" | grep ":$1\$" | cut -d: -f1
}

model_line_of() {
    grep -m1 '^model:' "$AGENT_DIR/$1.md" 2>/dev/null | sed 's/^model:[[:space:]]*//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --list) DO_LIST=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --deep) MODEL_deep="${2:-}"; shift 2 ;;
        --critic) MODEL_critic="${2:-}"; shift 2 ;;
        --builder) MODEL_builder="${2:-}"; shift 2 ;;
        --checker) MODEL_checker="${2:-}"; shift 2 ;;
        --mechanical) MODEL_mechanical="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [ ! -d "$AGENT_DIR" ]; then
    echo "ERROR: no agent directory at $AGENT_DIR" >&2
    echo "Run this from a deployed project that has .cursor/agents/ (DEPLOY.md Step 2)." >&2
    exit 1
fi

# --- Mapping completeness: the table and the directory must describe the same set ---
MAPPED="$(echo "$BUCKET_MAP" | grep -v '^$' | cut -d: -f2 | sort)"
ON_DISK="$(find "$AGENT_DIR" -maxdepth 1 -type f -name '*.md' -exec basename {} .md \; | sort)"

MISSING_FILE="$(comm -23 <(echo "$MAPPED") <(echo "$ON_DISK"))"
UNASSIGNED="$(comm -13 <(echo "$MAPPED") <(echo "$ON_DISK"))"

if [ -n "$MISSING_FILE" ]; then
    echo "ERROR: bucket table lists agents with no prompt file:" >&2
    echo "$MISSING_FILE" | sed 's/^/  /' >&2
    exit 1
fi

if [ -n "$UNASSIGNED" ]; then
    echo "ERROR: agent prompts with no bucket assignment:" >&2
    echo "$UNASSIGNED" | sed 's/^/  /' >&2
    echo "Add each to BUCKET_MAP in this script before setting models." >&2
    exit 1
fi

# --- Every prompt must already carry a model: line for this script to rewrite ---
for agent in $MAPPED; do
    if ! grep -q '^model:' "$AGENT_DIR/$agent.md"; then
        echo "ERROR: $AGENT_DIR/$agent.md has no 'model:' line in its frontmatter" >&2
        exit 1
    fi
done

if [ "$DO_LIST" -eq 1 ]; then
    echo "=== Agent model buckets ==="
    echo "Agent directory: $AGENT_DIR"
    echo ""
    for bucket in $BUCKETS; do
        FIRST=""
        MIXED=0
        for agent in $(agents_in_bucket "$bucket"); do
            CURRENT="$(model_line_of "$agent")"
            if [ -z "$FIRST" ]; then
                FIRST="$CURRENT"
            elif [ "$CURRENT" != "$FIRST" ]; then
                MIXED=1
            fi
        done
        if [ "$MIXED" -eq 1 ]; then
            echo "$bucket: MIXED (agents in this bucket disagree; re-run to normalize)"
        else
            echo "$bucket: $FIRST"
        fi
        for agent in $(agents_in_bucket "$bucket"); do
            printf '  %-28s %s\n' "$agent" "$(model_line_of "$agent")"
        done
        echo ""
    done
    exit 0
fi

for bucket in $BUCKETS; do
    eval "VALUE=\${MODEL_$bucket}"
    if [ -z "$VALUE" ]; then
        echo "ERROR: missing --$bucket" >&2
        echo "" >&2
        usage >&2
        exit 1
    fi
done

CHANGED=0
for bucket in $BUCKETS; do
    eval "VALUE=\${MODEL_$bucket}"
    for agent in $(agents_in_bucket "$bucket"); do
        FILE="$AGENT_DIR/$agent.md"
        CURRENT="$(model_line_of "$agent")"
        if [ "$CURRENT" = "$VALUE" ]; then
            continue
        fi
        CHANGED=$((CHANGED + 1))
        printf '%-28s %s -> %s\n' "$agent" "${CURRENT:-<empty>}" "$VALUE"
        if [ "$DRY_RUN" -eq 0 ]; then
            TMP="$(mktemp)"
            # Rewrite only the first model: line, which is the frontmatter one.
            awk -v m="$VALUE" '
                /^model:/ && !done { print "model: " m; done = 1; next }
                { print }
            ' "$FILE" >"$TMP"
            cat "$TMP" >"$FILE"
            rm -f "$TMP"
        fi
    done
done

echo ""
if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run: $CHANGED agent prompt(s) would change. Nothing written."
elif [ "$CHANGED" -eq 0 ]; then
    echo "All 25 agent prompts already match the requested buckets."
else
    echo "Updated $CHANGED agent prompt(s). Commit .cursor/agents/ so epic worktrees inherit the change."
fi
