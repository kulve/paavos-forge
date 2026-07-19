# Deployment Guide

How to deploy the AI execution framework into a downstream project.

## Prerequisites

- **Git** installed
- **[Taskwarrior](https://taskwarrior.org/) 2.x+** installed -- verify with `task --version`
- **[Cursor](https://cursor.com/) IDE** (for the agent system; other IDE support is future work)
- System packages for your target language (e.g. C++: cmake, compiler; Python: python3, pip)

## Deployment Inputs

The framework ships from three locations in this repository:

| Source | Deployed to | Purpose |
|--------|-------------|---------|
| `templates/base/` | Project root | Scaffolding: `AGENTS.md`, Taskwarrior, plan templates, project profile |
| `LOGIC.md` (repo root) | `ai-framework/LOGIC.md` | Canonical workflow specification (copied as-is) |
| `templates/cursor/.cursor/` | `.cursor/` | Cursor agents, rules, and commands |

`templates/base/AGENTS.md` becomes your project's root `AGENTS.md`. Customize it after deployment if you need project-specific AI guidance (extra rules, domain context, or stricter review standards). The workflow specification itself lives in `ai-framework/LOGIC.md` and should not be edited unless you are intentionally forking the framework.

## Step 1: Copy Base Templates

Copy the base framework files into your project root:

```bash
FRAMEWORK=/path/to/ai-execution-framework
PROJECT=/path/to/your-project

cp -r "$FRAMEWORK/templates/base/"* "$PROJECT/"
cp "$FRAMEWORK/templates/base/.taskrc" "$PROJECT/"
cp "$FRAMEWORK/templates/base/.gitignore" "$PROJECT/"
```

> **Note:** `cp -r base/*` does not copy dotfiles. Copy `.taskrc` and `.gitignore` explicitly, or use `cp -r base/. project/` if your shell supports it.

### Step 1b: Copy the Workflow Specification

`LOGIC.md` is maintained once at the framework repo root. Copy it into your project:

```bash
mkdir -p "$PROJECT/ai-framework"
cp "$FRAMEWORK/LOGIC.md" "$PROJECT/ai-framework/LOGIC.md"
```

This creates:
- `AGENTS.md` -- from `templates/base/AGENTS.md`; project-level AI instructions
- `ARCHITECTURE.md` -- domain dependency policy registry (populated by agents as domains are introduced)
- `.taskrc` -- per-project Taskwarrior config
- `.gitignore` -- ignores `.task/`, `build/`, and `.worktrees/`
- `ai-framework/LOGIC.md` -- workflow specification (copied from framework repo root)
- `ai-framework/project-profile.md` -- to be filled in by you
- `plan/templates/` -- 9 artifact templates used by agents (milestone, epic, story, requirement, phase-plan, plan-review-feedback, review-feedback, escalation, discovery)
- `plan/epics/.gitkeep` -- directory for epic definition files
- `taskwarrior/setup.sh` -- Taskwarrior UDA configuration script
- `taskwarrior/env.sh` -- environment setup (sets `TASKRC`, creates `.task/`)
- `taskwarrior/tw` -- project-local Taskwarrior wrapper (executable)
- `taskwarrior/recipes.md` -- command reference for agents
- `taskwarrior/` scripts -- epic lifecycle, story lifecycle, phase transitions, and lock management (see Step 4)

## Step 2: Copy Cursor Templates

Copy the Cursor-specific files:

```bash
cp -r "$FRAMEWORK/templates/cursor/.cursor" "$PROJECT/"
```

This creates:
- `.cursor/agents/` -- 22 agent prompt files (PM, Coordinator, 16 phase agents, 3 support agents, and fixer)
- `.cursor/rules/ai-framework.mdc` -- always-on framework rules
- `.cursor/commands/` -- `ai-status` and `ai-next` slash commands

## Step 3: Initialize Git

If your project is not already a git repository:

```bash
cd /path/to/your-project
git init
git branch -m main
```

## Step 4: Configure Taskwarrior

The framework uses **per-project Taskwarrior isolation** so each project has its own task database, independent of `~/.taskrc` and `~/.task/`.

Three files make this work:

| File | Purpose |
|------|---------|
| `.taskrc` | Project-local config: `data.location=.task`, `confirmation=off`, `news=off` |
| `taskwarrior/env.sh` | Sets `TASKRC` to point at `.taskrc`, creates `.task/` directory |
| `taskwarrior/tw` | Executable wrapper: sources `env.sh`, then runs `task` with correct config |

Run the setup script with `--main` to register the framework's UDAs in your project `.taskrc` and configure the main worktree:

```bash
cd /path/to/your-project
bash taskwarrior/setup.sh --main
```

> **Note:** The `--worktree` flag exists but you do not need to run it manually. It is called automatically by `epic-fork` when creating a new epic worktree.

Verify the UDAs exist:
```bash
taskwarrior/tw _udas | grep -E 'aiphase|aistate|aistory|aiepic'
```

You should see `aiphase`, `aistate`, `aistory`, and `aiepic` listed.

> **Important:** All agents use `taskwarrior/tw`, never bare `task`. The wrapper ensures every Taskwarrior command reads from the project `.taskrc` and writes to `.task/`, not your global `~/.task/`.

### Taskwarrior Scripts

The `taskwarrior/` directory contains orchestration scripts used by the agents:

| Script | Purpose |
|--------|---------|
| `epic-fork` | Create a git worktree and branch for a new epic |
| `epic-merge` | Merge a completed epic branch back to main |
| `epic-rebase` | Rebase an epic branch onto latest main |
| `epic-status` | Show status of all active epics |
| `epic-mark-ready` | Mark an epic as ready for merge |
| `epic-gate-status` | Check whether an epic's merge gate is open |
| `epic-gate-release` | Open an epic's merge gate |
| `story-init` | Initialize a new story within the current epic |
| `story-next` | Select the next story to execute |
| `story-complete` | Mark the current story as complete |
| `story-merge` | Merge story changes into the epic branch |
| `phase-start` | Begin a phase within a story |
| `phase-stop` | Pause or abandon a phase |
| `phase-transition` | Move to the next phase |
| `phase-annotate` | Add an annotation to the current phase |
| `phase-done` | Mark a phase as complete |
| `phase-block` | Mark a phase as blocked (triggers escalation) |
| `pm-lock-acquire` | Acquire the PM planning lock |
| `pm-lock-release` | Release the PM planning lock |
| `pm-preflight` | PM pre-flight checks before dispatching work |
| `coordinator-lock-acquire` | Acquire the Coordinator execution lock |
| `coordinator-lock-release` | Release the Coordinator execution lock |
| `coordinator-lock-status` | Check whether a Coordinator lock is held |
| `cleanup-ai-state.sh` | Manual cleanup of stale locks and state |

## Step 5: Fill in the Project Profile

Open `ai-framework/project-profile.md` and answer every question. This is the most important customization step -- it tells all agents how your project works.

### Questions to Answer

**Language and Build:**
- What language? (e.g. C++17, Python 3.12)
- What build system? (e.g. CMake, pip, npm)
- What build command? (e.g. `cmake --build build`)

**Directory Layout:**
- Where is source code? (e.g. `src/`)
- Where are architecture artifacts? (e.g. `include/` for C++ headers, `src/interfaces/` for Python ABCs)
- Where are integration tests? (e.g. `tests/integration/`)
- Where are unit tests? (e.g. `tests/unit/`)
- What directories are generated and should never be edited? (e.g. `build/`)

**Test Commands:**
- How to run integration tests? (e.g. `pytest tests/integration/`)
- How to run all tests? (e.g. `make test`)
- How to lint/typecheck? (e.g. `mypy src/`)

**Architecture Conventions:**
- What type of architecture artifact? (e.g. "C++ header files", "Python abstract base classes")
- How are requirement IDs traced in code? (e.g. `// REQ:XXXXX-name`)

**Mock Boundaries:**
- What may be mocked in tests? (e.g. file I/O, network, hardware)
- Everything else must use real objects.

**Review Standards:**
- Any project-specific quality requirements? (e.g. "no raw pointers", "all functions documented")

**Forbidden:**
- What must agents never touch? (e.g. `vendor/`, credentials, generated files)

**Domain Tags:**
- List the valid categories for organizing requirements (e.g. core, rendering, input, audio, network)

**Parallel Limit:**
- Recommended maximum concurrent epics (e.g. 2-3 for typical projects). This limits how many epic worktrees the PM will have active simultaneously. More epics means more context switches and merge conflicts; fewer means less parallelism. Start with 2 and increase once you're comfortable with the workflow.

### Examples

**C++ game project:**
```
- Primary language: C++17
- Build system: CMake
- Build command: cmake --build build
- Source code: src/
- Architecture artifacts: include/
- Integration tests: tests/integration/
- Test command: ctest --test-dir build
- Architecture artifact type: C++ header files
- Traceability: // REQ:XXXXX-name in header comments
- Mock boundaries: File I/O, Network sockets, GPU/Vulkan contexts
- Domain tags: core, rendering, input, audio, physics
- Parallel limit: 2
```

**Python web app:**
```
- Primary language: Python 3.12
- Build system: poetry
- Build command: poetry build
- Source code: src/
- Architecture artifacts: src/interfaces/
- Integration tests: tests/integration/
- Test command: pytest tests/integration/
- Architecture artifact type: Python abstract base classes
- Traceability: REQ:XXXXX-name in ABC docstrings
- Mock boundaries: HTTP requests, Database connections, File I/O
- Domain tags: core, api, auth, storage
- Parallel limit: 3
```

## Step 6: Create a README and Build Skeleton

Before invoking the PM agent, create at least a brief `README.md` so the PM has context about your project. Also set up any minimal build skeleton your project needs (e.g. `CMakeLists.txt`, `pyproject.toml`).

The PM reads `README.md` on its first run to understand the project scope.

## Step 7: Customize Agents (Optional)

The agent prompts are designed to be generic, but you may want to tune them for your project:

- **Review strictness:** edit the review agents' Quality Criteria sections to add project-specific checks
- **Anti-patterns:** add domain-specific mistakes to the Anti-Patterns sections (e.g. "never use raw SQL" for a web app)
- **Architecture conventions:** if your project uses something unusual (e.g. protocol buffers as architecture artifacts), update the architecture agents

## Step 8: Validate

Run the automated validation script (copy it from the framework repo):

```bash
cp /path/to/ai-execution-framework/scripts/validate-deployment.sh ./
bash validate-deployment.sh
```

Or verify manually:

- [ ] `AGENTS.md` exists at project root (deployed from `templates/base/AGENTS.md`)
- [ ] `ARCHITECTURE.md` exists at project root
- [ ] `.taskrc` exists at project root
- [ ] `.gitignore` contains `.task/` and `.worktrees/`
- [ ] `ai-framework/LOGIC.md` exists (copied from framework repo root `LOGIC.md` in Step 1b)
- [ ] `ai-framework/project-profile.md` exists and is filled in
- [ ] `plan/templates/` contains 9 template files (milestone, epic, story, requirement, phase-plan, plan-review-feedback, review-feedback, escalation, discovery)
- [ ] `plan/epics/.gitkeep` exists
- [ ] `taskwarrior/setup.sh` exists and is executable
- [ ] `taskwarrior/env.sh` exists and is executable
- [ ] `taskwarrior/tw` exists and is executable
- [ ] `taskwarrior/recipes.md` exists
- [ ] `taskwarrior/` contains 23 orchestration scripts (epic, story, phase, lock management)
- [ ] `.cursor/agents/` contains 22 agent files
- [ ] `.cursor/rules/ai-framework.mdc` exists
- [ ] `.cursor/commands/` contains `ai-status.md` and `ai-next.md`
- [ ] Taskwarrior UDAs are configured: `taskwarrior/tw _udas | grep aiphase`
- [ ] Project profile is filled in completely (including parallel limit)

## Step 9: First Run

The framework uses an **epic-based parallel execution model**. The hierarchy is:

```
Milestone (optional) → Epic (parallel) → Stories (serial within epic)
```

- **Milestones** group related epics and define high-level goals. They are optional for small projects.
- **Epics** are the unit of parallel work. Each epic gets its own git worktree and branch, allowing multiple epics to execute concurrently without interference.
- **Stories** within an epic execute serially, each passing through the full phase pipeline (requirements → architecture → implementation → integration testing).

### Starting the Workflow

1. Open your project in Cursor.
2. Start a new chat and select the **`project-manager`** agent (not a general agent).
3. Describe your project goals. The PM will discuss them with you and create a milestone (or work without one for small projects).
4. The PM defines one or more **epics** -- cohesive units of work that can proceed independently. Each epic gets a definition file in `plan/epics/`.
5. For each epic, the PM generates 2-5 stories that will execute serially within that epic.
6. The PM **dispatches** an epic: `epic-fork` creates a worktree and branch, and a Coordinator begins executing stories in that worktree.
7. Multiple epics can run in parallel (up to your configured parallel limit), each in its own worktree with its own Coordinator.
8. When an epic completes all stories, it is merged back to main via `epic-merge`.

Use `/ai-status` to check progress across all active epics at any time.

> **Critical:** Always use the `project-manager` agent to start work. Never ask a general/default agent to "implement the plan," "run the Coordinator," or write code. A general agent will bypass the framework pipeline and write code directly, skipping requirements, architecture, test-first development, and review -- losing all the traceability and quality gates the framework provides. The always-on rule in `.cursor/rules/ai-framework.mdc` will remind a general agent to redirect you, but using the correct entry point from the start is the most reliable approach.
>
> **For bug fixes:** you can use the `fixer` agent directly instead of the full PM pipeline. The fixer can modify source code and tests to fix bugs, but cannot add features, change interfaces, or create framework artifacts. Start a chat with the `fixer` agent and describe the bug.

### Planning with Todos

If you create plan-level todos (e.g. in a Cursor plan file) to track your project execution, phrase them as **human actions**, not framework-internal steps:

- **Good:** "Start `project-manager` agent chat for epic-01 (authentication)"
- **Bad:** "Run Coordinator for stories 00001-00003"

The "good" phrasing makes explicit that *you* open a chat with the PM agent. The "bad" phrasing is ambiguous -- a general agent may interpret "run Coordinator" as "produce the output that the Coordinator would produce" and bypass the pipeline entirely.

## Updating the Framework

If the upstream framework template is updated, you can selectively merge changes:

- `ai-framework/LOGIC.md` -- replace with the latest root `LOGIC.md` from the framework repo, or compare and merge workflow changes
- `.cursor/agents/` -- compare and merge agent prompt improvements
- `.cursor/rules/ai-framework.mdc` -- compare and merge rule changes
- `plan/templates/` -- compare and merge template changes
- `taskwarrior/` scripts -- compare and merge new or updated orchestration scripts

Preserve during updates:
- `ai-framework/project-profile.md` -- your project-specific settings
- `.taskrc` -- contains UDA definitions added by `setup.sh` and `data.location`
- `taskwarrior/tw` and `taskwarrior/env.sh` -- unless you haven't customized them
- `.task/` -- never overwrite or delete the Taskwarrior database
- `.worktrees/` -- active epic worktrees; do not delete while epics are in progress
- Any agent customizations you've made

After updating templates, re-run `bash taskwarrior/setup.sh --main` to pick up any new UDAs.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Setup hangs on "Would you like a sample .taskrc" | No `.taskrc` at project root | Ensure `.taskrc` was copied from templates (Step 1 dotfiles) |
| Setup hangs on "Are you sure you want to add" | `confirmation=off` missing | Check `.taskrc` has `confirmation=off` |
| UDAs missing in project but `task _udas` works | Verified wrong database (global `~/.taskrc`) | Use `taskwarrior/tw _udas`, not bare `task` |
| Tasks from project A appear in project B | Shared `~/.task` | Per-project `data.location=.task` in `.taskrc` |
| PM has no context on first run | No `README.md` | Create a brief README before invoking PM (Step 6) |
| Coordinator fails on git merge/reset | Command wrapper blocking local git | Allow local git merge, reset, checkout in wrapper config |
| Agent not found | Missing `.cursor/agents/` files | Verify Step 2 copied `.cursor/` directory |
| Coordinator stuck | State machine confusion or stale active state | Run `/ai-next` to inspect state; use manual cleanup only after confirming no agents are active |
| Escalation recovery stops | Needs product/scope/interface decision or active agent state is unsafe | Check `plan/escalations/` for the recovery report and give the PM direction |
| Escalation loop | Recurring failures after recovery | Check `plan/escalations/` for reports describing root cause and recovery |
| `epic-fork` fails | Branch or worktree already exists | Check `git worktree list`; remove stale worktrees with `git worktree remove <path>` |
| Worktree has stale changes | Epic branch diverged from main | Run `epic-rebase` to update, or resolve conflicts manually |
| `epic-merge` conflicts | Parallel epics modified same files | Rebase the epic first (`epic-rebase`), resolve conflicts, then retry merge |
| Multiple Coordinators in same epic | Stale lock from crashed agent | Confirm no agents are running, then run `bash taskwarrior/cleanup-ai-state.sh` |
| Epic worktree missing after reboot | `.worktrees/` was deleted or moved | Re-run `epic-fork` for affected epics (stories/tasks are preserved in Taskwarrior) |
