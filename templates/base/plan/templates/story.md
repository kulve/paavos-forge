# Story XXXXX: [Title]

## Epic

[Link: plan/epics/EXXXX-slug.md]

## Product Intent Source

Cite the Paavo's Codex articles this story derives from. Article ids are stable
across versions; titles are not. The id is the identity, the title is a human
label. Record the version here even though plan/project.md pins it: this story
is a historical record of the intent it was authored against.

- Paavo's Codex project: [project id from plan/project.md]
- Authored against version: [closed integer]
- Articles:
  - [article-id] -- "[title at that version]" [domain: domain-id]

If no single article backs this story (intent synthesized across a whole domain,
Forge scaffolding, and similar cases), state the absence deliberately
instead of leaving the list empty:

- Articles:
  - None -- [reason]

## Rigor

[full | light]

`full` runs all four phases: requirements, architecture, integration tests, implementation.
`light` runs the implementation phase only -- write plus review, two dispatches against ten.

A story qualifies as `light` only if **all three** of these hold. Any one false makes it `full`:

1. No new or changed architecture artifact.
2. No new integration test needed; existing tests already cover the behavior.
3. No new product intent -- `## Product Intent Source` cites a discovery rather than a Paavo
   Notes article, using the `None -- [reason]` form.

These tests are objective on purpose. Loosened into judgement, `light` becomes the default
and review disappears. Discovery-derived stories normally satisfy all three.

If a `light` story's write agent finds the change is not actually small, it escalates rather
than pushing on, and the story is reissued as `full`. Without that, `light` is a route for
unreviewed architectural change.

## Goal

[Plain English: WHAT this feature does and WHY a user needs it.
Do not describe technical approach. Describe observable behavior.]

## Scope Boundaries

### In Scope

- [Specific behavior 1]
- [Specific behavior 2]

### Out of Scope (do NOT implement)

- [Explicit exclusion 1 -- critical for preventing LLM scope creep]
- [Explicit exclusion 2]

## Trigger Conditions

[How the user or system invokes this feature]

## Acceptance Criteria (Definition of Done)

Phrase each criterion as an observable end-state or an executable scenario the implementation agent can verify by inspecting state or driving the app -- not as an internal implementation detail.

- [ ] [Binary, verifiable fact. e.g. "Running the project's full test command (from the project profile) passes all new tests"]
- [ ] [Observable outcome / scenario. e.g. "After the player collects a coin, the score snapshot increases by 10"]
- [ ] [Negative case. e.g. "Invalid input produces error message Z, not a crash"]

### Visual Acceptance Criteria (optional; only for UI stories)

Describe what a user should be able to **perceive or distinguish** on screen. These give the implementation agent a target and the visual verification step an oracle.

- [ ] [e.g. "The current score is visible during play"]
- [ ] [e.g. "The selected menu item is visually distinct from unselected items"]

Guardrail: describe perceivable intent only. NEVER specify exact pixels, colors, hex values, coordinates, fonts, or spacing -- those make correct implementations fail review and couple the story to a design that will change.

## Proposed Domain Tags

[e.g. core, rendering, network, input, audio -- proposals from the project-profile Domain Tags allowlist for requirement organization. Committed domains live in ARCHITECTURE.md after architecture planning; these tags remain historical proposals.]

## Dependencies

[Other story IDs within this epic that must be complete first, or "None"]

## Modifies Stories

[Optional. Include only when this story changes or deprecates behavior from earlier stories.
List old story files and a brief reason. Never edit old story files in place.]

- plan/stories/XXXXX-old-story.md -- [brief reason: changes behavior, deprecates feature, etc.]

## Non-Goals

[Things that might seem related but are explicitly deferred to future stories]
