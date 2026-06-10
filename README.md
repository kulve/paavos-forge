# AI Execution Framework

A generic template that enables AI agents to autonomously implement large projects from high-level goals. Deploy it into a downstream project, describe what you want to build, and the framework drives stories through requirements, architecture, tests, and implementation -- each phase planned, written, and reviewed by specialized agents.

## What It Does

You give a high-level milestone (e.g. "implement a simple game"). The framework:

1. Breaks it into vertical feature stories (2-3 at a time, no waterfall)
2. For each story, runs four phases in sequence: **requirements -> architecture -> integration tests -> implementation**
3. Each phase goes through **plan -> plan-review -> write -> review** with specialized agents
4. Taskwarrior tracks execution state; git manages code via ephemeral story branches
5. Failed reviews loop back (max 3 rounds); unresolvable issues halt execution and escalate to the user via the PM
6. Completed stories squash-merge to `main`

## What It Is Not

- Not an AI model or runtime -- it's a set of agent prompts, workflow rules, and templates
- Not tied to a single language -- optimized for C++ but works with Python, TypeScript, etc. via a project profile
- Not a CI/CD tool -- it orchestrates AI agents within an IDE (currently Cursor)
- Not a replacement for human judgment -- the PM agent discusses goals with the user and escalates when stuck

## Key Files

| File | Purpose |
|------|---------|
| `LOGIC.md` | Canonical workflow specification -- the single source of truth |
| `DEPLOY.md` | Step-by-step guide to deploy into a downstream project |
| `AGENTS.md` | Instructions for AI agents maintaining this framework repo |
| `templates/base/` | Files copied to every downstream project |
| `templates/cursor/` | Cursor-specific agents, rules, and commands |

## Quick Start

See [DEPLOY.md](DEPLOY.md) for the full deployment guide. The short version:

1. Copy `templates/base/*` into your project root
2. Copy `templates/cursor/.cursor/` into your project root
3. Run `bash taskwarrior/setup.sh` to configure Taskwarrior UDAs
4. Fill in `ai-framework/project-profile.md` with your project's details
5. Start a chat with the `project-manager` agent

## Architecture

The framework has a layered agent hierarchy:

- **Project Manager**: talks to the user, defines milestones, generates stories in rolling batches
- **Coordinator**: deterministic state machine that drives one story through all four phases
- **Phase Agents** (16 total): 4 phases x 4 states (plan/plan-review/write/review), each with narrow context
- **Support Agents**: story review, escalation analysis

All context passes through Taskwarrior annotations (file paths only). Agents never talk to each other directly, keeping context windows small and focused.

## Contributing

This is a generic template. When deploying into a project, you'll likely tune agent prompts and add domain-specific guidance. If your changes are generic enough to benefit other projects, contribute them back:

- Keep changes language-agnostic in core files; language-specific details go in the project profile
- Update `LOGIC.md` if you change any workflow rules
- Update agent prompts and templates together -- they must stay consistent
- Test by deploying into a real project

See [AGENTS.md](AGENTS.md) for maintenance guidelines.
