#!/bin/bash
# ==========================================================================
# Marlin V3 — Post-Model-Run Review & Evaluation (WSL-Optimized)
# ==========================================================================
# WSL version: uses apt, clip.exe, powershell.exe instead of macOS tools.
# Usage: bash marlin_review.sh <repo-dir>
# ==========================================================================
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✔${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
err()  { echo -e "  ${RED}✘${NC} $*"; }
info() { echo -e "  ${CYAN}ℹ${NC} $*"; }
divider() { echo -e "  ${DIM}──────────────────────────────────────────────────────${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="$SCRIPT_DIR/.marlin-bridge"
mkdir -p "$BRIDGE_DIR"

# Resolve repo directory
if [[ -n "${1:-}" && -d "$1" ]]; then
    REPO_DIR="$(cd "$1" && pwd)"
elif [[ -f "$BRIDGE_DIR/live_bridge.json" ]]; then
    REPO_DIR=$(python3 -c "
import json
try:
    d = json.load(open('$BRIDGE_DIR/live_bridge.json'))
    print(d.get('repo_dir', d.get('working_directory', '')))
except: pass
" 2>/dev/null || true)
fi

if [[ -z "${REPO_DIR:-}" || ! -d "${REPO_DIR:-}" ]]; then
    err "Usage: bash marlin_review.sh <repo-dir>"
    exit 1
fi

REPO_BASENAME="$(basename "$REPO_DIR")"

echo ""
echo -e "${BOLD}${CYAN}"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │   MARLIN V3 — POST-RUN REVIEW (WSL)         │"
echo "  └─────────────────────────────────────────────┘"
echo -e "${NC}"
echo -e "  ${DIM}Repo: $REPO_DIR${NC}"
echo ""

# ==========================================================================
# Detect Model Completion
# ==========================================================================
echo -e "${BOLD}${CYAN}  ── Detecting Model Completion ──${NC}"
echo ""

find_hfi_session_dir() {
    for tmp_base in /tmp/claude-hfi; do
        if [[ -d "$tmp_base" ]]; then
            for session_dir in "$tmp_base"/*/; do
                if [[ -f "${session_dir}result-0-A.json" || -f "${session_dir}result-0-B.json" ]]; then
                    echo "${session_dir%/}"; return 0
                fi
            done
            for session_dir in "$tmp_base"/*/; do
                [[ -d "$session_dir" ]] && { echo "${session_dir%/}"; return 0; }
            done
        fi
    done
    return 1
}

HFI_SESSION_DIR=""
POLL_COUNT=0

while true; do
    HFI_SESSION_DIR=$(find_hfi_session_dir 2>/dev/null || true)
    RESULT_A=false; RESULT_B=false
    if [[ -n "$HFI_SESSION_DIR" ]]; then
        [[ -f "$HFI_SESSION_DIR/result-0-A.json" ]] && RESULT_A=true
        [[ -f "$HFI_SESSION_DIR/result-0-B.json" ]] && RESULT_B=true
    fi

    [[ "$RESULT_A" == true && "$RESULT_B" == true ]] && { ok "Both trajectories completed!"; break; }
    [[ $POLL_COUNT -ge 360 ]] && { warn "Timeout. Proceeding with available data."; break; }

    printf "\r  ${DIM}[%03d] Waiting... (A:%s B:%s)${NC}  " "$POLL_COUNT" \
        "$([[ $RESULT_A == true ]] && echo done || echo running)" \
        "$([[ $RESULT_B == true ]] && echo done || echo running)"
    POLL_COUNT=$((POLL_COUNT + 1))
    sleep 5
done
echo ""

# ==========================================================================
# Extract Diffs
# ==========================================================================
echo -e "${BOLD}${CYAN}  ── Extracting Diffs ──${NC}"
echo ""

cd "$REPO_DIR"
WORKTREE_A=""; WORKTREE_B=""
while IFS= read -r wt_line; do
    wt_path=$(echo "$wt_line" | awk '{print $1}')
    [[ "$wt_path" == *"/A" ]] && WORKTREE_A="$wt_path"
    [[ "$wt_path" == *"/B" ]] && WORKTREE_B="$wt_path"
done < <(git worktree list 2>/dev/null)

# Fallback to cache
[[ -z "$WORKTREE_A" ]] && for c in "$HOME/.cache/claude-hfi/$REPO_BASENAME/A" "$HOME/.cache/claude-hfi/"*"$REPO_BASENAME"*/A; do
    [[ -d "$c" ]] && { WORKTREE_A="$c"; break; }
done
[[ -z "$WORKTREE_B" ]] && for c in "$HOME/.cache/claude-hfi/$REPO_BASENAME/B" "$HOME/.cache/claude-hfi/"*"$REPO_BASENAME"*/B; do
    [[ -d "$c" ]] && { WORKTREE_B="$c"; break; }
done

DIFF_A=""; DIFF_B=""
[[ -n "$WORKTREE_A" && -d "$WORKTREE_A" ]] && {
    DIFF_A=$(cd "$WORKTREE_A" && git diff HEAD~1..HEAD 2>/dev/null || echo "(no diff)")
    ok "Trajectory A diff: $(echo "$DIFF_A" | wc -l | tr -d ' ') lines"
} || warn "Trajectory A worktree not found."

[[ -n "$WORKTREE_B" && -d "$WORKTREE_B" ]] && {
    DIFF_B=$(cd "$WORKTREE_B" && git diff HEAD~1..HEAD 2>/dev/null || echo "(no diff)")
    ok "Trajectory B diff: $(echo "$DIFF_B" | wc -l | tr -d ' ') lines"
} || warn "Trajectory B worktree not found."

echo ""

# ==========================================================================
# Write Review Data & Trigger Evaluation
# ==========================================================================
echo -e "${BOLD}${CYAN}  ── Writing Review Data ──${NC}"
echo ""

REVIEW_DATA_FILE="$BRIDGE_DIR/review_data.json"
TMPDIR_REVIEW=$(mktemp -d)
echo "$DIFF_A" > "$TMPDIR_REVIEW/diff_a.txt"
echo "$DIFF_B" > "$TMPDIR_REVIEW/diff_b.txt"

python3 - "$TMPDIR_REVIEW" "$REVIEW_DATA_FILE" "$REPO_DIR" "$REPO_BASENAME" << 'PYEOF'
import json, sys, os
from datetime import datetime, timezone

tmp = sys.argv[1]
out_file = sys.argv[2]
repo_dir = sys.argv[3]
repo_name = sys.argv[4]

def read_file(path):
    try:
        with open(path) as f: return f.read()
    except: return ""

review_data = {
    "timestamp": datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    "repo_dir": repo_dir,
    "repo_name": repo_name,
    "platform": "wsl",
    "trajectory_a": {"diff": read_file(os.path.join(tmp, "diff_a.txt"))},
    "trajectory_b": {"diff": read_file(os.path.join(tmp, "diff_b.txt"))},
    "feedback_fields": [
        "expected_model_response",
        "model_a_strengths", "model_a_weaknesses",
        "model_b_strengths", "model_b_weaknesses",
        "correctness", "mergeability", "instruction_following",
        "scope_calibration", "risk_management", "honesty",
        "intellectual_independence", "verification",
        "clarification_behavior", "engineering_process",
        "tone_understandability",
        "preference", "key_axes", "overall_preference_justification"
    ]
}

with open(out_file, 'w') as f:
    json.dump(review_data, f, indent=2)
PYEOF

rm -rf "$TMPDIR_REVIEW"
[[ -f "$REVIEW_DATA_FILE" ]] && ok "Review data: $REVIEW_DATA_FILE" || { err "Failed!"; exit 1; }

# Trigger Cursor evaluation
python3 << PYEOF
import json
bridge_file = "$BRIDGE_DIR/live_bridge.json"
try:
    with open(bridge_file) as f: bridge = json.load(f)
except: bridge = {}
bridge["status"] = "waiting_for_cursor"
bridge["action"] = "generate_evaluation"
bridge["action_request"] = {
    "review_data_path": "$REVIEW_DATA_FILE",
    "output_path": "$BRIDGE_DIR/evaluation_answers.json",
    "repo_dir": "$REPO_DIR"
}
with open(bridge_file, 'w') as f:
    json.dump(bridge, f, indent=2)
PYEOF

ok "Bridge updated — action: generate_evaluation"
echo ""
echo -e "  ${YELLOW}Switch to Cursor and send a message to trigger evaluation.${NC}"

# Wait for evaluation
EVAL_POLL=0
while true; do
    [[ -f "$BRIDGE_DIR/evaluation_answers.json" ]] && { ok "Evaluation generated!"; break; }
    [[ $EVAL_POLL -ge 120 ]] && { warn "Timeout. Check $BRIDGE_DIR/evaluation_answers.json"; break; }
    printf "\r  ${DIM}Waiting for evaluation... (%d/120)${NC}  " "$EVAL_POLL"
    EVAL_POLL=$((EVAL_POLL + 1))
    sleep 5
done

echo ""
echo -e "  ${GREEN}${BOLD}Review automation complete.${NC}"
echo ""
