# AI Execution Framework -- Canonical Workflow Specification

This document is the single source of truth for the AI execution framework. All agent prompts, rules, templates, and deployment docs reference this file. If there is a conflict between this document and any other file, this document wins.

---

## 1. Core Philosophy

This framework enables AI agents to autonomously implement large projects from high-level goals. It relies on:

- **Strict isolation of concerns**: each agent has a narrow role and limited context
- **Explicit state management**: Taskwarrior owns execution state, not filesystem layout
- **Ephemeral git branching**: each story gets its own branch; commits happen only after review
- **Rolling batch execution**: no waterfall; stories are generated and executed in small batches
- **Shift-left testing**: integration tests are written before implementation to constrain AI behavior
- **Single active subagent**: at most one Taskwarrior task may be `+ACTIVE` at any time; the Coordinator enforces this via `start`/`stop` around every subagent invocation
- **Top-level singleton locks**: only one PM and one Coordinator may run at any time; duplicates are read-only status reporters that exit without modifying state

The framework is optimized for C++ projects but supports other languages (Python, TypeScript, etc.) through the project profile.

---

## 2. Roles

### 2.1 Project Manager (PM)

The top-level orchestrator. Talks to the user, defines milestones, generates stories in rolling batches, and invokes the Coordinator for each story. The PM never touches code.

### 2.2 Coordinator

A deterministic state machine that drives a single story through all four phases. The Coordinator is not creative -- it reads Taskwarrior state, decides which subagent to invoke next, manages git branches, and halts on escalations. It never reads code or artifact content directly. It invokes exactly one subagent at a time: before each invocation it verifies `taskwarrior/tw +ACTIVE -AI_LOCK count` is 0, calls `start` on the task, invokes the subagent in foreground, then calls `stop` when the subagent exits.

### 2.3 Phase Agents

Twenty specialized agents (4 phases x 5 roles: plan, plan-review, write, review) that produce and verify artifacts. Each has a narrow context window and strict input/output contracts. Plan-review agents verify plans before execution begins; review agents verify the artifacts produced by write agents.

### 2.4 Support Agents

Story Review and Escalation Analysis agents that assist the PM and Coordinator with quality assurance and failure diagnosis.

### 2.5 Fixer

A lightweight bug-fix agent that operates entirely outside the PM pipeline. The user invokes it directly to fix bugs in existing code. It may modify source files and tests, but must not add features, change public interfaces, create framework artifacts, or use Taskwarrior. It is not part of the Coordinator's dispatch table. If a fix exceeds its scope (architectural changes, new interfaces, new requirements), it redirects the user to the PM.

### 2.6 Top-Level Singleton Locks

Only one PM and one Coordinator may run at any time. Locks are Taskwarrior tasks tagged `+AI_LOCK` that are created once by `taskwarrior/setup.sh` and never completed -- they are `start`ed and `stop`ped to track liveness:

- `+AI_LOCK airole:pm` -- held by the PM for the duration of its session
- `+AI_LOCK airole:coordinator` -- held by the Coordinator for the duration of one story

**Duplicate agent startup rule**: when a PM or Coordinator agent starts, it first checks whether its lock is `+ACTIVE`. If the lock is already active, the duplicate agent must:
1. Run only read-only Taskwarrior queries to report what is currently running.
2. Exit immediately without modifying Taskwarrior, git, plan files, source, tests, or architecture artifacts.

If more than one matching active lock task exists for the same top-level role, framework state is inconsistent. The agent must report the lock task IDs, run only read-only status queries, and stop. User or parent-agent prompts cannot override lock semantics; duplicates must never be resumed or promoted to legitimate lock holders.

**Phase subagent guard**: the Coordinator checks `+ACTIVE -AI_LOCK count` (not plain `+ACTIVE count`) so that the Coordinator's own lock task does not appear to block legitimate phase-subagent starts.

