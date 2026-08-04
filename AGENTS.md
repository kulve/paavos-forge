# AI Agents: Paavo's Forge Maintenance Guide

This file is for AI agents maintaining the Paavo's Forge template repository itself. If you are an agent working in a downstream project that deployed this framework, read your project's `AGENTS.md` and `paavos-forge/LOGIC.md` instead.

## Repository Purpose

This repository is a generic, deployable template. It does not build or run anything on its own. Its outputs are documentation and template files that get copied into downstream projects.

Root `LOGIC.md` is deployed as `paavos-forge/LOGIC.md`; `templates/base/AGENTS.md` becomes the downstream root instructions; and `templates/cursor/.cursor/` becomes downstream Cursor configuration. Keep workflow rules editable only at root, then deploy or merge updates through the documented process.

## Key Principles

### Public Repository -- No Secrets or Local References

This repository is **public**. Everything committed here is world-readable. Never commit:

- Secrets of any kind: API keys, tokens, passwords, credentials, private keys.
- Personal or private data: private email addresses, real names tied to accounts, phone numbers.
- Machine-local references: absolute home paths (`/home/<user>/...`, `/Users/<user>/...`), internal hostnames, private IPs, machine-specific project slugs, or personal directory defaults.

Instead, use placeholders or required arguments (e.g. `<project-slug>`, `$HOME/.cursor/projects/<project-slug>/...`), and keep local state gitignored (`.task/`, `.worktrees/`, `/.cursor/`). When adding scripts or docs, prefer an explicit required argument over a personal default value. Before committing, scan your diff for the patterns above.

### Instruction Ownership

Root `LOGIC.md` is the single editable workflow specification; deployment copies it to `paavos-forge/LOGIC.md`. Keep instructions in one layer:

- `LOGIC.md`: complete normative workflow, state machine, recovery, artifacts, and Codex protocol.
- `templates/cursor/.cursor/rules/paavos-forge.mdc`: concise always-on invariants.
- `templates/base/AGENTS.md`: downstream entry point, instruction order, and write gates.
- Agent prompts: role-specific context, procedure, output, quality criteria, and escalation triggers.

Do not restore workflow summaries to every layer. When a workflow rule changes, update its authoritative `LOGIC.md` section, the always-on reminder only if every agent needs it, and only role prompts whose behavior changes. Validate with `bash scripts/validate-template-repo.sh`.

### Preserve Genericity

This template must work for C++, Python, TypeScript, and other languages. When making changes:

- Keep workflow rules language-agnostic in core files
- Language-specific details belong in the project profile (`templates/base/paavos-forge/project-profile.md`)
- Use "architecture artifacts" instead of "headers" in generic contexts
- Test your changes mentally against at least C++ and Python use cases

**Exception -- Paavo's Codex:** This framework intentionally couples to Paavo's Codex as the hard dependency for product intent (MCP knowledge source). Naming Paavo's Codex in `LOGIC.md`, agent prompts, the project profile, and deployment docs is allowed and required. Do not "genericize" that coupling away unless the user explicitly requests it. Still do not hardcode MCP tool names/signatures -- agents discover them via MCP.

### Keep Templates and Docs Consistent

Agent prompts reference artifact templates, Taskwarrior recipes, and LOGIC.md sections. When updating any of these:

- Verify all cross-references still point to correct section numbers, file paths, and command patterns
- Verify the artifact template fields match what agent prompts expect to read/write
- Verify Taskwarrior commands in recipes match UDA names in `setup.sh`

### No Project-Specific Leakage

Never add content that assumes a specific *downstream application* project. This includes:

- Specific class names, module names, or API endpoints of a deployed product
- Specific test frameworks (always reference "the test framework from the project profile")
- Specific build commands (always reference "the build command from the project profile")
- Hardcoded directory paths (always reference "the directory from the project profile")

Paavo's Codex as the product-intent knowledge source is a framework dependency, not leakage (see Preserve Genericity exception above).

## Script Protocol (`taskwarrior/`)

All state mutations in agent prompts and LOGIC.md must use the provided scripts, never raw `taskwarrior/tw` for writes. Read-only queries still use `taskwarrior/tw`.

When updating agent prompts or command references:
- Verify state mutations use scripts (`phase-transition`, `phase-annotate`, etc.)
- Verify read-only queries use `taskwarrior/tw`
- Verify script names match what exists in `templates/base/taskwarrior/`

AI lock and gate recovery is manual-only. Agents must never clear stale locks or gates automatically. Point users to `bash taskwarrior/cleanup-ai-state.sh` or `bash taskwarrior/epic-gate-release --force`.

## Model IDs Come From the Catalog, Not From Memory

`scripts/models/list-models.mjs` is authoritative for model IDs and parameters. Keep its consumer sites aligned: DEPLOY.md Step 6, `deploy-profile.md`, `set-agent-models.sh`, and `validate-deployment.sh`. Never infer identifiers from display names or edit model frontmatter manually.

## Isolation Invariants (do not regress these)

Worktree isolation is enforced by construction: scripts source `guard.sh`, use `AI_ROOT`, require their main/worktree context, and export absolute Taskwarrior state. Keep `.taskrc` generated and ignored; never reintroduce `SCRIPT_DIR`, `PROJECT_ROOT`, relative `data.location`, subagent `working_directory`, relative framework paths, or transcript-based Coordinator supervision.

After any change in `taskwarrior/`, `scripts/`, or the isolation-related prompt sections, run both:

```bash
bash scripts/validate-template-repo.sh
bash scripts/test-isolation.sh
```

## When Updating Agent Prompts

Comparable agent prompts follow this order: Role, Goal, Context Loading, Procedure, Output Specification, Taskwarrior Protocol (when applicable), Quality Criteria, review anchors (when applicable), Anti-Patterns, Escalation. Safety-specific sections may precede it (Coordinator Startup Assertion, recovery stop conditions/whitelist).

When editing prompts:

1. Keep shared invariants in `paavos-forge.mdc`, not copied into every prompt
2. Keep Context Loading precise -- list exactly what to read and what NOT to read
3. Keep Procedures numbered and unambiguous
4. Keep Anti-Patterns specific to the role (not generic advice)
5. Verify state mutations use scripts (not raw `taskwarrior/tw`)
6. Verify file paths match artifact templates
7. Verify script names match `recipes.md` and actual script files
8. Keep `model: inherit` in the frontmatter. Downstream deployments assign the real model by bucket; a concrete slug shipped upstream would override every deployed project's choice on merge.

**Adding or removing an agent prompt** also requires updating `BUCKET_MAP` in `templates/base/paavos-forge/set-agent-models.sh` and the agent counts in both validators. `validate-template-repo.sh` fails if the two sets disagree, so a forgotten bucket assignment cannot ship.

## Nesting Budget (do not regress this)

The PM remains the top-level `project-manager` skill, Coordinator is the only dispatching agent prompt, and phase agents plus `escalation-recovery` are leaves. Never ship a `project-manager` agent prompt or add dispatch instructions outside `coordinator.md`; the validator enforces both.
