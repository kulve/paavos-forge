#!/bin/bash
# Validate that the AI execution framework was deployed correctly into a project.
# Run from the deployed project root directory.
# For template-repo layout checks, use scripts/validate-template-repo.sh in the framework repo.
set -euo pipefail

ERRORS=0
WARNINGS=0

check_file() {
    if [ ! -f "$1" ]; then
        echo "ERROR: Missing file: $1"
        ERRORS=$((ERRORS + 1))
    fi
}

check_dir() {
    if [ ! -d "$1" ]; then
        echo "ERROR: Missing directory: $1"
        ERRORS=$((ERRORS + 1))
    fi
}

check_executable() {
    if [ ! -x "$1" ]; then
        echo "WARNING: Not executable: $1"
        WARNINGS=$((WARNINGS + 1))
    fi
}

check_nonempty() {
    if [ ! -s "$1" ]; then
        echo "WARNING: File is empty or missing: $1"
        WARNINGS=$((WARNINGS + 1))
    fi
}

check_placeholder() {
    if grep -q '\[e\.g\.' "$1" 2>/dev/null; then
        echo "WARNING: $1 still contains placeholder text (unfilled sections)"
        WARNINGS=$((WARNINGS + 1))
    fi
}

check_gitignore_entry() {
    if [ -f ".gitignore" ]; then
        if grep -q "$1" .gitignore 2>/dev/null; then
            true
        else
            echo "WARNING: .gitignore missing entry: $1"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo "WARNING: No .gitignore file found"
        WARNINGS=$((WARNINGS + 1))
    fi
}

echo "=== AI Execution Framework Deployment Validator ==="
echo ""

echo "--- Core Files ---"
check_file "AGENTS.md"
check_file "ARCHITECTURE.md"
check_file "ai-framework/LOGIC.md"
check_file "ai-framework/project-profile.md"

echo "--- Project Profile ---"
check_nonempty "ai-framework/project-profile.md"
check_placeholder "ai-framework/project-profile.md"

echo "--- Plan Templates (8 required) ---"
check_file "plan/templates/milestone.md"
check_file "plan/templates/story.md"
check_file "plan/templates/requirement.md"
check_file "plan/templates/phase-plan.md"
check_file "plan/templates/plan-review-feedback.md"
check_file "plan/templates/review-feedback.md"
check_file "plan/templates/escalation.md"
check_file "plan/templates/discovery.md"

echo "--- Taskwarrior ---"
check_file ".taskrc"
check_file "taskwarrior/setup.sh"
check_executable "taskwarrior/setup.sh"
check_file "taskwarrior/env.sh"
check_executable "taskwarrior/env.sh"
check_file "taskwarrior/tw"
check_executable "taskwarrior/tw"
check_file "taskwarrior/recipes.md"
check_gitignore_entry ".task/"

echo "--- Cursor Agents (22 required) ---"
check_file ".cursor/agents/project-manager.md"
check_file ".cursor/agents/coordinator.md"
check_file ".cursor/agents/fixer.md"
check_file ".cursor/agents/story-review.md"
check_file ".cursor/agents/requirements-plan.md"
check_file ".cursor/agents/requirements-plan-review.md"
check_file ".cursor/agents/requirements-write.md"
check_file ".cursor/agents/requirements-review.md"
check_file ".cursor/agents/architecture-plan.md"
check_file ".cursor/agents/architecture-plan-review.md"
check_file ".cursor/agents/architecture-write.md"
check_file ".cursor/agents/architecture-review.md"
check_file ".cursor/agents/integration-test-plan.md"
check_file ".cursor/agents/integration-test-plan-review.md"
check_file ".cursor/agents/integration-test-write.md"
check_file ".cursor/agents/integration-test-review.md"
check_file ".cursor/agents/implementation-plan.md"
check_file ".cursor/agents/implementation-plan-review.md"
check_file ".cursor/agents/implementation-write.md"
check_file ".cursor/agents/implementation-review.md"
check_file ".cursor/agents/escalation-analysis.md"
check_file ".cursor/agents/escalation-recovery.md"

echo "--- Cursor Rules and Commands ---"
check_file ".cursor/rules/ai-framework.mdc"
check_file ".cursor/commands/ai-status.md"
check_file ".cursor/commands/ai-next.md"

echo "--- Taskwarrior UDAs ---"
if [ -x "taskwarrior/tw" ]; then
    UDAS=$(taskwarrior/tw _udas 2>/dev/null || echo "")
    for UDA in aiphase aistate aistory airole; do
        if echo "$UDAS" | grep -q "$UDA"; then
            true
        else
            echo "ERROR: Taskwarrior UDA '$UDA' not configured. Run: bash taskwarrior/setup.sh"
            ERRORS=$((ERRORS + 1))
        fi
    done
    # Check that the two singleton lock tasks exist
    PM_LOCK=$(taskwarrior/tw +AI_LOCK airole:pm count 2>/dev/null || echo "0")
    if [ "$PM_LOCK" -lt 1 ]; then
        echo "ERROR: PM singleton lock task missing. Run: bash taskwarrior/setup.sh"
        ERRORS=$((ERRORS + 1))
    fi
    COORD_LOCK=$(taskwarrior/tw +AI_LOCK airole:coordinator count 2>/dev/null || echo "0")
    if [ "$COORD_LOCK" -lt 1 ]; then
        echo "ERROR: Coordinator singleton lock task missing. Run: bash taskwarrior/setup.sh"
        ERRORS=$((ERRORS + 1))
    fi
elif command -v task &> /dev/null; then
    echo "WARNING: taskwarrior/tw not executable. Falling back to bare 'task' for UDA check."
    WARNINGS=$((WARNINGS + 1))
    UDAS=$(task _udas 2>/dev/null || echo "")
    for UDA in aiphase aistate aistory airole; do
        if echo "$UDAS" | grep -q "$UDA"; then
            true
        else
            echo "ERROR: Taskwarrior UDA '$UDA' not configured. Run: bash taskwarrior/setup.sh"
            ERRORS=$((ERRORS + 1))
        fi
    done
else
    echo "WARNING: Taskwarrior not found. Install it and run: bash taskwarrior/setup.sh"
    WARNINGS=$((WARNINGS + 1))
fi

echo "--- Git ---"
if [ -d ".git" ]; then
    true
else
    echo "WARNING: Not a git repository. Initialize with: git init"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "=== Results ==="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "All checks passed. Deployment is valid."
elif [ $ERRORS -eq 0 ]; then
    echo "$WARNINGS warning(s), 0 errors. Deployment is functional but has issues to address."
else
    echo "$ERRORS error(s), $WARNINGS warning(s). Fix errors before using the framework."
fi

exit $ERRORS
