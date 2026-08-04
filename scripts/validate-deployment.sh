#!/bin/bash
# Validate that Paavo's Forge was deployed correctly into a project.
# Run from the deployed project root directory.
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
        if ! grep -q "$1" .gitignore 2>/dev/null; then
            echo "WARNING: .gitignore missing entry: $1"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo "WARNING: No .gitignore file found"
        WARNINGS=$((WARNINGS + 1))
    fi
}

echo "=== Paavo's Forge Deployment Validator ==="
echo ""

echo "--- Core Files ---"
check_file "AGENTS.md"
check_file "ARCHITECTURE.md"
check_file "paavos-forge/LOGIC.md"
check_file "paavos-forge/project-profile.md"

echo "--- Project Profile ---"
check_nonempty "paavos-forge/project-profile.md"
check_placeholder "paavos-forge/project-profile.md"

echo "--- Plan Templates (9 required) ---"
check_file "plan/templates/project.md"
check_file "plan/templates/milestone.md"
check_file "plan/templates/story.md"
check_file "plan/templates/epic.md"
check_file "plan/templates/requirement.md"
check_file "plan/templates/phase-plan.md"
check_file "plan/templates/review-feedback.md"
check_file "plan/templates/escalation.md"
check_file "plan/templates/discovery.md"

if ! grep -qF "Paavo's Codex" paavos-forge/project-profile.md 2>/dev/null; then
    echo "ERROR: paavos-forge/project-profile.md must include a Paavo's Codex MCP section"
    ERRORS=$((ERRORS + 1))
fi

echo "--- Plan Directories ---"
check_dir "plan/epics"

echo "--- Taskwarrior Core ---"
check_file ".taskrc"
check_file "taskwarrior/setup.sh"
check_executable "taskwarrior/setup.sh"
check_file "taskwarrior/env.sh"
check_executable "taskwarrior/env.sh"
check_file "taskwarrior/guard.sh"
check_executable "taskwarrior/guard.sh"
check_file "taskwarrior/taskrc.template"
check_file "taskwarrior/tw"
check_executable "taskwarrior/tw"
check_file "taskwarrior/recipes.md"
check_file "taskwarrior/cleanup-ai-state.sh"
check_executable "taskwarrior/cleanup-ai-state.sh"

echo "--- Isolation Invariants ---"
# .taskrc is mode-specific and generated. A tracked copy in a worktree would
# overwrite the main tree's UDAs when the epic branch merges.
if [ -d ".git" ] && git ls-files --error-unmatch .taskrc >/dev/null 2>&1; then
    echo "ERROR: .taskrc is tracked by git. Run: git rm --cached .taskrc"
    ERRORS=$((ERRORS + 1))
fi

if [ -f ".taskrc" ] && ! grep -q '^data.location=/' .taskrc; then
    echo "ERROR: .taskrc has no absolute data.location. Delete it and re-run: bash taskwarrior/setup.sh --main"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "taskwarrior/env.sh" ] && ! grep -q 'export TASKDATA' taskwarrior/env.sh; then
    echo "ERROR: taskwarrior/env.sh does not export TASKDATA; the database would depend on the caller's cwd"
    ERRORS=$((ERRORS + 1))
fi

