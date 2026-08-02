# AI Agents: Project Instructions

This file tells AI agents how this project uses the AI execution framework.

## Starting Development (READ THIS FIRST)

To add new features or implement changes, always start a new chat and invoke the **`/project-manager`** skill. Never ask a general agent to implement, write code, or "run the Coordinator."

The PM is a skill rather than a subagent so that it occupies the top-level chat. Cursor allows only two levels of subagents below the top-level chat, and the pipeline needs both: the PM launches a Coordinator, and the Coordinator dispatches phase agents. Delegating to the PM instead would push Coordinators down a level, where they cannot dispatch anything.

The framework only produces requirements, architecture, tested code, and full traceability when the PM drives the pipeline. Each agent runs in its own constrained context with a narrow role -- this is what makes the pipeline reliable.

**If you are a general agent** and the user asks you to implement a feature, write code, create requirements, or execute the framework pipeline: **do not do it**. Instead, tell the user to start a new chat, invoke `/project-manager`, and describe the goal there.

## Framework

This project uses the AI execution framework. The canonical workflow specification is in `ai-framework/LOGIC.md`. Read it before doing any work.

## Project Profile

Project-specific conventions (language, directories, test commands, architecture type, mock boundaries, review standards, forbidden areas) are defined in `ai-framework/project-profile.md`. Read it before every task.

## Execution Model

The framework uses a four-level hierarchy:

- **Project** (mandatory): `plan/project.md` pins a Paavo Notes closed version and an ordered milestone roadmap to product completion
- **Milestone**: derived from the roadmap; groups related epics; Status Done / In Progress / TODO
- **Epic**: the unit of parallel execution; each epic gets its own git worktree
- **Story**: a vertical feature slice; stories within an epic execute serially

Multiple epics run in parallel in isolated git worktrees. Each worktree has its own Taskwarrior database. A merge gate ensures only one epic merges to main at a time.

## Paavo Notes (Hard Dependency)

Product intent lives in Paavo Notes (MCP). The framework caches a pinned execution roadmap in `plan/project.md`.

- If the Paavo Notes MCP is unreachable, the PM hard-stops and requirements agents escalate. Do not invent product goals.
- Always read the closed integer version pinned in `plan/project.md`.
- Agents discover MCP tool signatures via Cursor; do not hardcode tool APIs.
- **Who may access Paavo Notes**: PM, Roadmap Planner, and the four requirements-phase agents.
- Architecture, test, and implementation agents must never access Paavo Notes.
- Open questions may be posted append-only against the pinned version; agents must not list/read existing open questions.
- Local discoveries are for code/impl findings; product-intent gaps belong in Paavo Notes.

## Agent Roles

Agents follow a strict hierarchy:

- **Project Manager** (`/project-manager` skill, runs as the top-level chat): owns `plan/project.md`, defines milestones from the roadmap, creates epics, generates stories, dispatches epics for parallel execution, merges back to main, orchestrates escalation recovery
- **Roadmap Planner** (`roadmap-planner`): PM-invoked; synthesizes `plan/project.md` from Paavo Notes
- **Coordinator** (`coordinator`): drives all stories in an epic through phases, manages Taskwarrior and git within its worktree (never accesses Paavo Notes)
- **Phase Agents**: specialized agents for each phase (requirements, architecture, tests, implementation) and state (plan, plan-review, write, review)
- **Support Agents**: story review, escalation analysis, escalation triage, escalation recovery, environment recovery
- **Fixer** (`fixer`): fixes bugs in existing code outside the PM pipeline; invoked directly by the user

See `ai-framework/LOGIC.md` for the full role descriptions and workflow rules.

## Script Protocol

All Taskwarrior state mutations must go through the provided scripts under `taskwarrior/`. Agents must never call `taskwarrior/tw` directly for state changes (modify, add, done, start, stop, annotate). Read-only queries are allowed.

Key scripts:
- **PM**: `pm-lock-acquire`, `pm-lock-release`, `epic-fork`, `epic-merge`, `epic-mark-ready`, `epic-status`, `pm-preflight`
- **Coordinator**: `coordinator-lock-acquire`, `coordinator-lock-release`, `story-init`, `story-next`, `story-complete`, `story-merge`
- **Phase**: `phase-start`, `phase-stop`, `phase-transition`, `phase-annotate`, `phase-done`, `phase-block`
- **Diagnostics and telemetry**: `doctor`, `coordinator-status` (main tree), `coordinator-heartbeat` (called by the scripts above, never by agents)

**Invoke every script by absolute path**: `bash <tree-root>/taskwarrior/<script>`. Subagents cannot be given a working directory, so a relative invocation silently targets whatever tree the agent happens to be standing in. Each script sources `taskwarrior/guard.sh`, which resolves its own tree and exits 2 if it was invoked against the wrong one (main-only script in a worktree, or the reverse).

See `taskwarrior/recipes.md` for full documentation.

## Subagent Models

