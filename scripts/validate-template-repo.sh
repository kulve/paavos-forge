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

echo "--- Cursor agent prompts ---"
if [ ! -d "templates/cursor/.cursor/agents" ]; then
    fail "Missing Cursor agent prompt directory"
else
    AGENT_COUNT=$(find templates/cursor/.cursor/agents -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
    if [ "$AGENT_COUNT" -ne 22 ]; then
        fail "Expected 22 Cursor agent prompt files, found $AGENT_COUNT"
    fi
    if [ ! -f "templates/cursor/.cursor/agents/escalation-recovery.md" ]; then
        fail "Missing escalation recovery agent prompt"
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
