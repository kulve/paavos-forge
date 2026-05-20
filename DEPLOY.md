# Deployment Guide

How to deploy the AI execution framework into a downstream project.

## Prerequisites

- A git repository for your project (can be empty or existing)
- [Taskwarrior](https://taskwarrior.org/) installed (`task --version` to verify)
- [Cursor](https://cursor.com/) IDE (for the agent system; other IDE support is future work)

## Step 1: Copy Base Templates

Copy the base framework files into your project root:

```bash
cp -r /path/to/ai-execution-framework/templates/base/* /path/to/your-project/
```

This creates:
- `AGENTS.md` -- project-level AI instructions
- `ARCHITECTURE.md` -- domain dependency policy registry (populated by agents as domains are introduced)
- `ai-framework/LOGIC.md` -- the workflow specification
- `ai-framework/project-profile.md` -- to be filled in by you
- `plan/templates/` -- artifact templates used by agents
- `taskwarrior/setup.sh` -- Taskwarrior configuration script
- `taskwarrior/recipes.md` -- command reference for agents

## Step 2: Copy Cursor Templates

Copy the Cursor-specific files:

```bash
cp -r /path/to/ai-execution-framework/templates/cursor/.cursor /path/to/your-project/
```

This creates:
- `.cursor/agents/` -- 16 agent prompt files
- `.cursor/rules/ai-framework.mdc` -- always-on framework rules
- `.cursor/commands/` -- `ai-status` and `ai-next` slash commands

## Step 3: Configure Taskwarrior

Run the setup script to create the required UDAs:

```bash
cd /path/to/your-project
bash taskwarrior/setup.sh
```

Verify the UDAs exist:
```bash
task _udas | grep -E 'aiphase|aistate|aistory'
```

You should see `aiphase`, `aistate`, and `aistory` listed.

## Step 4: Fill in the Project Profile

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

## Step 5: Customize Agents (Optional)

The agent prompts are designed to be generic, but you may want to tune them for your project:

- **Review strictness:** edit the review agents' Quality Criteria sections to add project-specific checks
- **Anti-patterns:** add domain-specific mistakes to the Anti-Patterns sections (e.g. "never use raw SQL" for a web app)
- **Architecture conventions:** if your project uses something unusual (e.g. protocol buffers as architecture artifacts), update the architecture agents

## Step 6: Validate

You can run the automated validation script (copy it from the framework repo):

```bash
cp /path/to/ai-execution-framework/scripts/validate-deployment.sh ./
bash validate-deployment.sh
```

Or verify manually:

- [ ] `AGENTS.md` exists at project root
- [ ] `ARCHITECTURE.md` exists at project root
- [ ] `ai-framework/LOGIC.md` exists
- [ ] `ai-framework/project-profile.md` exists and is filled in
- [ ] `plan/templates/` contains 6 template files (milestone, story, requirement, phase-plan, review-feedback, escalation)
- [ ] `taskwarrior/setup.sh` exists
- [ ] `taskwarrior/recipes.md` exists
- [ ] `.cursor/agents/` contains 16 agent files
- [ ] `.cursor/rules/ai-framework.mdc` exists
- [ ] `.cursor/commands/` contains `ai-status.md` and `ai-next.md`
- [ ] Taskwarrior UDAs are configured: `task _udas | grep aiphase`
- [ ] Project profile is filled in completely

## Step 7: First Run

1. Open your project in Cursor.
2. Start a new chat and invoke the `project-manager` agent.
3. Describe your project goals. The PM will discuss them with you and create the first milestone.
4. The PM will generate the first 2-3 stories, review them, and start executing via the Coordinator.
5. Watch the pipeline work. Use `/ai-status` to check progress at any time.

## Updating the Framework

If the upstream framework template is updated, you can selectively merge changes:

- `ai-framework/LOGIC.md` -- compare and merge workflow changes
- `.cursor/agents/` -- compare and merge agent prompt improvements
- `.cursor/rules/ai-framework.mdc` -- compare and merge rule changes
- `plan/templates/` -- compare and merge template changes

Your `ai-framework/project-profile.md` and any agent customizations should be preserved during updates.

## Troubleshooting

**Taskwarrior UDAs not recognized:** re-run `bash taskwarrior/setup.sh`

**Agent not found:** verify `.cursor/agents/` contains the agent `.md` files

**Coordinator stuck:** run `/ai-next` to see the current state and manually advance if needed

**Escalation loop:** check `plan/escalations/` for reports. The escalation file will describe what went wrong and propose a recovery path.