Each agent's model is pinned in its own `.cursor/agents/*.md` frontmatter, assigned by bucket via `ai-framework/set-agent-models.sh` (see `DEPLOY.md` Step 6). Run it with `--list` to see the current assignment. The PM has no bucket: it is a skill, so it runs on whatever model you select for the top-level chat.

**Never pass a `model` parameter when invoking a subagent.** That argument overrides the frontmatter and silently replaces a deliberate capability assignment with the parent's model. Do not hand-edit `model:` lines either; re-run the script so a whole bucket stays consistent.

## Taskwarrior

All Taskwarrior read-only commands must use `taskwarrior/tw`, never bare `task`. The wrapper ensures per-project database isolation:

- Config: `.taskrc` at each tree root -- **generated by `taskwarrior/setup.sh` and gitignored**, never committed. Its UDAs are mode-specific, so a committed worktree copy would corrupt the main tree's configuration on merge.
- Main tree database: `.task/` (PM-level: epic tracking, PM lock, merge gate)
- Worktree databases: `.worktrees/epic-*/.task/` (Coordinator-level: phase tasks, Coordinator lock, heartbeat)
- Wrapper: `taskwarrior/tw` sources `taskwarrior/guard.sh`, which exports `TASKRC` and an absolute `TASKDATA`, so the database never depends on the caller's working directory
- Setup: `taskwarrior/setup.sh --main` (project root) or `--worktree` (epic worktrees); it validates the tree against the flag

## Key Rules

1. Taskwarrior is the source of truth for execution state.
2. All state mutations go through scripts, never raw `taskwarrior/tw` for writes.
3. Agents follow the phase state machine: `plan -> plan-review -> write -> review -> done`.
4. Reviews focus on blocking issues, not style nits.
5. If you cannot complete your task, write an escalation to `plan/escalations/` and exit.
6. All templates are in `plan/templates/`. Use them for every artifact.
7. Read the project profile before every task for language and convention details.
8. Only one PM runs at a time (global). Only one Coordinator runs per worktree.
9. The merge gate allows only one epic to merge to main at a time. Scripts enforce this.
10. Stale locks and gates require manual user recovery via `cleanup-ai-state.sh`.
11. The PM must not invoke a Coordinator while one is already running in that worktree.
12. Agents may record significant out-of-scope findings as discoveries; only PM triages them.
13. Paavo Notes MCP is a hard dependency; never invent product intent when it is unavailable.
14. `plan/project.md` is mandatory before milestone/epic work; create it via `roadmap-planner`.
15. Invoke framework scripts by absolute path; never rely on the working directory.
16. Never pass a `model` parameter to a subagent; its frontmatter owns that choice.
17. Coordinators run in the background. Supervise them with `taskwarrior/coordinator-status`, never by reading agent transcripts.
18. Escalations are classified by `escalation-triage` before recovery: environment failures go to `environment-recovery`, artifact failures to `escalation-recovery`, and product or scope decisions to the user.
19. One automatic recovery attempt per root-cause fingerprint. A repeat fingerprint goes to the user.
20. The nesting budget is two levels of subagents: PM at the top-level chat, Coordinator below it, phase agents below that. Never delegate to the PM, and never give a phase agent a dispatch step.

## Artifact Locations

- Project roadmap: `plan/project.md`
- Milestones: `plan/milestones/`
- Epics: `plan/epics/`
- Stories: `plan/stories/`
- Requirements: `plan/requirements/[domain]/`
- Phase plans: `plan/*-plans/`
- Plan review feedback: `plan/*-plan-review/`
- Review feedback: `plan/*-review/`
- Escalations: `plan/escalations/`
- Discoveries: `plan/discoveries/`
- Templates: `plan/templates/`
- Domain dependency policy: `ARCHITECTURE.md` (project root)

Source code, architecture artifacts, and test directories are defined in the project profile.

## Write Gates (CRITICAL)

Only specifically designated phase agents may write to implementation directories:

- **Source code** (e.g. `src/`) -- only the `implementation-write` agent
- **Architecture artifacts** (e.g. `include/`, `src/interfaces/`) -- only the `architecture-write` agent
- **Integration tests** (e.g. `tests/integration/`) -- only the `integration-test-write` agent
- **Requirements** (`plan/requirements/`) -- only the `requirements-write` agent
- **Phase plans** (`plan/*-plans/`) -- only the respective plan agents
- **Plan review feedback** (`plan/*-plan-review/`) -- only the respective plan-review agents
- **Review feedback** (`plan/*-review/`) -- only the respective review agents

The `escalation-recovery` agent may modify artifacts for bounded corrections after a clean Coordinator halt. The `environment-recovery` agent may not modify artifacts at all: it repairs framework state through `taskwarrior/doctor --fix` and appends to the escalation file. The `escalation-triage` agent writes nothing. The `fixer` agent has limited write access to source and test directories for bug fixes only.

Any agent receiving a request to implement a feature or "run the Coordinator" must **NOT** do the work directly. Instead: tell the user to start a new chat and invoke `/project-manager`.
