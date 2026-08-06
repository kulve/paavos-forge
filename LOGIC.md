# Paavo's Forge -- Canonical Workflow Specification

This document is the single source of truth for Paavo's Forge. All agent prompts, rules, templates, and deployment docs reference this file. If there is a conflict between this document and any other file, this document wins.

---

## 1. Core Philosophy

Paavo's Forge turns pinned product intent into tested changes through a project roadmap, isolated parallel epics, serial stories, narrow agent contexts, Taskwarrior state, and script-enforced gates. Integration tests precede implementation. Only one PM and one Coordinator per worktree may run at once.

The workflow is language-agnostic: language, layout, build, test, and architecture-artifact conventions live in the project profile. Paavo's Codex is the hard product-intent dependency (Section 16).

---

## 2. Roles

| Role | Owns / may read | Must not do |
|------|-----------------|-------------|
| PM (`/project-manager` skill) | Roadmap, milestones, epics, stories, Paavo's Codex; main tree | Read or edit code, tests, requirements, or architecture artifacts |
| Coordinator | One epic's Taskwarrior state and dispatch; worktree | Read artifact content or Paavo's Codex |
| Requirements agents | Problem-space requirements and pinned Paavo's Codex | Read source, tests, or architecture artifacts |
| Architecture agents | Interfaces, requirements, DAG | Read source or tests |
| Test agents | Integration tests, requirements, interfaces | Read implementation source |
| Implementation agents | Source, tests, interfaces, requirements | Access Paavo's Codex |
| Roadmap Planner / Story Review | Roadmap or story quality | Enter the Coordinator phase pipeline |
| Escalation Triage / Environment Recovery | Classification or Forge repair | Respectively write artifacts / run outside the closed whitelist |
| Escalation Recovery | Bounded cross-phase correction | Change intent, task state, or unbounded scope |
| Fixer | Existing source and tests outside the pipeline | Add features, interfaces, requirements, or Taskwarrior state |

Architecture and implementation have plan, write, and review agents; requirements and tests have write and review agents. There are no plan-review agents. Paavo's Codex access and recovery details are defined in Sections 9 and 16.

### 2.1 Locks

- The main tree has one `+AI_LOCK airole:pm`, managed by `pm-lock-acquire` / `pm-lock-release`.
- Each epic worktree has one `+AI_LOCK airole:coordinator`, managed by `coordinator-lock-*`.
- A duplicate PM or Coordinator reports read-only status and exits. Agents never clear stale locks; only the user may run `cleanup-ai-state.sh`.

---

## 3. State Machine

### 3.1 Hierarchy

```
Project (mandatory: plan/project.md — pins Paavo's Codex version + milestone roadmap)
└── Milestone (derived from roadmap; Status: Done | In Progress | TODO)
    └── Epic (parallel execution, one worktree per epic)
        └── Story (serial execution within epic)
            └── Phase tasks (req → arch → test → impl)
```

The Project layer is mandatory; every milestone traces to `plan/project.md`.

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

#### Story rigor

Every story declares a `## Rigor` in its story file, `full` or `light`, set by the PM and enforced by `story-review`. `story-init` reads it as `--rigor`.

- **`full`** (default) runs all four phases: 10 dispatches.
- **`light`** runs the implementation phase only -- write plus review, skipping even the implementation plan: 2 dispatches.

A story qualifies as `light` only if **all three** of these hold; any one false makes it `full`:

1. No new or changed architecture artifact.
2. No new integration test needed; existing tests already cover the behavior.
3. No new product intent -- `## Product Intent Source` cites a discovery rather than a Paavo's Codex article, using the `None -- [reason]` form.

The tests are objective so `light` cannot become a size judgment. A light-story write agent that finds a wider change escalates; the reconciler or PM reissues it as `full`.

#### Phase tasks

A full story spawns four Taskwarrior tasks, one per phase, with explicit dependencies; a light story spawns only the `impl` task, at `aistate:write`:

```
requirements --> architecture --> integration_tests --> implementation
```

Each task transitions through states:

```
blocked -> [plan] -> write -> review -> gate -> done
                       ^         |
                       +--reject-+
```

- **blocked**: waiting for upstream phase to complete (managed by Taskwarrior dependencies)
- **plan**: the Plan agent reads context and writes a plan file. **Present only for the `arch` and `impl` phases.** The `req` and `test` tasks start directly at `write`.
- **write**: the Write agent executes the plan (or, for `req` and `test`, plans and executes) or addresses review feedback
- **review**: the Review agent evaluates the produced artifacts
- **gate**: an executable check from the project profile, run by the Coordinator between review approval and `done` (Section 5.1)
- **done**: the phase passed both review and its gate; artifacts are committed

Per-phase initial state, set by `story-init` and restored by `phase-done` when it opens the successor task:

| Phase | Initial state |
|-------|---------------|
| `req` | `write` |
| `arch` | `plan` |
| `test` | `write` |
| `impl` | `plan` |

Review can return to write (rejection), and only blocking findings do so (Section 13.1). After 3 rejections of the same phase the Coordinator escalates instead of retrying.

`done` is terminal: no transition leaves it. Corrections to a completed phase are made by the reconciler in Section 9, which edits the artifact and re-runs the invalidated gates rather than reopening the task.

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
uda.aistate.values=blocked,plan,write,review,done

uda.aistory.type=string
uda.aistory.label=AI Story ID

