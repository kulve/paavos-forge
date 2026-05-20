#!/bin/bash
# Source this file (or use taskwarrior/tw) so task uses this project's database.
# Usage: source taskwarrior/env.sh   OR   taskwarrior/tw <args>
TASKWARRIOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TASKRC="${TASKWARRIOR_ROOT}/.taskrc"
mkdir -p "${TASKWARRIOR_ROOT}/.task"