# Every framework script must go through the context guard.
if [ -d "taskwarrior" ]; then
    for script_path in taskwarrior/*; do
        script_name="$(basename "$script_path")"
        case "$script_name" in
            guard.sh|env.sh|recipes.md|taskrc.template) continue ;;
        esac
        if ! grep -q 'guard.sh' "$script_path" 2>/dev/null; then
            echo "ERROR: taskwarrior/${script_name} does not source guard.sh (context guard missing)"
            ERRORS=$((ERRORS + 1))
        fi
    done
fi

echo "--- Taskwarrior Scripts (Epic) ---"
for script in epic-fork epic-merge epic-status epic-mark-ready epic-gate-status epic-gate-release epic-rebase; do
    check_file "taskwarrior/$script"
    check_executable "taskwarrior/$script"
done

echo "--- Taskwarrior Scripts (Story/Phase) ---"
for script in story-init story-next story-complete story-merge phase-start phase-stop phase-transition phase-annotate phase-gate phase-done phase-block phase-resume; do
    check_file "taskwarrior/$script"
    check_executable "taskwarrior/$script"
done

echo "--- Taskwarrior Scripts (Lock) ---"
for script in pm-lock-acquire pm-lock-release pm-preflight coordinator-lock-acquire coordinator-lock-release coordinator-lock-status; do
    check_file "taskwarrior/$script"
    check_executable "taskwarrior/$script"
done

echo "--- Taskwarrior Scripts (Diagnostics/Telemetry) ---"
for script in doctor coordinator-heartbeat coordinator-status; do
    check_file "taskwarrior/$script"
    check_executable "taskwarrior/$script"
done

echo "--- .gitignore ---"
check_gitignore_entry ".task/"
check_gitignore_entry ".worktrees/"
check_gitignore_entry ".taskrc"

echo "--- Cursor Agents (19 required) ---"
check_file ".cursor/agents/coordinator.md"
check_file ".cursor/agents/fixer.md"
check_file ".cursor/agents/roadmap-planner.md"
check_file ".cursor/agents/story-review.md"
check_file ".cursor/agents/requirements-write.md"
check_file ".cursor/agents/requirements-review.md"
check_file ".cursor/agents/architecture-plan.md"
check_file ".cursor/agents/architecture-write.md"
check_file ".cursor/agents/architecture-review.md"
check_file ".cursor/agents/integration-test-write.md"
check_file ".cursor/agents/integration-test-review.md"
check_file ".cursor/agents/implementation-plan.md"
check_file ".cursor/agents/implementation-write.md"
check_file ".cursor/agents/implementation-review.md"
check_file ".cursor/agents/escalation-analysis.md"
check_file ".cursor/agents/escalation-recovery.md"
check_file ".cursor/agents/escalation-triage.md"
check_file ".cursor/agents/environment-recovery.md"
check_file ".cursor/agents/deploy-profile.md"

if [ -d ".cursor/agents" ]; then
    AGENT_COUNT=$(find .cursor/agents -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
    if [ "$AGENT_COUNT" -ne 19 ]; then
        echo "WARNING: Expected 19 agent prompt files, found $AGENT_COUNT"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

if [ -f ".cursor/agents/project-manager.md" ]; then
    echo "ERROR: .cursor/agents/project-manager.md exists; the PM is a skill, not a subagent"
    echo "       An agent file makes /project-manager delegate, which puts Coordinators at a"
    echo "       nesting depth where they cannot dispatch phase agents. Delete it."
    ERRORS=$((ERRORS + 1))
fi

echo "--- Agent Models ---"
check_file "paavos-forge/set-agent-models.sh"
check_executable "paavos-forge/set-agent-models.sh"
if [ -d ".cursor/agents" ]; then
    INHERIT_COUNT=0
    for agent_path in .cursor/agents/*.md; do
        [ -e "$agent_path" ] || continue
        agent_name="$(basename "$agent_path" .md)"
        if ! grep -q '^model:' "$agent_path"; then
            echo "ERROR: .cursor/agents/${agent_name}.md has no 'model:' frontmatter line"
            ERRORS=$((ERRORS + 1))
            continue
        elif grep -q '^model: inherit$' "$agent_path"; then
            INHERIT_COUNT=$((INHERIT_COUNT + 1))
            continue
        fi

        # Cursor accepts a bad model string silently: an unrecognised ID runs on
        # the parent chat's model, and an unrecognised parameter is dropped so
        # the model default applies. Both look correct in the frontmatter, so
        # catch them here rather than several hours into a pipeline run.
        MODEL_VALUE="$(grep -m1 '^model:' "$agent_path" | sed 's/^model:[[:space:]]*//')"
        MODEL_ID="${MODEL_VALUE%%[*}"
        case "$MODEL_ID" in
            cursor-*)
                echo "ERROR: .cursor/agents/${agent_name}.md uses '$MODEL_ID'; model IDs carry no 'cursor-' prefix"
                echo "       That is a billing display name. Use '${MODEL_ID#cursor-}' (see DEPLOY.md Step 6)."
                ERRORS=$((ERRORS + 1))
                ;;
        esac
        case "$MODEL_ID:$MODEL_VALUE" in
            gpt-*:*effort=*|glm-*:*effort=*|kimi-*:*effort=*)
                echo "ERROR: .cursor/agents/${agent_name}.md uses 'effort' on '$MODEL_ID', which takes 'reasoning'"
                ERRORS=$((ERRORS + 1))
                ;;
            claude-*:*reasoning=*|grok-*:*reasoning=*|gemini-*:*reasoning=*)
                echo "ERROR: .cursor/agents/${agent_name}.md uses 'reasoning' on '$MODEL_ID', which takes 'effort'"
                ERRORS=$((ERRORS + 1))
                ;;
        esac
    done
    if [ "$INHERIT_COUNT" -gt 0 ]; then
        echo "WARNING: $INHERIT_COUNT agent(s) still on 'model: inherit'; they will run on whatever model the chat happens to use"
        echo "         Assign models by bucket: bash paavos-forge/set-agent-models.sh --list  (see DEPLOY.md Step 6)"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

