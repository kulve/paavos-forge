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

The framework is optimized for C++ projects but supports other languages (Python, TypeScript, etc.) through the project profile.

---

## 2. Roles

### 2.1 Project Manager (PM)

The top-level orchestrator. Talks to the user, defines milestones, generates stories in rolling batches, and invokes the Coordinator for each story. The PM never touches code.

### 2.2 Coordinator

A deterministic state machine that drives a single story through all four phases. The Coordinator is not creative -- it reads Taskwarrior state, decides which subagent to invoke next, manages git branches, and handles escalations. It never reads code or artifact content directly.

### 2.3 Phase Agents

Twelve specialized agents (4 phases x 3 states: plan, write, review) that produce and verify artifacts. Each has a narrow context window and strict input/output contracts.

### 2.4 Support Agents

Story Review and Escalation Analysis agents that assist the PM and Coordinator with quality assurance and failure diagnosis.

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
blocked -> plan -> write -> review -> done
                     ^         |
                     +--reject-+
```

- **blocked**: waiting for upstream phase to complete (managed by Taskwarrior dependencies)
- **plan**: the Plan agent reads context and writes a plan file
- **write**: the Write agent executes the plan or addresses review feedback
- **review**: the Review agent evaluates the artifacts
- **done**: the phase passed review; artifacts are committed

Review can return to write (rejection). After 3 rejections of the same phase, the Coordinator writes an escalation instead of retrying.

### 3.3 Taskwarrior UDAs

```
uda.aiphase.type=string
uda.aiphase.label=AI Phase
uda.aiphase.values=req,arch,test,impl

uda.aistate.type=string
uda.aistate.label=AI State
uda.aistate.values=blocked,plan,write,review,done

