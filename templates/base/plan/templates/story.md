# Story XXXXX: [Title]

## Epic

[Link: plan/epics/EXXXX-slug.md]

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

## Domain Tags

[e.g. core, rendering, network, input, audio -- used for requirement organization]

## Dependencies

[Other story IDs within this epic that must be complete first, or "None"]

## Modifies Stories

[Optional. Include only when this story changes or deprecates behavior from earlier stories.
List old story files and a brief reason. Never edit old story files in place.]

- plan/stories/XXXXX-old-story.md -- [brief reason: changes behavior, deprecates feature, etc.]

## Non-Goals

[Things that might seem related but are explicitly deferred to future stories]
