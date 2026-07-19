# AI Execution Framework -- Canonical Workflow Specification

This document is the single source of truth for the AI execution framework. All agent prompts, rules, templates, and deployment docs reference this file. If there is a conflict between this document and any other file, this document wins.

---

## 1. Core Philosophy

This framework enables AI agents to autonomously implement large projects from high-level goals. It relies on:

- **Strict isolation of concerns**: each agent has a narrow role and limited context
- **Explicit state management**: Taskwarrior owns execution state, not filesystem layout
- **Parallel epic execution**: independent epics run in isolated git worktrees; stories within an epic execute serially
- **Script-enforced gates**: all state mutations go through deterministic scripts; agents react to exit codes, never manipulate Taskwarrior directly
- **Shift-left testing**: integration tests are written before implementation to constrain AI behavior
- **Single active subagent per worktree**: at most one Taskwarrior task may be `+ACTIVE` at any time within a given worktree; the Coordinator enforces this via scripts
- **Top-level singleton locks**: only one PM may run at any time (global); only one Coordinator may run per worktree

The framework is optimized for C++ projects but supports other languages (Python, TypeScript, etc.) through the project profile.

---

## 2. Roles

### 2.1 Project Manager (PM)

The top-level orchestrator. Talks to the user, defines milestones, creates epics, generates stories in rolling batches, and dispatches epics to worktrees for parallel execution. The PM never touches code. Operates in the main project tree.

### 2.2 Coordinator

A deterministic state machine that drives all stories within a single epic through all four phases. The Coordinator is not creative -- it reads Taskwarrior state via scripts, decides which subagent to invoke next, and halts on escalations. It never reads code or artifact content directly. It invokes exactly one subagent at a time. Operates within an epic's worktree.

### 2.3 Phase Agents

Sixteen specialized agents (4 phases x 4 states: plan, plan-review, write, review) that produce and verify artifacts. Each has a narrow context window and strict input/output contracts. Plan-review agents verify plans before execution begins; review agents verify the artifacts produced by write agents.

### 2.4 Support Agents

Story Review, Escalation Analysis, and Escalation Recovery agents that assist the PM and Coordinator with quality assurance, failure diagnosis, and bounded automatic recovery.

### 2.5 Escalation Recovery

A PM-invoked support agent that operates inside the PM pipeline after a clean Coordinator escalation halt. It reads the escalation report and the minimum relevant story artifacts, applies the smallest correction needed to make the current story internally consistent, and reports the earliest phase state that must be rerun. It is not part of the Coordinator's dispatch table. It must stop for human input if recovery requires changing product intent, widening scope, changing public interfaces, adding dependencies, creating stories, skipping phases, or resolving suspicious runtime state.

### 2.6 Fixer

A lightweight bug-fix agent that operates entirely outside the PM pipeline. The user invokes it directly to fix bugs in existing code. It may modify source files and tests, but must not add features, change public interfaces, create framework artifacts, or use Taskwarrior. It is not part of the Coordinator's dispatch table. If a fix exceeds its scope (architectural changes, new interfaces, new requirements), it redirects the user to the PM.

### 2.7 Singleton Locks

**PM lock** (global, main tree): only one PM may run at any time. The PM lock is a `+AI_LOCK airole:pm` task in the main tree's Taskwarrior, managed via `pm-lock-acquire` and `pm-lock-release` scripts.

**Coordinator lock** (per-worktree): only one Coordinator may run per epic worktree. The Coordinator lock is a `+AI_LOCK airole:coordinator` task in the worktree's Taskwarrior, managed via `coordinator-lock-acquire` and `coordinator-lock-release` scripts.

**Duplicate agent startup rule**: when a PM or Coordinator agent starts, it first checks its lock via the status script. If the lock is already active, the duplicate agent must run only read-only queries to report what is currently running, then exit without modifying state.

**Stale lock recovery**: agents must never auto-clear stale locks. If the user confirms no Cursor agents or subagents are still running for the workspace, the user may run the manual cleanup script:
```
ccmd bash taskwarrior/cleanup-ai-state.sh
ccmd bash taskwarrior/cleanup-ai-state.sh --apply
```

---

## 3. State Machine

### 3.1 Hierarchy

