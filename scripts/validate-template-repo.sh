#!/bin/bash
# Validate the AI execution framework template repository layout.
# Run from the framework repo root.
set -euo pipefail

ERRORS=0

fail() {
    echo "ERROR: $1"
    ERRORS=$((ERRORS + 1))
}

echo "=== AI Execution Framework Template Repo Validator ==="
echo ""

echo "--- Canonical workflow spec ---"
if [ ! -f "LOGIC.md" ]; then
    fail "Missing canonical workflow spec: LOGIC.md"
elif [ ! -s "LOGIC.md" ]; then
    fail "LOGIC.md is empty"
fi

echo "--- No duplicate LOGIC.md in templates/base ---"
if [ -f "templates/base/ai-framework/LOGIC.md" ]; then
    fail "templates/base/ai-framework/LOGIC.md must not exist; copy root LOGIC.md at deploy time instead"
fi

echo "--- Deploy guidance present ---"
if [ ! -f "templates/base/ai-framework/README.md" ]; then
    fail "Missing templates/base/ai-framework/README.md (deploy-time LOGIC.md guidance)"
fi

if [ ! -f "templates/base/ai-framework/project-profile.md" ]; then
    fail "Missing templates/base/ai-framework/project-profile.md"
fi

if [ ! -f "templates/base/AGENTS.md" ]; then
    fail "Missing templates/base/AGENTS.md (downstream project template)"
fi

if [ ! -f "DEPLOY.md" ]; then
    fail "Missing DEPLOY.md"
fi

if ! grep -q 'ai-framework/LOGIC.md' DEPLOY.md; then
    fail "DEPLOY.md must document copying LOGIC.md to ai-framework/LOGIC.md"
fi

echo "--- Plan templates (10 required) ---"
for tmpl in project milestone story epic requirement phase-plan plan-review-feedback review-feedback escalation discovery; do
    if [ ! -f "templates/base/plan/templates/${tmpl}.md" ]; then
        fail "Missing plan template: templates/base/plan/templates/${tmpl}.md"
    fi
done

if ! grep -q 'Paavo Notes' templates/base/ai-framework/project-profile.md; then
    fail "project-profile.md must include a Paavo Notes MCP section"
fi

echo "--- Epic directory ---"
if [ ! -d "templates/base/plan/epics" ]; then
    fail "Missing templates/base/plan/epics/ directory"
fi

echo "--- Taskwarrior scripts ---"
REQUIRED_SCRIPTS="tw env.sh guard.sh setup.sh taskrc.template cleanup-ai-state.sh recipes.md
    epic-fork epic-merge epic-status epic-mark-ready epic-gate-status epic-gate-release epic-rebase
    story-init story-next story-complete story-merge
    phase-start phase-stop phase-transition phase-annotate phase-done phase-block
    pm-lock-acquire pm-lock-release pm-preflight
    coordinator-lock-acquire coordinator-lock-release coordinator-lock-status
    coordinator-heartbeat coordinator-status doctor"

for script in $REQUIRED_SCRIPTS; do
    if [ ! -f "templates/base/taskwarrior/${script}" ]; then
        fail "Missing taskwarrior script: templates/base/taskwarrior/${script}"
    fi
done

echo "--- Isolation invariants ---"
if [ -f "templates/base/.taskrc" ]; then
    fail "templates/base/.taskrc must not exist; setup.sh generates .taskrc from taskwarrior/taskrc.template"
fi

if [ -f "templates/base/taskwarrior/taskrc.template" ] && grep -q '^data.location' templates/base/taskwarrior/taskrc.template; then
    fail "taskrc.template must not set data.location; setup.sh appends an absolute path"
fi

if [ -f "templates/base/taskwarrior/env.sh" ] && ! grep -q 'export TASKDATA' templates/base/taskwarrior/env.sh; then
    fail "env.sh must export an absolute TASKDATA so the database never depends on the caller's cwd"
fi

