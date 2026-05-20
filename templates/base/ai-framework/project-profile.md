# Project Profile

Fill in this file when deploying the AI execution framework. Agents read this to adapt their behavior to your project's language, conventions, and directory layout.

## Language and Build

- Primary language: [e.g. C++17, Python 3.12, TypeScript 5.x]
- Build system: [e.g. CMake, pip/poetry, npm/yarn]
- Build command: [e.g. `cmake --build build`, `python -m build`]

## Directory Layout

- Source code: [e.g. `src/`]
- Architecture artifacts: [e.g. `include/` for C++ headers, `src/interfaces/` for Python ABCs]
- Integration tests: [e.g. `tests/integration/`]
- Unit tests: [e.g. `tests/unit/`]
- Generated/build output (agents must never edit): [e.g. `build/`, `dist/`]

## Test Commands

- Run integration tests: [e.g. `ctest --test-dir build`, `pytest tests/integration/`]
- Run all tests: [e.g. `make test`, `pytest`]
- Lint/typecheck: [e.g. `clang-tidy src/`, `mypy src/`, `eslint .`]

## Architecture Conventions

- Architecture artifact type: [e.g. "C++ header files", "Python abstract base classes", "TypeScript interfaces"]
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

- [e.g. "Never modify files in `vendor/` or `third_party/`"]
- [e.g. "Never commit credentials or API keys"]
- [e.g. "Never use `unsafe` blocks without escalation"]
- [e.g. "Never modify generated files in `build/`"]

## Domain Tags

Valid domain tags for organizing requirements in this project:

- core
- [add project-specific domains here]
