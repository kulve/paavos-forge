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

## Key Principles

### LOGIC.md is Authoritative

`LOGIC.md` is the single source of truth for the workflow specification. If you need to change how the framework works (phases, states, Taskwarrior protocol, git policy, escalation protocol), change `LOGIC.md` first, then update all files that reference those rules:

- All agent prompts in `templates/cursor/.cursor/agents/`
- The Cursor rule in `templates/cursor/.cursor/rules/ai-framework.mdc`
- The Taskwarrior recipes in `templates/base/taskwarrior/recipes.md`
- The deployed copy at `templates/base/ai-framework/LOGIC.md`
- The deployment guide `DEPLOY.md`

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

## Taskwarrior Wrapper (`taskwarrior/tw`)

All Taskwarrior CLI references in agent prompts, recipes, and LOGIC.md must use `taskwarrior/tw`, never bare `task`. This ensures per-project database isolation in downstream projects.

When updating agent prompts or command references, verify that every Taskwarrior CLI invocation uses `taskwarrior/tw`.

## File Structure

```
LOGIC.md                                   # Change workflow rules here first
README.md                                  # Human overview
AGENTS.md                                  # This file
DEPLOY.md                                  # Deployment guide

templates/base/                            # Copied to downstream project root
  AGENTS.md                                # Project-level AI instructions
  ARCHITECTURE.md                          # Domain dependency policy skeleton
  .taskrc                                  # Per-project Taskwarrior config
  .gitignore                               # Ignores .task/ and build/
  ai-framework/LOGIC.md                    # Deployed workflow spec
  ai-framework/project-profile.md          # Filled by deploying user
  plan/templates/*.md                      # Artifact templates
  taskwarrior/setup.sh                     # UDA setup (sources env.sh)
  taskwarrior/env.sh                       # Sets TASKRC, creates .task/
  taskwarrior/tw                           # Project-local task wrapper
  taskwarrior/recipes.md                   # Command patterns

templates/cursor/.cursor/                  # Copied to downstream .cursor/
  agents/*.md                              # Agent prompts
  rules/ai-framework.mdc                   # Always-on rules
  commands/*.md                            # Slash commands
```

## When Updating Agent Prompts

Agent prompts follow a standard structure (see LOGIC.md section 4). When editing them:

1. Maintain the standard sections: Role, Goal, Context Loading, Procedure, Output Specification, Taskwarrior Protocol, Quality Criteria, Anti-Patterns, Escalation
2. Keep Context Loading precise -- list exactly what to read and what NOT to read
3. Keep Procedures numbered and unambiguous
4. Keep Anti-Patterns specific to the role (not generic advice)
5. Verify Taskwarrior commands match `recipes.md`
6. Verify file paths match artifact templates
