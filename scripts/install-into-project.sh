#!/bin/bash
# Copy Paavo's Forge templates into a downstream project.
# Copy-only: does not run setup.sh, fill the profile, or assign models.
#
# Usage:
#   bash scripts/install-into-project.sh --framework <forge-root> --project <target-root>
#   bash scripts/install-into-project.sh --framework <forge-root> --project <target-root> --force
#
# Always refuses if any ancestor that must be a directory already exists as a
# file or symlink (including under --force). Without --force, also refuses to
# overwrite leaf destination files/symlinks. --force only overwrites those
# leaf conflicts. Real directories alone do not count as conflicts.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  bash scripts/install-into-project.sh --framework <forge-root> --project <target-root> [--force]

Copy templates/base/, LOGIC.md -> ai-framework/LOGIC.md, and templates/cursor/.cursor/
into the target project. Does not run Taskwarrior setup or assign agent models.

Always abort if any parent path component exists as a file or symlink (ancestors
must be real directories or absent), even with --force. Without --force, also
abort if any destination leaf file/symlink already exists. --force overwrites
existing leaf files/symlinks only (use for intentional template resets).
EOF
}

FRAMEWORK=""
PROJECT=""
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --framework)
            [ $# -ge 2 ] || { echo "ERROR: --framework requires a path" >&2; exit 2; }
            FRAMEWORK=$2
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

if [ -z "$FRAMEWORK" ] || [ -z "$PROJECT" ]; then
    echo "ERROR: --framework and --project are required" >&2
    usage >&2
    exit 2
fi

if [ ! -d "$FRAMEWORK" ]; then
    echo "ERROR: framework path is not a directory: $FRAMEWORK" >&2
    exit 2
fi

FRAMEWORK=$(cd "$FRAMEWORK" && pwd)
mkdir -p "$PROJECT"
PROJECT=$(cd "$PROJECT" && pwd)

for required in \
    "$FRAMEWORK/LOGIC.md" \
    "$FRAMEWORK/templates/base/AGENTS.md" \
    "$FRAMEWORK/templates/cursor/.cursor/agents"
do
    if [ ! -e "$required" ]; then
        echo "ERROR: framework tree does not look like Paavo's Forge (missing $required)" >&2
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

collect_conflicts_from_tree "$FRAMEWORK/templates/base" ""
check_dest_path "ai-framework/LOGIC.md"
collect_conflicts_from_tree "$FRAMEWORK/templates/cursor/.cursor" ".cursor/"

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

cp -a "$FRAMEWORK/templates/base/." "$PROJECT/"
mkdir -p "$PROJECT/ai-framework"
cp -a "$FRAMEWORK/LOGIC.md" "$PROJECT/ai-framework/LOGIC.md"
cp -a "$FRAMEWORK/templates/cursor/.cursor" "$PROJECT/"

echo "Installed Paavo's Forge into $PROJECT"
echo
echo "Next steps (see DEPLOY.md):"
echo "  1. Ensure git is initialized (Step 3)"
echo "  2. bash taskwarrior/setup.sh --main (Step 4)"
echo "  3. Fill ai-framework/project-profile.md (Step 5)"
echo "  4. Assign agent models with ai-framework/set-agent-models.sh (Step 6)"
echo "  5. Validate, commit, then start /project-manager (Steps 7-11)"
echo
echo "Keep the framework STAGE/checkout until Steps 6 and 9 finish (list-models, validate-deployment)."