# Every executable script must source guard.sh; guard.sh and env.sh are the exceptions.
for script_path in templates/base/taskwarrior/*; do
    script_name="$(basename "$script_path")"
    case "$script_name" in
        guard.sh|env.sh|recipes.md|taskrc.template) continue ;;
    esac
    if ! grep -q 'guard.sh' "$script_path"; then
        fail "${script_name} does not source taskwarrior/guard.sh (context guard missing)"
    fi
    if grep -q 'SCRIPT_DIR=' "$script_path"; then
        fail "${script_name} still defines SCRIPT_DIR; use AI_ROOT from guard.sh"
    fi
done

# Context assignment must match the tree each script is allowed to touch.
for script_name in epic-fork epic-merge epic-rebase epic-mark-ready epic-status \
                   epic-gate-status epic-gate-release pm-lock-acquire pm-lock-release \
                   pm-preflight cleanup-ai-state.sh coordinator-status doctor; do
    if ! grep -q 'require_context main' "templates/base/taskwarrior/${script_name}"; then
        fail "${script_name} must call require_context main"
    fi
done

for script_name in coordinator-lock-acquire coordinator-lock-release coordinator-lock-status \
                   coordinator-heartbeat story-init story-next story-complete story-merge \
                   phase-start phase-stop phase-transition phase-annotate phase-done phase-block; do
    if ! grep -q 'require_context worktree' "templates/base/taskwarrior/${script_name}"; then
        fail "${script_name} must call require_context worktree"
    fi
done

echo "--- Agent prompts must not use a subagent working directory ---"
if grep -rq 'working_directory. set to' templates/cursor/.cursor/agents/; then
    fail "An agent prompt instructs setting a subagent working_directory; that parameter does not exist"
fi

echo "--- Agent model buckets ---"
BUCKET_SCRIPT="templates/base/ai-framework/set-agent-models.sh"
if [ ! -f "$BUCKET_SCRIPT" ]; then
    fail "Missing $BUCKET_SCRIPT (agent-to-bucket mapping and model assignment)"
elif [ ! -x "$BUCKET_SCRIPT" ]; then
    fail "$BUCKET_SCRIPT is not executable"
else
    # The template must ship `inherit`. A concrete slug here would override every
    # deployed project's own bucket choice the next time it merges upstream.
    for agent_path in templates/cursor/.cursor/agents/*.md; do
        agent_name="$(basename "$agent_path" .md)"
        if ! grep -q '^model:' "$agent_path"; then
            fail "${agent_name}.md has no 'model:' frontmatter line for set-agent-models.sh to rewrite"
        elif ! grep -q '^model: inherit$' "$agent_path"; then
            fail "${agent_name}.md must ship 'model: inherit'; concrete models are assigned per deployment"
        fi
    done

    # The mapping and the prompt directory must describe the same set of agents,
    # so a newly added prompt cannot ship without a bucket.
    MAPPED_AGENTS="$(grep -oE '^(deep|critic|builder|checker|mechanical):[a-z-]+' "$BUCKET_SCRIPT" | cut -d: -f2 | sort)"
    PROMPT_AGENTS="$(find templates/cursor/.cursor/agents -maxdepth 1 -type f -name '*.md' -exec basename {} .md \; | sort)"

    for agent in $(comm -13 <(echo "$MAPPED_AGENTS") <(echo "$PROMPT_AGENTS")); do
        fail "Agent prompt ${agent}.md has no bucket in ${BUCKET_SCRIPT}"
    done
    for agent in $(comm -23 <(echo "$MAPPED_AGENTS") <(echo "$PROMPT_AGENTS")); do
        fail "${BUCKET_SCRIPT} assigns a bucket to ${agent}, which has no prompt file"
    done
fi

echo "--- Isolation smoke test present ---"
if [ ! -f "scripts/test-isolation.sh" ]; then
    fail "Missing scripts/test-isolation.sh"
fi

echo "--- Cursor agent prompts ---"
if [ ! -d "templates/cursor/.cursor/agents" ]; then
    fail "Missing Cursor agent prompt directory"
else
    AGENT_COUNT=$(find templates/cursor/.cursor/agents -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
    if [ "$AGENT_COUNT" -ne 26 ]; then
        fail "Expected 26 Cursor agent prompt files, found $AGENT_COUNT"
    fi
    for agent in escalation-recovery escalation-triage environment-recovery roadmap-planner; do
        if [ ! -f "templates/cursor/.cursor/agents/${agent}.md" ]; then
            fail "Missing agent prompt: ${agent}.md"
        fi
    done
fi

echo "--- Cursor rules and commands ---"
if [ ! -f "templates/cursor/.cursor/rules/ai-framework.mdc" ]; then
    fail "Missing Cursor rule: templates/cursor/.cursor/rules/ai-framework.mdc"
fi
if [ ! -f "templates/cursor/.cursor/commands/ai-status.md" ]; then
    fail "Missing slash command: templates/cursor/.cursor/commands/ai-status.md"
fi
if [ ! -f "templates/cursor/.cursor/commands/ai-next.md" ]; then
    fail "Missing slash command: templates/cursor/.cursor/commands/ai-next.md"
fi

echo "--- .gitignore entries ---"
if [ -f "templates/base/.gitignore" ]; then
    if ! grep -q '.task/' templates/base/.gitignore; then
        fail ".gitignore missing .task/ entry"
    fi
    if ! grep -q '.worktrees/' templates/base/.gitignore; then
        fail ".gitignore missing .worktrees/ entry"
    fi
    if ! grep -qx '.taskrc' templates/base/.gitignore; then
        fail ".gitignore missing .taskrc entry (a committed worktree .taskrc corrupts main's UDAs on merge)"
    fi
fi

echo ""
echo "=== Results ==="
if [ $ERRORS -eq 0 ]; then
    echo "All checks passed. Template repo layout is valid."
else
    echo "$ERRORS error(s). Fix before releasing template changes."
fi

exit $ERRORS
