# System Architecture Policy

This file is a domain dependency policy registry maintained by the Architecture Plan agent. It defines the project's domains and the strict dependency rules between them as a directed acyclic graph (DAG).

This file must NEVER list classes, methods, function signatures, or internal design patterns. It is strictly a domain-level policy.

## Domain Definitions

[Populated by the architecture-plan agent as domains are introduced. Example:]

- core: Basic data structures, OS abstractions, configuration.

## Strict Dependency Rules (Directed Acyclic Graph)

[Populated by the architecture-plan agent. Example:]

- `core` must have ZERO internal project dependencies.

CRITICAL: Circular dependencies across domains are strictly prohibited.