```
Milestone (optional)
└── Epic (parallel execution, one worktree per epic)
    └── Story (serial execution within epic)
        └── Phase tasks (req → arch → test → impl)
```

### 3.2 Epic States (tracked in main tree Taskwarrior)

```
active → merge-ready → merging → merged
                  ↘ conflict ↗
```

- **active**: epic worktree exists, Coordinator is executing stories
- **merge-ready**: all stories complete, ready to merge to main
- **merging**: merge gate held, squash-merge in progress
- **merged**: successfully merged to main, worktree removed
- **conflict**: merge failed due to conflicts, needs rebase

### 3.3 Phase States (tracked per-worktree)

Every story spawns four Taskwarrior tasks, one per phase, with explicit dependencies:

```
requirements --> architecture --> integration_tests --> implementation
```

Each task transitions through states:

```
blocked -> plan -> plan-review -> write -> review -> done
             ^         |            ^         |
             +--reject-+            +--reject-+
```

- **blocked**: waiting for upstream phase to complete (managed by Taskwarrior dependencies)
- **plan**: the Plan agent reads context and writes a plan file
- **plan-review**: the Plan Review agent evaluates the plan for completeness and feasibility
- **write**: the Write agent executes the approved plan or addresses review feedback
- **review**: the Review agent evaluates the produced artifacts
- **done**: the phase passed review; artifacts are committed

Plan-review can return to plan (rejection). Review can return to write (rejection). After 3 rejections of either review loop, the Coordinator writes an escalation instead of retrying.

### 3.4 Taskwarrior UDAs

**Main tree** (PM-level, configured by `setup.sh --main`):
```
uda.aiepic.type=string
uda.aiepic.label=AI Epic ID

uda.epicstate.type=string
uda.epicstate.label=Epic State
uda.epicstate.values=active,merge-ready,merging,merged,conflict,cancelled

uda.airole.type=string
uda.airole.label=AI Role Lock
uda.airole.values=pm
```

**Worktree** (Coordinator/phase-level, configured by `setup.sh --worktree`):
```
uda.aiphase.type=string
uda.aiphase.label=AI Phase
uda.aiphase.values=req,arch,test,impl

uda.aistate.type=string
uda.aistate.label=AI State
uda.aistate.values=blocked,plan,plan-review,write,review,done

uda.aistory.type=string
uda.aistory.label=AI Story ID

uda.airole.type=string
uda.airole.label=AI Role Lock
uda.airole.values=coordinator
```

### 3.5 Context Passing

Agents never talk to each other directly. All context passes through Taskwarrior annotations containing file paths:

- Plan agents annotate: `Plan: plan/requirement-plans/XXXXX-slug.md`
- Plan-review agents annotate: `Plan-review: approved` or `Plan-feedback: plan/requirement-plan-review/XXXXX-feedback.md`
- Write agents annotate: `Artifact: plan/requirements/core/XXXXX-name.md`
- Review agents annotate: `Review: approved` or `Feedback: plan/requirements-review/XXXXX-feedback.md`
- Escalating agents annotate: `Escalation: plan/escalations/XXXXX-phase-slug.md`

The Coordinator reads these annotations (via `story-next` script output) to construct the next subagent's prompt. Annotations contain file paths only, never large text payloads.

---

## 4. PM Loop (Parallel Epic Dispatch)

The PM operates in the main project tree. It defines epics and dispatches them for parallel execution.

1. **Milestone definition** (optional): PM writes `plan/milestones/XX-name.md` containing high-level goals, epic list, boundaries, and done criteria. PM discusses goals with user in chat; important decisions are captured in the milestone file.

2. **Epic definition**: PM writes `plan/epics/EXXXX-slug.md` containing goal, boundaries, ordered story list, done criteria, and epic dependencies. Epics are coherent feature areas that can execute independently.

3. **Story generation**: PM reads the epic, existing stories, and codebase README, then writes the next 2-3 stories to `plan/stories/XXXXX-slug.md`. Stories are vertical feature slices, not horizontal technical layers. When new behavior conflicts with or replaces behavior from an earlier story, the new story must include a **Modifies Stories** section.

4. **Story review**: PM invokes the story-review subagent for the batch. PM addresses feedback by updating story files directly.

