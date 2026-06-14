# Deployment Guide

How to deploy the AI execution framework into a downstream project.

## Prerequisites

- **Git** installed
- **[Taskwarrior](https://taskwarrior.org/) 2.x+** installed -- verify with `task --version`
- **[Cursor](https://cursor.com/) IDE** (for the agent system; other IDE support is future work)
- System packages for your target language (e.g. C++: cmake, compiler; Python: python3, pip)

## Step 1: Copy Base Templates

Copy the base framework files into your project root:

```bash
cp -r /path/to/ai-execution-framework/templates/base/* /path/to/your-project/
cp /path/to/ai-execution-framework/templates/base/.taskrc /path/to/your-project/
cp /path/to/ai-execution-framework/templates/base/.gitignore /path/to/your-project/
```

> **Note:** `cp -r base/*` does not copy dotfiles. Copy `.taskrc` and `.gitignore` explicitly, or use `cp -r base/. project/` if your shell supports it.

This creates:
- `AGENTS.md` -- project-level AI instructions
- `ARCHITECTURE.md` -- domain dependency policy registry (populated by agents as domains are introduced)
- `.taskrc` -- per-project Taskwarrior config
- `.gitignore` -- ignores `.task/` and `build/`
- `ai-framework/LOGIC.md` -- the workflow specification
- `ai-framework/project-profile.md` -- to be filled in by you
- `plan/templates/` -- 8 artifact templates used by agents
- `taskwarrior/setup.sh` -- Taskwarrior UDA configuration script
- `taskwarrior/env.sh` -- environment setup (sets `TASKRC`, creates `.task/`)
- `taskwarrior/tw` -- project-local Taskwarrior wrapper (executable)
- `taskwarrior/recipes.md` -- command reference for agents

## Step 2: Copy Cursor Templates

Copy the Cursor-specific files:

```bash
cp -r /path/to/ai-execution-framework/templates/cursor/.cursor /path/to/your-project/
```

This creates:
- `.cursor/agents/` -- 21 agent prompt files (20 pipeline agents + fixer)
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

Run the setup script to register the framework's UDAs in your project `.taskrc`:

```bash
cd /path/to/your-project
bash taskwarrior/setup.sh
```

Verify the UDAs exist:
```bash
taskwarrior/tw _udas | grep -E 'aiphase|aistate|aistory'
```

You should see `aiphase`, `aistate`, and `aistory` listed.

> **Important:** All agents use `taskwarrior/tw`, never bare `task`. The wrapper ensures every Taskwarrior command reads from the project `.taskrc` and writes to `.task/`, not your global `~/.task/`.

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

- [ ] `AGENTS.md` exists at project root
- [ ] `ARCHITECTURE.md` exists at project root
- [ ] `.taskrc` exists at project root
- [ ] `.gitignore` contains `.task/`
- [ ] `ai-framework/LOGIC.md` exists
- [ ] `ai-framework/project-profile.md` exists and is filled in
- [ ] `plan/templates/` contains 8 template files (milestone, story, requirement, phase-plan, plan-review-feedback, review-feedback, escalation, discovery)
- [ ] `taskwarrior/setup.sh` exists and is executable
- [ ] `taskwarrior/env.sh` exists and is executable
- [ ] `taskwarrior/tw` exists and is executable
- [ ] `taskwarrior/recipes.md` exists
- [ ] `.cursor/agents/` contains 21 agent files
- [ ] `.cursor/rules/ai-framework.mdc` exists
- [ ] `.cursor/commands/` contains `ai-status.md` and `ai-next.md`
- [ ] Taskwarrior UDAs are configured: `taskwarrior/tw _udas | grep aiphase`
- [ ] Project profile is filled in completely

## Step 9: First Run

1. Open your project in Cursor.
2. Start a new chat and select the **`project-manager`** agent (not a general agent).
3. Describe your project goals. The PM will discuss them with you and create the first milestone.
4. The PM will generate the first 2-3 stories, review them, and start executing via the Coordinator.
5. Watch the pipeline work. Use `/ai-status` to check progress at any time.

> **Critical:** Always use the `project-manager` agent to start work. Never ask a general/default agent to "implement the plan," "run the Coordinator," or write code. A general agent will bypass the framework pipeline and write code directly, skipping requirements, architecture, test-first development, and review -- losing all the traceability and quality gates the framework provides. The always-on rule in `.cursor/rules/ai-framework.mdc` will remind a general agent to redirect you, but using the correct entry point from the start is the most reliable approach.
>
> **For bug fixes:** you can use the `fixer` agent directly instead of the full PM pipeline. The fixer can modify source code and tests to fix bugs, but cannot add features, change interfaces, or create framework artifacts. Start a chat with the `fixer` agent and describe the bug.

### Planning with Todos

If you create plan-level todos (e.g. in a Cursor plan file) to track your project execution, phrase them as **human actions**, not framework-internal steps:

- **Good:** "Start `project-manager` agent chat for milestone 01 stories 00001-00003"
- **Bad:** "Run Coordinator for stories 00001-00003"

The "good" phrasing makes explicit that *you* open a chat with the PM agent. The "bad" phrasing is ambiguous -- a general agent may interpret "run Coordinator" as "produce the output that the Coordinator would produce" and bypass the pipeline entirely.

## Updating the Framework

If the upstream framework template is updated, you can selectively merge changes:

- `ai-framework/LOGIC.md` -- compare and merge workflow changes
- `.cursor/agents/` -- compare and merge agent prompt improvements
- `.cursor/rules/ai-framework.mdc` -- compare and merge rule changes
- `plan/templates/` -- compare and merge template changes

Preserve during updates:
- `ai-framework/project-profile.md` -- your project-specific settings
- `.taskrc` -- contains UDA definitions added by `setup.sh` and `data.location`
- `taskwarrior/tw` and `taskwarrior/env.sh` -- unless you haven't customized them
- `.task/` -- never overwrite or delete the Taskwarrior database
- Any agent customizations you've made

After updating templates, re-run `bash taskwarrior/setup.sh` to pick up any new UDAs.

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
| Coordinator stuck | State machine confusion | Run `/ai-next` to see the current state and manually advance if needed |
| Escalation loop | Recurring failures | Check `plan/escalations/` for reports describing root cause and recovery |