uda.airole.type=string
uda.airole.label=AI Role Lock
uda.airole.values=coordinator
```

### 3.5 Context Passing

Agents never talk to each other directly. All context passes through Taskwarrior annotations containing file paths:

- Plan agents annotate: `Plan: plan/arch-plans/XXXXX-slug.md`
- Write agents annotate: `Artifact: plan/requirements/core/XXXXX-name.md`
- Review agents annotate: `Review: approved` or `Feedback: plan/requirements-review/XXXXX-feedback.md`
- Escalating agents annotate: `Escalation: plan/escalations/XXXXX-phase-slug.md`

The Coordinator reads these annotations (via `story-next` script output) to construct the next subagent's prompt. Annotations contain file paths only, never large text payloads.

---

## 4. PM Loop (Parallel Epic Dispatch)

The PM operates in the main project tree. It owns the project roadmap, defines milestones from that roadmap, and dispatches epics for parallel execution.

0. **Paavo's Codex hard dependency**: Before any planning or execution work, the PM verifies the Paavo's Codex MCP is reachable (using Cursor MCP discovery / a lightweight tool call). If unreachable, the PM stops all Forge work and reports to the user. This is a hard stop -- already-planned work must not continue while product intent is unavailable. See Section 16.

1. **Project init**: If `plan/project.md` does not exist, the PM invokes the `roadmap-planner` subagent (foreground, human-in-loop). The planner synthesizes a milestone roadmap from Paavo's Codex and writes `plan/project.md`, pinning the Paavo's Codex project id and a closed version. The PM discusses refinements with the user, then commits `plan/project.md` to `main`. Project init must complete before any milestone is created.

2. **Milestone definition**: PM writes `plan/milestones/XX-name.md` for the current In-Progress (or next TODO) roadmap entry. The milestone must be traceable to `plan/project.md`. It contains high-level goals, epic list, boundaries, Status, and done criteria. Important decisions from chat are captured in the milestone file. Mark the matching roadmap entry In Progress; at most one milestone is In Progress at a time.

3. **Epic definition**: PM writes `plan/epics/EXXXX-slug.md` containing goal, boundaries, ordered story list, done criteria, and epic dependencies. Epics are coherent feature areas that can execute independently.

4. **Story generation**: PM reads the epic, existing stories, and codebase README, then writes the next 2-3 stories to `plan/stories/XXXXX-slug.md`. Stories are vertical feature slices, not horizontal technical layers. Every story records its **Product Intent Source**: the Paavo's Codex project id, the pinned closed version it was authored against, and the article ids it derives from (Section 16.4). When new behavior conflicts with or replaces behavior from an earlier story, the new story must include a **Modifies Stories** section.

5. **Story review**: PM invokes the story-review subagent for the batch. PM addresses feedback by updating story files directly.

6. **Epic dispatch**: PM runs the preflight check and forks the epic:
   ```
   bash taskwarrior/pm-preflight
   bash taskwarrior/epic-fork EXXXX slug
   ```
   The fork script checks the merge gate, creates the worktree, initializes Taskwarrior, and registers the epic. Preflight for the PM also includes the Paavo's Codex reachability check from step 0.

7. **Coordinator invocation**: PM launches a Coordinator subagent with `run_in_background: true`. Subagents cannot be given a working directory, so the Coordinator starts in the main tree: its prompt must carry the absolute worktree path and the invariant that every Forge script is invoked as `bash <worktree>/taskwarrior/<script>`. The Coordinator runs its Startup Assertion before any other work.

8. **Parallel dispatch**: PM may repeat steps 3-7 for additional independent epics. Multiple epics execute simultaneously in their own worktrees.

9. **Supervision**: PM supervises background Coordinators through the aggregator and acts on its exit code (Section 17):
   ```
   bash taskwarrior/coordinator-status
   bash taskwarrior/epic-status
   ```
   The PM must never infer Coordinator progress from agent transcripts.

10. **Epic completion**: When a Coordinator signals that all stories are done (epic becomes merge-ready):
    ```
    bash taskwarrior/epic-mark-ready EXXXX
    ```

11. **Merge**: PM merges completed epics to main:
    ```
    bash taskwarrior/epic-merge EXXXX
    ```
    If exit 1 (gate blocked): another merge in progress, wait and retry.
    If exit 2 (conflict): report to user, suggest `epic-rebase`.

12. **Re-evaluation**: After epic merge, PM re-reads the milestone file and `plan/project.md`. If milestone done criteria are met:
    - Mark the milestone Status Done (immutable history) in both the milestone file and the roadmap entry in `plan/project.md`
    - Perform discovery triage on whatever accumulated since the last story batch (Section 15)
    - Invoke `project-profile-maintainer` (foreground) with the completed milestone path and the git range on `main` since the previous milestone Done commit (or project init if first). That agent is the only post-deploy writer of `paavos-forge/project-profile.md`; it fills deferred knobs and corrects stale ones from milestone evidence, or reports `no-change`
    - Advance the next TODO roadmap entry to In Progress, or rewrite/reorder remaining TODO milestones (optionally re-invoke `roadmap-planner`) based on Paavo's Codex and user direction
    - If the product Definition of Done in `plan/project.md` is met, declare the product complete
    - **Version migration**: if Paavo's Codex has a newer closed version the user wants to adopt, the PM re-pins `plan/project.md` to the new version, scopes changes via the MCP per-step change/diff tools (one call per version step), and inserts one or more **migration milestones** (Status TODO / In Progress as appropriate) before continuing normal roadmap work
    - Commit planning artifacts and `paavos-forge/project-profile.md` together on the milestone closeout

13. **Git for planning artifacts**: PM commits project, milestone, epic, and story files to `main` directly, before dispatching the epic.

14. **Escalation received**: A Coordinator that returns due to escalation has already tried inline recovery (Section 9.0), so what reaches the PM is what the reconciler could not settle. PM reads the escalation file, verifies the Coordinator lock is inactive (via worktree status), then invokes `escalation-triage` in the foreground and routes by class per Section 9.1. If a handler resolves it, PM clears the block with `phase-resume` and launches a fresh Coordinator for the same epic.

15. **Discovery triage**: Once a milestone is otherwise complete (all epics merged), the PM reads `plan/discoveries/`, groups findings, writes `plan/discoveries/triage-XX.md`, and summarizes proposed handling for the user. Product-intent gaps that belong in Paavo's Codex are surfaced as open questions there (Section 16), not as local discoveries.

---

## 5. Coordinator Loop

The Coordinator drives all stories within a single epic through all four phases. It operates on one epic worktree, addressing it by absolute path.

0. **Startup assertion**: first confirm a subagent-dispatch tool is available; without it the Coordinator was launched at the wrong nesting depth (Section 11.5) and cannot do its only job. Then bind `WT` to the absolute worktree path from the prompt and confirm `bash "$WT/taskwarrior/coordinator-lock-status"` prints FREE and exits 0. Abort and report to the PM (do not escalate, there is no story state yet) if dispatch is unavailable, the path is missing, the script exits 2, or the lock is HELD. Abort before any state mutation: no lock acquisition, no `story-init`, no escalation file. Every subsequent script call uses `bash "$WT/taskwarrior/<script>"`; the Coordinator never `cd`s and never uses a relative script path.

1. Read the epic file to get the ordered story list.

2. Acquire Coordinator lock:
   ```
   bash "$WT/taskwarrior/coordinator-lock-acquire"
   ```
   If exit 1 (already held): report and exit as duplicate. If exit 2: wrong context, abort and report to the PM.

3. **For each story in the epic** (serial, in order):

4. Read the story file's `## Rigor` field -- the only content the Coordinator reads from a story file -- and initialize its tasks:
   ```
   bash "$WT/taskwarrior/story-init" XXXXX slug --rigor <full|light>
   ```
   `full` creates four phase tasks; `light` creates only the `impl` task, at `aistate:write` (Section 3.3). A missing or unreadable field means `full`.