5. **Epic dispatch**: PM runs the preflight check and forks the epic:
   ```
   ccmd bash taskwarrior/pm-preflight
   ccmd bash taskwarrior/epic-fork EXXXX slug
   ```
   The fork script checks the merge gate, creates the worktree, initializes Taskwarrior, and registers the epic.

6. **Coordinator invocation**: PM launches a Coordinator subagent with `working_directory` set to the epic's worktree path. The Coordinator may run in background (`run_in_background: true`) to allow the PM to dispatch additional epics.

7. **Parallel dispatch**: PM may repeat steps 2-6 for additional independent epics. Multiple epics execute simultaneously in their own worktrees.

8. **Monitoring**: PM periodically checks status:
   ```
   ccmd bash taskwarrior/epic-status
   ccmd bash taskwarrior/pm-preflight
   ```

9. **Epic completion**: When a Coordinator signals that all stories are done (epic becomes merge-ready):
   ```
   ccmd bash taskwarrior/epic-mark-ready EXXXX
   ```

10. **Merge**: PM merges completed epics to main:
    ```
    ccmd bash taskwarrior/epic-merge EXXXX
    ```
    If exit 1 (gate blocked): another merge in progress, wait and retry.
    If exit 2 (conflict): report to user, suggest `epic-rebase`.

11. **Re-evaluation**: After epic merge, PM re-reads the codebase and milestone file. If milestone goals are met, PM performs discovery triage before discussing the next milestone with the user.

12. **Git for planning artifacts**: PM commits milestone, epic, and story files to `main` directly, before dispatching the epic.

13. **Escalation received**: When a Coordinator returns due to escalation, PM reads the escalation file, verifies the Coordinator lock is inactive (via worktree status), then invokes `escalation-recovery` in foreground within the epic's worktree. If recovery succeeds, PM clears the resolved escalation state via scripts and launches a fresh Coordinator for the same epic.

14. **Discovery triage**: Once a milestone is otherwise complete (all epics merged), the PM reads `plan/discoveries/`, groups findings, writes `plan/discoveries/triage-XX.md`, and summarizes proposed handling for the user.

---

## 5. Coordinator Loop

The Coordinator drives all stories within a single epic through all four phases. It operates within an epic's worktree directory.

1. Read the epic file to get the ordered story list.

2. Acquire Coordinator lock:
   ```
   ccmd bash taskwarrior/coordinator-lock-acquire
   ```
   If exit 1 (already held): report and exit as duplicate.

3. **For each story in the epic** (serial, in order):

4. Initialize story tasks:
   ```
   ccmd bash taskwarrior/story-init XXXXX slug
   ```

5. **Story loop start**: Query next actionable task:
   ```
   ccmd bash taskwarrior/story-next XXXXX
   ```

6. If output is "NONE" and all tasks complete, go to step 14.

7. Read the task's `phase` and `state` from the JSON output.

8. Determine subagent from the mapping:
   - `(req, plan)` -> `requirements-plan`
   - `(req, plan-review)` -> `requirements-plan-review`
   - `(req, write)` -> `requirements-write`
   - `(req, review)` -> `requirements-review`
   - `(arch, plan)` -> `architecture-plan`
   - `(arch, plan-review)` -> `architecture-plan-review`
   - `(arch, write)` -> `architecture-write`
   - `(arch, review)` -> `architecture-review`
   - `(test, plan)` -> `integration-test-plan`
   - `(test, plan-review)` -> `integration-test-plan-review`
   - `(test, write)` -> `integration-test-write`
   - `(test, review)` -> `integration-test-review`
   - `(impl, plan)` -> `implementation-plan`
   - `(impl, plan-review)` -> `implementation-plan-review`
   - `(impl, write)` -> `implementation-write`
   - `(impl, review)` -> `implementation-review`

9. Construct the subagent prompt with: task ID, story file path, phase, current state, and relevant file paths from task annotations.

10. Start the phase task:
    ```
    ccmd bash taskwarrior/phase-start <task-id>
    ```
    If exit 1 (another task active): stop and investigate.

11. Invoke the subagent in foreground and wait for completion.

12. Stop the phase task:
    ```
    ccmd bash taskwarrior/phase-stop <task-id>
    ```

