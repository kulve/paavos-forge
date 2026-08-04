# AI Agents: Paavo's Forge Maintenance Guide

This file is for AI agents maintaining the Paavo's Forge template repository itself. If you are an agent working in a downstream project that deployed this framework, read your project's `AGENTS.md` and `ai-framework/LOGIC.md` instead.

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
| `templates/base/ai-framework/set-agent-models.sh` | Canonical agent-to-bucket mapping | Copied to `ai-framework/`; the user picks the model per bucket |
| `.cursor/agents/*.md` frontmatter `model:` | Always `inherit` | Set per bucket at deploy time by `set-agent-models.sh` |
| `DEPLOY.md` | Human deployment procedure for new projects | Not copied -- lives only in this repo |
| `README.md` | Human overview of the framework template | Each project has its own README |

Downstream projects never edit workflow rules in place. They receive a copy of root `LOGIC.md` during deployment and may merge upstream updates later (see `DEPLOY.md`).

## Key Principles

### Public Repository -- No Secrets or Local References

This repository is **public**. Everything committed here is world-readable. Never commit:

- Secrets of any kind: API keys, tokens, passwords, credentials, private keys.
- Personal or private data: private email addresses, real names tied to accounts, phone numbers.
- Machine-local references: absolute home paths (`/home/<user>/...`, `/Users/<user>/...`), internal hostnames, private IPs, machine-specific project slugs, or personal directory defaults.

Instead, use placeholders or required arguments (e.g. `<project-slug>`, `$HOME/.cursor/projects/<project-slug>/...`), and keep local state gitignored (`.task/`, `.worktrees/`, `/.cursor/`). When adding scripts or docs, prefer an explicit required argument over a personal default value. Before committing, scan your diff for the patterns above.

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

**Exception -- Paavo's Codex:** This framework intentionally couples to Paavo's Codex as the hard dependency for product intent (MCP knowledge source). Naming Paavo's Codex in `LOGIC.md`, agent prompts, the project profile, and deployment docs is allowed and required. Do not "genericize" that coupling away unless the user explicitly requests it. Still do not hardcode MCP tool names/signatures -- agents discover them via MCP.

### Keep Templates and Docs Consistent

Agent prompts reference artifact templates, Taskwarrior recipes, and LOGIC.md sections. When updating any of these:

- Verify all cross-references still point to correct section numbers, file paths, and command patterns
- Verify the artifact template fields match what agent prompts expect to read/write
- Verify Taskwarrior commands in recipes match UDA names in `setup.sh`

### No Project-Specific Leakage

Never add content that assumes a specific *downstream application* project. This includes:

- Specific class names, module names, or API endpoints of a deployed product
- Specific test frameworks (always reference "the test framework from the project profile")
- Specific build commands (always reference "the build command from the project profile")
- Hardcoded directory paths (always reference "the directory from the project profile")

Paavo's Codex as the product-intent knowledge source is a framework dependency, not leakage (see Preserve Genericity exception above).

## Script Protocol (`taskwarrior/`)

All state mutations in agent prompts and LOGIC.md must use the provided scripts, never raw `taskwarrior/tw` for writes. Read-only queries still use `taskwarrior/tw`.

When updating agent prompts or command references:
- Verify state mutations use scripts (`phase-transition`, `phase-annotate`, etc.)
- Verify read-only queries use `taskwarrior/tw`
- Verify script names match what exists in `templates/base/taskwarrior/`

AI lock and gate recovery is manual-only. Agents must never clear stale locks or gates automatically. Point users to `bash taskwarrior/cleanup-ai-state.sh` or `bash taskwarrior/epic-gate-release --force`.

## File Structure

```
LOGIC.md                                   # Canonical workflow spec (edit here only)
README.md                                  # Human overview
AGENTS.md                                  # This file (template-repo maintenance)
DEPLOY.md                                  # Deployment guide for downstream projects

templates/base/                            # Copied to downstream project root
  AGENTS.md                                # Becomes downstream project AGENTS.md
  ARCHITECTURE.md                          # Domain dependency policy skeleton
  .gitignore                               # Ignores .task/, .taskrc, .worktrees/, build/
  ai-framework/project-profile.md          # Filled by deploying user
  ai-framework/README.md                   # Notes that LOGIC.md is copied at deploy time
  ai-framework/set-agent-models.sh         # Canonical agent->bucket map; writes model: lines
  plan/templates/*.md                      # 9 artifact templates (incl. project.md, epic.md)
  plan/epics/.gitkeep                      # Epic artifacts directory
  taskwarrior/setup.sh                     # Generates .taskrc + UDA setup (--main / --worktree)
  taskwarrior/taskrc.template              # Base config for the generated .taskrc
  taskwarrior/env.sh                       # Exports TASKRC + absolute TASKDATA, creates .task/
  taskwarrior/guard.sh                     # Sourced by every script: AI_ROOT + context enforcement
  taskwarrior/tw                           # Project-local task wrapper (read-only use)
  taskwarrior/recipes.md                   # Script usage documentation
  taskwarrior/cleanup-ai-state.sh          # Manual recovery script
  taskwarrior/doctor                       # Invariant checks D01-D12, --fix for safe repairs
  taskwarrior/coordinator-heartbeat        # Progress telemetry writer (called by scripts)
  taskwarrior/coordinator-status           # Liveness/progress aggregator (PM supervision)
  taskwarrior/epic-*                       # Epic lifecycle scripts (7)
  taskwarrior/story-*                      # Story lifecycle scripts (4)
  taskwarrior/phase-*                      # Phase state scripts (8, incl. phase-gate, phase-resume)
  taskwarrior/pm-lock-* / pm-preflight     # PM lock/status scripts (3)
  taskwarrior/coordinator-lock-*           # Coordinator lock scripts (3)

templates/cursor/.cursor/                  # Copied to downstream .cursor/
  agents/*.md                              # 19 agent prompts (incl. roadmap-planner, deploy-profile,
                                           #   escalation-triage, environment-recovery). No PM here.
  rules/ai-framework.mdc                   # Always-on rules
  skills/project-manager/SKILL.md          # The PM; runs as the top-level chat, not a subagent
  skills/ai-status/SKILL.md                # Read-only pipeline status report

scripts/
  install-into-project.sh                  # Copies templates + LOGIC.md into a target project (DEPLOY.md)
  test-install-into-project.sh             # Installer conflict-preflight smoke (called by validate-template-repo)
  validate-template-repo.sh                # Validates template-repo layout
  validate-deployment.sh                   # Validates a deployed downstream project
  test-isolation.sh                        # Worktree isolation + telemetry + doctor smoke test
  models/list-models.mjs                   # Lists real model IDs/parameters for DEPLOY.md Step 6
  models/package.json                      # Its @cursor/sdk dependency (node_modules gitignored)
```