5. **Story loop start**: Query next actionable task:
   ```
   bash "$WT/taskwarrior/story-next" XXXXX
   ```

6. If output is "NONE" and all tasks complete, go to step 14.

7. Read the task's `phase` and `state` from the JSON output.

8. Determine subagent from the mapping. `plan` exists only for `arch` and `impl`:
   - `(req, write)` -> `requirements-write`
   - `(req, review)` -> `requirements-review`
   - `(arch, plan)` -> `architecture-plan`
   - `(arch, write)` -> `architecture-write`
   - `(arch, review)` -> `architecture-review`
   - `(test, write)` -> `integration-test-write`
   - `(test, review)` -> `integration-test-review`
   - `(impl, plan)` -> `implementation-plan`
   - `(impl, write)` -> `implementation-write`
   - `(impl, review)` -> `implementation-review`

9. Construct the subagent prompt with: task ID, story file path, phase, current state, and relevant file paths from task annotations.

10. Start the phase task:
    ```
    bash "$WT/taskwarrior/phase-start" <task-id>
    ```
    If exit 1 (another task active): stop and investigate.

11. Invoke the subagent in foreground and wait for completion.

12. Stop the phase task:
    ```
    bash "$WT/taskwarrior/phase-stop" <task-id>
    ```

13. Process outcome. Track one reject counter per phase:
    - If a plan was written (annotation says `Plan:`): state is already `write`, continue loop
    - If review approved (annotation says `Review: approved`): run the phase gate (Section 5.1) and only then call `bash "$WT/taskwarrior/phase-done" <uuid>`, commit phase artifacts: `git commit -am "phase(PHASE): XXXXX"`; reset the reject counter. `phase-done` opens the successor phase task at its initial state
    - If review rejected (feedback file annotated): state is already `write`; increment the reject counter; if the counter reaches 2, dispatch the reconciler (Section 9); otherwise continue loop
    - If escalation annotated: dispatch the reconciler (Section 9); go to step 15 only if it returns `needs-human`

    Task identity: use the `uuid` from `story-next`, never the numeric `id`. Taskwarrior renumbers pending ids whenever a task completes, so an id captured before a `phase-done` points at a different task after it.

    **Story loop end**: go to step 5.

14. **Story complete** -- every phase done, four for a full story or one for a light one. Verify and merge within worktree:
    ```
    bash "$WT/taskwarrior/story-complete" XXXXX --run-tests
    bash "$WT/taskwarrior/story-merge" XXXXX slug
    ```
    If tests fail: write an escalation for the implementation phase, block the task, and go to step 15.
    Otherwise: proceed to the next story in the epic (go to step 4 with next story).

15. **Escalation halt** (reject limit reached or subagent wrote escalation):
    - If reject limit: write `plan/escalations/XXXXX-<phase>-reject-loop.md` using the escalation template and annotate the task
    - Block the task: `bash "$WT/taskwarrior/phase-block" <task-id> <escalation-path>`
    - Release the Coordinator lock: `bash "$WT/taskwarrior/coordinator-lock-release"`
    - Return control to the PM with the escalation file path. Do not roll back git. Do not reopen upstream phases. Do not continue the loop.

16. **All stories done**: Release Coordinator lock:
    ```
    bash "$WT/taskwarrior/coordinator-lock-release"
    ```
    Signal completion (the PM detects this via `epic-status` or checks the worktree state).

### 5.1 Phase Gates

A review approval is a judgement about text. It cannot catch two artifacts that are each individually reasonable and jointly contradictory, because no reviewer sees both against a compiler. Every phase therefore has a second completion condition that a command either satisfies or does not:

```
bash "$WT/taskwarrior/phase-gate" <uuid>
```

The Coordinator runs it after `Review: approved` and before `phase-done`. Exit 0 completes the phase; exit 2 routes to the reconciler in Section 9 exactly as an escalation does, with the gate output as the failure description.

Gate per phase, resolved from `paavos-forge/project-profile.md`:

| Phase | Profile line | What it proves |
|-------|--------------|----------------|
| `req` | none | Prose has nothing to compile; review is the only gate. |
| `arch` | `Architecture gate` | The architecture artifacts compile or typecheck standalone, without linking. |
| `test` | `Test compile gate` | The integration tests compile against the architecture with no implementation present. |
| `impl` | `Run integration tests` | The tests written in the `test` phase now pass. |

An unfilled placeholder skips its gate with a warning rather than failing, so an incompletely filled profile degrades to the pre-gate behaviour instead of blocking the pipeline.

The integration test phase is red-gated: the tests must compile **and** the named tests must fail. A green suite before any implementation exists means the tests do not constrain anything. The compile half is the gate; whether the failure is for the right reason is the reviewer's judgement, made against the gate's actual output rather than by reading the file.

---

## 6. Git Policy

- **One worktree per epic**: created from `main` via `epic-fork`, named `epic/EXXXX-slug`.
- **One branch per story within the worktree**: `story/XXXXX-slug`, created from the epic branch.
- **Commit after each reviewed phase**: `git commit -am "phase(req): XXXXX"`, `phase(arch): XXXXX`, `phase(test): XXXXX`, `phase(impl): XXXXX`.
- **Squash-merge story to epic branch**: when all four phases are done and tests pass.
- **Squash-merge epic to main**: when all stories are done, via `epic-merge` with merge gate.
- **Planning artifacts on main**: PM commits project, milestone, epic, and story files to `main` directly.
- **No automatic rollback on escalation**: escalations halt the Coordinator and return control to the PM; git state is preserved for recovery.

---

## 7. Merge Gate Protocol

`setup.sh --main` creates the permanent `+MERGE_GATE` task. `epic-merge` acquires and releases it around a squash merge; `epic-fork` exits 1 while it is held. Thus only one merge runs and no worktree forks during a merge. The PM never manipulates the gate directly. A user may inspect it with `epic-gate-status` and, only after confirming no merge runs, release a stale gate with `epic-gate-release --force`.

---

## 8. Epic Lifecycle

1. PM writes and commits `plan/epics/EXXXX-slug.md` and its stories, then runs `epic-fork EXXXX slug`. The script creates `.worktrees/epic-EXXXX-slug/`, initializes its Taskwarrior database, and marks the epic active.
2. PM launches a Coordinator for that worktree; it processes stories serially.
3. When the Coordinator finishes, PM runs `epic-mark-ready EXXXX`, then `epic-merge EXXXX`. The merge script gates, squash-merges, removes the worktree, and marks the epic merged.
4. Exit 2 from `epic-merge` marks a conflict. PM may run `epic-rebase EXXXX` or route manual resolution; successful rebase restores `merge-ready`.

