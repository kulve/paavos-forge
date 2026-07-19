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
REQUIRED_SCRIPTS="tw env.sh setup.sh cleanup-ai-state.sh recipes.md
    epic-fork epic-merge epic-status epic-mark-ready epic-gate-status epic-gate-release epic-rebase
    story-init story-next story-complete story-merge
    phase-start phase-stop phase-transition phase-annotate phase-done phase-block
    pm-lock-acquire pm-lock-release pm-preflight
    coordinator-lock-acquire coordinator-lock-release coordinator-lock-status"

for script in $REQUIRED_SCRIPTS; do
    if [ ! -f "templates/base/taskwarrior/${script}" ]; then
        fail "Missing taskwarrior script: templates/base/taskwarrior/${script}"
    fi
done

echo "--- Cursor agent prompts ---"
if [ ! -d "templates/cursor/.cursor/agents" ]; then
    fail "Missing Cursor agent prompt directory"
else
    AGENT_COUNT=$(find templates/cursor/.cursor/agents -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
    if [ "$AGENT_COUNT" -ne 24 ]; then
        fail "Expected 24 Cursor agent prompt files, found $AGENT_COUNT"
    fi
    if [ ! -f "templates/cursor/.cursor/agents/escalation-recovery.md" ]; then
        fail "Missing escalation recovery agent prompt"
    fi
    if [ ! -f "templates/cursor/.cursor/agents/roadmap-planner.md" ]; then
        fail "Missing roadmap planner agent prompt"
    fi
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
fi

echo ""
echo "=== Results ==="
if [ $ERRORS -eq 0 ]; then
    echo "All checks passed. Template repo layout is valid."
else
    echo "$ERRORS error(s). Fix before releasing template changes."
fi

exit $ERRORS