echo "--- Cursor Rules and Skills ---"
check_file ".cursor/rules/paavos-forge.mdc"
check_file ".cursor/skills/project-manager/SKILL.md"
check_file ".cursor/skills/ai-status/SKILL.md"

echo "--- Taskwarrior UDAs (main tree) ---"
if [ -x "taskwarrior/tw" ]; then
    UDAS=$(taskwarrior/tw _udas 2>/dev/null || echo "")
    for UDA in aiepic epicstate airole; do
        if ! echo "$UDAS" | grep -q "$UDA"; then
            echo "ERROR: Taskwarrior UDA '$UDA' not configured. Run: bash taskwarrior/setup.sh --main"
            ERRORS=$((ERRORS + 1))
        fi
    done
    PM_LOCK=$(taskwarrior/tw +AI_LOCK airole:pm count 2>/dev/null || echo "0")
    if [ "$PM_LOCK" -lt 1 ]; then
        echo "ERROR: PM singleton lock task missing. Run: bash taskwarrior/setup.sh --main"
        ERRORS=$((ERRORS + 1))
    fi
    GATE=$(taskwarrior/tw +MERGE_GATE count 2>/dev/null || echo "0")
    if [ "$GATE" -lt 1 ]; then
        echo "ERROR: Merge gate task missing. Run: bash taskwarrior/setup.sh --main"
        ERRORS=$((ERRORS + 1))
    fi
elif command -v task &> /dev/null; then
    echo "WARNING: taskwarrior/tw not executable. Cannot verify UDAs."
    WARNINGS=$((WARNINGS + 1))
else
    echo "WARNING: Taskwarrior not found. Install it and run: bash taskwarrior/setup.sh --main"
    WARNINGS=$((WARNINGS + 1))
fi

echo "--- Git ---"
if [ ! -d ".git" ]; then
    echo "WARNING: Not a git repository. Initialize with: git init"
    WARNINGS=$((WARNINGS + 1))
else
    # Epic worktrees are created from main, so the framework must be committed there.
    for required in taskwarrior paavos-forge plan/templates AGENTS.md; do
        if [ -z "$(git ls-tree --name-only main -- "$required" 2>/dev/null)" ]; then
            echo "WARNING: '$required' is not committed to main. epic-fork will refuse until it is."
            WARNINGS=$((WARNINGS + 1))
        fi
    done
fi

echo "--- Framework Invariants (doctor) ---"
if [ -x "taskwarrior/doctor" ] && command -v task &> /dev/null; then
    if bash taskwarrior/doctor >/dev/null 2>&1; then
        echo "doctor: all checks passed"
    else
        DOCTOR_RC=$?
        echo "WARNING: bash taskwarrior/doctor exited ${DOCTOR_RC}. Run it directly for details."
        WARNINGS=$((WARNINGS + 1))
    fi
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
