# AI Agents: Framework Maintenance Guide

This file is for AI agents maintaining the AI execution framework template repository itself. If you are an agent working in a downstream project that deployed this framework, read your project's `AGENTS.md` and `ai-framework/LOGIC.md` instead.

## Shell Commands (`ccmd`)

All shell commands in this repository must run through `ccmd`. This avoids per-command approval prompts in Cursor.

- Prefix every command with `ccmd`. Never run bare `git`, `ls`, `bash`, etc.
- Piping: wrap each stage -- `ccmd ls -la | ccmd grep foo` (not `ccmd ls | grep foo`).
- Do not pass shell metacharacter bundles as one argument (e.g. avoid `ccmd "ls && rm -rf ."`).
- If blocked, `ccmd` exits 1 with `ccmd: blocked: <reason>`. Do not retry with bypass syntax; use a safe alternative.

**Git (allowed):** `ccmd git status`, `ccmd git diff`, `ccmd git log`, `ccmd git add`, `ccmd git commit`, `ccmd git init`, `ccmd git show`, `ccmd git fetch`, `ccmd git blame`, `ccmd git ls-files`.

**Git (blocked):** `ccmd git push`, `ccmd git rebase`, `ccmd git reset --hard`, and other destructive operations unless the user explicitly requests them.

## Repository Purpose

This repository is a generic, deployable template. It does not build or run anything on its own. Its outputs are documentation and template files that get copied into downstream projects.

## This Repo vs Deployed Projects

| File | In this template repo | In a deployed downstream project |
|------|----------------------|----------------------------------|
| `AGENTS.md` (root) | Instructions for agents maintaining this framework repo | Not present -- use the deployed copy instead |
| `templates/base/AGENTS.md` | Template for downstream project agent instructions | Copied to project root as `AGENTS.md` |
| `LOGIC.md` (root) | Canonical workflow specification -- edit here only | Copied to `ai-framework/LOGIC.md` at deploy time |
| `ai-framework/LOGIC.md` | Not present at repo root | Deployed workflow spec used by all project agents |
| `templates/base/ai-framework/project-profile.md` | Blank template | Copied and filled in by the deploying user |
| `DEPLOY.md` | Human deployment procedure for new projects | Not copied -- lives only in this repo |
| `README.md` | Human overview of the framework template | Each project has its own README |

Downstream projects never edit workflow rules in place. They receive a copy of root `LOGIC.md` during deployment and may merge upstream updates later (see `DEPLOY.md`).

## Key Principles

### LOGIC.md is Authoritative

Root `LOGIC.md` is the single source of truth for the workflow specification. Do not maintain a second editable copy under `templates/base/`. If you need to change how the framework works (phases, states, Taskwarrior protocol, git policy, escalation protocol), change root `LOGIC.md` first, then update all files that reference those rules:

- All agent prompts in `templates/cursor/.cursor/agents/`
- The Cursor rule in `templates/cursor/.cursor/rules/ai-framework.mdc`
- The Taskwarrior recipes in `templates/base/taskwarrior/recipes.md`
- The deployment guide `DEPLOY.md`

After editing `LOGIC.md`, run `bash scripts/validate-template-repo.sh` to confirm the template repo layout is valid. Downstream projects receive `LOGIC.md` via the copy step in `DEPLOY.md`.

### Preserve Genericity

This template must work for C++, Python, TypeScript, and other languages. When making changes:

- Keep workflow rules language-agnostic in core files
- Language-specific details belong in the project profile (`templates/base/ai-framework/project-profile.md`)
- Use "architecture artifacts" instead of "headers" in generic contexts
- Test your changes mentally against at least C++ and Python use cases

### Keep Templates and Docs Consistent

Agent prompts reference artifact templates, Taskwarrior recipes, and LOGIC.md sections. When updating any of these:

- Verify all cross-references still point to correct section numbers, file paths, and command patterns
- Verify the artifact template fields match what agent prompts expect to read/write
- Verify Taskwarrior commands in recipes match UDA names in `setup.sh`

### No Project-Specific Leakage

Never add content that assumes a specific downstream project. This includes:

- Specific class names, module names, or API endpoints
- Specific test frameworks (always reference "the test framework from the project profile")
- Specific build commands (always reference "the build command from the project profile")
- Hardcoded directory paths (always reference "the directory from the project profile")

## Script Protocol (`taskwarrior/`)

All state mutations in agent prompts and LOGIC.md must use the provided scripts, never raw `taskwarrior/tw` for writes. Read-only queries still use `taskwarrior/tw`.

When updating agent prompts or command references:
- Verify state mutations use scripts (`phase-transition`, `phase-annotate`, etc.)
- Verify read-only queries use `taskwarrior/tw`
- Verify script names match what exists in `templates/base/taskwarrior/`

AI lock and gate recovery is manual-only. Agents must never clear stale locks or gates automatically. Point users to `ccmd bash taskwarrior/cleanup-ai-state.sh` or `ccmd bash taskwarrior/epic-gate-release --force`.

## File Structure

```
LOGIC.md                                   # Canonical workflow spec (edit here only)
README.md                                  # Human overview
AGENTS.md                                  # This file (template-repo maintenance)
DEPLOY.md                                  # Deployment guide for downstream projects

templates/base/                            # Copied to downstream project root
  AGENTS.md                                # Becomes downstream project AGENTS.md
  ARCHITECTURE.md                          # Domain dependency policy skeleton
  .taskrc                                  # Per-project Taskwarrior config
  .gitignore                               # Ignores .task/, .worktrees/, build/
  ai-framework/project-profile.md          # Filled by deploying user
  ai-framework/README.md                   # Notes that LOGIC.md is copied at deploy time
  plan/templates/*.md                      # 9 artifact templates (incl. epic.md)
  plan/epics/.gitkeep                      # Epic artifacts directory
  taskwarrior/setup.sh                     # UDA setup (--main / --worktree modes)
  taskwarrior/env.sh                       # Sets TASKRC, creates .task/
  taskwarrior/tw                           # Project-local task wrapper (read-only use)
  taskwarrior/recipes.md                   # Script usage documentation
  taskwarrior/cleanup-ai-state.sh          # Manual recovery script
  taskwarrior/epic-*                       # Epic lifecycle scripts (7)
  taskwarrior/story-*                      # Story lifecycle scripts (4)
  taskwarrior/phase-*                      # Phase state scripts (6)
  taskwarrior/pm-lock-* / pm-preflight     # PM lock/status scripts (3)
  taskwarrior/coordinator-lock-*           # Coordinator lock scripts (3)

templates/cursor/.cursor/                  # Copied to downstream .cursor/
  agents/*.md                              # 22 agent prompts
  rules/ai-framework.mdc                   # Always-on rules
  commands/*.md                            # Slash commands

scripts/
  validate-template-repo.sh                # Validates template-repo layout
  validate-deployment.sh                   # Validates a deployed downstream project
```

## When Updating Agent Prompts

Agent prompts follow a standard structure (see LOGIC.md section 11). When editing them:

1. Maintain the standard sections: Role, Goal, Context Loading, Procedure, Output Specification, Taskwarrior Protocol, Quality Criteria, Anti-Patterns, Escalation
2. Keep Context Loading precise -- list exactly what to read and what NOT to read
3. Keep Procedures numbered and unambiguous
4. Keep Anti-Patterns specific to the role (not generic advice)
5. Verify state mutations use scripts (not raw `taskwarrior/tw`)
6. Verify file paths match artifact templates
7. Verify script names match `recipes.md` and actual script files