## Model IDs Come From the Catalog, Not From Memory

`scripts/models/list-models.mjs` is the authoritative source for the model IDs and bracket parameters that DEPLOY.md Step 6 tells users to write. Cursor's model picker and billing exports both show display names: `cursor-grok-4.5-high-fast` in billing is the model whose selectable ID is `grok-4.5`. Neither kind of mistake reports an error at run time -- a wrong ID silently runs the agent on the parent chat's model, and an unrecognised parameter is silently dropped so the model's own default applies.

The script lives in `scripts/` rather than `templates/base/` so deployed C++ or Python projects do not inherit a Node dependency.

Four places encode model-string knowledge: DEPLOY.md Step 6, `templates/cursor/.cursor/agents/deploy-profile.md`, the lint rules in `templates/base/ai-framework/set-agent-models.sh`, and the frontmatter checks in `scripts/validate-deployment.sh`. Change one and check the rest. Re-run the listing rather than editing any of them from memory.

## Isolation Invariants (do not regress these)

Worktree isolation is enforced by construction, not by agent discipline. When touching `templates/base/taskwarrior/`:

- Every script sources `taskwarrior/guard.sh`. Every script except `tw`, `env.sh`, and `setup.sh` calls `require_context main` or `require_context worktree`; `setup.sh` validates the tree against its own `--main`/`--worktree` flag.
- Never reintroduce `SCRIPT_DIR` or `PROJECT_ROOT`. Use `AI_ROOT`, which `guard.sh` exports and `cd`s into.
- Taskwarrior state must stay absolute: `env.sh` exports `TASKDATA`, and generated `.taskrc` files carry an absolute `data.location`. A relative `data.location` reintroduces the bug where the caller's working directory selects the database.
- `.taskrc` stays generated and gitignored. Never add it back under `templates/base/`.
- Agent prompts must never pass `working_directory` to a subagent (the parameter does not exist) and must instruct absolute script invocation.
- Agent prompts must never pass a `model` parameter to a subagent. That argument overrides the target's frontmatter, which would defeat the bucket assignment entirely.
- Coordinator progress is observed only through `coordinator-status`. Do not add guidance that reads agent transcripts.

After any change in `taskwarrior/`, `scripts/`, or the isolation-related prompt sections, run both:

```bash
bash scripts/validate-template-repo.sh
bash scripts/test-isolation.sh
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
8. Keep `model: inherit` in the frontmatter. Downstream deployments assign the real model by bucket; a concrete slug shipped upstream would override every deployed project's choice on merge.

**Adding or removing an agent prompt** also requires updating `BUCKET_MAP` in `templates/base/ai-framework/set-agent-models.sh` and the agent counts in both validators. `validate-template-repo.sh` fails if the two sets disagree, so a forgotten bucket assignment cannot ship.

**The Project Manager is not an agent prompt.** It lives at `templates/cursor/.cursor/skills/project-manager/SKILL.md` and has no bucket, because a skill loads into the top-level chat and therefore runs on that chat's model. Never move it back under `agents/`: see the nesting budget below.

## Nesting Budget (do not regress this)

Cursor allows two levels of subagents below the top-level chat. A subagent launched by another subagent receives no dispatch tool at all. The framework consumes the entire budget:

| Level | Who | May dispatch |
|-------|-----|--------------|
| 0 | PM, via the `project-manager` skill in the top-level chat | yes |
| 1 | Coordinator, `roadmap-planner`, `story-review`, escalation agents | Coordinator only |
| 2 | Phase agents and `escalation-recovery`, dispatched by a Coordinator | no |

Consequences for anything you edit here:

- The PM stays a skill. Shipping a `project-manager` agent prompt makes `/project-manager` delegate, which moves every Coordinator to level 2 and silently disables the whole phase pipeline. Both validators fail if that file reappears.
- The Coordinator is the only agent prompt permitted to contain subagent-dispatch instructions. `validate-template-repo.sh` enforces this by asserting that `run_in_background` appears in `coordinator.md` and nowhere else under `templates/cursor/.cursor/agents/`.
- Do not add a dispatch step to any phase agent, or to `escalation-recovery`. There is no level left for it: the reconciler runs at level 2 when the Coordinator dispatches it inline, and it must do its own repair work rather than delegate.
