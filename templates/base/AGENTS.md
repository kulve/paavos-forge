# AI Agents: Project Instructions

This file tells AI agents how this project uses the AI execution framework.

## Starting Development (READ THIS FIRST)

To add new features or implement changes, always start a **`project-manager`** agent chat. Never ask a general agent to implement, write code, or "run the Coordinator."

The framework only produces requirements, architecture, tested code, and full traceability when the PM drives the Coordinator, which drives the phase agents. Each agent runs in its own constrained context with a narrow role -- this is what makes the pipeline reliable.

**If you are a general agent** and the user asks you to implement a feature, write code, create requirements, or execute the framework pipeline: **do not do it**. Instead, tell the user to open a new chat with the `project-manager` agent and describe the goal there.

## Framework

This project uses the AI execution framework. The canonical workflow specification is in `ai-framework/LOGIC.md`. Read it before doing any work.

## Project Profile

Project-specific conventions (language, directories, test commands, architecture type, mock boundaries, review standards, forbidden areas) are defined in `ai-framework/project-profile.md`. Read it before every task.

## Agent Roles

Agents in this project follow a strict hierarchy:

- **Project Manager** (`project-manager`): defines milestones and stories, invokes the Coordinator
- **Coordinator** (`coordinator`): drives stories through phases, manages Taskwarrior and git
- **Phase Agents**: specialized agents for each phase (requirements, architecture, tests, implementation) and state (plan, plan-review, write, review)
- **Support Agents**: story review, escalation analysis
- **Fixer** (`fixer`): fixes bugs in existing code outside the PM pipeline; invoked directly by the user

See `ai-framework/LOGIC.md` for the full role descriptions and workflow rules.

## Taskwarrior

All Taskwarrior commands must use `taskwarrior/tw`, never bare `task`. The wrapper ensures per-project database isolation:

- Config: `.taskrc` at project root (`data.location=.task`, `confirmation=off`)
- Database: `.task/` directory (gitignored, never committed)
- Wrapper: `taskwarrior/tw` sources `taskwarrior/env.sh` and sets `TASKRC`
- Command patterns: see `taskwarrior/recipes.md`

## Key Rules

1. Taskwarrior is the source of truth for execution state.
2. Every artifact written must be annotated on the corresponding Taskwarrior task.
3. Agents follow the phase state machine: `plan -> plan-review -> write -> review -> done`.
4. Reviews focus on blocking issues, not style nits.
5. If you cannot complete your task, write an escalation to `plan/escalations/` and exit.
6. All templates are in `plan/templates/`. Use them for every artifact.
7. Read the project profile before every task for language and convention details.
8. All Taskwarrior commands use `taskwarrior/tw`, never bare `task`.
9. Only one PM and one Coordinator may run at a time. If you are a duplicate (the matching `+AI_LOCK` task is already `+ACTIVE`), report status with read-only Taskwarrior queries and exit. Do not modify anything.
10. Agents may record significant out-of-scope findings as new discovery files, but only the PM may read and triage discoveries.

## Artifact Locations

- Milestones: `plan/milestones/`
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

Any agent may create one new discovery file under `plan/discoveries/` for a significant out-of-scope finding, using `plan/templates/discovery.md`, then continue its assigned task. Subagents must never read, list, modify, deduplicate, or delete existing discoveries; the PM triages them after milestone completion.

The exact directories are defined in `ai-framework/project-profile.md`. The ownership rules above apply to whatever directories the project profile specifies.

The `fixer` agent has limited write access to source and test directories for bug fixes only. It must not create or modify framework artifacts (`plan/`, requirements, architecture), add features, or change public interfaces. If a fix exceeds this scope, the fixer redirects the user to the PM pipeline.

Any agent receiving a request to implement a feature, write code, create architecture artifacts, write tests, or "run the Coordinator" must **NOT** do the work directly. Instead: tell the user to start a `project-manager` agent chat.