13. Process outcome. Track a reject counter per phase (plan-review rejections and review rejections counted separately):
    - If plan-review approved (annotation says `Plan-review: approved`): state is already `write`, continue loop; reset plan-review reject counter
    - If plan-review rejected (annotation says `Plan-feedback:`): state is already `plan`, continue loop; increment plan-review reject counter; if counter reaches 3, go to step 15
    - If review approved (annotation says `Review: approved`): call `ccmd bash taskwarrior/phase-done <task-id>`, commit phase artifacts: `git commit -am "phase(PHASE): XXXXX"`; reset review reject counter
    - If review rejected (feedback file annotated): state is already `write`; increment review reject counter; if counter reaches 3, go to step 15; otherwise continue loop
    - If escalation annotated: go to step 15

    **Story loop end**: go to step 5.

14. **Story complete**: Verify and merge within worktree:
    ```
    ccmd bash taskwarrior/story-complete XXXXX --run-tests
    ccmd bash taskwarrior/story-merge XXXXX slug
    ```
    If tests fail: write an escalation for the implementation phase, block the task, and go to step 15.
    Otherwise: proceed to the next story in the epic (go to step 4 with next story).

15. **Escalation halt** (reject limit reached or subagent wrote escalation):
    - If reject limit: write `plan/escalations/XXXXX-<phase>-reject-loop.md` using the escalation template and annotate the task
    - Block the task: `ccmd bash taskwarrior/phase-block <task-id> <escalation-path>`
    - Release the Coordinator lock: `ccmd bash taskwarrior/coordinator-lock-release`
    - Return control to the PM with the escalation file path. Do not roll back git. Do not reopen upstream phases. Do not continue the loop.

16. **All stories done**: Release Coordinator lock:
    ```
    ccmd bash taskwarrior/coordinator-lock-release
    ```
    Signal completion (the PM detects this via `epic-status` or checks the worktree state).

---

## 6. Git Policy

- **One worktree per epic**: created from `main` via `epic-fork`, named `epic/EXXXX-slug`.
- **One branch per story within the worktree**: `story/XXXXX-slug`, created from the epic branch.
- **Commit after each reviewed phase**: `git commit -am "phase(req): XXXXX"`, `phase(arch): XXXXX`, `phase(test): XXXXX`, `phase(impl): XXXXX`.
- **Squash-merge story to epic branch**: when all four phases are done and tests pass.
- **Squash-merge epic to main**: when all stories are done, via `epic-merge` with merge gate.
- **Planning artifacts on main**: PM commits milestone, epic, and story files to `main` directly.
- **No automatic rollback on escalation**: escalations halt the Coordinator and return control to the PM; git state is preserved for recovery.

---

## 7. Merge Gate Protocol

The merge gate ensures atomic operations on `main`. It prevents concurrent merges and prevents forks during a merge.

1. **Gate implementation**: a permanent `+MERGE_GATE` task in the main tree's Taskwarrior, created by `setup.sh --main`. It is started/stopped to hold/release the gate.

2. **Acquire**: `epic-merge` starts the gate task before performing the squash-merge.

3. **Release**: `epic-merge` stops the gate task after the merge completes (or on failure).

4. **Fork guard**: `epic-fork` checks if the gate is active; if so, it exits 1 (retry later).

5. **Stale gate recovery**: if a merge is interrupted (LLM context dies mid-merge), the gate remains held. The user inspects via `epic-gate-status` and force-releases via `epic-gate-release --force` after confirming no merge is in progress.

6. **Invariants enforced by scripts**:
   - At most one merge to main at any time
   - No new worktrees forked while a merge is in progress
   - The PM never directly manipulates the gate -- only `epic-merge` and `epic-fork` scripts do

---

## 8. Epic Lifecycle

### 8.1 Definition

PM writes `plan/epics/EXXXX-slug.md` using the epic template. The file contains the goal, boundaries, ordered story list, done criteria, and inter-epic dependencies.

### 8.2 Dispatch

PM commits the epic file and stories to `main`, then forks:
```
ccmd bash taskwarrior/epic-fork EXXXX slug
```
This creates the worktree at `.worktrees/epic-EXXXX-slug/`, initializes a fresh Taskwarrior database, and registers the epic as `active` in the main tree.