Parallelism is bounded by disk, agent context, and merge-conflict risk; the project profile may recommend a limit.

---

## 9. Escalation Protocol

Most failures are two artifacts disagreeing, which is a technical problem with a technical answer. The Coordinator therefore repairs them inline (9.0) and halts only when repair is impossible or the decision is genuinely the user's. Stopping for the user is a routing outcome for product decisions, not the default response to failure.

### 9.0 Inline Recovery (the normal path)

The Coordinator dispatches `escalation-recovery` in the foreground, while holding its lock, on any of three triggers:

- a subagent wrote an `Escalation:` annotation,
- a `phase-gate` exited 2,
- the same phase was rejected by review for the **2nd** time.

The reconciler may edit any story artifact, including one belonging to a completed phase. It returns `resolved` with a list of **invalidated gates**, `needs-human`, or `failed-recovery`. On `resolved` the Coordinator re-runs those gates and continues the same phase; the completed task stays completed and nothing is re-opened. Returning a resume state instead is what produced the `Illegal transition done -> review` deadlock this protocol replaced.

Domain disposition mismatches (architecture-plan rejects a Proposed Domain Tag and requires requirement refile under a surviving domain) are ordinary `artifact` contradictions. The normal path is this inline recovery, not a human halt and not reopening the requirements task (Section 10.10).

Only `needs-human`, `failed-recovery`, a gate that fails again after a fix, or a recurrence of the same cause reaches the halt below. One reconciliation attempt per cause.

### 9.1 Escalation Halt (the exception path)

1. **Trigger**: inline recovery could not resolve the failure, the Coordinator detects the 3rd review rejection for the same phase, the Paavo's Codex MCP is unreachable when required, or a product-intent gap cannot be resolved from the pinned Paavo's Codex version (blocking). Non-blocking product-intent gaps may instead be posted as open questions to Paavo's Codex (Section 16) without escalating.

2. **Report**: the subagent (or Coordinator on reject limit) writes `plan/escalations/XXXXX-phase-slug.md` using the escalation template, annotates the task with `Escalation: <path>`, and exits immediately. The subagent does not continue working after writing the escalation.

3. **Coordinator halt**: the Coordinator blocks the task via `bash taskwarrior/phase-block <uuid> <path>`, releases the Coordinator lock via `bash taskwarrior/coordinator-lock-release`, and returns control to the PM, reporting the reconciler's outcome alongside the escalation path. No git rollback.

