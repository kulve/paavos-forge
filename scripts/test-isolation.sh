#!/bin/bash
# Worktree isolation smoke test for Paavo's Forge.
# Deploys the templates into a throwaway git repo and proves that Taskwarrior and
# git state cannot leak between the main tree and an epic worktree, regardless of
# the caller's working directory.
#
# Usage: bash scripts/test-isolation.sh   (from the Forge repository root)
# Exit 0: all assertions passed. Exit 1: an assertion failed.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

assert_eq() {
    # assert_eq <label> <expected> <actual>
    if [ "$2" = "$3" ]; then pass "$1 ($2)"; else fail "$1 (expected '$2', got '$3')"; fi
}

echo "=== Paavo's Forge Isolation Test ==="
echo ""

if ! command -v task >/dev/null 2>&1; then
    echo "SKIP: Taskwarrior is not installed; cannot run isolation test."
    exit 0
fi

# --- 1. Deploy into a temp git repo --------------------------------------
echo "--- 1. Deploy ---"
TMPDIR_TEST="$(mktemp -d)"
PROJ="${TMPDIR_TEST}/proj"
mkdir -p "$PROJ"

bash "${REPO_ROOT}/scripts/install-into-project.sh" \
  --forge "$REPO_ROOT" --project "$PROJ"
chmod +x "${PROJ}/taskwarrior/"* 2>/dev/null || true

git -C "$PROJ" init -q -b main
git -C "$PROJ" config user.email "isolation-test@example.invalid"
git -C "$PROJ" config user.name "Isolation Test"

if ! bash "${PROJ}/taskwarrior/setup.sh" --main >/dev/null 2>&1; then
    fail "setup.sh --main"
    echo "=== Results: aborting, main setup failed ==="
    exit 1
fi
pass "setup.sh --main"

if [ -f "${PROJ}/.taskrc" ]; then
    pass ".taskrc generated"
else
    fail ".taskrc generated"
fi

# .taskrc must be gitignored so a worktree copy can never overwrite main's UDAs.
if git -C "$PROJ" check-ignore -q .taskrc; then
    pass ".taskrc is gitignored"
else
    fail ".taskrc is gitignored"
fi

git -C "$PROJ" add -A >/dev/null 2>&1
git -C "$PROJ" commit -qm "deploy Forge" >/dev/null 2>&1
pass "Forge committed to main"

# --- 2. Fork an epic -----------------------------------------------------
echo "--- 2. Fork epic E0001 ---"
WT="${PROJ}/.worktrees/epic-E0001-smoke"
if bash "${PROJ}/taskwarrior/epic-fork" E0001 smoke >/dev/null 2>&1; then
    pass "epic-fork E0001 smoke"
else
    fail "epic-fork E0001 smoke"
    bash "${PROJ}/taskwarrior/epic-fork" E0001 smoke || true
    echo "=== Results: aborting, fork failed ==="
    exit 1
fi

# --- 3. Coordinator state lives only in the worktree ---------------------
echo "--- 3. Lock placement ---"
WT_LOCKS=$(bash "${WT}/taskwarrior/tw" +AI_LOCK airole:coordinator count 2>/dev/null || echo "ERR")
assert_eq "worktree DB coordinator locks" "1" "$WT_LOCKS"

MAIN_LOCKS=$(bash "${PROJ}/taskwarrior/tw" +AI_LOCK airole:coordinator count 2>/dev/null || echo "ERR")
assert_eq "main DB coordinator locks" "0" "$MAIN_LOCKS"

MAIN_PM_LOCKS=$(bash "${PROJ}/taskwarrior/tw" +AI_LOCK airole:pm count 2>/dev/null || echo "ERR")
assert_eq "main DB PM locks" "1" "$MAIN_PM_LOCKS"

