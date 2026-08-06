# paavos-forge/

Forge configuration and workflow for a deployed project.

## Contents

| Path | Ownership | Role |
|------|-----------|------|
| `LOGIC.md` | Forge (upstream) | Workflow specification. Copied from the Forge repo root at deploy; do not edit unless forking Forge. |
| `scripts/set-agent-models.sh` | Forge (upstream) | Assigns a Cursor model to every agent prompt by bucket. Re-run after merging upstream agent prompts. |
| `project-profile.md` | Project | Concise knobs: language, layout, build/test/gate commands, conventions, Codex binding. Filled at deploy (`deploy-profile`); synced after each milestone by `project-profile-maintainer`. |

`LOGIC.md` is not stored under `templates/base/` in the Forge repo because it is maintained once at the repo root. Deployment copies it here as-is.

## Project profile

`project-profile.md` is a knob file, not a handbook. Deploy fills `[e.g. ...]` placeholders (build, directories, gates, UI kind, Codex). Sections marked `[No content yet]` wait until milestone work provides evidence. Keep values short; detailed architecture lives in `ARCHITECTURE.md` and architecture artifacts.

## Model buckets

```bash
bash paavos-forge/scripts/set-agent-models.sh --list
```

See `DEPLOY.md` Step 6 for bucket meanings and how to list selectable model IDs.
