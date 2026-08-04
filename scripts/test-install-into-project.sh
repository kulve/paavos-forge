#!/bin/bash
# Smoke tests for scripts/install-into-project.sh conflict preflight.
# Run from the framework repo root: bash scripts/test-install-into-project.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="${REPO_ROOT}/scripts/install-into-project.sh"
FAILURES=0
TMPDIR_TEST=""

cleanup() {
    if [ -n "$TMPDIR_TEST" ] && [ -d "$TMPDIR_TEST" ]; then
        rm -rf "$TMPDIR_TEST"
    fi
}
trap cleanup EXIT

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; FAILURES=$((FAILURES + 1)); }

echo "=== Paavo's Forge install-into-project smoke ==="
echo ""

if [ ! -x "$INSTALL" ]; then
    echo "ERROR: missing executable $INSTALL" >&2
    exit 1
fi

TMPDIR_TEST="$(mktemp -d)"

# --- Empty project -------------------------------------------------------
EMPTY="${TMPDIR_TEST}/empty"
mkdir -p "$EMPTY"
if bash "$INSTALL" --framework "$REPO_ROOT" --project "$EMPTY" >/dev/null; then
    if [ -f "$EMPTY/AGENTS.md" ] \
        && [ -f "$EMPTY/paavos-forge/LOGIC.md" ] \
        && [ -f "$EMPTY/.cursor/agents/coordinator.md" ] \
        && [ -f "$EMPTY/.gitignore" ]; then
        pass "empty project install"
    else
        fail "empty project install (missing expected files)"
    fi
else
    fail "empty project install (exit nonzero)"
fi

# --- Leaf conflict -------------------------------------------------------
LEAF="${TMPDIR_TEST}/leaf"
mkdir -p "$LEAF/.cursor/agents"
echo preexisting > "$LEAF/.cursor/agents/coordinator.md"
LEAF_ERR="${TMPDIR_TEST}/leaf.err"
if bash "$INSTALL" --framework "$REPO_ROOT" --project "$LEAF" >/dev/null 2>"$LEAF_ERR"; then
    fail "leaf conflict should exit nonzero"
else
    if grep -q 'coordinator.md' "$LEAF_ERR" && [ ! -f "$LEAF/AGENTS.md" ]; then
        pass "leaf conflict refuses and copies nothing"
    else
        fail "leaf conflict (stderr or partial copy wrong)"
    fi
fi

# --- Parent is a file ----------------------------------------------------
PARENT_FILE="${TMPDIR_TEST}/parent-file"
mkdir -p "$PARENT_FILE"
echo notadir > "$PARENT_FILE/plan"
PF_ERR="${TMPDIR_TEST}/parent-file.err"
if bash "$INSTALL" --framework "$REPO_ROOT" --project "$PARENT_FILE" >/dev/null 2>"$PF_ERR"; then
    fail "parent-as-file should exit nonzero"
else
    if grep -qE '(^|[[:space:]])plan$' "$PF_ERR" || grep -q 'plan' "$PF_ERR"; then
        if [ ! -f "$PARENT_FILE/AGENTS.md" ]; then
            pass "parent-as-file refuses and copies nothing"
        else
            fail "parent-as-file left partial payload (AGENTS.md)"
        fi
    else
        fail "parent-as-file stderr missing plan conflict"
    fi
fi

# --- Parent is a symlink -------------------------------------------------
PARENT_LINK="${TMPDIR_TEST}/parent-link"
LINK_TARGET="${TMPDIR_TEST}/taskwarrior-elsewhere"
mkdir -p "$PARENT_LINK" "$LINK_TARGET"
ln -s "$LINK_TARGET" "$PARENT_LINK/taskwarrior"
PL_ERR="${TMPDIR_TEST}/parent-link.err"
if bash "$INSTALL" --framework "$REPO_ROOT" --project "$PARENT_LINK" >/dev/null 2>"$PL_ERR"; then
    fail "parent-as-symlink should exit nonzero"
else
    if grep -q 'taskwarrior' "$PL_ERR" && [ ! -f "$PARENT_LINK/AGENTS.md" ]; then
        pass "parent-as-symlink refuses and copies nothing"
    else
        fail "parent-as-symlink (stderr or partial copy wrong)"
    fi
fi

# --- --force over leaf conflict ------------------------------------------
FORCE_PROJ="${TMPDIR_TEST}/force"
mkdir -p "$FORCE_PROJ/.cursor/agents"
echo preexisting > "$FORCE_PROJ/.cursor/agents/coordinator.md"
if bash "$INSTALL" --framework "$REPO_ROOT" --project "$FORCE_PROJ" --force >/dev/null; then
    if [ -f "$FORCE_PROJ/AGENTS.md" ] \
        && [ -f "$FORCE_PROJ/.cursor/agents/coordinator.md" ] \
        && ! grep -qx preexisting "$FORCE_PROJ/.cursor/agents/coordinator.md"; then
        pass "--force overwrites leaf conflict"
    else
        fail "--force did not complete expected overwrite"
    fi
else
    fail "--force over leaf conflict (exit nonzero)"
fi

# --- --force still refuses parent-as-file --------------------------------
FORCE_PF="${TMPDIR_TEST}/force-parent-file"
mkdir -p "$FORCE_PF"
echo notadir > "$FORCE_PF/plan"
FORCE_PF_ERR="${TMPDIR_TEST}/force-parent-file.err"
if bash "$INSTALL" --framework "$REPO_ROOT" --project "$FORCE_PF" --force >/dev/null 2>"$FORCE_PF_ERR"; then
    fail "--force parent-as-file should exit nonzero"
else
    if grep -q 'plan' "$FORCE_PF_ERR" && [ ! -f "$FORCE_PF/AGENTS.md" ]; then
        pass "--force parent-as-file still refuses"
    else
        fail "--force parent-as-file (stderr or partial copy wrong)"
    fi
fi

# --- --force still refuses parent-as-symlink -----------------------------
FORCE_PL="${TMPDIR_TEST}/force-parent-link"
FORCE_LINK_TARGET="${TMPDIR_TEST}/force-taskwarrior-elsewhere"
mkdir -p "$FORCE_PL" "$FORCE_LINK_TARGET"
ln -s "$FORCE_LINK_TARGET" "$FORCE_PL/taskwarrior"
FORCE_PL_ERR="${TMPDIR_TEST}/force-parent-link.err"
if bash "$INSTALL" --framework "$REPO_ROOT" --project "$FORCE_PL" --force >/dev/null 2>"$FORCE_PL_ERR"; then
    fail "--force parent-as-symlink should exit nonzero"
else
    if grep -q 'taskwarrior' "$FORCE_PL_ERR" && [ ! -f "$FORCE_PL/AGENTS.md" ]; then
        pass "--force parent-as-symlink still refuses"
    else
        fail "--force parent-as-symlink (stderr or partial copy wrong)"
    fi
fi

echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo "=== Results: all install-into-project checks passed ==="
    exit 0
fi
echo "=== Results: $FAILURES failure(s) ==="
exit 1