4. **Triage**: the PM first verifies the Coordinator lock is FREE in the epic's worktree:
   ```
   bash <worktree>/taskwarrior/coordinator-lock-status    # must show FREE
   ```
   If the lock is HELD, the PM does not recover and does not triage: it reports and waits for the user. Otherwise the PM invokes `escalation-triage` in the foreground. Triage is read-only and returns a fixed block with `Class`, `Confidence`, `Root cause`, `Doctor findings`, `Blast radius`, `Proposed handler`, `Verification`, and `Fingerprint`.

   Routing is mechanical:

   | Class | Handler | Rationale |
   |-------|---------|-----------|
   | `environment` | `environment-recovery` | Forge state, configuration, or runtime damage. Mechanical, so no user decision exists to make. |
   | `artifact` | `escalation-recovery` | Story-local inconsistency between requirements, architecture, tests, or source. Rare at this point: the Coordinator already tried it inline. |
   | `product-intent` | user (or a Paavo's Codex open question) | The required behavior is missing or contradictory. **Always stops for the user.** |
   | `scope-policy` | user | Widening story scope, adding an external dependency, or creating/skipping a story or phase. **Always stops for the user.** Technical design -- interfaces, decomposition, fixtures, code -- is not in this class. |

   Any `Confidence: low` result routes to the user regardless of class.

   **One attempt per fingerprint**: before dispatching to an automated handler, the PM checks the blocked task's annotations for the triage fingerprint. If an annotation already contains the same `fp=<fingerprint>`, the same root cause has already been attempted: route to the user instead of retrying. The PM records each attempt as
   ```
   bash <worktree>/taskwarrior/phase-annotate <id> Recovery "attempt <n> class=<class> fp=<fingerprint>"
   ```
   This makes the repeated-root-cause stop condition mechanical rather than a judgment call.

5. **Bounded recovery**: the PM invokes the handler from step 4 in the foreground, passing the absolute worktree path, the escalation path, the blocked task's **uuid**, the story path, and the triage block. Subagents receive no working directory, so every path must be absolute or explicitly relative to the given worktree. Both recovery agents return one of:
   - `resolved`: `escalation-recovery` includes the list of gates its change invalidated; `environment-recovery` includes a recorded clean `doctor` run (exit 0)
   - `needs-human`: explains the decision required
   - `failed-recovery`: explains why its attempted fix did not resolve the blocker

6. **PM state restoration**: if recovery returns `resolved`, the PM clears the block and leaves the task in the state it was already in:
   ```
   bash <worktree>/taskwarrior/phase-resume <uuid> "<summary>"
   ```
   `phase-resume` is the counterpart to `phase-block`: it clears `+blocked` and annotates. `phase-transition` does **not** clear `+blocked` -- it only changes `aistate` -- so a task recovered without `phase-resume` never becomes READY again.

7. **Resume**: PM launches a fresh Coordinator for the same epic in the background (see Section 17). The Coordinator picks up from the restored task state. The old Coordinator is never resumed.

8. **Human stop conditions**: PM stops and asks the user when a decision is **irreversible**, is about **product intent**, or **exceeds the current milestone's scope**. Concretely: changing story intent, widening acceptance criteria, adding a new external dependency, creating or skipping stories, skipping phases, adopting a new Paavo's Codex version or rewriting product goals, or resolving a root cause whose fingerprint has already been attempted.

   Technical design is explicitly **not** a stop condition. Interfaces, decomposition, module boundaries, test fixtures, and code are the agents' to decide, and asking the user to approve them is the failure mode this rule exists to prevent -- a user asked to approve a struct field is a user who stops reading. Milestone completion is the natural checkpoint, not each technical choice inside one.

   Runtime-state cleanup remains user-only exactly where `taskwarrior/doctor` marks a check manual: D07 (`.taskrc` tracked by git), D09 (multiple active phase tasks in a worktree), D10 (a held Coordinator lock with a stale, dead, or missing heartbeat), D11 (an active epic with no worktree), and D12 (blocked task / escalation file mismatch). Checks that `doctor` marks fixable are not human stop conditions: `environment-recovery` repairs them through `doctor --fix`. No agent may ever clear a lock or an orphaned active task; that is `cleanup-ai-state.sh`, run by the user.

---

## 10. Artifact Definitions

### 10.0 Projects (`plan/project.md`)

Mandatory living document owned by the PM (produced by the Roadmap Planner). Pins the Paavo's Codex project identity and a closed integer version, states the product vision and product-level Definition of Done, and lists an ordered milestone roadmap. Each roadmap entry has Status `Done` (immutable), `In Progress` (at most one), or `TODO` (freely rewritable on re-evaluation). Near milestones are detailed; far milestones may be brief bullets. Includes a Version Migration Log when the pinned Paavo's Codex version changes.

### 10.1 Milestones (`plan/milestones/XX-name.md`)

High-level planning documents derived from the project roadmap. Contain a backlink to `plan/project.md`, Status (`Done` / `In Progress` / `TODO`), vision, goals, boundaries, epic list, and done criteria. Updated by the PM as epics are generated and completed. **Migration milestones** are a special kind used when adopting a newer Paavo's Codex version: their scope is the product-intent delta between the old and new pinned versions (scoped via MCP per-step change/diff tools).

### 10.2 Epics (`plan/epics/EXXXX-slug.md`)

Coherent feature areas decomposed into ordered stories. Contain goal, boundaries, ordered story list, done criteria, and inter-epic dependencies. Each epic is the unit of parallel execution -- it gets its own git worktree.

### 10.3 Stories (`plan/stories/XXXXX-slug.md`)

Problem-space documents describing vertical feature slices. Must include: epic reference, product intent source, goal (what and why), scope boundaries, trigger conditions, binary acceptance criteria, **Proposed Domain Tags**, dependencies, and non-goals. Stories describe user-facing behavior, not technical tasks.

**Proposed Domain Tags** are proposals for requirement organization, drawn from the project profile's Domain Tags allowlist. They are not committed DAG membership. Committed domains live in `ARCHITECTURE.md` after the architecture-plan gatekeeper runs (Section 10.10). Story tags are left as historical proposals even when recovery refiles requirements under different domain folders.

Mandatory **Product Intent Source** section: the story's citation of the Paavo's Codex articles it derives from. It records the Paavo's Codex project id, the closed version the story was authored against, and one line per source article (id, title at that version, domain id). Article ids are stable across versions while titles are not, so the id is the identity and the title is only a human label. The version is recorded per story even though `plan/project.md` pins it: project.md is re-pinned over time, while a completed story is a historical record of the intent it was written against. When no single article backs the story -- intent synthesized across a whole domain, Forge scaffolding, and similar cases -- the section states `None -- [reason]` so the absence is a deliberate, reviewable claim rather than an omission. See Section 16.4.

Optional **Modifies Stories** section: when a new story changes or deprecates behavior from earlier stories, list the old story file paths and a brief reason.

### 10.4 Requirements (`plan/requirements/[domain]/XXXXX-name.md`)

Problem-space rules organized by domain. Translate the vertical story into categorized logic, constraints, and business rules. Must backlink to parent story IDs. Contain no code, no class names -- only plain English descriptions.

When a later story modifies behavior covered by an existing requirement, the Requirements Write agent must either:
- **Update in place**: add the new story to traceback, revise rules
- **Delete**: remove the requirement file when fully superseded

### 10.5 Architecture Artifacts

Solution-space interface definitions: declarations and signatures only, with no implementation bodies. The artifact type, location, and requirement-traceability syntax are defined by the project profile (for example, C++ header files under `include/[domain]/`, Python abstract base classes, TypeScript interfaces, or Rust trait definitions).

### 10.6 Integration Tests (`tests/integration/` or as specified in profile)

Shift-left tests written BEFORE implementation. They enforce interface contracts by instantiating concrete classes across domains. Testing philosophy:
- Use real collaborator objects (Detroit/Chicago school)
- Only mock at true system boundaries: file I/O, network sockets, OS system calls, hardware contexts
- Never mock internal collaborators
- Tests must compile/parse against the architecture artifacts even before implementation exists

These contract tests are distinct from the **verification tooling** the implementation agent builds and runs during the impl phase (state inspection, scenario checks, screenshot capture -- see Section 13.2). Contract tests constrain the implementation up front; verification tooling lets the implementation agent confirm the feature actually works while building it.

### 10.7 Phase Plans (`plan/*-plans/XXXXX-slug.md`)

Written by the Architecture Plan and Implementation Plan agents, in `plan/arch-plans/` and `plan/implementation-plans/` respectively. Specify what the Write agent should do: which files to create/modify, the approach, risks, and verification steps. Plans are not reviewed, so they must be concrete enough to execute without further interpretation. The requirements and integration-test phases have no plan artifact.

### 10.8 Review Feedback (`plan/*-review/XXXXX-feedback.md`)

Written by Review agents when rejecting artifacts. Must contain: verdict, specific blocking issues each carrying an anchor, a file path, and a fix instruction, missed requirements, non-blocking observations, and approved aspects.

### 10.9 Escalation Reports (`plan/escalations/XXXXX-phase-slug.md`)

Written by any agent that cannot complete its task. Must contain: blocked task ID, failure description with exact errors, reproduction steps, root cause analysis, and proposed recovery action. Proposed recovery describes which artifacts to edit in place; it must not ask to reopen a completed phase task (Section 9.0). Domain-disposition escalations also include a **Domain Disposition** block listing proposed-domain → surviving-domain mappings and the requirement paths to refile.

### 10.10 Architecture Policy (`ARCHITECTURE.md`)

A living document at the project root maintained by the Architecture Plan agent. It is the committed domain vocabulary and dependency policy for the project. Must NEVER list classes, methods, function signatures, or internal design patterns.

**Domain vocabulary lifecycle** (one shared vocabulary):

1. **Propose** -- the story lists `## Proposed Domain Tags` from the profile allowlist.
2. **File** -- requirements-write places requirement files under `plan/requirements/[domain]/` using those names (folders may exist before the domain is committed in this file).
3. **Commit or escalate** -- architecture-plan is the gatekeeper. For every domain that has requirement files for the current story it must either already appear here or be committed by this plan. Prefer introducing a real domain over expanding `core`. Silent fold (satisfying a proposed domain by appending prose to another domain without refiling) is forbidden. When a proposal cannot be committed, architecture-plan writes an escalation with a **Domain Disposition** and exits; inline `escalation-recovery` refiles the requirements (class `artifact`). Completed phase tasks stay completed.
4. **Consume** -- later agents use only the committed domains and DAG in this file. Story Proposed Domain Tags remain historical proposals.

**Per-domain policy schema** (under Domain Definitions). Each domain uses these fields, kept consistent with the Strict Dependency Rules DAG:

- **Owns** -- responsibilities and concern areas (no types or APIs)
- **Does not own** -- explicit exclusions
- **May depend on** -- allowed upstream domains (empty for a root such as `core`)
- **Artifacts under** -- path prefix consistent with the project-profile directory layout

The Strict Dependency Rules section summarizes the DAG; circular dependencies across domains are prohibited.

### 10.11 Discoveries (`plan/discoveries/YYYYMMDD-HHMMSS-slug.md`)

Short records of significant findings, and the destination for every advisory review finding. Any subagent may create one; only the PM triages, at the start of each story batch and again at milestone completion.

---

## 11. Agent Invocation Contract

When the Coordinator invokes a subagent, it constructs a prompt with this structure:

```
You are the [Role] agent. Your task:
- Task ID: <taskwarrior-id>
- Story: plan/stories/XXXXX-slug.md
- Epic: plan/epics/EXXXX-slug.md
- Phase: <req|arch|test|impl>
- State: <plan|write|review>
- Plan file: <path from the Plan annotation, if applicable>
- Feedback: <path from Feedback annotation, if re-doing after review rejection>

Follow your role instructions. Read the files listed above. Write your outputs.
Update Taskwarrior via scripts when done.
```

The subagent reads its own agent definition file for role instructions, then reads the files listed in the prompt for task-specific context.

**Never pass a `model` parameter when invoking a subagent.** Each agent's model is pinned in its own prompt frontmatter, assigned by bucket at deploy time. A `model` argument supplied by the invoking agent overrides that frontmatter, which silently replaces a deliberate cost-and-capability assignment with whatever the parent happened to be running. This applies to every invocation in Forge: the Coordinator dispatching phase agents, and the PM launching Coordinators, `roadmap-planner`, `story-review`, and the escalation agents. The PM itself is a skill and has no frontmatter model; it runs on whatever model the top-level chat is set to.

### 11.5 Nesting Budget (hard constraint)

The runtime allows **two levels of subagents** below the top-level chat. The main agent and its direct children may dispatch; a subagent launched by another subagent receives no dispatch tool at all. Forge consumes that budget exactly, with no slack:

| Level | Who | May dispatch |
|-------|-----|--------------|
| 0 | PM, via the `project-manager` skill loaded into the top-level chat | yes |
| 1 | Coordinator (background), `roadmap-planner`, `story-review`, `escalation-triage`, `escalation-recovery`, `environment-recovery` | Coordinator only |
| 2 | Phase agents dispatched by a Coordinator | no |

Three rules follow, and all three are enforced rather than merely documented:

1. **The PM must occupy level 0.** It is a skill, not an agent prompt, so invoking `/project-manager` loads it into the current chat instead of delegating to a subagent. Delegating the PM instead shifts every Coordinator to level 2, where it cannot dispatch phase agents and the pipeline cannot run at all. Both validators fail if a `project-manager` agent prompt exists.

2. **Only the Coordinator dispatches at level 1.** `coordinator.md` is the sole agent prompt permitted to contain subagent-dispatch instructions. `validate-template-repo.sh` asserts that `run_in_background` appears in that file and nowhere else under `.cursor/agents/`.

3. **Phase agents are leaves.** They must never dispatch. There is no level left for a subagent of a phase agent, and one would fail with no dispatch tool rather than with a useful error.

A Coordinator that finds itself without a dispatch tool was launched at the wrong depth. That is a startup failure, not an escalation: it aborts before acquiring the lock and reports to the PM (Section 5, step 0).

Stopping the top-level chat stops every subagent beneath it, so the PM chat must stay open while background Coordinators are running.

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

Every script sources `taskwarrior/guard.sh`, which resolves the project tree root from the script's own location, exports an absolute `TASKDATA`, and enforces the required execution context. A main-tree script run inside a worktree (or vice versa) exits 2 without touching state. **Invoke scripts by absolute path** (`bash <tree-root>/taskwarrior/<script>`): correctness then never depends on an agent's working directory, which subagents cannot be given.

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

**Diagnostics and telemetry**:
- `doctor` (main tree): checks Forge invariants D01-D12; dry-run by default, `--fix` applies only the repairs marked fixable, `--json` for machine consumption. Exit 0 all clear, 1 only fixable failures remain, 2 a failure needs a human.
- `coordinator-heartbeat` (epic worktree): records Coordinator liveness and progress. Called automatically by the lifecycle scripts; agents never call it directly. Never fails its caller.
- `coordinator-status` (main tree): read-only liveness and progress aggregator across all worktrees, with `--epic` and `--json`. Exit 0 healthy, 1 stale, 2 dead / no heartbeat / escalation.

**Setup** (both trees):
- `setup.sh --main` / `setup.sh --worktree`: generates the tree's `.taskrc` (gitignored, with an absolute `data.location`) and configures the UDAs for that mode. It validates that the tree matches the flag and exits 2 on mismatch.

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

All review agents follow these principles:
- Focus on blocking issues: logic errors, missed requirements, incorrect contracts, test gaps
- Do NOT nitpick formatting, naming conventions, or style unless they cause actual confusion
- If it works and is structurally sound, approve it
- Every rejection must include exact file paths, line references, and concrete fix instructions
- Never rubber-stamp -- actually read and verify each artifact
- Limit to 3 review rounds per artifact; the Coordinator enforces this by counting rejections, and dispatches the reconciler at the 2nd

**Two tiers of finding.** Review is not binary. Every finding a reviewer makes is one of:

- **Blocking** -- the work is incorrect, unsafe, fails to meet a requirement, or diverges from the architecture. It goes in the review feedback file, the Write agent must fix it, and it counts toward the rejection limit.
- **Advisory** -- everything else, including anything the reviewer would have done differently. It does not enter the feedback file at all. The reviewer records advisories in **one** discovery file (Section 15) and approves.

**A review with zero blocking findings is APPROVED, however many advisories it produced.** Binary review is why every "I would have done this differently" used to cost a full Write agent re-dispatch. Each classification carries one line of justification.

**The out-of-scope demotion test.** A finding that falls outside the story's declared scope boundaries is advisory whatever its severity, cited against the specific In Scope / Out of Scope line. Either party may apply this one, because it is a check against a written contract rather than a judgement. The Write agent has no other demotion power: letting the criticized party reclassify criticism is how review quietly stops happening.

Two risks are accepted rather than engineered around. A reviewer could label everything advisory, which the phase gate (Section 5.1) and `implementation-review`'s independent test re-run already catch. Advisory volume could grow, which the "no style nits" bar above and the per-classification justification must keep in check.

**Anchoring.** A blocking finding is binding: the Write agent must comply with it and has no channel to dispute it. It must therefore be **anchored** -- it names a specific artifact element and states how the work under review contradicts it. An issue the reviewer cannot anchor is advisory by definition.

Each review agent's prompt lists the anchors valid for its phase, drawn only from what that agent is permitted to read. Across the pipeline they are: a story acceptance criterion, a requirement ID, a rule or DAG edge in `ARCHITECTURE.md`, a named element in an architecture artifact, a named test case, an observed command or test result, a project-profile entry (domain tag, mock boundary, convention, review standard, or Forbidden entry), and a Paavo's Codex item at the pinned closed version.

Judgment criteria -- cohesion, meaningfulness, actionability, scope appropriateness -- remain enforceable. They are anchored by naming the specific element and the concrete consequence, never by asserting a quality label. "Interface X is not cohesive" is not anchored; "class X exposes `save()` and `render()`; `render()` traces to no requirement" is.

Unanchored concerns are advisory and go to the discovery file, never to the feedback file. If every concern a reviewer holds is unanchored, it approves and writes no feedback file. The approval contract is unchanged: approval is a task annotation only.

Anchoring constrains how a rejection is justified, not whether one happens. It is not licence to rubber-stamp: every quality criterion in each review prompt still applies, and each maps to at least one valid anchor.

### 13.2 Implementation Standards

Implementation agents must never:
- Hardcode expected test values to make tests pass
- Write empty method bodies or stub implementations
- Use mocks or fakes in production code
- Write code that only works for specific test inputs
- Skip error handling mentioned in requirements
- Add dependencies not justified by requirements
- Silently deviate from the architecture

Implementation agents must also self-verify before review. Beyond passing the integration tests, the implementation agent builds and runs **verification tooling** (defined by the project profile's "Verification Tooling" section) to confirm the feature actually works:
- Verify acceptance-criteria scenarios via a read-only internal-state inspection surface (snapshot -> act -> snapshot -> assert the observable delta). The inspection surface must be derived from real runtime state, never a hand-maintained parallel field.
- For projects with a UI, verify each Visual Acceptance Criterion by driving the app to a named state, capturing a screenshot, and reasoning about the image with the agent's own vision. Verifying screenshots with image-processing scripts (histograms, pixel/color counts) does not count as visual verification.
- The implementation-review agent independently re-runs these checks; it must not approve verifiable behavior or visuals on code-reading alone.

### 13.3 Domain Dependency Compliance

All architecture artifacts and implementation source files must respect the dependency DAG defined in `ARCHITECTURE.md`.

### 13.4 Requirement Standards

Requirement agents must never leak solution-space concepts into requirements. Requirements describe WHAT, never HOW.

---

## 14. Extension Points

Forge is designed to be extended via the project profile. Downstream projects customize:

- **Language and build system**: affects architecture artifact type, test framework, build commands
- **Directory layout**: source, architecture, test, and build output directories
- **Test commands**: integration tests, full suite, lint/typecheck
- **Architecture conventions**: what architecture artifacts look like
- **Mock boundaries**: what may be mocked in tests
- **Verification tooling**: UI kind, the UI harness (launch/drive/screenshot commands), and internal-state inspection conventions used by the implementation agent to self-verify
- **Review standards**: project-specific quality requirements
- **Forbidden areas**: directories and actions agents must never touch
- **Domain tags**: allowlist for story Proposed Domain Tags and requirement folders; committed DAG membership is in `ARCHITECTURE.md`
- **Parallel limit**: recommended maximum concurrent epics
- **Paavo's Codex MCP**: endpoint URL (Cursor MCP registration) and Paavo's Codex project name/id. The pinned closed version lives in `plan/project.md`, not the profile.

Agent prompts read the project profile to adapt their behavior. The core workflow (phases, states, script protocol, git policy) remains fixed. Paavo's Codex is a hard dependency of Forge (see Section 16); it is not a generic swappable knowledge-source plug-in.

`deploy-profile` fills deploy-required knobs at install time. After each milestone, `project-profile-maintainer` is the only agent that may update the profile: it fills deferred `[No content yet]` sections and corrects stale knobs from milestone evidence, keeping the file concise.

---

## 15. Discovery Protocol

Discoveries preserve important observations without derailing the current task. They are also the destination for every advisory review finding (Section 13.1), which is what lets a review approve while still recording what it saw.

1. **Trigger**, either of:
   - While performing its assigned task, any subagent notices a clear and significant bug, gap, stub, design flaw, or risk. The finding need not be outside the current task's scope: an advisory about the very artifact under review is the common case, and the earlier "outside the current task scope" wording wrongly excluded it.
   - A review agent classifies one or more findings as advisory.

2. **Record**: the subagent writes one new file under `plan/discoveries/` using `plan/templates/discovery.md`, named `YYYYMMDD-HHMMSS-slug.md`. One file per occasion, not per finding: a review that produced six advisories writes one file holding all six.

3. **Do not inspect existing discoveries**: the subagent must not read, list, search, deduplicate, modify, or delete existing files in `plan/discoveries/`.

4. **Continue current task**: after writing the discovery, the subagent continues its assigned task. For a review, that means approving if it has no blocking findings.

5. **PM triage at story-batch start**: before generating each batch of stories, the PM reads all files in `plan/discoveries/`, groups related findings, and writes `plan/discoveries/triage-XX.md` recording a disposition for every file: **keep** (becomes a story in this batch) or **decline** (with a one-line reason). The PM then deletes the declined files -- git preserves them and the triage file is the durable record -- and generates stories for the kept ones **without asking the user**. Triage also runs at milestone completion, on whatever has accumulated since the last batch.

   Because subagents cannot read existing discoveries, the same advisory recurs across stories. That is signal, not duplication: three independent reviewers flagging the same awkwardness is stronger evidence than one. Triage reports grouping counts rather than a flat list.

   Discovery-derived stories default to `light` rigor (Section 3.3).

**Discoveries vs open questions**: local discoveries capture code/implementation findings that belong in the repo. Product-intent gaps (unclear goals, missing product rules, ambiguous user-facing behavior) belong in Paavo's Codex as open questions (Section 16), not as discovery files.

---

## 16. Project Knowledge Source Protocol (Paavo's Codex)

Product intent lives in Paavo's Codex. Forge caches a pinned execution roadmap in `plan/project.md`. Agents discover MCP tool names and signatures via Cursor's MCP tool listing -- this specification does **not** hardcode tool APIs.

### 16.1 Hard dependency

The Paavo's Codex MCP is required for all Forge work. If it is unreachable, the PM hard-stops (Section 4 step 0) and requirements agents escalate. Do not invent product goals or continue execution while product intent is unavailable.

### 16.2 Identity and pinning

- The project profile names the Paavo's Codex project (name and/or id) and how the MCP is registered in Cursor.
- `plan/project.md` pins the Paavo's Codex `project_id` and a **closed integer version**.
- Every Paavo's Codex read for a given project run uses that single pinned closed version. Do not query the open/live version. Do not silently switch versions mid-milestone.

### 16.3 Intent-level retrieval (agents select tools on the fly)

Agents that may access Paavo's Codex pursue these outcomes, choosing appropriate MCP tools themselves:

1. Discover/resolve the project by the name/id from the profile.
2. Confirm or select a closed (published/frozen) version; pin it in `plan/project.md` when creating or migrating the roadmap.
3. Read the project overview and domain structure; search for relevant topics; fetch specific articles as needed.
4. For version migration: use per-step change/diff tools (one step per version bump for multi-version jumps), then fetch article bodies for changed items as needed. The changed article ids from each step are then matched against the story citations in `plan/stories/` (Section 16.4) to obtain the exact set of stories the new version affects; that set scopes the migration milestone(s).

### 16.4 Story-level intent citations

Every story cites the product intent it derives from as `(project_id, version, article_id)` triples in its **Product Intent Source** section (Section 10.3). This closes the traceability chain: requirements back-link to stories, and stories back-link to Paavo's Codex articles.

- Article ids are stable across versions; titles are mutable. Cite the id as the identity and carry the title only as a human label.
- A citation is verifiable: fetching a cited id at the pinned version either returns the article or reports that it does not exist at that version. A cited id that does not resolve is a stale citation, not a product-intent gap, and requirements agents escalate it as such.
- Citations are the input to version-migration impact analysis (Section 16.3 item 4).
- Only the PM writes citations, because only the PM writes stories. Agents downstream of the story read them.
- `None -- [reason]` is the only acceptable form of absence. An unfilled template placeholder is a defect that story review must reject.

### 16.5 Who may access Paavo's Codex

- **Allowed**: PM, Roadmap Planner, and the two requirements-phase agents (write, review).
- **Forbidden**: Coordinator, architecture / integration-test / implementation agents, story-review, escalation-analysis, escalation-triage, escalation-recovery, environment-recovery, fixer, and general agents.

Requirements-plan and requirements-write may post open questions. Review agents may read the pinned version to verify traceability but should not post open questions unless needed to record a blocking product-intent gap.

### 16.6 Open questions (append-only)

Open questions are metadata attached to a frozen Paavo's Codex version (clarifications / deferred product decisions), not mutations of KB content.

Rules (mirror the Discovery Protocol):

- Allowed agents may **post** a new open question against the pinned closed version, then continue their task.
- Agents must **never** list, search, read, deduplicate, modify, answer, or delete existing open questions as part of Forge work.
- Non-blocking product-intent gap: post an open question and continue.
- Blocking product-intent gap (cannot proceed without changed/clarified intent): escalate (and optionally also post an open question so the gap is captured at the source). Answers and classification (clarification vs real change for a future version) happen in the Paavo's Codex web UI / user process, not in Forge.

---

## 17. Coordinator Observability

Coordinators run as background subagents so that epics execute in parallel. Background execution is only safe if the PM has a reliable, cheap way to tell working from stuck. That signal is a heartbeat written by the Forge scripts themselves, never by an agent's own reporting.

### 17.1 Heartbeat file

Each epic worktree has `.task/coordinator-status.json` (inside the gitignored `.task/` directory), rewritten atomically on every event:

```json
{
  "schema": 1,
  "epic": "E0001",
  "worktree": "/abs/path/.worktrees/epic-E0001-foundational-runtime",
  "branch": "story/00001-buildable-desktop-binary",
  "sequence": 42,
  "updated_epoch": 1785299763,
  "updated_utc": "2026-07-29T10:12:03Z",
  "event": "phase-start",
  "story": "00001",
  "phase": "req",
  "state": "write",
  "agent": "requirements-write",
  "detail": "",
  "escalation": ""
}
```

`sequence` increments monotonically, so progress is detectable even when two events land in the same second. Each event is also appended to `.task/coordinator-events.log` as one line, giving an ordered history without a database query.

### 17.2 Events

`coordinator-heartbeat` is called by the lifecycle scripts, so telemetry does not depend on an agent remembering to report:

| Script | Event |
|--------|-------|
| `coordinator-lock-acquire` | `started` |
| `coordinator-lock-release` | `stopped` |
| `story-init` | `story-init` |
| `phase-start` | `phase-start` |
| `phase-stop` | `phase-stop` |
| `phase-annotate` | `annotate` |
| `phase-transition` | `state` |
| `phase-done` | `phase-done` |
| `phase-block` | `escalated` (carries the escalation path) |
| `story-complete` | `story-verified` |
| `story-merge` | `story-merged` |

Because phase agents call `phase-annotate` and `phase-transition` during their own work, even a long-running implementation subagent keeps advancing the heartbeat. Silence therefore means genuinely stuck work, not a quiet agent.

### 17.3 Liveness

`coordinator-status` derives liveness per worktree from `updated_epoch`:

- `NO-HEARTBEAT` -- the status file is missing: the Coordinator never started
- `OK` -- age below `AI_HEARTBEAT_STALE_SECONDS` (default 1800)
- `STALE` -- age between the stale and dead thresholds
- `DEAD` -- age at or above `AI_HEARTBEAT_DEAD_SECONDS` (default 5400)
- `DONE` -- last event is `stopped` or `completed` and the Coordinator lock is FREE

Both thresholds are overridable by environment variable; a project may document its own values in the project profile when its phases legitimately run longer.

### 17.4 Aggregator exit codes

- **0** -- every worktree is `OK` or `DONE`
- **1** -- at least one `STALE` worktree: attention, not action
- **2** -- at least one `DEAD` or `NO-HEARTBEAT` worktree, or a recorded escalation

### 17.5 PM supervision loop

The PM supervises exclusively through `bash taskwarrior/coordinator-status` and acts on its exit code:

1. Exit 0 -- continue other PM work (next epic's stories, another dispatch, or wait), then re-check.
2. Exit 1 -- do other work and re-check once. If the same worktree is still `STALE` on the second consecutive check, treat it as exit 2.
3. Exit 2 with an escalation -- run the Section 9 escalation protocol.
4. Exit 2 with `NO-HEARTBEAT` or `DEAD` -- the Coordinator subagent died. Run `doctor` and route through Section 9; triage will classify this as `environment`. Never clear a HELD lock.
5. `DONE` -- mark the epic merge-ready and merge it (Section 8).

Reading agent transcripts, chat logs, or `.jsonl` files to infer progress is forbidden: it is unreliable, expensive, and it is what the heartbeat replaces.