# --- 3b. No heartbeat yet: the Coordinator has not started ---------------
# This is the state epic E0001 was actually in when its Coordinator died, and it
# used to be invisible to the PM.
echo "--- 3b. Liveness before the Coordinator starts ---"
CS_OUT=$(bash "${PROJ}/taskwarrior/coordinator-status" 2>&1)
CS_RC=$?
assert_eq "coordinator-status exit code (no heartbeat)" "2" "$CS_RC"
if echo "$CS_OUT" | grep -q "liveness:    NO-HEARTBEAT"; then
    pass "liveness reported NO-HEARTBEAT"
else
    fail "liveness reported NO-HEARTBEAT"
    echo "$CS_OUT" | sed 's/^/    /'
fi

# --- 4. story-init from the WRONG cwd still hits the worktree ------------
# This is the exact failure that took down epic E0001: the Coordinator's cwd was
# the main tree, so story-init wrote malformed tasks into main's DB and moved
# main's HEAD onto a story branch.
echo "--- 4. story-init invoked from the main tree cwd ---"
SI_OUT=$(cd "$PROJ" && bash .worktrees/epic-E0001-smoke/taskwarrior/story-init 00001 smoke-story 2>&1)
SI_RC=$?
assert_eq "story-init exit code" "0" "$SI_RC"
if [ "$SI_RC" -ne 0 ]; then
    echo "$SI_OUT" | sed 's/^/    /'
fi

WT_PHASE=$(bash "${WT}/taskwarrior/tw" aiphase.any: count 2>/dev/null || echo "ERR")
assert_eq "worktree DB phase tasks" "4" "$WT_PHASE"

WT_REQ_PHASE=$(bash "${WT}/taskwarrior/tw" aistory:00001 aiphase:req export 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0].get('aiphase','') if d else 'MISSING')" 2>/dev/null || echo "ERR")
assert_eq "req task has a real aiphase UDA" "req" "$WT_REQ_PHASE"

MAIN_PHASE=$(bash "${PROJ}/taskwarrior/tw" status:pending count 2>/dev/null || echo "ERR")
assert_eq "main DB pending tasks (PM lock + gate + epic only)" "3" "$MAIN_PHASE"

MAIN_MALFORMED=$(bash "${PROJ}/taskwarrior/tw" status:pending export 2>/dev/null \
    | python3 -c "import sys,json; print(sum(1 for t in json.load(sys.stdin) if 'aiphase:' in t.get('description','')))" 2>/dev/null || echo "ERR")
assert_eq "main DB malformed tasks (UDAs folded into description)" "0" "$MAIN_MALFORMED"

MAIN_HEAD=$(git -C "$PROJ" rev-parse --abbrev-ref HEAD)
assert_eq "main HEAD unchanged" "main" "$MAIN_HEAD"

WT_HEAD=$(git -C "$WT" rev-parse --abbrev-ref HEAD)
assert_eq "worktree HEAD on story branch" "story/00001-smoke-story" "$WT_HEAD"

# --- 5. Context guards reject cross-tree invocation ----------------------
echo "--- 5. Context guards ---"
(cd "$WT" && bash taskwarrior/epic-status >/dev/null 2>&1)
assert_eq "main-only script rejected inside worktree" "2" "$?"

(cd "$PROJ" && bash taskwarrior/story-next 00001 >/dev/null 2>&1)
assert_eq "worktree-only script rejected in main tree" "2" "$?"

# --- 6. Coordinator telemetry -------------------------------------------
echo "--- 6. Heartbeat and progress ---"
HB_FILE="${WT}/.task/coordinator-status.json"
if [ -f "$HB_FILE" ]; then
    pass "heartbeat file written by story-init"
else
    fail "heartbeat file written by story-init"
fi

HB_EVENT=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('event',''))" "$HB_FILE" 2>/dev/null || echo "ERR")
assert_eq "last heartbeat event" "story-init" "$HB_EVENT"

SEQ_BEFORE=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('sequence',0))" "$HB_FILE" 2>/dev/null || echo "0")

