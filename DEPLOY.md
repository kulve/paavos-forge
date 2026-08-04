# Deployment Guide

How to deploy Paavo's Forge into a downstream project.

**This guide is meant to be applied by a coding AI**, not followed manually by a human. Deployment has many steps (archive install, Taskwarrior setup, project-profile interview, model-bucket assignment, MCP check, first PM run). A human opens the empty target project in Cursor and points the AI at this document:

`https://raw.githubusercontent.com/kulve/paavos-forge/main/DEPLOY.md`

**Deploy into an empty project before starting real product work.** The framework should own requirements → architecture → tests → implementation from the start so artifacts and Taskwarrior state stay consistent. Do not bolt Forge onto a codebase that already has substantial features or a conflicting `.cursor/` / `taskwarrior/` layout. A fresh repo with `README.md` and `git init` is fine; deploy Forge, then begin work through the PM.

## Prerequisites

- **Git** installed
- **[Taskwarrior](https://taskwarrior.org/) 2.x+** installed -- verify with `task --version`
- **[Cursor](https://cursor.com/) IDE** (for the agent system; other IDE support is future work)
- **curl** and **tar** (to fetch the framework archive)
- System packages for your target language (e.g. C++: cmake, compiler; Python: python3, pip)

## Deployment Inputs

The framework ships from three locations in the Forge repository:

| Source | Deployed to | Purpose |
|--------|-------------|---------|
| `templates/base/` | Project root | Scaffolding: `AGENTS.md`, Taskwarrior, plan templates, project profile |
| `LOGIC.md` (repo root) | `paavos-forge/LOGIC.md` | Canonical workflow specification (copied as-is) |
| `templates/cursor/.cursor/` | `.cursor/` | Cursor agents, rules, and commands |

`templates/base/AGENTS.md` becomes your project's root `AGENTS.md`. Customize it after deployment if you need project-specific AI guidance (extra rules, domain context, or stricter review standards). The workflow specification itself lives in `paavos-forge/LOGIC.md` and should not be edited unless you are intentionally forking the framework.

There is no `.taskrc` to copy. It is generated per tree by `taskwarrior/setup.sh` from `taskwarrior/taskrc.template` and is gitignored, because its UDAs differ between the main tree and epic worktrees.

## Step 1: Obtain the Framework Archive

Work from the **target project root**. Download the full Forge archive to a file, inspect it, then extract it. Do **not** pipe a remote script into bash.

This guide tracks bleeding-edge **`main`**. Pinning to version tags is future work.

```bash
PROJECT="$(pwd)"
STAGE=$(mktemp -d)
ARCHIVE=$(mktemp /tmp/paavos-forge.XXXXXX.tar.gz)

curl -fsSL -o "$ARCHIVE" \
  "https://codeload.github.com/kulve/paavos-forge/tar.gz/refs/heads/main"

# Inspect the archive listing before extracting
tar -tzf "$ARCHIVE" | head -n 40

tar -xzf "$ARCHIVE" -C "$STAGE" --strip-components=1
rm -f "$ARCHIVE"

# Confirm the extracted tree looks like Forge
test -f "$STAGE/LOGIC.md"
test -f "$STAGE/scripts/install-into-project.sh"
```

**Keep `$STAGE` until after Step 6 (model catalog) and Step 9 (validate).** Remove it only when those steps are done.

### Alternate: local Forge checkout

If you already have a clone of this repository on disk, skip the download and set:

```bash
STAGE=/path/to/paavos-forge   # existing checkout
PROJECT="$(pwd)"              # target project root
```

## Step 2: Install Templates into the Project

Inspect the install script, then run it. It copies `templates/base/`, `LOGIC.md` → `paavos-forge/LOGIC.md`, and `templates/cursor/.cursor/`. It does **not** run Taskwarrior setup or assign models.

```bash
# Inspect before running (Read tool in Cursor, or a pager)
# $STAGE/scripts/install-into-project.sh

bash "$STAGE/scripts/install-into-project.sh" \
  --framework "$STAGE" \
  --project "$PROJECT"
```

By default the script **refuses to overwrite** any destination path that already exists as a file or symlink (for example a same-named `.cursor/agents/*.md`), and always refuses if a parent that must be a directory is already a file or symlink. If it lists conflicts, stop and report them to the user. `--force` overwrites conflicting **leaf** files only; it cannot replace a blocking parent. Do **not** pass `--force` unless the user explicitly wants a leaf-level template overwrite/reset.

After a successful install, the project contains:

- `AGENTS.md` -- from `templates/base/AGENTS.md`; project-level AI instructions
- `ARCHITECTURE.md` -- domain dependency policy registry (populated by agents as domains are introduced)
- `.gitignore` -- ignores `.task/`, `.taskrc`, `build/`, and `.worktrees/`
- `paavos-forge/LOGIC.md` -- workflow specification (copied from framework repo root)
- `paavos-forge/project-profile.md` -- to be filled in (Step 5)
- `paavos-forge/set-agent-models.sh` -- assigns a model to every agent prompt by bucket (Step 6)
- `plan/templates/` -- 9 artifact templates used by agents (project, milestone, epic, story, requirement, phase-plan, review-feedback, escalation, discovery)
- `plan/epics/.gitkeep` -- directory for epic definition files
- `taskwarrior/` -- setup, wrappers, recipes, and orchestration scripts (Step 4)
- `.cursor/agents/` -- 19 agent prompt files (Coordinator, 10 phase agents, Roadmap Planner, Deploy Profile, Story Review, Escalation Analysis, Escalation Triage, Escalation Recovery, Environment Recovery, and Fixer)
- `.cursor/skills/` -- the `project-manager` and `ai-status` skills, invoked as `/project-manager` and `/ai-status`
- `.cursor/rules/paavos-forge.mdc` -- always-on framework rules

## Step 3: Initialize Git

If the project is not already a git repository:

```bash
cd "$PROJECT"
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
cd "$PROJECT"
bash taskwarrior/setup.sh --main
```

> **Note:** The `--worktree` flag exists but you do not need to run it manually. It is called automatically by `epic-fork` when creating a new epic worktree.

Verify the main-tree UDAs exist:
```bash
taskwarrior/tw _udas | grep -E 'aiepic|epicstate|airole'
taskwarrior/tw aiepics
```

You should see `aiepic`, `epicstate`, and `airole` listed. The phase UDAs (`aiphase`, `aistate`, `aistory`) are worktree-scoped and are **not** registered here -- `epic-fork` creates them by running `setup.sh --worktree` in each new epic worktree. Grepping the main tree for `aiphase` returns nothing, and that is correct.

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

Open `paavos-forge/project-profile.md` and answer every question. This is the most important customization step -- it tells all agents how your project works.

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

**Project Knowledge Source (Paavo's Codex MCP):**
- MCP endpoint URL (e.g. `http://127.0.0.1:8770/mcp`)
- Exact Paavo's Codex project name (and optional id after first discovery)
- Optional roadmap-relevant entry domains

Paavo's Codex is a hard dependency. Fill this section before the first PM run.

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

Note: adapting the framework to a language requires editing only `paavos-forge/project-profile.md` (plus your `README.md` and build skeleton). Do not edit the agent prompts under `.cursor/agents/` per language -- they read the profile at runtime, and keeping them untouched lets you merge upstream framework updates cleanly.

## Step 6: Choose Models for Agent Buckets

The framework ships every agent prompt with `model: inherit`, which means each agent runs on whatever model happens to be selected in the chat that started the PM. That makes pipeline quality a side effect of an unrelated UI choice, and it drifts whenever you switch models. Pin the models deliberately before your first run.

Model choice trades off two independent axes. **World knowledge** decides which library, algorithm, or architecture is the right one -- it matters enormously where designs are generated and barely at all where a written plan is being executed. **Reasoning effort** buys long-horizon consistency and self-checking, which matters wherever an agent runs a long tool loop, even when the thinking has already been done upstream. Configuring 19 agents individually is unmanageable, so the framework groups them into six buckets. The PM is not among them: it is a skill, so it runs on whatever model you select for the top-level chat (see "Project Manager model" below).

### The buckets

| Bucket | For | Why it is separate |
|--------|-----|--------------------|
| `frontier` | Architecture planning only | The scarce high-leverage slot: interfaces, dependency direction, extensibility. One dispatch per full story. |
| `deep` | Roadmap, escalation recovery, environment repair, deploy-profile | Generative design and diagnosis that still needs real technical judgment, without spending the frontier budget. |
| `critic` | Adversarial review: architecture, implementation, stories, requirements | Must judge semantic correctness of work it did not write. This is where weak models rubber-stamp. |
| `builder` | Requirements write, architecture write, implementation plan/write, tests | Your largest token consumer, and the place where the hard decisions are already made upstream. |
| `checker` | Integration-test review, escalation triage | Bounded checks against written artifacts, gate output, and fixed routing rules. |
| `orchestration` | Coordinator state machine | Procedure following with no artifact or code interpretation. Failures are loud, not silent (see below). |

To see which agent is in which bucket and what each currently resolves to:

```bash
bash paavos-forge/set-agent-models.sh --list
```

The agent-to-bucket assignment is framework knowledge and lives in the script. The bucket-to-model choice is yours.

### Constraints you must respect

- **Keep Opus (or an equivalent frontier model) in `frontier` only.** Putting it on `deep` as well quietly burns the budget that this split exists to protect. Sonnet is the intended default for every other Anthropic role.
- **Prefer a different model family for a reviewer than for the bucket it reviews.** Every write agent is reviewed by a `checker` or `critic` agent, and `architecture-plan` (`frontier`) / `architecture-write` (`builder`) are reviewed by `architecture-review` (`critic`). `requirements-review` sits in `critic` for the same reason: it must not share the writer's family with `requirements-write`. A reviewer from the same family as the writer shares its blind spots.

  This is a recommendation, not a hard rule, and it is worth most among the expensive buckets. Inside Cursor's included first-party pool the practical bulk writer is Grok; do not introduce Composer just to buy family separation for `checker`. A same-family Grok checker that actually rejects catches more than a weaker separated option that rubber-stamps.
- **`builder` must be vision-capable whenever the project profile's UI kind is not `none`.** `implementation-write` captures screenshots and must actually look at them to verify Visual Acceptance Criteria; its prompt explicitly forbids substituting histogram or pixel-count scripts. A non-vision model there degrades visual verification into "the agent claims it looked," silently.
- **Set `context` explicitly, to the smaller tier.** A 200-300k window covers every agent in this pipeline, but `claude-opus-5`, `claude-sonnet-5`, and the GPT family default to the `1m` tier, which bills at a premium. Omitting the parameter opts you into the expensive option rather than out of it.
- **Do not downgrade `critic` to save money.** The framework's safety property -- severity-graded reviews, the rejection limit, the escalation protocol -- only works if reviewers actually reject. If `critic` is too expensive, move down one tier within the same family (Sol -> Terra) rather than into the `builder` model.
- **`orchestration` can be genuinely cheap.** The Coordinator is the highest-frequency agent, but `guard.sh` enforces tree isolation by construction and the scripts exit non-zero on invalid transitions, so a confused Coordinator fails loudly instead of corrupting state. Luna is enough here.
- **Do not use Composer.** Grok covers the included-pool bulk work, and Luna covers the Coordinator. Composer adds no capability the framework needs and has a history of resolving to its expensive fast variant.
- **Check your plan.** On legacy request-based plans without Max Mode, subagents run on Cursor's own model regardless of what you configure here, and several frontier models are unavailable. On usage-based plans this step takes effect for every agent, including subagents launched by other subagents; nesting depth does not weaken the assignment.

### Project Manager model

The PM has no bucket. Pick the top-level chat model when you start `/project-manager`:

- **Sonnet** when the session will create or revise roadmaps, milestones, epics, stories, or discovery triage. That work is product planning, not bookkeeping: the PM decomposes Paavo's Codex into vertical slices, assigns rigor, cites article ids, and decides which discoveries become stories.
- **Luna** only for a supervision-only session: watching `coordinator-status`, launching Coordinators for already-planned epics, and running fork/merge scripts. If that chat later needs a new story batch, switch back to Sonnet (or start a fresh chat) rather than asking Luna to invent product structure.

### Picking current models

Model lineups, IDs, and parameters change faster than this document. Worse, the two places you would naturally look both show marketing names rather than selectable IDs: Cursor's model picker calls it "Cursor Grok 4.5" and your billing export calls it `cursor-grok-4.5-high-fast`, but the ID you must write is `grok-4.5`. Guessing from either one produces a model string that fails silently.

Ask your account what it actually exposes. From the retained Forge stage (or a local checkout):

```bash
cd "$STAGE/scripts/models" && npm install
CURSOR_API_KEY=<your key> node list-models.mjs
```

This prints every model ID available to your account, the parameters each one accepts with their allowed values, and which variant is the default. That output is the source of truth for this step. It needs Node 22.13 or later and an API key from <https://cursor.com/dashboard/api>.

For prices, see <https://cursor.com/docs/models-and-pricing>. Note the two usage pools: Cursor's own models (Grok 4.5 and Composer) come from a separate first-party pool with generous included usage and are exempt from the Cursor Token Rate. This framework's recommended bulk writer is Grok from that pool; Composer is not used.

#### Writing a model string

A model string is an ID followed by bracket parameters:

```
model: claude-opus-5[thinking=true,context=300k,effort=high,fast=false]
model: claude-sonnet-5[thinking=true,context=300k,effort=high,fast=false]
model: gpt-5.6-terra[context=272k,reasoning=high,fast=false]
model: grok-4.5[effort=high,fast=false]
model: gpt-5.6-luna[context=272k,reasoning=medium,fast=false]
```

**State every parameter.** Each model's default variant is the expensive one. `grok-4.5` defaults to `fast=true`; `claude-opus-5`, `claude-sonnet-5`, and the GPT family default to the `1m` context tier. A bare `grok-4.5` resolves to the fast variant.

**Parameter names differ by family.** Claude, Grok, and Gemini take `effort`; the GPT family takes `reasoning`; Claude also takes `thinking`. Both take `context` and `fast`.

Both kinds of mistake are silent at run time:

| Mistake | What happens |
|---------|--------------|
| Unrecognised model ID | The agent runs on the parent chat's model, while its frontmatter still reads correctly. This is what makes a whole pipeline quietly run on one model. |
| Unrecognised parameter | The parameter is dropped and the model's default applies. `gpt-5.6-terra[effort=high]` runs at `reasoning=medium`. |

Neither reports an error. `set-agent-models.sh` rejects both patterns before it writes anything, but it cannot know about models released after it was written; the catalog listing above can.

Billing exports append display suffixes such as `-fast` or `-medium` that are not a faithful audit of the parameters you wrote. Always state `fast=false` anyway. If the dashboard still shows only fast variants for Grok after an explicit `fast=false`, treat that as a Cursor routing/billing labeling issue rather than proof that the frontmatter was wrong -- and verify with a controlled one-agent test before assuming non-fast is active.

The `deploy-profile` agent can do this step with you: it asks you to run the listing above, proposes candidates per bucket with prices, and applies your confirmed choices.

### Example configuration

A working starting point that keeps Opus scarce, puts bulk work on Grok, and avoids Composer. Verified against the model catalog shape in August 2026; **re-check the IDs with the catalog listing above before using it**:

```bash
bash paavos-forge/set-agent-models.sh \
  --frontier       "claude-opus-5[thinking=true,context=300k,effort=high,fast=false]" \
  --deep           "claude-sonnet-5[thinking=true,context=300k,effort=high,fast=false]" \
  --critic         "gpt-5.6-terra[context=272k,reasoning=high,fast=false]" \
  --builder        "grok-4.5[effort=high,fast=false]" \
  --checker        "grok-4.5[effort=high,fast=false]" \
  --orchestration  "gpt-5.6-luna[context=272k,reasoning=medium,fast=false]"
```

What this buys:

- `frontier` (Opus) is only `architecture-plan` -- about one expensive design dispatch per full story.
- `deep` (Sonnet) covers roadmap, recovery, environment repair, and deploy-profile without spending Opus.
- `critic` (Terra) reviews architecture, implementation, stories, and requirements. Requirements review left the Grok `checker` bucket so it does not share a family with `requirements-write`.
- `builder` and `checker` (Grok) absorb the bulk token volume from Cursor's included first-party pool. High effort is fine there because that pool's usage is included.
- `orchestration` (Luna) runs the Coordinator. It never reads code or artifacts; isolation scripts make mistakes fail loudly.

Add `--dry-run` to preview changes. Re-run the command at any time to re-tune.

## Step 7: Register Paavo's Codex MCP and Create a README

### Paavo's Codex MCP (required)

Product intent lives in Paavo's Codex. Register the Paavo's Codex MCP server in the project's Cursor MCP configuration so agents can discover tools (streamable HTTP, typically `http://127.0.0.1:8770/mcp`). Ensure:

1. The Paavo's Codex MCP process is running and reachable.
2. The project profile's Paavo's Codex project name matches a real project with at least one **closed** (published) version.
3. Cursor can list MCP tools for that server.

Agents discover tool names and signatures via MCP -- the framework does not hardcode the API. If the MCP is unreachable, the PM hard-stops and requirements agents escalate; do not invent product goals.

The pinned closed version for a run is stored in `plan/project.md` (created by the `roadmap-planner` on first PM run), not only in the profile.

### README and build skeleton

Before invoking the PM agent, create at least a brief `README.md` so the PM has context about your project. Also set up any minimal build skeleton your project needs (e.g. `CMakeLists.txt`, `pyproject.toml`).

The PM reads `README.md` on its first run and invokes `roadmap-planner` to create `plan/project.md` from Paavo's Codex.

## Step 8: Customize Agents (Optional)

The agent prompts are designed to be generic, but you may want to tune them for your project:

- **Review strictness:** edit the review agents' Quality Criteria sections to add project-specific checks
- **Anti-patterns:** add domain-specific mistakes to the Anti-Patterns sections (e.g. "never use raw SQL" for a web app)
- **Architecture conventions:** if your project uses something unusual (e.g. protocol buffers as architecture artifacts), update the architecture agents

## Step 9: Validate

Run the automated validation script (copy it from the retained Forge stage):

```bash
cd "$PROJECT"
cp "$STAGE/scripts/validate-deployment.sh" ./
bash validate-deployment.sh
```

Or verify manually:

- [ ] `AGENTS.md` exists at project root (deployed from `templates/base/AGENTS.md`)
- [ ] `ARCHITECTURE.md` exists at project root
- [ ] `.taskrc` exists at project root (generated by `setup.sh`, not copied)
- [ ] `.gitignore` contains `.task/`, `.taskrc`, and `.worktrees/`
- [ ] `.taskrc` is NOT tracked by git: `git ls-files --error-unmatch .taskrc` must fail
- [ ] `paavos-forge/LOGIC.md` exists (copied from framework repo root `LOGIC.md` by the install script)
- [ ] `paavos-forge/project-profile.md` exists and is filled in
- [ ] `plan/templates/` contains 9 template files (project, milestone, epic, story, requirement, phase-plan, review-feedback, escalation, discovery)
- [ ] `plan/epics/.gitkeep` exists
- [ ] `taskwarrior/setup.sh` exists and is executable
- [ ] `taskwarrior/env.sh` exists and is executable
- [ ] `taskwarrior/guard.sh` exists and is executable
- [ ] `taskwarrior/taskrc.template` exists
- [ ] `taskwarrior/tw` exists and is executable
- [ ] `taskwarrior/recipes.md` exists
- [ ] `taskwarrior/` contains 27 orchestration scripts (epic, story, phase, lock management, diagnostics, telemetry)
- [ ] `bash taskwarrior/doctor` exits 0
- [ ] `.cursor/agents/` contains 19 agent files (including `roadmap-planner.md`, `escalation-triage.md`, and `environment-recovery.md`) and **no** `project-manager.md`
- [ ] `paavos-forge/set-agent-models.sh` exists and is executable
- [ ] Every agent has a model assigned and none still says `inherit`: `bash paavos-forge/set-agent-models.sh --list`
- [ ] `.cursor/rules/paavos-forge.mdc` exists
- [ ] `.cursor/skills/` contains `project-manager/SKILL.md` and `ai-status/SKILL.md`
- [ ] Main-tree Taskwarrior UDAs are configured: `taskwarrior/tw _udas | grep aiepic` (the phase UDAs are worktree-scoped and appear only after `epic-fork`)
- [ ] Project profile is filled in completely (including parallel limit and Paavo's Codex MCP section)
- [ ] Paavo's Codex MCP is registered in Cursor and reachable

## Step 10: Commit the Framework to main

**Required before the first `epic-fork`.** Epic worktrees are created from `main`, so anything uncommitted does not exist inside the worktree: the Coordinator would find no scripts, no templates, and no profile. `epic-fork` refuses to run until this is done.

```bash
cd "$PROJECT"
git add AGENTS.md ARCHITECTURE.md .gitignore README.md paavos-forge/ plan/ taskwarrior/ .cursor/
git commit -m "chore: deploy Paavo's Forge"
```

After Step 9 (and this commit), you may remove the temporary stage:

```bash
rm -rf "$STAGE"
```

This includes the `model:` lines written in Step 6. Epic worktrees are created from `main`, so an unconfigured `.cursor/` there means Coordinators dispatch subagents on the wrong models.

Do not add `.taskrc` or `.task/`; both are gitignored on purpose. Verify:

```bash
git status --porcelain -- taskwarrior/ paavos-forge/ plan/   # must be empty
git ls-tree --name-only main -- taskwarrior paavos-forge plan/templates AGENTS.md
```

Commit planning artifacts to `main` the same way before each later dispatch. The PM does this as part of its normal loop.

## Step 11: First Run

The framework uses a **project → milestone → epic** model with parallel epic execution. The hierarchy is:

```
Project (mandatory: plan/project.md) → Milestone → Epic (parallel) → Stories (serial within epic)
```

- **Project** (`plan/project.md`) is mandatory. It pins a Paavo's Codex closed version and lists an ordered milestone roadmap to product completion. Created via the `roadmap-planner` agent on first PM run.
- **Milestones** are derived from the roadmap. They group related epics and define high-level goals. Status: Done / In Progress / TODO.
- **Epics** are the unit of parallel work. Each epic gets its own git worktree and branch, allowing multiple epics to execute concurrently without interference.
- **Stories** within an epic execute serially, each passing through the full phase pipeline (requirements → architecture → integration tests → implementation).

### Starting the Workflow

1. Open your project in Cursor with the Paavo's Codex MCP registered and running.
2. Start a new chat and invoke the **`/project-manager`** skill. The skill loads into the chat you are already in, so from that point on you are talking to the PM directly, with no intermediary agent relaying messages. You do not need to invoke it again in the same thread.
3. Confirm the Paavo's Codex project name in the profile. The PM verifies MCP reachability (hard-stop if down).
4. If `plan/project.md` is missing, the PM invokes **`roadmap-planner`** to synthesize a milestone roadmap from Paavo's Codex (human-in-loop). Refine and accept the roadmap.
5. The PM creates the current In Progress milestone from the roadmap, then defines one or more **epics** in `plan/epics/`.
6. For each epic, the PM generates stories in rolling batches of 2-3 that execute serially within that epic.
7. The PM **dispatches** an epic: `epic-fork` creates a worktree and branch, and a Coordinator begins executing stories in that worktree.
8. Multiple epics can run in parallel (up to your configured parallel limit), each in its own worktree with its own Coordinator.
9. When an epic completes all stories, it is merged back to main via `epic-merge`. After a milestone completes, the PM updates roadmap statuses and may rewrite TODO milestones or migrate to a newer Paavo's Codex version.

Use `/ai-status` to check project/roadmap progress and all active epics at any time. Run it in its own chat, without the PM skill loaded: it is a read-only report and deliberately sits outside the pipeline.

> **Critical:** Always start work by invoking `/project-manager` in a fresh chat. Never ask a general/default agent to "implement the plan," "run the Coordinator," or write code, and never delegate to the PM as a subagent. A general agent will bypass the framework pipeline and write code directly, skipping requirements, architecture, test-first development, and review -- losing all the traceability and quality gates the framework provides. Delegating to the PM breaks the pipeline differently: it consumes a nesting level, and the Coordinator the PM launches then has none left for phase agents. The always-on rule in `.cursor/rules/paavos-forge.mdc` will remind a general agent to redirect you, but using the correct entry point from the start is the most reliable approach.
>
> **Use a fresh chat.** The PM skill runs in your normal chat context, so anything discussed earlier in that thread stays visible to it. The PM is forbidden from reading source code, tests, and artifacts below the story level, which is easier to honour when the thread starts clean.
>
> **For bug fixes:** you can use the `fixer` agent directly instead of the full PM pipeline. The fixer can modify source code and tests to fix bugs, but cannot add features, change interfaces, or create framework artifacts. Start a chat with the `fixer` agent and describe the bug.

### Planning with Todos

If you create plan-level todos (e.g. in a Cursor plan file) to track your project execution, phrase them as **human actions**, not framework-internal steps:

- **Good:** "Start a `/project-manager` chat for epic-01 (authentication)"
- **Bad:** "Run Coordinator for stories 00001-00003"

The "good" phrasing makes explicit that *you* open a chat and load the PM skill. The "bad" phrasing is ambiguous -- a general agent may interpret "run Coordinator" as "produce the output that the Coordinator would produce" and bypass the pipeline entirely.

## Cost and Quality Telemetry

Once buckets are assigned, each bucket maps to a distinct model, so **Cursor's per-model usage dashboard already is your per-bucket spend** -- no instrumentation needed. That answers the question worth asking: which bucket is consuming the budget.

Do not try to count tokens per agent. Agents cannot measure their own usage, and Cursor does not hand a subagent its own token count. What you have instead is better suited to the decision anyway:

- **Invocation counts and durations per phase state**, from the `phase-start` / `phase-stop` brackets that already wrap every subagent call. Within a single bucket, duration is a reasonable token proxy.
- **Rejection counts per phase**, tracked by the Coordinator against the three-rejection limit, plus escalation frequency.

Read those signals as follows. If you downgrade a bucket and a phase's rejection rate falls toward zero, that is the reviewer rubber-stamping, not the writer improving -- the two look identical in the spend report and opposite in the artifact quality. If rejections spike or escalations cluster in one phase, that bucket is underpowered for this project. Tuning is a measurement, not a guess.

Attribute a falling rejection rate to the model only if the model is what changed. Review agents must anchor every blocking issue to a named artifact element (LOGIC.md Section 13.1), which by design removes unanchored preferences from the blocking set. A project adopting that rule for the first time should see a one-time drop in rejections with no loss of real findings, and rejections that do land should carry an `Anchor:` field. Take your baseline after that change, not across it.

One caveat on attribution: your PM chat runs on the model selected in the Cursor UI, not on the `deep` bucket's frontmatter. If that happens to be a bucket model, its spend is indistinguishable from that bucket's. Select something outside your bucket set for the PM chat to keep the report clean.

## Updating the Framework

Re-fetch the `main` archive into a new `$STAGE` (same download/inspect/extract steps as Step 1), then selectively merge changes from that tree:

- `paavos-forge/LOGIC.md` -- replace with the latest root `LOGIC.md` from the stage, or compare and merge workflow changes
- `.cursor/agents/` -- compare and merge agent prompt improvements, then re-run `bash paavos-forge/set-agent-models.sh` with your chosen models. Upstream ships every prompt with `model: inherit`, so a merge can reset the line, and a newly added agent arrives unconfigured. The script exits non-zero if an agent prompt has no bucket assignment, which is how you find out.
- `paavos-forge/set-agent-models.sh` -- take the upstream version when the agent set changes; it carries the canonical agent-to-bucket mapping
- `.cursor/rules/paavos-forge.mdc` -- compare and merge rule changes
- `plan/templates/` -- compare and merge template changes
- `taskwarrior/` scripts -- compare and merge new or updated orchestration scripts

Use `bash "$STAGE/scripts/install-into-project.sh" --framework "$STAGE" --project "$PROJECT" --force` only when the user explicitly wants leaf files overwritten. Prefer selective merges for lived-in projects. `--force` still refuses if a parent path is a file or symlink.

Preserve during updates:
- `paavos-forge/project-profile.md` -- your project-specific settings
- `.taskrc` -- generated, contains UDA definitions added by `setup.sh` and an absolute `data.location`. Delete it only if you want `setup.sh` to regenerate it.
- `taskwarrior/tw` and `taskwarrior/env.sh` -- unless you haven't customized them
- `.task/` -- never overwrite or delete the Taskwarrior database
- `.worktrees/` -- active epic worktrees; do not delete while epics are in progress
- Any agent customizations you've made

After updating templates, re-run `bash taskwarrior/setup.sh --main` to pick up any new UDAs.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `curl` / archive download fails | Network error, wrong URL, or GitHub unavailable | Retry; confirm `https://codeload.github.com/kulve/paavos-forge/tar.gz/refs/heads/main` is reachable |
| Install script lists conflicting paths | Destination already has Forge-like files (e.g. same-named `.cursor/agents/*.md`) or a blocking parent (file/symlink where a directory is required) | Use a fresh empty project or remove the listed paths; `--force` only overwrites leaf files, not blocking parents |
| Install onto a lived-in codebase | Forge deployed after substantial product work | Prefer starting a new repo, deploy Forge first, then begin work through the PM |
| Setup hangs on "Would you like a sample .taskrc" | `taskwarrior/taskrc.template` missing, so `.taskrc` could not be generated | Re-run the install script (or restore `taskwarrior/` from `$STAGE`), then re-run `setup.sh --main` |
| Setup hangs on "Are you sure you want to add" | `confirmation=off` missing | Delete `.taskrc` and re-run `setup.sh` to regenerate it from the template |
| UDAs missing in project but `task _udas` works | Verified wrong database (global `~/.taskrc`) | Use `taskwarrior/tw _udas`, not bare `task` |
| Tasks from project A appear in project B | Shared `~/.task` | Generated `.taskrc` has an absolute `data.location`; `env.sh` also exports `TASKDATA`. Re-run `setup.sh` |
| Script exits 2 with "must run in the main/worktree tree" | Script invoked against the wrong tree | Use the absolute path of the intended tree: `bash <tree-root>/taskwarrior/<script>` |
| `epic-fork` refuses: "Framework files are not committed to main" | Deployment not committed | Complete Step 10 |
| Phase tasks appear in the main database | Historical failure mode; now blocked by the context guard | `bash taskwarrior/doctor` then `--fix` via the `environment-recovery` agent |
| PM cannot tell whether a Coordinator is alive | Looking in the wrong place | `bash taskwarrior/coordinator-status`; never read agent transcripts |
| `coordinator-status` shows `NO-HEARTBEAT` | Coordinator subagent never started or died at startup | Run `bash taskwarrior/doctor`, then launch a fresh Coordinator with the absolute worktree path in its prompt |
| `coordinator-status` shows `STALE`/`DEAD` | Coordinator stopped mid-story, or a phase legitimately runs longer than the threshold | Re-check once; raise `AI_HEARTBEAT_STALE_SECONDS` if your phases are genuinely slower |
| PM has no context on first run | No `README.md` / no project roadmap | Create a brief README; ensure Paavo's Codex MCP is up and profile names the project (Step 7) |
| PM hard-stops immediately | Paavo's Codex MCP unreachable | Start the MCP server; fix Cursor MCP registration; verify a closed version exists |
| Roadmap invents goals | MCP not used / wrong project | Check profile project name; re-run `roadmap-planner` against Paavo's Codex |
| Coordinator fails on git merge/reset | Command wrapper blocking local git | Allow local git merge, reset, checkout in wrapper config |
| Agent not found | Missing `.cursor/agents/` files | Re-run the install script from `$STAGE`, or verify `.cursor/agents/` exists |
| Subagent runs on the wrong model | Parent agent passed a `model` parameter when invoking it, which overrides frontmatter | Check the PM/Coordinator prompt: subagent invocations must never pass `model` |
| Every agent runs on the model of the chat you launched, despite correct-looking frontmatter | Unrecognised model ID; Cursor falls back to the parent model without reporting anything | List the real IDs (Step 6) and re-run `set-agent-models.sh`. A `cursor-` prefix copied from a billing export is the usual cause |
| An agent runs on the right model but the wrong reasoning level | Unrecognised parameter for that family; it is dropped and the model default applies | Check the parameter name against the family: `reasoning` for GPT, `effort` for Claude/Grok/Gemini |
| Bill is higher than expected with no config change | A parameter was omitted, so the model's default variant applies -- `fast=true`, or the `1m` context tier | State `fast` and `context` explicitly on every bucket |
| All subagents run on one cheap model regardless of config | Legacy request-based plan without Max Mode forces Cursor's own model for subagents | Switch to a usage-based plan, or accept that Step 6 has no effect |
| Visual acceptance criteria always pass | `builder` bucket model cannot see images | Assign a vision-capable model to `builder` whenever the profile's UI kind is not `none` |
| Reviews stopped rejecting anything after a model change | `critic` or `checker` bucket is too weak and is rubber-stamping | Raise that bucket; see Cost and Quality Telemetry |
| Rejections dropped but no model changed | Expected once, after adopting the anchoring rule in LOGIC.md Section 13.1 | Check that the rejections you do get carry an `Anchor:` field; re-baseline rather than raising a bucket |
| `set-agent-models.sh` exits "agent prompts with no bucket assignment" | An agent prompt was added without a bucket | Add it to `BUCKET_MAP` in the script, or take the upstream version of the script |
| Coordinator stuck | State machine confusion or stale active state | Run `taskwarrior/coordinator-status` (or `/ai-status`) to inspect liveness; use manual cleanup only after confirming no agents are active |
| Coordinator halts with "no subagent dispatch" | Launched at the wrong nesting depth, almost always because the PM was delegated instead of loaded as a skill | Start a fresh top-level chat, invoke `/project-manager`, and confirm no `.cursor/agents/project-manager.md` exists |
| Escalation recovery stops | Needs product/scope/interface decision or active agent state is unsafe | Check `plan/escalations/` for the recovery report and give the PM direction |
| Escalation loop | Recurring failures after recovery | Check `plan/escalations/` for reports describing root cause and recovery |
| `epic-fork` fails | Branch or worktree already exists | Check `git worktree list`; remove stale worktrees with `git worktree remove <path>` |
| Worktree has stale changes | Epic branch diverged from main | Run `epic-rebase` to update, or resolve conflicts manually |
| `epic-merge` conflicts | Parallel epics modified same files | Rebase the epic first (`epic-rebase`), resolve conflicts, then retry merge |
| Multiple Coordinators in same epic | Stale lock from crashed agent | Confirm no agents are running, then run `bash taskwarrior/cleanup-ai-state.sh` |
| Epic worktree missing after reboot | `.worktrees/` was deleted or moved | Re-run `epic-fork` for affected epics (stories/tasks are preserved in Taskwarrior) |
