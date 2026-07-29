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
cp "$FRAMEWORK/templates/base/.gitignore" "$PROJECT/"
```

> **Note:** `cp -r base/*` does not copy dotfiles. Copy `.gitignore` explicitly, or use `cp -r base/. project/` if your shell supports it.
>
> There is no `.taskrc` to copy. It is generated per tree by `taskwarrior/setup.sh` from `taskwarrior/taskrc.template` and is gitignored, because its UDAs differ between the main tree and epic worktrees.

### Step 1b: Copy the Workflow Specification

`LOGIC.md` is maintained once at the framework repo root. Copy it into your project:

```bash
mkdir -p "$PROJECT/ai-framework"
cp "$FRAMEWORK/LOGIC.md" "$PROJECT/ai-framework/LOGIC.md"
```

This creates:
- `AGENTS.md` -- from `templates/base/AGENTS.md`; project-level AI instructions
- `ARCHITECTURE.md` -- domain dependency policy registry (populated by agents as domains are introduced)
- `.gitignore` -- ignores `.task/`, `.taskrc`, `build/`, and `.worktrees/`
- `ai-framework/LOGIC.md` -- workflow specification (copied from framework repo root)
- `ai-framework/project-profile.md` -- to be filled in by you
- `plan/templates/` -- 10 artifact templates used by agents (project, milestone, epic, story, requirement, phase-plan, plan-review-feedback, review-feedback, escalation, discovery)
- `plan/epics/.gitkeep` -- directory for epic definition files
- `taskwarrior/setup.sh` -- generates `.taskrc` and configures the UDAs for the tree
- `taskwarrior/taskrc.template` -- base config used to generate `.taskrc`
- `taskwarrior/env.sh` -- environment setup (exports `TASKRC` and an absolute `TASKDATA`, creates `.task/`)
- `taskwarrior/guard.sh` -- sourced by every script: resolves the tree from the script's own path and enforces the execution context
- `taskwarrior/tw` -- project-local Taskwarrior wrapper (executable)
- `taskwarrior/recipes.md` -- command reference for agents
- `taskwarrior/` scripts -- epic lifecycle, story lifecycle, phase transitions, lock management, diagnostics, and telemetry (see Step 4)

## Step 2: Copy Cursor Templates

Copy the Cursor-specific files:

```bash
cp -r "$FRAMEWORK/templates/cursor/.cursor" "$PROJECT/"
```

This creates:
- `.cursor/agents/` -- 26 agent prompt files (PM, Coordinator, 16 phase agents, Roadmap Planner, Deploy Profile, Story Review, Escalation Analysis, Escalation Triage, Escalation Recovery, Environment Recovery, and Fixer)
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

Four files make this work:

| File | Purpose |
|------|---------|
| `taskwarrior/taskrc.template` | Base config (`confirmation=off`, `news=off`, verbosity) used to generate `.taskrc` |
| `.taskrc` | Generated per tree with an **absolute** `data.location`; gitignored, mode-specific UDAs |
| `taskwarrior/env.sh` | Exports `TASKRC` and an absolute `TASKDATA`, creates `.task/` |
| `taskwarrior/guard.sh` | Sourced by every script: resolves the tree from the script's own path, then enforces main-vs-worktree context |
| `taskwarrior/tw` | Executable wrapper: sources `guard.sh`, then runs `task` with the correct config |

`TASKDATA` is an absolute path derived from the script's own location, so the database is never selected by the caller's working directory. This is what keeps a Coordinator standing in the main tree from mutating the main database.

Run the setup script with `--main` to generate the project `.taskrc`, register the framework's UDAs, and configure the main tree:

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
| `coordinator-heartbeat` | Record Coordinator liveness/progress (called by the scripts above, never by agents) |
| `coordinator-status` | Aggregate liveness and progress across all epic worktrees (PM supervision) |
| `doctor` | Check framework invariants D01-D12; `--fix` applies only the safe repairs |
| `cleanup-ai-state.sh` | Manual cleanup of stale locks and state |

All scripts are invoked by **absolute path** (`bash <tree-root>/taskwarrior/<script>`) and exit 2 if run against the wrong kind of tree.

## Step 5: Fill in the Project Profile

Open `ai-framework/project-profile.md` and answer every question. This is the most important customization step -- it tells all agents how your project works.

You can fill this in by hand, or open a chat with the `deploy-profile` agent, which interviews you with the questions below and writes the profile for you (it edits only `project-profile.md`).

### Questions to Answer

**Language and Build:**
- What language? (e.g. C++17, Python 3.12, Rust 2021)
- What build system? (e.g. CMake, pip, npm, cargo)
- What build command? (e.g. `cmake --build build`, `cargo build`)

**Directory Layout:**
- Where is source code? (e.g. `src/`)
- Where are architecture artifacts? (e.g. `include/` for C++ headers, `src/interfaces/` for Python ABCs, a `-api` crate or trait modules for Rust)
- Where are integration tests? (e.g. `tests/integration/`)
- Where are unit tests? (e.g. `tests/unit/`)
- What directories are generated and should never be edited? (e.g. `build/`)

**Test Commands:**
- How to run integration tests? (e.g. `pytest tests/integration/`)
- How to run all tests? (e.g. `make test`)
- How to lint/typecheck? (e.g. `mypy src/`)

**Architecture Conventions:**
- What type of architecture artifact? (e.g. "C++ header files", "Python abstract base classes", "Rust trait definitions")
- How are requirement IDs traced in code? (e.g. `// REQ:XXXXX-name`)

**Mock Boundaries:**
- What may be mocked in tests? (e.g. file I/O, network, hardware)
- Everything else must use real objects.

**Verification Tooling:**
- How does the app expose a deterministic, read-only snapshot of internal state for verification? (e.g. `World::snapshot()`, a `state()` dataclass, a store selector)
- What is the UI kind? (web / game / TUI / none)
- If it has a UI: how to launch/drive it to a named state and capture a screenshot, which named states to capture, and where screenshots are written. This lets the implementation agent self-verify behavior and visuals while building.

**Review Standards:**
- Any project-specific quality requirements? (e.g. "no raw pointers", "all functions documented")

**Forbidden:**
- What must agents never touch? (e.g. `vendor/`, credentials, generated files)

**Domain Tags:**
- List the valid categories for organizing requirements (e.g. core, rendering, input, audio, network)

**Parallel Limit:**
- Recommended maximum concurrent epics (e.g. 2-3 for typical projects). This limits how many epic worktrees the PM will have active simultaneously. More epics means more context switches and merge conflicts; fewer means less parallelism. Start with 2 and increase once you're comfortable with the workflow.

**Project Knowledge Source (Paavo Notes MCP):**
- MCP endpoint URL (e.g. `http://127.0.0.1:8770/mcp`)
- Exact Paavo Notes project name (and optional id after first discovery)
- Optional roadmap-relevant entry domains

Paavo Notes is a hard dependency. Fill this section before the first PM run.

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

**Rust service:**
```
- Primary language: Rust 2021
- Build system: cargo
- Build command: cargo build
- Source code: src/
- Architecture artifacts: crates/<name>-api/ (trait definitions)
- Integration tests: tests/
- Test command: cargo test
- Architecture artifact type: Rust trait definitions (signatures only, no bodies)
- Traceability: // REQ:XXXXX-name above trait items
- Mock boundaries: Network I/O, Filesystem, Clock/time
- Review standards: No `unsafe` blocks without escalation; `cargo clippy` clean
- Domain tags: core, api, storage, worker
- Parallel limit: 2
```

Note: adapting the framework to a language requires editing only `ai-framework/project-profile.md` (plus your `README.md` and build skeleton). Do not edit the agent prompts under `.cursor/agents/` per language -- they read the profile at runtime, and keeping them untouched lets you merge upstream framework updates cleanly.

## Step 6: Register Paavo Notes MCP and Create a README

### Paavo Notes MCP (required)

Product intent lives in Paavo Notes. Register the Paavo Notes MCP server in the project's Cursor MCP configuration so agents can discover tools (streamable HTTP, typically `http://127.0.0.1:8770/mcp`). Ensure:

1. The Paavo Notes MCP process is running and reachable.
2. The project profile's Paavo Notes project name matches a real project with at least one **closed** (published) version.
3. Cursor can list MCP tools for that server.

Agents discover tool names and signatures via MCP -- the framework does not hardcode the API. If the MCP is unreachable, the PM hard-stops and requirements agents escalate; do not invent product goals.

The pinned closed version for a run is stored in `plan/project.md` (created by the `roadmap-planner` on first PM run), not only in the profile.

### README and build skeleton

Before invoking the PM agent, create at least a brief `README.md` so the PM has context about your project. Also set up any minimal build skeleton your project needs (e.g. `CMakeLists.txt`, `pyproject.toml`).

The PM reads `README.md` on its first run and invokes `roadmap-planner` to create `plan/project.md` from Paavo Notes.

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
- [ ] `.taskrc` exists at project root (generated by `setup.sh`, not copied)
- [ ] `.gitignore` contains `.task/`, `.taskrc`, and `.worktrees/`
- [ ] `.taskrc` is NOT tracked by git: `git ls-files --error-unmatch .taskrc` must fail
- [ ] `ai-framework/LOGIC.md` exists (copied from framework repo root `LOGIC.md` in Step 1b)
- [ ] `ai-framework/project-profile.md` exists and is filled in
- [ ] `plan/templates/` contains 10 template files (project, milestone, epic, story, requirement, phase-plan, plan-review-feedback, review-feedback, escalation, discovery)
- [ ] `plan/epics/.gitkeep` exists
- [ ] `taskwarrior/setup.sh` exists and is executable
- [ ] `taskwarrior/env.sh` exists and is executable
- [ ] `taskwarrior/guard.sh` exists and is executable
- [ ] `taskwarrior/taskrc.template` exists
- [ ] `taskwarrior/tw` exists and is executable
- [ ] `taskwarrior/recipes.md` exists
- [ ] `taskwarrior/` contains 27 orchestration scripts (epic, story, phase, lock management, diagnostics, telemetry)
- [ ] `bash taskwarrior/doctor` exits 0
- [ ] `.cursor/agents/` contains 26 agent files (including `roadmap-planner.md`, `escalation-triage.md`, and `environment-recovery.md`)
- [ ] `.cursor/rules/ai-framework.mdc` exists
- [ ] `.cursor/commands/` contains `ai-status.md` and `ai-next.md`
- [ ] Taskwarrior UDAs are configured: `taskwarrior/tw _udas | grep aiphase`
- [ ] Project profile is filled in completely (including parallel limit and Paavo Notes MCP section)
- [ ] Paavo Notes MCP is registered in Cursor and reachable

## Step 9: Commit the Framework to main

**Required before the first `epic-fork`.** Epic worktrees are created from `main`, so anything uncommitted does not exist inside the worktree: the Coordinator would find no scripts, no templates, and no profile. `epic-fork` refuses to run until this is done.

```bash
cd /path/to/your-project
git add AGENTS.md ARCHITECTURE.md .gitignore README.md ai-framework/ plan/ taskwarrior/ .cursor/
git commit -m "chore: deploy AI execution framework"
```

Do not add `.taskrc` or `.task/`; both are gitignored on purpose. Verify:

```bash
git status --porcelain -- taskwarrior/ ai-framework/ plan/   # must be empty
git ls-tree --name-only main -- taskwarrior ai-framework plan/templates AGENTS.md
```

Commit planning artifacts to `main` the same way before each later dispatch. The PM does this as part of its normal loop.

## Step 10: First Run

The framework uses a **project → milestone → epic** model with parallel epic execution. The hierarchy is:

```
Project (mandatory: plan/project.md) → Milestone → Epic (parallel) → Stories (serial within epic)
```

- **Project** (`plan/project.md`) is mandatory. It pins a Paavo Notes closed version and lists an ordered milestone roadmap to product completion. Created via the `roadmap-planner` agent on first PM run.
- **Milestones** are derived from the roadmap. They group related epics and define high-level goals. Status: Done / In Progress / TODO.
- **Epics** are the unit of parallel work. Each epic gets its own git worktree and branch, allowing multiple epics to execute concurrently without interference.
- **Stories** within an epic execute serially, each passing through the full phase pipeline (requirements → architecture → integration tests → implementation).

### Starting the Workflow

1. Open your project in Cursor with the Paavo Notes MCP registered and running.
2. Start a new chat and select the **`project-manager`** agent (not a general agent).
3. Confirm the Paavo Notes project name in the profile. The PM verifies MCP reachability (hard-stop if down).
4. If `plan/project.md` is missing, the PM invokes **`roadmap-planner`** to synthesize a milestone roadmap from Paavo Notes (human-in-loop). Refine and accept the roadmap.
5. The PM creates the current In Progress milestone from the roadmap, then defines one or more **epics** in `plan/epics/`.
6. For each epic, the PM generates stories in rolling batches of 2-3 that execute serially within that epic.
7. The PM **dispatches** an epic: `epic-fork` creates a worktree and branch, and a Coordinator begins executing stories in that worktree.
8. Multiple epics can run in parallel (up to your configured parallel limit), each in its own worktree with its own Coordinator.
9. When an epic completes all stories, it is merged back to main via `epic-merge`. After a milestone completes, the PM updates roadmap statuses and may rewrite TODO milestones or migrate to a newer Paavo Notes version.

Use `/ai-status` to check project/roadmap progress and all active epics at any time.

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
- `.taskrc` -- generated, contains UDA definitions added by `setup.sh` and an absolute `data.location`. Delete it only if you want `setup.sh` to regenerate it.
- `taskwarrior/tw` and `taskwarrior/env.sh` -- unless you haven't customized them
- `.task/` -- never overwrite or delete the Taskwarrior database
- `.worktrees/` -- active epic worktrees; do not delete while epics are in progress
- Any agent customizations you've made

After updating templates, re-run `bash taskwarrior/setup.sh --main` to pick up any new UDAs.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Setup hangs on "Would you like a sample .taskrc" | `taskwarrior/taskrc.template` missing, so `.taskrc` could not be generated | Re-copy `templates/base/taskwarrior/`, then re-run `setup.sh --main` |
| Setup hangs on "Are you sure you want to add" | `confirmation=off` missing | Delete `.taskrc` and re-run `setup.sh` to regenerate it from the template |
| UDAs missing in project but `task _udas` works | Verified wrong database (global `~/.taskrc`) | Use `taskwarrior/tw _udas`, not bare `task` |
| Tasks from project A appear in project B | Shared `~/.task` | Generated `.taskrc` has an absolute `data.location`; `env.sh` also exports `TASKDATA`. Re-run `setup.sh` |
| Script exits 2 with "must run in the main/worktree tree" | Script invoked against the wrong tree | Use the absolute path of the intended tree: `bash <tree-root>/taskwarrior/<script>` |
| `epic-fork` refuses: "Framework files are not committed to main" | Deployment not committed | Complete Step 9 |
| Phase tasks appear in the main database | Historical failure mode; now blocked by the context guard | `bash taskwarrior/doctor` then `--fix` via the `environment-recovery` agent |
| PM cannot tell whether a Coordinator is alive | Looking in the wrong place | `bash taskwarrior/coordinator-status`; never read agent transcripts |
| `coordinator-status` shows `NO-HEARTBEAT` | Coordinator subagent never started or died at startup | Run `bash taskwarrior/doctor`, then launch a fresh Coordinator with the absolute worktree path in its prompt |
| `coordinator-status` shows `STALE`/`DEAD` | Coordinator stopped mid-story, or a phase legitimately runs longer than the threshold | Re-check once; raise `AI_HEARTBEAT_STALE_SECONDS` if your phases are genuinely slower |
| PM has no context on first run | No `README.md` / no project roadmap | Create a brief README; ensure Paavo Notes MCP is up and profile names the project (Step 6) |
| PM hard-stops immediately | Paavo Notes MCP unreachable | Start the MCP server; fix Cursor MCP registration; verify a closed version exists |
| Roadmap invents goals | MCP not used / wrong project | Check profile project name; re-run `roadmap-planner` against Paavo Notes |
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
