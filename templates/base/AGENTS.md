# AI Agents: Project Instructions

This file tells AI agents how this project uses the AI execution framework.

## Framework

This project uses the AI execution framework. The canonical workflow specification is in `ai-framework/LOGIC.md`. Read it before doing any work.

## Project Profile

Project-specific conventions (language, directories, test commands, architecture type, mock boundaries, review standards, forbidden areas) are defined in `ai-framework/project-profile.md`. Read it before every task.

## Agent Roles

Agents in this project follow a strict hierarchy:

- **Project Manager** (`project-manager`): defines milestones and stories, invokes the Coordinator
- **Coordinator** (`coordinator`): drives stories through phases, manages Taskwarrior and git
- **Phase Agents**: specialized agents for each phase (requirements, architecture, tests, implementation) and state (plan, write, review)
- **Support Agents**: story review, escalation analysis

See `ai-framework/LOGIC.md` for the full role descriptions and workflow rules.

## Key Rules

1. Taskwarrior is the source of truth for execution state.
2. Every artifact written must be annotated on the corresponding Taskwarrior task.
3. Agents follow the phase state machine: `plan -> write -> review -> done`.
4. Reviews focus on blocking issues, not style nits.
5. If you cannot complete your task, write an escalation to `plan/escalations/` and exit.
6. All templates are in `plan/templates/`. Use them for every artifact.
7. Read the project profile before every task for language and convention details.

## Artifact Locations

- Milestones: `plan/milestones/`
- Stories: `plan/stories/`
- Requirements: `plan/requirements/[domain]/`
- Phase plans: `plan/*-plans/`
- Review feedback: `plan/*-review/`
- Escalations: `plan/escalations/`
- Templates: `plan/templates/`
- Domain dependency policy: `ARCHITECTURE.md` (project root)

Source code, architecture artifacts, and test directories are defined in the project profile.
