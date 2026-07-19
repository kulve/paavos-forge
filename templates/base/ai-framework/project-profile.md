# Project Profile

Fill in this file when deploying the AI execution framework. Agents read this to adapt their behavior to your project's language, conventions, and directory layout.

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

## Architecture Conventions

- Architecture artifact type: [e.g. "C++ header files", "Python abstract base classes", "TypeScript interfaces", "Rust trait definitions"]
- Architecture artifacts list requirements in: [e.g. "comments above declarations", "docstrings on abstract methods"]
- Requirement-to-code traceability syntax: [e.g. `// REQ:XXXXX-name` in header comments]

## Mock Boundaries

Only mock these system boundaries in tests:

- [e.g. File I/O]
- [e.g. Network sockets]
- [e.g. GPU/hardware contexts]
- [e.g. OS system calls]

Do NOT mock internal collaborators.

## Review Standards

- [e.g. "All public functions must have error handling for invalid inputs"]
- [e.g. "No raw pointers in new code (use smart pointers)"]
- [e.g. "All new functions must have docstrings/documentation comments"]

## Forbidden

Framework-enforced write gates (do not remove):
- Never write to the source code directory except when operating as the `implementation-write` agent with an active Taskwarrior task at `aiphase:impl aistate:write`.
- Never write to the architecture artifacts directory except when operating as the `architecture-write` agent with an active Taskwarrior task at `aiphase:arch aistate:write`.
- Never write to the integration tests directory except when operating as the `integration-test-write` agent with an active Taskwarrior task at `aiphase:test aistate:write`.
- Never write to `plan/requirements/` except when operating as the `requirements-write` agent with an active Taskwarrior task at `aiphase:req aistate:write`.
- A general agent must never write to any of the above directories. If asked to implement or write code, redirect the user to the `project-manager` agent.

Project-specific forbidden items:
- [e.g. "Never modify files in `vendor/` or `third_party/`"]
- [e.g. "Never commit credentials or API keys"]
- [e.g. "Never use `unsafe` blocks without escalation"]
- [e.g. "Never modify generated files in `build/`"]

## Taskwarrior

- Wrapper command: `taskwarrior/tw` (never bare `task`)
- Config: `.taskrc` at project root
- Data directory: `.task/` (gitignored, not committed)
- Setup script: `bash taskwarrior/setup.sh`
- Command patterns: `taskwarrior/recipes.md`

## Domain Tags

Valid domain tags for organizing requirements in this project:

- core
- [add project-specific domains here]

## Project Knowledge Source (Paavo Notes MCP)

Paavo Notes is a hard dependency. Register the MCP server in the project's Cursor MCP config (see `DEPLOY.md`). Agents discover tool names/signatures via MCP -- do not hardcode them here.

- MCP endpoint URL: [e.g. `http://127.0.0.1:8770/mcp`]
- Paavo Notes project name: [exact project name]
- Paavo Notes project id: [optional; filled after first MCP discovery]
- Roadmap-relevant entry domains: [optional hints, e.g. "Product Goals", "Roadmap"]

The pinned closed version for a run lives in `plan/project.md`, not in this profile.
