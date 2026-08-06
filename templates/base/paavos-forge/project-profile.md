# Project Profile

Fill in this file when deploying Paavo's Forge. Agents read this to adapt their behavior to your project's language, conventions, and directory layout.

Sections marked `[e.g. ...]` must be filled at deploy (`deploy-profile` or by hand). Sections marked `[No content yet]` may wait until the `project-profile-maintainer` agent fills them after a milestone lands evidence. Keep every filled value concise -- this file is a knob list, not a handbook.

## Language and Build

- Primary language: [e.g. C++17, Python 3.12, TypeScript 5.x, Rust 2021]
- Build system: [e.g. CMake, pip/poetry, npm/yarn, cargo]
- Build command: [e.g. `cmake --build build`, `python -m build`, `cargo build`]

## Directory Layout

- Source code: [e.g. `src/`]
- Architecture artifacts: [e.g. `include/` for C++ headers, `src/interfaces/` for Python ABCs, a `-api` crate or trait modules for Rust]
- Integration tests: [e.g. `tests/integration/`]
- Unit tests: [e.g. `tests/unit/`]
- Generated/build output (agents must never edit): [e.g. `build/`, `dist/`]

## Test Commands

- Run integration tests: [e.g. `ctest --test-dir build`, `pytest tests/integration/`, `cargo test --test '*'`]
- Run all tests: [e.g. `make test`, `pytest`, `cargo test`]
- Lint/typecheck: [e.g. `clang-tidy src/`, `mypy src/`, `eslint .`, `cargo clippy`]

### Phase Gates

`taskwarrior/phase-gate` runs one of these commands before a phase may reach `done`. A review approval is a judgement about text; the gate is the part a command either satisfies or does not. Leaving a placeholder unfilled skips that gate with a warning, which puts the phase back on review approval alone -- fill them in.

Each command must succeed (exit 0) when the phase's artifacts are correct, and must not require artifacts from a later phase to exist.

- Architecture gate: [compile or typecheck the architecture artifacts standalone, no linking. e.g. `for h in include/**/*.hpp; do g++ -std=c++17 -fsyntax-only -Iinclude "$h" || exit 1; done`, `mypy src/interfaces/`, `tsc --noEmit -p tsconfig.interfaces.json`]
- Test compile gate: [compile or parse the integration test target without linking it against an implementation. e.g. `cmake --build build --target integration_tests_compile`, `pytest --collect-only tests/integration/`, `tsc --noEmit -p tsconfig.test.json`]

The integration test phase completes when this gate passes **and** the named tests fail for the right reason -- the tests are written before the implementation exists, so a green suite at this point means the tests do not test anything. The compile half is the gate; "for the right reason" is the reviewer's call, made against the gate's actual output rather than by reading the file.

The implementation phase gate is `Run integration tests` above.

## Architecture Conventions

- Architecture artifact type: [No content yet]
- Architecture artifacts list requirements in: [No content yet]
- Requirement-to-code traceability syntax: [No content yet]

## Mock Boundaries

Only mock these system boundaries in tests:

- [No content yet]

Do NOT mock internal collaborators.

## Verification Tooling

This section guides the implementation agent's self-verification during the impl phase. The tooling described here is real code the implementation agent builds and runs while implementing a story -- it is distinct from the shift-left integration tests. Keep entries concrete and deterministic so a weak model can rely on them.

### Internal State Inspection

How the app exposes a deterministic, read-only snapshot/query of internal state for verification:

- [No content yet]

Rules:
- The inspection surface must be **derived from real runtime state**, never a parallel bookkeeping field the implementation updates by hand.
- It must be read-only and side-effect free.

### UI Kind

- UI kind: [one of: web / game / TUI / none]

If `none`, the visual verification step is not applicable; the implementation agent skips screenshots and verifies via state inspection and scenario checks only. Do not invent screenshots for a library or CLI.

### UI Harness (only if UI kind is not `none`)

How to launch the app in a drivable mode, drive it into a named state, and capture a screenshot to a file path:

- Launch/drive command: [No content yet]
- Named states to capture: [No content yet]
- Screenshot output path: [No content yet]

Rules:
- Setup for each named state must be **deterministic/seeded** so a screenshot is a stable oracle (no random layout, no wall-clock-dependent content).
- Screenshot artifacts belong in a scratch/ignored directory, not committed.

## Review Standards

- [No content yet]

## Forbidden

Forge-enforced write gates (do not remove):
- Never write to the source code directory except when operating as the `implementation-write` agent with an active Taskwarrior task at `aiphase:impl aistate:write`.
- Never write to the architecture artifacts directory except when operating as the `architecture-write` agent with an active Taskwarrior task at `aiphase:arch aistate:write`.
- Never write to the integration tests directory except when operating as the `integration-test-write` agent with an active Taskwarrior task at `aiphase:test aistate:write`.
- Never write to `plan/requirements/` except when operating as the `requirements-write` agent with an active Taskwarrior task at `aiphase:req aistate:write`.
- A general agent must never write to any of the above directories. If asked to implement or write code, tell the user to start a new chat and invoke the `/project-manager` skill.

Project-specific forbidden items:
- [No content yet]

## Taskwarrior

- Wrapper command: `taskwarrior/tw` (never bare `task`)
- Config: `.taskrc` at each tree root -- generated by `setup.sh`, gitignored, never committed
- Data directory: `.task/` (gitignored, not committed)
- Setup script: `bash taskwarrior/setup.sh --main` (or `--worktree`, run automatically by `epic-fork`)
- Command patterns: `taskwarrior/recipes.md`
- Invoke every script by absolute path: `bash <tree-root>/taskwarrior/<script>`

## Coordinator Heartbeat Thresholds

`coordinator-status` calls a worktree `STALE` and then `DEAD` based on how long ago its heartbeat last advanced. Raise these if a single phase in this project legitimately runs longer than the default (for example a slow full build in the implementation phase).

- Stale threshold (`AI_HEARTBEAT_STALE_SECONDS`): [No content yet]
- Dead threshold (`AI_HEARTBEAT_DEAD_SECONDS`): [No content yet]
- Longest expected single phase for this project: [No content yet]

## Domain Tags

Allowlist for story `## Proposed Domain Tags` and `plan/requirements/[domain]/` folders. Committed DAG membership lives in `ARCHITECTURE.md` (architecture-plan is the gatekeeper). Keep `core`; add tags when evidence exists -- do not seed a speculative wishlist at deploy.

- core
- [No content yet]

## Project Knowledge Source (Paavo's Codex MCP)

Paavo's Codex is a hard dependency. Register the MCP server in the project's Cursor MCP config (see `DEPLOY.md`). Agents discover tool names/signatures via MCP -- do not hardcode them here.

- MCP endpoint URL: [e.g. `http://127.0.0.1:8770/mcp`]
- Paavo's Codex project name: [exact project name]
- Paavo's Codex project id: [optional; filled after first MCP discovery]
- Roadmap-relevant entry domains: [optional hints, e.g. "Product Goals", "Roadmap"]

The pinned closed version for a run lives in `plan/project.md`, not in this profile.
