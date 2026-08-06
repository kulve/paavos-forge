#!/bin/bash
# Copy Paavo's Forge templates into a downstream project.
# Copy-only: does not run setup.sh, fill the profile, or assign models.
#
# Usage:
#   bash scripts/install-into-project.sh --forge <forge-root> --project <target-root>
#   bash scripts/install-into-project.sh --forge <forge-root> --project <target-root> --force
#
# Always refuses if any ancestor that must be a directory already exists as a
# file or symlink (including under --force). Without --force, also refuses to
# overwrite leaf destination files/symlinks. --force only overwrites those
# leaf conflicts. Real directories alone do not count as conflicts.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  bash scripts/install-into-project.sh --forge <forge-root> --project <target-root> [--force]

Copy templates/base/, LOGIC.md -> paavos-forge/LOGIC.md, and templates/cursor/.cursor/
into the target project. Does not run Taskwarrior setup or assign agent models.

Always abort if any parent path component exists as a file or symlink (ancestors
must be real directories or absent), even with --force. Without --force, also
abort if any destination leaf file/symlink already exists. --force overwrites
existing leaf files/symlinks only (use for intentional template resets).
EOF
}

FORGE=""
PROJECT=""
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --forge)
            [ $# -ge 2 ] || { echo "ERROR: --forge requires a path" >&2; exit 2; }
            FORGE=$2
            shift 2
            ;;
        --project)
            [ $# -ge 2 ] || { echo "ERROR: --project requires a path" >&2; exit 2; }
            PROJECT=$2
            shift 2
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$FORGE" ] || [ -z "$PROJECT" ]; then
    echo "ERROR: --forge and --project are required" >&2
    usage >&2
    exit 2
fi

if [ ! -d "$FORGE" ]; then
    echo "ERROR: Forge path is not a directory: $FORGE" >&2
    exit 2
fi

FORGE=$(cd "$FORGE" && pwd)
mkdir -p "$PROJECT"
PROJECT=$(cd "$PROJECT" && pwd)

for required in \
    "$FORGE/LOGIC.md" \
    "$FORGE/templates/base/AGENTS.md" \
    "$FORGE/templates/cursor/.cursor/agents"
do
    if [ ! -e "$required" ]; then
        echo "ERROR: Forge tree does not look like Paavo's Forge (missing $required)" >&2
        exit 2
    fi
done

ancestor_conflicts=()
leaf_conflicts=()

# True if path exists as a symlink or non-directory.
is_blocking_node() {
    local path=$1
    [ -L "$path" ] || { [ -e "$path" ] && [ ! -d "$path" ]; }
}

# Walk ancestors of relative path $1 (everything except the leaf). Record the
# first blocking ancestor (file or symlink).
check_ancestors() {
    local rel=$1
    local cur=""
    local part prefix
    local -a parts

    IFS=/ read -r -a parts <<< "$rel"
    # Drop the leaf: only validate parents that must be directories.
    if [ "${#parts[@]}" -lt 2 ]; then
        return 0
    fi
    local last=$((${#parts[@]} - 2))
    local i
    for ((i = 0; i <= last; i++)); do
        part=${parts[$i]}
        [ -n "$part" ] || continue
        if [ -z "$cur" ]; then
            cur=$part
        else
            cur="$cur/$part"
        fi
        prefix="$PROJECT/$cur"
        if is_blocking_node "$prefix"; then
            ancestor_conflicts+=("$cur")
            return 0
        fi
    done
}

# Record a leaf conflict if the full destination exists as a file or symlink.
check_leaf() {
    local rel=$1
    local dest="$PROJECT/$rel"
    if is_blocking_node "$dest"; then
        leaf_conflicts+=("$rel")
    fi
}

check_dest_path() {
    local rel=$1
    check_ancestors "$rel"
    check_leaf "$rel"
}

# dest_prefix is prepended to each relative path under src_root (e.g. ".cursor/").
collect_conflicts_from_tree() {
    local src_root=$1
    local dest_prefix=$2
    local path rel
    while IFS= read -r -d '' path; do
        rel=${path#./}
        check_dest_path "${dest_prefix}${rel}"
    done < <(cd "$src_root" && find . -type f -print0)
}

collect_conflicts_from_tree "$FORGE/templates/base" ""
check_dest_path "paavos-forge/LOGIC.md"
collect_conflicts_from_tree "$FORGE/templates/cursor/.cursor" ".cursor/"

if [ "${#ancestor_conflicts[@]}" -gt 0 ]; then
    echo "ERROR: refusing to install into $PROJECT; blocking parent paths cannot be overwritten" >&2
    echo "Blocking parent paths (file or symlink where a directory is required):" >&2
    printf '  %s\n' "${ancestor_conflicts[@]}" | sort -u >&2
    echo >&2
    echo "Remove or rename these paths. --force cannot replace a file/symlink parent with a directory." >&2
    exit 1
fi

if [ "$FORCE" -eq 0 ] && [ "${#leaf_conflicts[@]}" -gt 0 ]; then
    echo "ERROR: refusing to overwrite existing paths in $PROJECT" >&2
    echo "Conflicting paths:" >&2
    printf '  %s\n' "${leaf_conflicts[@]}" | sort -u >&2
    echo >&2
    echo "Use a fresh/empty project, remove the conflicts, or pass --force to overwrite leaf files." >&2
    exit 1
fi

cp -a "$FORGE/templates/base/." "$PROJECT/"
mkdir -p "$PROJECT/paavos-forge"
cp -a "$FORGE/LOGIC.md" "$PROJECT/paavos-forge/LOGIC.md"
cp -a "$FORGE/templates/cursor/.cursor" "$PROJECT/"

echo "Installed Paavo's Forge into $PROJECT"
echo
echo "Next steps (see DEPLOY.md):"
echo "  1. Ensure git is initialized (Step 3)"
echo "  2. bash taskwarrior/setup.sh --main (Step 4)"
echo "  3. Fill paavos-forge/project-profile.md (Step 5)"
echo "  4. Assign agent models with paavos-forge/scripts/set-agent-models.sh (Step 6)"
echo "  5. Validate, commit, then start /project-manager (Steps 7-11)"
echo
echo "Keep the Forge STAGE/checkout until Steps 6 and 9 finish (list-models, validate-deployment)."
