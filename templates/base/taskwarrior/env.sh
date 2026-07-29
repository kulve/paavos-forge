#!/bin/bash
# Source this file (or use taskwarrior/tw) so task uses this project's database.
# Usage: source taskwarrior/env.sh   OR   taskwarrior/tw <args>
#
# TASKDATA is exported as an absolute path and overrides data.location, so the
# database is selected by this file's location and never by the caller's cwd.
TASKWARRIOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TASKRC="${TASKWARRIOR_ROOT}/.taskrc"
export TASKDATA="${TASKWARRIOR_ROOT}/.task"
mkdir -p "${TASKDATA}"