# Drive one phase forward the way a Coordinator and a phase agent would.
bash "${WT}/taskwarrior/coordinator-lock-acquire" >/dev/null 2>&1
REQ_TASK=$(bash "${WT}/taskwarrior/tw" aistory:00001 aiphase:req ids 2>/dev/null | awk '{print $1}')
bash "${WT}/taskwarrior/phase-start" "$REQ_TASK" >/dev/null 2>&1
bash "${WT}/taskwarrior/phase-annotate" "$REQ_TASK" Artifact plan/requirements/core/00001-smoke.md >/dev/null 2>&1
bash "${WT}/taskwarrior/phase-transition" "$REQ_TASK" review >/dev/null 2>&1

SEQ_AFTER=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('sequence',0))" "$HB_FILE" 2>/dev/null || echo "0")
if [ "$SEQ_AFTER" -gt "$SEQ_BEFORE" ]; then
    pass "heartbeat sequence advanced with pipeline work (${SEQ_BEFORE} -> ${SEQ_AFTER})"
else
    fail "heartbeat sequence advanced with pipeline work (${SEQ_BEFORE} -> ${SEQ_AFTER})"
fi

bash "${PROJ}/taskwarrior/coordinator-status" >/dev/null 2>&1
assert_eq "coordinator-status exit code (live Coordinator)" "0" "$?"

CS_LIVE=$(bash "${PROJ}/taskwarrior/coordinator-status" 2>&1)
if echo "$CS_LIVE" | grep -q "liveness:    OK"; then
    pass "liveness reported OK"
else
    fail "liveness reported OK"
    echo "$CS_LIVE" | sed 's/^/    /'
fi
if echo "$CS_LIVE" | grep -q "lock:        HELD"; then
    pass "lock reported HELD"
else
    fail "lock reported HELD"
fi
if echo "$CS_LIVE" | grep -q "phases 0/4 done"; then
    pass "progress counts phase tasks"
else
    fail "progress counts phase tasks"
    echo "$CS_LIVE" | sed 's/^/    /'
fi

AI_HEARTBEAT_STALE_SECONDS=0 AI_HEARTBEAT_DEAD_SECONDS=9999 \
    bash "${PROJ}/taskwarrior/coordinator-status" >/dev/null 2>&1
assert_eq "stale threshold crossed exits 1" "1" "$?"

AI_HEARTBEAT_STALE_SECONDS=0 AI_HEARTBEAT_DEAD_SECONDS=0 \
    bash "${PROJ}/taskwarrior/coordinator-status" >/dev/null 2>&1
assert_eq "dead threshold crossed exits 2" "2" "$?"

if bash "${PROJ}/taskwarrior/coordinator-status" --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['worktrees'], 'no worktrees in json'
assert d['worktrees'][0]['epic'] == 'E0001', d['worktrees'][0]['epic']
" 2>/dev/null; then
    pass "--json output is valid and populated"
else
    fail "--json output is valid and populated"
fi

# A released lock plus a `stopped` event means the Coordinator finished cleanly.
bash "${WT}/taskwarrior/coordinator-lock-release" >/dev/null 2>&1
CS_DONE=$(bash "${PROJ}/taskwarrior/coordinator-status" 2>&1)
CS_DONE_RC=$?
assert_eq "coordinator-status exit code (finished)" "0" "$CS_DONE_RC"
if echo "$CS_DONE" | grep -q "liveness:    DONE"; then
    pass "liveness reported DONE after lock release"
else
    fail "liveness reported DONE after lock release"
    echo "$CS_DONE" | sed 's/^/    /'
fi

# --- 6b. Phase boundary, gate, and rigor --------------------------------
# The failed run this rework came from deadlocked at a phase boundary: phase-done
# completed a task without opening its successor, which stayed aistate:blocked
# forever. Guard that, the gate, and light rigor here.
echo "--- 6b. Phase boundary, gate, and rigor ---"