### 8.3 Execution

PM launches a Coordinator subagent pointed at the worktree. The Coordinator processes all stories in the epic serially.

### 8.4 Completion

When the Coordinator finishes all stories and releases its lock, the PM marks the epic merge-ready:
```
ccmd bash taskwarrior/epic-mark-ready EXXXX
```

### 8.5 Merge

PM merges the epic to main:
```
ccmd bash taskwarrior/epic-merge EXXXX
```
The script acquires the merge gate, performs a squash-merge, removes the worktree, and updates epic state to `merged`.

### 8.6 Conflict Resolution

If `epic-merge` fails with a conflict (exit 2), the epic enters `conflict` state. The PM may:
- Run `ccmd bash taskwarrior/epic-rebase EXXXX` to rebase on latest main
- Report the conflict to the user for manual resolution

After successful rebase, the epic returns to `merge-ready` and merge can be retried.

### 8.7 Parallel Limits

The number of concurrent epics is not hard-limited by the framework but is bounded by practical considerations:
- Each worktree duplicates the working tree (disk space)
- Each Coordinator needs its own agent context (token budget)
- More parallel epics means more potential merge conflicts

The project profile may specify a recommended concurrency limit.

---

## 9. Escalation Protocol

Escalations halt Coordinator work and surface the problem to the PM. The PM may attempt one bounded automatic recovery only after proving that no Coordinator or phase subagent is still active.

1. **Trigger**: a subagent hits an impossible constraint, a contradiction it cannot resolve, or the Coordinator detects the 3rd plan-review or review rejection for the same phase.

2. **Report**: the subagent (or Coordinator on reject limit) writes `plan/escalations/XXXXX-phase-slug.md` using the escalation template, annotates the task with `Escalation: <path>`, and exits immediately. The subagent does not continue working after writing the escalation.

3. **Coordinator halt**: the Coordinator detects the `Escalation:` annotation or reject limit, blocks the task via `ccmd bash taskwarrior/phase-block <task-id> <path>`, releases the Coordinator lock via `ccmd bash taskwarrior/coordinator-lock-release`, and returns control to the PM. No git rollback. No upstream phase reopening.

4. **PM recovery preflight**: before invoking recovery, the PM must verify the worktree state:
   ```
   ccmd bash taskwarrior/coordinator-lock-status    # (run in worktree) must show FREE
   ```
   If the Coordinator lock is held, the PM must not recover automatically.

5. **Escalation Recovery**: the PM invokes `escalation-recovery` in foreground within the epic's worktree with the escalation path, blocked task ID, story path, and current task metadata. The recovery agent may make only bounded corrections and must return one of:
   - `resolved`: includes the earliest phase and `aistate` to rerun
   - `needs-human`: explains the decision required
   - `failed-recovery`: explains why its attempted fix did not resolve the blocker

6. **PM state restoration**: if recovery returns `resolved`, the PM uses scripts to clear the escalation and restore the task:
   ```
   ccmd bash taskwarrior/phase-annotate <id> Recovery "<summary>"
   ccmd bash taskwarrior/phase-transition <id> <resume-state>
   ```
   (The `phase-transition` script handles clearing `+blocked` when transitioning from blocked state.)

7. **Resume**: PM launches a fresh Coordinator for the same epic in foreground. The Coordinator picks up from the restored task state.

8. **Human stop conditions**: PM stops and asks the user when recovery requires changing story intent, widening acceptance criteria, changing public interfaces, adding dependencies, creating or skipping stories, skipping phases, clearing stale/duplicate locks, clearing orphaned active phase tasks, or resolving the same root cause repeatedly.

---

## 10. Artifact Definitions

### 10.1 Milestones (`plan/milestones/XX-name.md`)

High-level planning documents. Contain vision, goals, boundaries, epic list, and done criteria. Updated by the PM as epics are generated and completed.

### 10.2 Epics (`plan/epics/EXXXX-slug.md`)

Coherent feature areas decomposed into ordered stories. Contain goal, boundaries, ordered story list, done criteria, and inter-epic dependencies. Each epic is the unit of parallel execution -- it gets its own git worktree.

### 10.3 Stories (`plan/stories/XXXXX-slug.md`)