**Stale lock recovery**: agents must never auto-clear stale locks. If the user confirms no Cursor agents or subagents are still running for the workspace, the user may run the manual cleanup script:
```
ccmd bash taskwarrior/cleanup-ai-state.sh
ccmd bash taskwarrior/cleanup-ai-state.sh --apply
```
The script stops active AI locks and active phase tasks, and deletes duplicate singleton lock tasks (keeping the lowest task ID per `airole`). It does not recover or roll back git changes, mark phase tasks done, or modify `aistate`. After cleanup, the PM must analyze status before launching a fresh Coordinator.

**Duplicate lock tasks**: `taskwarrior/setup.sh` creates one permanent `+AI_LOCK` task per role. If a lock task is briefly deleted and setup is re-run, a second lock task can appear. PM/Coordinator agents must start/stop by task ID, not by role filter. More than one pending `+AI_LOCK` task for the same `airole` is inconsistent framework state; run cleanup to dedupe.

---

## 3. State Machine

### 3.1 Phases

Every story spawns four Taskwarrior tasks, one per phase, with explicit dependencies:

```
requirements --> architecture --> integration_tests --> implementation
```

The dependency chain means architecture cannot start until requirements are done, tests cannot start until architecture is done, and implementation cannot start until tests are done.

### 3.2 States

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