# req has no gate, so phase-gate must pass rather than block the phase.
bash "${WT}/taskwarrior/phase-gate" "$REQ_TASK" >/dev/null 2>&1
assert_eq "phase-gate exit code (req has no gate)" "0" "$?"

bash "${WT}/taskwarrior/phase-transition" "$REQ_TASK" done >/dev/null 2>&1
bash "${WT}/taskwarrior/phase-done" "$REQ_TASK" >/dev/null 2>&1
assert_eq "phase-done exit code" "0" "$?"

ARCH_STATE=$(bash "${WT}/taskwarrior/tw" aistory:00001 aiphase:arch export 2>/dev/null | python3 -c "
import json, sys
t = json.load(sys.stdin)
print(t[0].get('aistate', '') if t else 'MISSING')
" 2>/dev/null || echo "ERR")
assert_eq "phase-done opened the successor at its initial state" "plan" "$ARCH_STATE"

# An unfilled gate placeholder must warn and pass, not fail the pipeline.
bash "${WT}/taskwarrior/phase-gate" "$(bash "${WT}/taskwarrior/tw" aistory:00001 aiphase:arch ids 2>/dev/null | awk '{print $1}')" >/dev/null 2>&1
assert_eq "phase-gate exit code (unfilled profile placeholder)" "0" "$?"

# A light story gets one impl task, opened at write. story-init cuts story
# branches from the epic branch, so go back to it first.
git -C "$WT" checkout -q "epic/E0001-smoke" 2>/dev/null
bash "${WT}/taskwarrior/story-init" 00002 light-story --rigor light >/dev/null 2>&1
assert_eq "story-init --rigor light exit code" "0" "$?"
LIGHT_COUNT=$(bash "${WT}/taskwarrior/tw" aistory:00002 count 2>/dev/null || echo "0")
assert_eq "light story phase task count" "1" "$LIGHT_COUNT"
LIGHT_STATE=$(bash "${WT}/taskwarrior/tw" aistory:00002 export 2>/dev/null | python3 -c "
import json, sys
t = json.load(sys.stdin)
print('%s:%s' % (t[0].get('aiphase', ''), t[0].get('aistate', '')) if t else 'MISSING')
" 2>/dev/null || echo "ERR")
assert_eq "light story opens at impl/write" "impl:write" "$LIGHT_STATE"

git -C "$WT" checkout -q "epic/E0001-smoke" 2>/dev/null
bash "${WT}/taskwarrior/story-init" 00003 bad-rigor --rigor sloppy >/dev/null 2>&1
assert_eq "story-init rejects an unknown rigor" "2" "$?"

# Put the tree back where section 7 and doctor expect it.
git -C "$WT" checkout -q "story/00001-smoke-story" 2>/dev/null

# --- 7. Escalation is visible to the PM ---------------------------------
# The req task is completed by now, so block the arch task instead.
echo "--- 7. Escalation visibility ---"
ARCH_TASK=$(bash "${WT}/taskwarrior/tw" aistory:00001 aiphase:arch ids 2>/dev/null | awk '{print $1}')
mkdir -p "${WT}/plan/escalations"
echo "# Escalation" > "${WT}/plan/escalations/00001-req-smoke.md"
bash "${WT}/taskwarrior/phase-block" "$ARCH_TASK" plan/escalations/00001-req-smoke.md >/dev/null 2>&1
CS_ESC=$(bash "${PROJ}/taskwarrior/coordinator-status" 2>&1)
CS_ESC_RC=$?
assert_eq "coordinator-status exit code (escalation recorded)" "2" "$CS_ESC_RC"
if echo "$CS_ESC" | grep -q "escalation:  plan/escalations/00001-req-smoke.md"; then
    pass "escalation path surfaced to the PM"
else
    fail "escalation path surfaced to the PM"
    echo "$CS_ESC" | sed 's/^/    /'
fi

# phase-resume is the only thing that clears +blocked; phase-transition does not.
bash "${WT}/taskwarrior/phase-resume" "$ARCH_TASK" "smoke recovery" >/dev/null 2>&1
assert_eq "phase-resume exit code" "0" "$?"
BLOCKED_AFTER=$(bash "${WT}/taskwarrior/tw" "$ARCH_TASK" +blocked count 2>/dev/null || echo "ERR")
assert_eq "phase-resume cleared +blocked" "0" "$BLOCKED_AFTER"

# Re-block so doctor's blocked-task/escalation-file invariant still holds below.
bash "${WT}/taskwarrior/phase-block" "$ARCH_TASK" plan/escalations/00001-req-smoke.md >/dev/null 2>&1

# --- 8. Doctor sees a healthy deployment --------------------------------
echo "--- 8. Doctor ---"
DOC_OUT=$(bash "${PROJ}/taskwarrior/doctor" 2>&1)
DOC_RC=$?
if [ "$DOC_RC" -eq 0 ]; then
    pass "doctor exit code on a healthy tree (0)"
else
    fail "doctor exit code on a healthy tree (got ${DOC_RC})"
    echo "$DOC_OUT" | sed 's/^/    /'
fi

if bash "${PROJ}/taskwarrior/doctor" --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert len(d['checks']) >= 12, len(d['checks'])
" 2>/dev/null; then
    pass "doctor --json reports all checks"
else
    fail "doctor --json reports all checks"
fi

# Recreate the exact E0001 contamination and confirm doctor detects and fixes it.
git -C "$PROJ" branch stray-story-branch main >/dev/null 2>&1
git -C "$PROJ" symbolic-ref HEAD refs/heads/stray-story-branch
bash "${PROJ}/taskwarrior/tw" add "Story 09999: Requirements aiphase:req aistate:plan aistory:09999" >/dev/null 2>&1
bash "${PROJ}/taskwarrior/tw" add "Forge Lock: Coordinator" +AI_LOCK airole:coordinator >/dev/null 2>&1

bash "${PROJ}/taskwarrior/doctor" >/dev/null 2>&1
assert_eq "doctor detects contamination (exit 1, fixable)" "1" "$?"

bash "${PROJ}/taskwarrior/doctor" --fix --force >/dev/null 2>&1
FIX_RC=$?
MAIN_HEAD_AFTER=$(git -C "$PROJ" rev-parse --abbrev-ref HEAD)
assert_eq "doctor --fix restored main HEAD" "main" "$MAIN_HEAD_AFTER"

MAIN_MALFORMED_AFTER=$(bash "${PROJ}/taskwarrior/tw" status:pending export 2>/dev/null \
    | python3 -c "import sys,json; print(sum(1 for t in json.load(sys.stdin) if 'aiphase:' in t.get('description','')))" 2>/dev/null || echo "ERR")
assert_eq "doctor --fix removed malformed tasks" "0" "$MAIN_MALFORMED_AFTER"

MAIN_COORD_AFTER=$(bash "${PROJ}/taskwarrior/tw" +AI_LOCK airole:coordinator count 2>/dev/null || echo "ERR")
assert_eq "doctor --fix removed stray coordinator lock" "0" "$MAIN_COORD_AFTER"

# --- 9. Deployment validator agrees ------------------------------------
echo "--- 9. Deployment validator ---"
VAL_OUT=$(cd "$PROJ" && bash "${REPO_ROOT}/scripts/validate-deployment.sh" 2>&1)
VAL_RC=$?
if [ "$VAL_RC" -eq 0 ]; then
    pass "validate-deployment.sh reports no errors"
else
    fail "validate-deployment.sh reported ${VAL_RC} error(s)"
    echo "$VAL_OUT" | grep -E '^(ERROR|WARNING)' | sed 's/^/    /'
fi

# --- Results ------------------------------------------------------------
echo ""
echo "=== Results ==="
if [ "$FAILURES" -eq 0 ]; then
    echo "All isolation assertions passed."
    exit 0
fi
echo "$FAILURES assertion(s) failed."
exit 1