Problem-space documents describing vertical feature slices. Must include: epic reference, goal (what and why), scope boundaries, trigger conditions, binary acceptance criteria, domain tags, dependencies, and non-goals. Stories describe user-facing behavior, not technical tasks.

Optional **Modifies Stories** section: when a new story changes or deprecates behavior from earlier stories, list the old story file paths and a brief reason.

### 10.4 Requirements (`plan/requirements/[domain]/XXXXX-name.md`)

Problem-space rules organized by domain. Translate the vertical story into categorized logic, constraints, and business rules. Must backlink to parent story IDs. Contain no code, no class names -- only plain English descriptions.

When a later story modifies behavior covered by an existing requirement, the Requirements Write agent must either:
- **Update in place**: add the new story to traceback, revise rules
- **Delete**: remove the requirement file when fully superseded

### 10.5 Architecture Artifacts

Solution-space definitions. The exact form depends on the project profile:
- **C++**: header files in `include/[domain]/` -- declarations only
- **Python**: abstract base classes or typed interface modules
- **Other languages**: as specified in the project profile

### 10.6 Integration Tests (`tests/integration/` or as specified in profile)

Shift-left tests written BEFORE implementation. They enforce interface contracts by instantiating concrete classes across domains. Testing philosophy:
- Use real collaborator objects (Detroit/Chicago school)
- Only mock at true system boundaries: file I/O, network sockets, OS system calls, hardware contexts
- Never mock internal collaborators
- Tests must compile/parse against the architecture artifacts even before implementation exists

### 10.7 Phase Plans (`plan/*-plans/XXXXX-slug.md`)

Written by Plan agents. Specify what the Write agent should do: which files to create/modify, the approach, risks, and verification steps.

### 10.8 Plan Review Feedback (`plan/*-plan-review/XXXXX-feedback.md`)

Written by Plan Review agents when rejecting plans. Must contain: verdict, specific blocking issues with fix instructions, missing coverage, and approved aspects.

### 10.9 Review Feedback (`plan/*-review/XXXXX-feedback.md`)

Written by Review agents when rejecting artifacts. Must contain: verdict, specific blocking issues with file paths and fix instructions, missed requirements, and approved aspects.

### 10.10 Escalation Reports (`plan/escalations/XXXXX-phase-slug.md`)

Written by any agent that cannot complete its task. Must contain: blocked task ID, failure description with exact errors, reproduction steps, root cause analysis, and proposed recovery action.

### 10.11 Architecture Policy (`ARCHITECTURE.md`)

A living document at the project root maintained by the Architecture Plan agent. Lists domain definitions and their strict dependency rules as a DAG. Must NEVER list classes, methods, or internal design patterns.

### 10.12 Discoveries (`plan/discoveries/YYYYMMDD-HHMMSS-slug.md`)

Short records of significant out-of-scope findings. Any subagent may create one; only the PM triages after milestone completion.

---

## 11. Agent Invocation Contract

When the Coordinator invokes a subagent, it constructs a prompt with this structure:

```
You are the [Role] agent. Your task:
- Task ID: <taskwarrior-id>
- Story: plan/stories/XXXXX-slug.md
- Epic: plan/epics/EXXXX-slug.md
- Phase: <req|arch|test|impl>
- State: <plan|plan-review|write|review>
- Plan file: <path from annotation, if applicable>
- Plan feedback: <path from Plan-feedback annotation, if re-doing after plan-review rejection>
- Feedback: <path from Feedback annotation, if re-doing after review rejection>

Follow your role instructions. Read the files listed above. Write your outputs.
Update Taskwarrior via scripts when done.
```

The subagent reads its own agent definition file for role instructions, then reads the files listed in the prompt for task-specific context.

---

## 12. Script Protocol

All Taskwarrior state mutations must go through the provided scripts. Agents must never call `taskwarrior/tw` directly for state changes.

### 12.1 Why Scripts

Scripts are the enforcement layer. They:
- Check preconditions before acting (exit non-zero on violation)
- Validate state transitions (prevent illegal moves)
- Enforce mutual exclusion (merge gate, active task guard)
- Provide structured output for agent consumption

### 12.2 Script Categories

