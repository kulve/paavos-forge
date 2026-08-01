# ai-framework/

This directory holds project-specific framework configuration in deployed projects.

## Files at deploy time

| File | Source |
|------|--------|
| `LOGIC.md` | Copied from the framework repo root `LOGIC.md` (see `DEPLOY.md` Step 1b) |
| `project-profile.md` | Copied from `templates/base/ai-framework/project-profile.md` and filled in by you |
| `set-agent-models.sh` | Copied from `templates/base/ai-framework/`; assigns a model to every agent prompt by bucket (see `DEPLOY.md` Step 6) |

`LOGIC.md` is not stored in `templates/base/` because it is maintained once at the framework repo root. Deployment copies it here as-is.

`set-agent-models.sh` carries the canonical agent-to-bucket mapping and rewrites the `model:` line in each `.cursor/agents/*.md`. Run `bash ai-framework/set-agent-models.sh --list` to see the current assignment, and re-run it with your chosen models after merging upstream agent prompt updates.
