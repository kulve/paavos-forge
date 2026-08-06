# System Architecture Policy

This file is a domain dependency policy registry maintained by the Architecture Plan agent. It defines the project's domains and the strict dependency rules between them as a directed acyclic graph (DAG). It is the committed domain vocabulary: story Proposed Domain Tags are proposals only until architecture-plan commits them here (or escalation-recovery refiles requirements to match).

This file must NEVER list classes, methods, function signatures, or internal design patterns. It is strictly a domain-level policy.

## Domain Definitions

Each domain uses the same schema. Prefer introducing a real domain over expanding `core`. Refine Owns / Does not own when ownership changes; split a bloated domain rather than turning its Owns line into a feature inventory.

### core

- **Owns:** [e.g. shared value types, application-neutral ports, configuration defaults]
- **Does not own:** [e.g. platform adapters, executable composition, feature-specific simulation]
- **May depend on:** (none -- zero internal project dependencies)
- **Artifacts under:** [e.g. `include/<project>/core/` -- match the project-profile architecture layout]

[Populated by the architecture-plan agent as domains are introduced. Add a `### <domain>` subsection per domain using the four fields above.]

## Strict Dependency Rules (Directed Acyclic Graph)

[Populated by the architecture-plan agent. Must stay consistent with each domain's May depend on field. Example:]

- `core` must have ZERO internal project dependencies.
- [e.g. `rendering` may depend on `core` only.]
- [e.g. `tooling` may depend on `core` and `rendering`.]
- [e.g. No domain may depend on `tooling`.]

CRITICAL: Circular dependencies across domains are strictly prohibited.
