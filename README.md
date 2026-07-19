# AI Execution Framework

A generic template that enables AI agents to autonomously implement large projects from high-level goals. Deploy it into a downstream project, describe what you want to build, and the framework drives epics through requirements, architecture, tests, and implementation -- each phase planned, written, and reviewed by specialized agents. Multiple epics execute in parallel via git worktrees.

## What It Does

You give a high-level goal (e.g. "implement a multiplayer game"). The framework:

1. Organizes work into **epics** (independent feature areas) and **stories** (vertical slices within each epic)
2. Dispatches each epic to its own **git worktree** for isolated parallel execution
3. For each story, runs four phases in sequence: **requirements -> architecture -> integration tests -> implementation**
4. Each phase goes through **plan -> plan-review -> write -> review** with specialized agents
5. All state mutations go through **deterministic scripts** -- agents react to exit codes, never manipulate state directly
6. A **merge gate** ensures atomic merges back to main when epics complete
7. Failed reviews loop back (max 3 rounds); unresolvable issues halt and escalate

## What It Is Not

- Not an AI model or runtime -- it's a set of agent prompts, workflow rules, scripts, and templates
- Not tied to a single language -- language-agnostic; works with C++, Python, TypeScript, Rust, and others via a project profile
- Not a CI/CD tool -- it orchestrates AI agents within an IDE (currently Cursor)
- Not a replacement for human judgment -- the PM agent discusses goals with the user and stops when recovery needs a product or scope decision

## Key Files

| File | Purpose |
|------|---------|
| `LOGIC.md` | Canonical workflow specification -- maintained here only; copied to `ai-framework/LOGIC.md` at deploy time |
| `DEPLOY.md` | Step-by-step guide to deploy into a downstream project |
| `AGENTS.md` | Instructions for AI agents maintaining this framework repo |
| `templates/base/AGENTS.md` | Template that becomes the downstream project's root `AGENTS.md` |
| `templates/base/` | Scaffolding copied to every downstream project (except `LOGIC.md`) |
| `templates/cursor/` | Cursor-specific agents, rules, and commands |

## Quick Start

See [DEPLOY.md](DEPLOY.md) for the full deployment guide. The short version:

1. Copy `templates/base/*` into your project root (plus `.taskrc` and `.gitignore`)
2. Copy root `LOGIC.md` to `ai-framework/LOGIC.md` in your project
3. Copy `templates/cursor/.cursor/` into your project root
4. Run `bash taskwarrior/setup.sh --main` to configure PM-level Taskwarrior state
5. Fill in `ai-framework/project-profile.md` with your project's details
6. Start a chat with the `project-manager` agent

## Architecture

The framework has a layered agent hierarchy:

- **Project Manager**: owns the project roadmap, defines milestones from Paavo Notes goals, creates epics, generates stories, dispatches epics to worktrees for parallel execution, merges completed epics back to main
- **Coordinator**: deterministic state machine that drives all stories in one epic through all four phases (operates within an epic's worktree)
- **Phase Agents** (16 total): 4 phases x 4 states (plan/plan-review/write/review), each with narrow context
- **Support Agents**: roadmap planner, story review, escalation analysis, escalation recovery

Product intent comes from **Paavo Notes** (MCP hard dependency). The framework caches a pinned milestone roadmap in `plan/project.md`. All state mutations go through deterministic scripts under `taskwarrior/`. Scripts enforce preconditions and mutual exclusion (merge gate, active-task guards). Context passes through Taskwarrior annotations. Agents never talk to each other directly.

### Execution Model

```
Project (mandatory: plan/project.md — pins Paavo Notes version + roadmap)
└── Milestone (Done / In Progress / TODO)
    └── Epic (parallel, one git worktree each)
        └── Story (serial within epic)
            └── Phase tasks (req → arch → test → impl)
```

## Contributing

This is a generic template. When deploying into a project, you'll likely tune agent prompts and add domain-specific guidance. If your changes are generic enough to benefit other projects, contribute them back:

- Keep changes language-agnostic in core files; language-specific details go in the project profile
- Update root `LOGIC.md` if you change any workflow rules
- Update agent prompts and templates together -- they must stay consistent
- Run `bash scripts/validate-template-repo.sh` before releasing template changes
- Test by deploying into a real project

See [AGENTS.md](AGENTS.md) for maintenance guidelines.