uda.aistory.type=string
uda.aistory.label=AI Story ID
```

### 3.4 Context Passing

Agents never talk to each other directly. All context passes through Taskwarrior annotations containing file paths:

- Plan agents annotate: `Plan: plan/requirement-plans/XXXXX-slug.md`
- Write agents annotate: `Artifact: plan/requirements/core/XXXXX-name.md`
- Review agents annotate: `Review: approved` or `Feedback: plan/requirements-review/XXXXX-feedback.md`
- Escalating agents annotate: `Escalation: plan/escalations/XXXXX-phase-slug.md`

The Coordinator reads these annotations to construct the next subagent's prompt. Annotations contain file paths only, never large text payloads.

---

## 4. PM Loop (Rolling Batches)

The PM does not generate all stories for a milestone upfront. It works in rolling batches:

1. **Milestone definition**: PM writes `plan/milestones/XX-name.md` containing high-level goals, epics, boundaries, and done criteria. PM discusses goals with user in chat; important decisions are captured in the milestone file.

2. **Story generation**: PM reads the milestone, existing stories, and codebase README, then writes the next 2-3 stories to `plan/stories/XXXXX-slug.md`. Stories are vertical feature slices, not horizontal technical layers.

3. **Story review**: PM invokes the story-review subagent for the batch. PM addresses feedback by updating story files directly. No re-review unless the reviewer flagged fundamental scope problems.

4. **Execution**: PM invokes the Coordinator subagent for each story, one at a time, in foreground. Stories are processed strictly in serial.

5. **Re-evaluation**: After stories merge to `main`, PM re-reads the codebase and milestone file. If milestone goals are met, PM discusses the next milestone with the user. If not, PM generates the next 2-3 stories and repeats.

6. **Git for planning artifacts**: PM commits milestone and story files to `main` directly, before invoking the Coordinator.

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

5. If no READY tasks and all are done, go to step 13.

6. Read the READY task's `aiphase` and `aistate`.

7. Determine subagent from the mapping:
   - `(req, plan)` -> `requirements-plan`
   - `(req, write)` -> `requirements-write`
   - `(req, review)` -> `requirements-review`
   - `(arch, plan)` -> `architecture-plan`
   - `(arch, write)` -> `architecture-write`
   - `(arch, review)` -> `architecture-review`
   - `(test, plan)` -> `integration-test-plan`
   - `(test, write)` -> `integration-test-write`
   - `(test, review)` -> `integration-test-review`
   - `(impl, plan)` -> `implementation-plan`
   - `(impl, write)` -> `implementation-write`
   - `(impl, review)` -> `implementation-review`

8. Construct the subagent prompt with: task ID, story file path, phase, current state, and relevant file paths from task annotations.

9. Invoke the subagent in foreground and wait for completion.

10. After the subagent completes, query Taskwarrior for updated state:
    - If review approved (annotation says `Review: approved`): set `aistate:done`, mark task done, commit phase artifacts: `git commit -am "phase(PHASE): XXXXX"`
    - If review rejected (feedback file annotated): set `aistate:write`; the feedback path is already annotated for the next write invocation
    - If escalation annotated: block the task, roll back git to the last phase commit (`git reset --hard`), reopen the upstream phase task to `write` state with the escalation file as context

11. **Loop end**: go to step 4.

12. If stuck in a reject loop (same phase rejected 3+ times): write an escalation report and return control to the PM.

13. All four tasks done. Run the full test suite from the project profile.

14. If tests pass: `git checkout main && git merge --squash story/XXXXX-slug && git commit -m "story: XXXXX-slug"`

15. If tests fail: write an escalation for the implementation phase and re-enter the loop.

---

## 6. Git Policy

- **One branch per story**: `story/XXXXX-slug`, created from `main`.
- **Commit after each reviewed phase**: `git commit -am "phase(req): XXXXX"`, `phase(arch): XXXXX`, `phase(test): XXXXX`, `phase(impl): XXXXX`.
- **Rollback on catastrophic failure**: `git reset --hard` to the last phase commit.
- **Squash-merge to main**: when all four phases are done and the full test suite passes.
- **Planning artifacts on main**: PM commits milestone and story files to `main` directly.

---

## 7. Escalation Protocol

There is no omnipotent escalation agent with global write access. Escalations are handled via state reversal:

1. **Trigger**: a downstream agent (e.g. implementation) hits an impossible constraint, a contradiction between requirements and architecture, or a loop it cannot resolve.

2. **Report**: the agent writes `plan/escalations/XXXXX-phase-slug.md` using the escalation template, annotates the task, and exits.

3. **Analysis**: the Coordinator optionally invokes the escalation-analysis subagent for a read-only diagnosis. This agent analyzes the report and adds recovery recommendations but never modifies code or requirements.

4. **Reversal**: the Coordinator rolls back the git branch to the last good phase commit.

5. **Recovery**: the Coordinator reopens the upstream phase task to `write` state, attaching the escalation file as primary context. The upstream agent re-runs with knowledge of what went wrong downstream.

6. **PM escalation**: if the Coordinator cannot resolve the escalation (e.g. the escalation points to a story-level problem), it returns control to the PM with the escalation report.

---

## 8. Artifact Definitions

### 8.1 Milestones (`plan/milestones/XX-name.md`)

High-level planning documents. Contain vision, goals, boundaries, epics, and done criteria. Updated by the PM as stories are generated and completed.

### 8.2 Stories (`plan/stories/XXXXX-slug.md`)

Problem-space documents describing vertical feature slices. Must include: goal (what and why), scope boundaries (in-scope and out-of-scope), trigger conditions, binary acceptance criteria, domain tags, dependencies, and non-goals. Stories describe user-facing behavior, not technical tasks.

### 8.3 Requirements (`plan/requirements/[domain]/XXXXX-name.md`)

Problem-space rules organized by domain. Translate the vertical story into categorized logic, constraints, and business rules. Must backlink to parent story IDs. Contain no code, no class names -- only plain English descriptions of what the system must do.

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

### 8.7 Review Feedback (`plan/*-review/XXXXX-feedback.md`)

Written by Review agents when rejecting artifacts. Must contain: verdict, specific blocking issues with file paths and fix instructions, missed requirements, and approved aspects (so the Write agent knows what not to change).

### 8.8 Escalation Reports (`plan/escalations/XXXXX-phase-slug.md`)

Written by any agent that cannot complete its task. Must contain: blocked task ID, failure description with exact errors, reproduction steps, root cause analysis pointing to the upstream artifact, and proposed recovery action.

### 8.9 Architecture Policy (`ARCHITECTURE.md`)

A living document at the project root maintained by the Architecture Plan agent. It acts as a domain dependency policy registry: it lists domain definitions and their strict dependency rules as a directed acyclic graph (DAG).

Rules:
- The Architecture Plan agent creates `ARCHITECTURE.md` when the first story introduces domains, and updates it whenever new domains or cross-domain dependencies are introduced.
- `ARCHITECTURE.md` must NEVER list classes, methods, function signatures, or internal design patterns. It is strictly a domain-level policy.
- Circular dependencies across domains are strictly prohibited.
- All architecture and implementation artifacts must comply with the dependency DAG. The Architecture Review and Implementation Review agents are the primary enforcement points.
- All agents read `ARCHITECTURE.md` to understand the domain structure and dependency constraints.

---

## 9. Agent Invocation Contract

When the Coordinator invokes a subagent, it constructs a prompt with this structure:

```
You are the [Role] agent. Your task:
- Task ID: <taskwarrior-id>
- Story: plan/stories/XXXXX-slug.md
- Phase: <req|arch|test|impl>
- State: <plan|write|review>
- Plan file: <path from annotation, if applicable>
- Feedback: <path from annotation, if re-doing after review>
- Escalation context: <path, if re-doing after escalation>

Follow your role instructions. Read the files listed above. Write your outputs.
Update Taskwarrior when done.
```

The subagent reads its own agent definition file for role instructions, then reads the files listed in the prompt for task-specific context. This keeps each agent's context window small and focused.

---

## 10. Quality Standards

### 10.1 Review Principles

All review agents follow these principles:
- Focus on blocking issues: logic errors, missed requirements, incorrect contracts, test gaps
- Do NOT nitpick formatting, naming conventions, or style unless they cause actual confusion
- If it works and is structurally sound, approve it
- Every rejection must include exact file paths, line references, and concrete fix instructions
- Never rubber-stamp -- actually read and verify each artifact
- Limit to 3 review rounds per artifact; after 3 rejections, escalate

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
