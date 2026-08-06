# AI Agents: Project Instructions

This project uses Paavo's Forge.

## Entry Point

Feature work starts in a new chat with `/project-manager`. The PM is a top-level skill, not a subagent: it dispatches Coordinators, which dispatch phase agents. A general agent must not implement features, create Forge artifacts, or run the Coordinator; direct the user to `/project-manager`.

## Instruction Order

`paavos-forge/LOGIC.md` is authoritative if instructions conflict. For each task:

1. Follow the always-on Paavo's Forge rule.
2. Follow your named agent or skill prompt, especially its `Context Loading` and forbidden-read list.
3. Read `paavos-forge/project-profile.md` for project conventions and paths.
4. Read only the named section(s) of `paavos-forge/LOGIC.md` when your role prompt requires them; it is not mandatory per-task context.

`ARCHITECTURE.md` defines the committed domain vocabulary and DAG. Story Proposed Domain Tags are proposals only. Artifact templates live in `plan/templates/`; the project profile defines source, architecture-artifact, and test directories.

## Write Gates

Only these roles may write their respective artifacts:

- `requirements-write`: `plan/requirements/`
- `architecture-plan` / `implementation-plan`: phase plans
- `architecture-write`: architecture artifacts
- `integration-test-write`: integration tests
- `implementation-write`: source code
- matching review agent: its review feedback
- `deploy-profile` (deploy time only) / `project-profile-maintainer` (after each milestone): `paavos-forge/project-profile.md`

`escalation-recovery` may make bounded current-story corrections; `environment-recovery` may only perform its whitelisted repairs and append its recovery result; `escalation-triage` writes nothing; `fixer` fixes existing source and tests only.

All workflow and state rules, including script paths, Taskwarrior mutations, models, Codex access, reviews, escalations, discoveries, locks, and git policy, are in the always-on rule and `paavos-forge/LOGIC.md`.