### 3.3 Taskwarrior UDAs

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
uda.airole.values=pm,coordinator
```

Lock tasks carry `+AI_LOCK` and an `airole` value. They are never completed.

### 3.4 Context Passing

Agents never talk to each other directly. All context passes through Taskwarrior annotations containing file paths:

- Plan agents annotate: `Plan: plan/requirement-plans/XXXXX-slug.md`
- Plan-review agents annotate: `Plan-review: approved` or `Plan-feedback: plan/requirement-plan-review/XXXXX-feedback.md`
- Write agents annotate: `Artifact: plan/requirements/core/XXXXX-name.md`
- Review agents annotate: `Review: approved` or `Feedback: plan/requirements-review/XXXXX-feedback.md`
- Escalating agents annotate: `Escalation: plan/escalations/XXXXX-phase-slug.md`

The Coordinator reads these annotations to construct the next subagent's prompt. Annotations contain file paths only, never large text payloads.

---

## 4. PM Loop (Rolling Batches)

The PM does not generate all stories for a milestone upfront. It works in rolling batches:

1. **Milestone definition**: PM writes `plan/milestones/XX-name.md` containing high-level goals, epics, boundaries, and done criteria. PM discusses goals with user in chat; important decisions are captured in the milestone file.

2. **Story generation**: PM reads the milestone, existing stories, and codebase README, then writes the next 2-3 stories to `plan/stories/XXXXX-slug.md`. Stories are vertical feature slices, not horizontal technical layers. When new behavior conflicts with or replaces behavior from an earlier story, the new story must include a **Modifies Stories** section listing the old story files and why -- never edit old story files in place.

3. **Story review**: PM invokes the story-review subagent for the batch. PM addresses feedback by updating story files directly. No re-review unless the reviewer flagged fundamental scope problems.

4. **Execution**: before invoking or resuming any Coordinator, PM runs this hard preflight:
   ```
   taskwarrior/tw +AI_LOCK airole:coordinator +ACTIVE count
   taskwarrior/tw +ACTIVE -AI_LOCK count
   taskwarrior/tw status:pending aistory.any: export
   ```
   If the Coordinator lock count is nonzero, PM must not invoke a new Coordinator, resume a Coordinator subagent, or send follow-up prompts to a Coordinator. PM may only run read-only Taskwarrior status queries, report that Coordinator work is already active, and wait for the user. If phase active count is nonzero but the Coordinator lock is inactive, PM treats it as interrupted or orphaned phase work, reports active task IDs, story, phase, and `aistate`, and asks the user to inspect running agents and optionally run the manual cleanup script. Only when Coordinator lock count and active phase count are both zero may PM invoke the Coordinator subagent for each story, one at a time, in foreground with `run_in_background: false`. Stories are processed strictly in serial.

5. **Re-evaluation**: After stories merge to `main`, PM re-reads the codebase and milestone file. If milestone goals are met, PM performs discovery triage before discussing the next milestone with the user. If not, PM generates the next 2-3 stories and repeats.

6. **Git for planning artifacts**: PM commits milestone and story files to `main` directly, before invoking the Coordinator.

7. **Escalation received**: when the Coordinator returns due to an escalation, the PM reads the escalation file, explains the problem to the user in chat, and **stops**. The PM does not re-invoke the Coordinator until the user provides direction (e.g. update a story, change requirements, skip the story).

8. **Unexpectedly stopped Coordinator**: Coordinator work has stopped unexpectedly when a story has pending phase tasks and the Coordinator lock is inactive, no Coordinator subagent is known to be running, a phase task remains `+ACTIVE -AI_LOCK`, or branch/story state indicates work is incomplete and not cleanly merged. PM must not auto-resume, clear locks, modify Taskwarrior, or modify git. PM gathers read-only status (`+AI_LOCK +ACTIVE export`, `+ACTIVE -AI_LOCK export`, pending story tasks, `ainext`, branch, and recent commits if needed), summarizes the likely state as active, cleanly completed, interrupted, orphaned active task, or stale lock, and asks the user for next steps.

---

## 5. Coordinator Loop

The Coordinator drives a single story through all four phases. It is a deterministic loop:

1. Read the story file to get the story ID and slug.

2. Check if Taskwarrior tasks exist for this story. If not, create four tasks with dependencies:
   ```
   taskwarrior/tw add "Story XXXXX: Requirements" aiphase:req aistate:plan aistory:XXXXX
   taskwarrior/tw add "Story XXXXX: Architecture" aiphase:arch aistate:blocked aistory:XXXXX depends:<req-id>
   taskwarrior/tw add "Story XXXXX: Integration Tests" aiphase:test aistate:blocked aistory:XXXXX depends:<arch-id>
   taskwarrior/tw add "Story XXXXX: Implementation" aiphase:impl aistate:blocked aistory:XXXXX depends:<test-id>
   ```

3. Create git branch: `git checkout -b story/XXXXX-slug` (from `main`).

4. **Loop start**: Query `taskwarrior/tw aistory:XXXXX status:pending +READY export` to find the next actionable task.

5. If no READY tasks and all are done, go to step 15.

6. Read the READY task's `aiphase` and `aistate`.

7. Determine subagent from the mapping:
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

8. Construct the subagent prompt with: task ID, story file path, phase, current state, and relevant file paths from task annotations.

9. **Active task guard** -- before invoking a subagent:
   ```
   taskwarrior/tw +ACTIVE -AI_LOCK count    # must be 0; if not, stop and investigate
   taskwarrior/tw <id> start                # marks task +ACTIVE
   ```

10. Invoke the subagent in foreground and wait for completion.

11. After the subagent completes:
    ```
    taskwarrior/tw <id> stop        # clears +ACTIVE
    ```

12. Query Taskwarrior for updated state. Track a reject counter per phase (plan-review rejections and review rejections counted separately):
    - If plan-review approved (annotation says `Plan-review: approved`): state is already `write`, continue loop; reset plan-review reject counter for this phase
    - If plan-review rejected (annotation says `Plan-feedback:`): state is already `plan`, continue loop; increment plan-review reject counter; if counter reaches 3, go to step 14
    - If review approved (annotation says `Review: approved`): set `aistate:done`, mark task done, commit phase artifacts: `git commit -am "phase(PHASE): XXXXX"`; reset review reject counter for this phase
    - If review rejected (feedback file annotated): set `aistate:write`; increment review reject counter; if counter reaches 3, go to step 14; otherwise continue loop
    - If escalation annotated: go to step 14

13. **Loop end**: go to step 4.

14. **Escalation halt** (reject limit reached or subagent wrote escalation):
    - If reject limit: write `plan/escalations/XXXXX-<phase>-reject-loop.md` using the escalation template and annotate the task
    - `taskwarrior/tw <id> stop` (if still active)
    - `taskwarrior/tw <id> modify +blocked`
    - `taskwarrior/tw <id> annotate "Escalation: plan/escalations/XXXXX-<phase>-slug.md"` (if not already annotated)
    - Return control to the PM with the escalation file path. Do not roll back git. Do not reopen upstream phases. Do not continue the loop.

15. All four tasks done. Run the full test suite from the project profile.

16. If tests pass: `git checkout main && git merge --squash story/XXXXX-slug && git commit -m "story: XXXXX-slug"`

17. If tests fail: write an escalation for the implementation phase, block the task, and return control to the PM (same halt behavior as step 14).

---

## 6. Git Policy

- **One branch per story**: `story/XXXXX-slug`, created from `main`.
- **Commit after each reviewed phase**: `git commit -am "phase(req): XXXXX"`, `phase(arch): XXXXX`, `phase(test): XXXXX`, `phase(impl): XXXXX`.
- **No automatic rollback on escalation**: escalations halt execution and return control to the PM; git state is preserved for human review.
- **Squash-merge to main**: when all four phases are done and the full test suite passes.
- **Planning artifacts on main**: PM commits milestone and story files to `main` directly.

---

## 7. Escalation Protocol

Escalations halt all AI work and surface the problem to the user. There is no automatic recovery loop.

1. **Trigger**: a subagent hits an impossible constraint, a contradiction it cannot resolve, or the Coordinator detects the 3rd plan-review or review rejection for the same phase.

2. **Report**: the subagent (or Coordinator on reject limit) writes `plan/escalations/XXXXX-phase-slug.md` using the escalation template, annotates the task with `Escalation: <path>`, and exits immediately. The subagent does not continue working after writing the escalation.

3. **Coordinator halt**: the Coordinator detects the `Escalation:` annotation or reject limit, calls `taskwarrior/tw <id> stop`, marks the task `+blocked`, and returns control to the PM with the escalation file path. No git rollback. No upstream phase reopening. No further subagent invocations.

4. **PM escalation**: the PM reads the escalation file, explains the situation and root cause to the user in chat, and **stops**. The PM waits for user direction before taking any further action (e.g. updating a story, writing a corrective story with Modifies Stories, or skipping the story).

The escalation-analysis subagent remains available for manual invocation by the user or PM when deeper diagnosis is needed. It is not part of the automatic Coordinator loop.

---

## 8. Artifact Definitions

### 8.1 Milestones (`plan/milestones/XX-name.md`)

High-level planning documents. Contain vision, goals, boundaries, epics, and done criteria. Updated by the PM as stories are generated and completed.

### 8.2 Stories (`plan/stories/XXXXX-slug.md`)

Problem-space documents describing vertical feature slices. Must include: goal (what and why), scope boundaries (in-scope and out-of-scope), trigger conditions, binary acceptance criteria, domain tags, dependencies, and non-goals. Stories describe user-facing behavior, not technical tasks.

Optional **Modifies Stories** section: when a new story changes or deprecates behavior from earlier stories, list the old story file paths and a brief reason. Old story files are never edited in place -- the new story carries the change intent. Downstream phase agents use this section to update or delete affected requirements, architecture artifacts, tests, and implementation.

### 8.3 Requirements (`plan/requirements/[domain]/XXXXX-name.md`)

Problem-space rules organized by domain. Translate the vertical story into categorized logic, constraints, and business rules. Must backlink to parent story IDs in **Parent Stories**. Contain no code, no class names -- only plain English descriptions of what the system must do.

When a later story modifies behavior covered by an existing requirement, the Requirements Write agent must either:
- **Update in place**: add the new story to **Parent Stories** (and **Also Modified By**), revise rules to reflect the new behavior
- **Delete**: remove the requirement file entirely when fully superseded (annotate the task with `Deleted: <path>`)

Updated or deleted requirements must remain traceable: surviving requirements list all stories that modified them in **Also Modified By**. Downstream architecture, test, and implementation phases must update artifacts to match.

### 8.4 Architecture Artifacts

Solution-space definitions. The exact form depends on the project profile:
- **C++**: header files in `include/[domain]/` -- declarations only, no implementation bodies. Each header lists the requirement IDs it satisfies in comments.
- **Python**: abstract base classes or typed interface modules in the directory specified by the project profile. Each ABC lists requirement IDs in docstrings.
- **Other languages**: as specified in the project profile.

The architecture artifact IS the architecture definition. There are no separate markdown architecture summaries.

### 8.5 Integration Tests (`tests/integration/` or as specified in profile)

Shift-left tests written BEFORE implementation. They enforce interface contracts by instantiating concrete classes across domains. Testing philosophy:
- Use real collaborator objects (Detroit/Chicago school)
- Only mock at true system boundaries: file I/O, network sockets, OS system calls, hardware contexts
- Never mock internal collaborators
- Tests must compile/parse against the architecture artifacts even before implementation exists

### 8.6 Phase Plans (`plan/*-plans/XXXXX-slug.md`)

Written by Plan agents. Specify what the Write agent should do: which files to create/modify, the approach, risks, and verification steps.

### 8.7 Plan Review Feedback (`plan/*-plan-review/XXXXX-feedback.md`)

Written by Plan Review agents when rejecting plans. Must contain: verdict, specific blocking issues referencing plan sections with fix instructions, missing coverage of acceptance criteria, and approved aspects (so the Plan agent knows what not to change on revision).

### 8.8 Review Feedback (`plan/*-review/XXXXX-feedback.md`)

Written by Review agents when rejecting artifacts. Must contain: verdict, specific blocking issues with file paths and fix instructions, missed requirements, and approved aspects (so the Write agent knows what not to change).

### 8.9 Escalation Reports (`plan/escalations/XXXXX-phase-slug.md`)

Written by any agent that cannot complete its task. Must contain: blocked task ID, failure description with exact errors, reproduction steps, root cause analysis pointing to the upstream artifact, and proposed recovery action.

### 8.10 Architecture Policy (`ARCHITECTURE.md`)

A living document at the project root maintained by the Architecture Plan agent. It acts as a domain dependency policy registry: it lists domain definitions and their strict dependency rules as a directed acyclic graph (DAG).

Rules:
- The Architecture Plan agent creates `ARCHITECTURE.md` when the first story introduces domains, and updates it whenever new domains or cross-domain dependencies are introduced.
- `ARCHITECTURE.md` must NEVER list classes, methods, function signatures, or internal design patterns. It is strictly a domain-level policy.
- Circular dependencies across domains are strictly prohibited.
- All architecture and implementation artifacts must comply with the dependency DAG. The Architecture Review and Implementation Review agents are the primary enforcement points.
- All agents read `ARCHITECTURE.md` to understand the domain structure and dependency constraints.

### 8.11 Discoveries (`plan/discoveries/YYYYMMDD-HHMMSS-slug.md`)

Discoveries are short records of significant out-of-scope findings noticed while an agent performs its assigned task. A discovery may describe a bug, gap, stub, design flaw, or risk that is not part of the current task and should be considered later.

Rules:
- Any subagent may write a new discovery file using `plan/templates/discovery.md`, then continue its current task.
- Subagents must never read, list, modify, deduplicate, delete, or act on existing discovery files. They are write-only for subagents.
- A discovery must not expand the current task scope, trigger implementation work, or replace the escalation protocol for blockers in the current task.
- Record only clear, obvious, significant, or otherwise worthy findings that meaningfully affect functionality, correctness, security, or performance. Do not record minor typos, trivial documentation gaps, cosmetic issues, or micro-optimizations.
- Discovery filenames use a timestamp plus a short slug, e.g. `20260614-151530-save-load-stub.md`, so agents can create unique files without reading the discovery directory.
- Only the PM reads and triages discoveries, and only after the milestone is otherwise complete.

---

## 9. Agent Invocation Contract

When the Coordinator invokes a subagent, it constructs a prompt with this structure:

```
You are the [Role] agent. Your task:
- Task ID: <taskwarrior-id>
- Story: plan/stories/XXXXX-slug.md
- Phase: <req|arch|test|impl>
- State: <plan|plan-review|write|review>
- Plan file: <path from annotation, if applicable>
- Plan feedback: <path from Plan-feedback annotation, if re-doing after plan-review rejection>
- Feedback: <path from Feedback annotation, if re-doing after review rejection>

Follow your role instructions. Read the files listed above. Write your outputs.
Update Taskwarrior when done.
```

The subagent reads its own agent definition file for role instructions, then reads the files listed in the prompt for task-specific context. This keeps each agent's context window small and focused.

---

## 10. Quality Standards

### 10.1 Review Principles

All review agents (plan-review and review) follow these principles:
- Focus on blocking issues: logic errors, missed requirements, incorrect contracts, test gaps
- Do NOT nitpick formatting, naming conventions, or style unless they cause actual confusion
- If it works and is structurally sound, approve it
- Every rejection must include exact file paths, line references, and concrete fix instructions
- Never rubber-stamp -- actually read and verify each artifact
- Limit to 3 review rounds per artifact; the Coordinator enforces this by counting rejections and writing an escalation on the 3rd rejection. Review agents write feedback on any rejection; they may also write an escalation as a belt-and-suspenders measure, but the Coordinator is the primary enforcer

### 10.2 Implementation Standards

Implementation agents must never:
- Hardcode expected test values to make tests pass
- Write empty method bodies or stub implementations
- Use mocks or fakes in production code
- Write code that only works for specific test inputs
- Skip error handling mentioned in requirements
- Add dependencies not justified by requirements
- Silently deviate from the architecture

If implementation is genuinely impossible given the architecture, the agent must escalate rather than silently working around the problem.

### 10.3 Domain Dependency Compliance

All architecture artifacts and implementation source files must respect the dependency DAG defined in `ARCHITECTURE.md`. Specifically:
- A source file or header in domain X may only import/include from domains listed as allowed dependencies of X.
- The Architecture Review agent must reject any artifact that introduces an unsanctioned dependency.
- The Implementation Review agent must reject any source file that imports from a domain not allowed by `ARCHITECTURE.md`.
- Requirements must not implicitly require cross-domain dependencies that violate the DAG.

### 10.4 Requirement Standards

Requirement agents must never:
- Leak solution-space concepts (class names, function signatures) into requirements
- Write requirements that are not traceable to a story
- Include implementation details or code examples

Requirements describe WHAT the system must do and its constraints, never HOW.

---

## 11. Extension Points

The framework is designed to be extended via the project profile. Downstream projects customize:

- **Language and build system**: affects architecture artifact type, test framework, build commands
- **Directory layout**: source, architecture, test, and build output directories
- **Test commands**: integration tests, full suite, lint/typecheck
- **Architecture conventions**: what architecture artifacts look like for this language
- **Mock boundaries**: what may be mocked in tests
- **Review standards**: project-specific quality requirements
- **Forbidden areas**: directories and actions agents must never touch
- **Domain tags**: valid categories for organizing requirements

Agent prompts read the project profile to adapt their behavior. The core workflow (phases, states, Taskwarrior protocol, git policy) remains fixed.

---

## 12. Discovery Protocol

Discoveries preserve important out-of-scope observations without derailing the current task.

1. **Trigger**: while performing its assigned task, any subagent notices a clear and significant bug, gap, stub, design flaw, or risk that is outside the current task scope.

2. **Record**: the subagent writes exactly one new file under `plan/discoveries/` using `plan/templates/discovery.md`. The filename must be `YYYYMMDD-HHMMSS-slug.md`.

3. **Do not inspect existing discoveries**: the subagent must not read, list, search, deduplicate, modify, or delete existing files in `plan/discoveries/`. Timestamp filenames avoid collisions without requiring a directory read.

4. **Continue current task**: after writing the discovery, the subagent continues its assigned task. It must not implement, plan, review, or otherwise act on the discovery unless the user later brings it into scope through the PM.

5. **PM triage**: once a milestone is otherwise complete, the PM reads all files in `plan/discoveries/`, groups duplicates and related findings, writes `plan/discoveries/triage-XX.md`, and summarizes proposed handling options for the user. The PM must wait for user direction before creating stories, deleting discoveries, deferring them, or creating a dedicated milestone.