**PM scripts** (run in main tree):
- `pm-lock-acquire` / `pm-lock-release`: PM singleton lock
- `pm-preflight`: read-only status check across all worktrees
- `epic-fork`: create worktree and register epic
- `epic-merge`: merge epic to main with gate
- `epic-mark-ready`: mark epic as merge-ready
- `epic-status`: read-only epic status report
- `epic-gate-status` / `epic-gate-release`: merge gate inspection and recovery
- `epic-rebase`: rebase epic branch on latest main

**Coordinator scripts** (run in epic worktree):
- `coordinator-lock-acquire` / `coordinator-lock-release` / `coordinator-lock-status`: Coordinator singleton lock
- `story-init`: create phase tasks and story branch
- `story-next`: query next actionable task (JSON output)
- `story-complete`: verify all phases done, run tests
- `story-merge`: squash-merge story branch to epic branch

**Phase scripts** (run in epic worktree):
- `phase-start`: active-task guard + start
- `phase-stop`: stop task
- `phase-transition`: validated state change
- `phase-annotate`: validated annotation
- `phase-done`: mark task done
- `phase-block`: block task with escalation

### 12.3 Exit Code Convention

All scripts follow this convention:
- **Exit 0**: success
- **Exit 1**: precondition not met (retry later -- e.g., gate blocked, lock held)
- **Exit 2**: error (invalid arguments, illegal state, conflict)

### 12.4 Read-Only Queries

Agents may call `taskwarrior/tw` directly for **read-only queries** (status checks, exports, counts). Only state mutations require scripts.

---

## 13. Quality Standards

### 13.1 Review Principles

All review agents (plan-review and review) follow these principles:
- Focus on blocking issues: logic errors, missed requirements, incorrect contracts, test gaps
- Do NOT nitpick formatting, naming conventions, or style unless they cause actual confusion
- If it works and is structurally sound, approve it
- Every rejection must include exact file paths, line references, and concrete fix instructions
- Never rubber-stamp -- actually read and verify each artifact
- Limit to 3 review rounds per artifact; the Coordinator enforces this by counting rejections

### 13.2 Implementation Standards

Implementation agents must never:
- Hardcode expected test values to make tests pass
- Write empty method bodies or stub implementations
- Use mocks or fakes in production code
- Write code that only works for specific test inputs
- Skip error handling mentioned in requirements
- Add dependencies not justified by requirements
- Silently deviate from the architecture

### 13.3 Domain Dependency Compliance

All architecture artifacts and implementation source files must respect the dependency DAG defined in `ARCHITECTURE.md`.

### 13.4 Requirement Standards

Requirement agents must never leak solution-space concepts into requirements. Requirements describe WHAT, never HOW.

---

## 14. Extension Points

The framework is designed to be extended via the project profile. Downstream projects customize:

- **Language and build system**: affects architecture artifact type, test framework, build commands
- **Directory layout**: source, architecture, test, and build output directories
- **Test commands**: integration tests, full suite, lint/typecheck
- **Architecture conventions**: what architecture artifacts look like
- **Mock boundaries**: what may be mocked in tests
- **Review standards**: project-specific quality requirements
- **Forbidden areas**: directories and actions agents must never touch
- **Domain tags**: valid categories for organizing requirements
- **Parallel limit**: recommended maximum concurrent epics

Agent prompts read the project profile to adapt their behavior. The core workflow (phases, states, script protocol, git policy) remains fixed.

---

## 15. Discovery Protocol

Discoveries preserve important out-of-scope observations without derailing the current task.

1. **Trigger**: while performing its assigned task, any subagent notices a clear and significant bug, gap, stub, design flaw, or risk outside the current task scope.

2. **Record**: the subagent writes exactly one new file under `plan/discoveries/` using `plan/templates/discovery.md`. The filename must be `YYYYMMDD-HHMMSS-slug.md`.

3. **Do not inspect existing discoveries**: the subagent must not read, list, search, deduplicate, modify, or delete existing files in `plan/discoveries/`.

4. **Continue current task**: after writing the discovery, the subagent continues its assigned task.

5. **PM triage**: once a milestone is otherwise complete, the PM reads all files in `plan/discoveries/`, groups duplicates, writes `plan/discoveries/triage-XX.md`, and summarizes proposed handling for the user.
