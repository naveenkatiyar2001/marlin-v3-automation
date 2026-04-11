#!/bin/bash
# ==========================================================================
#  Marlin V3 — Post-Model-Run Review & Evaluation Automation
#  Waits for model completion, extracts diffs & traces from both
#  trajectories, then triggers Cursor to generate all 19 HFI feedback
#  answers via the self-healing bridge protocol.
#
#  Usage: bash marlin_review.sh <repo-dir>
#         bash marlin_review.sh   (auto-detects from bridge state)
# ==========================================================================
set -euo pipefail

# ── Colors ──
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

# ── Bridge directory ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="$SCRIPT_DIR/.marlin-bridge"
mkdir -p "$BRIDGE_DIR"

# ── Resolve repo directory ──
if [[ -n "${1:-}" && -d "$1" ]]; then
    REPO_DIR="$(cd "$1" && pwd)"
elif [[ -f "$BRIDGE_DIR/live_bridge.json" ]]; then
    REPO_DIR=$(python3 -c "
import json, sys
try:
    d = json.load(open('$BRIDGE_DIR/live_bridge.json'))
    print(d.get('repo_dir', d.get('working_directory', '')))
except: pass
" 2>/dev/null || true)
fi

if [[ -z "${REPO_DIR:-}" || ! -d "${REPO_DIR:-}" ]]; then
    echo ""
    err "Usage: bash marlin_review.sh <repo-dir>"
    err "Could not determine repo directory."
    exit 1
fi

REPO_BASENAME="$(basename "$REPO_DIR")"

echo ""
echo -e "${BOLD}${CYAN}"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │   MARLIN V3 — POST-RUN REVIEW AUTOMATION    │"
echo "  └─────────────────────────────────────────────┘"
echo -e "${NC}"
echo -e "  ${DIM}Repo: $REPO_DIR${NC}"
echo -e "  ${DIM}Time: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""

# ==========================================================================
# PHASE 4: DETECT MODEL COMPLETION
# ==========================================================================
echo -e "${BOLD}${CYAN}  ── Phase 4: Detecting Model Completion ──${NC}"
echo ""

find_hfi_session_dir() {
    local tmp_base
    for tmp_base in /var/folders/*/*/T/claude-hfi /tmp/claude-hfi; do
        if [[ -d "$tmp_base" ]]; then
            for session_dir in "$tmp_base"/*/; do
                if [[ -f "${session_dir}result-0-A.json" || -f "${session_dir}result-0-B.json" ]]; then
                    echo "${session_dir%/}"
                    return 0
                fi
            done
            for session_dir in "$tmp_base"/*/; do
                if [[ -d "$session_dir" ]]; then
                    echo "${session_dir%/}"
                    return 0
                fi
            done
        fi
    done
    return 1
}

HFI_SESSION_DIR=""
POLL_COUNT=0
MAX_POLLS=360  # 30 minutes at 5s intervals

info "Checking for active tmux/HFI sessions..."
echo ""

while true; do
    TMUX_ACTIVE=$(tmux ls 2>/dev/null | grep -cE '[-_][AB]' || true)
    HFI_SESSION_DIR=$(find_hfi_session_dir 2>/dev/null || true)

    RESULT_A_EXISTS=false
    RESULT_B_EXISTS=false
    if [[ -n "$HFI_SESSION_DIR" ]]; then
        [[ -f "$HFI_SESSION_DIR/result-0-A.json" ]] && RESULT_A_EXISTS=true
        [[ -f "$HFI_SESSION_DIR/result-0-B.json" ]] && RESULT_B_EXISTS=true
    fi

    if [[ "$RESULT_A_EXISTS" == true && "$RESULT_B_EXISTS" == true ]]; then
        ok "Both model trajectories completed!"
        echo -e "    ${DIM}Session: $HFI_SESSION_DIR${NC}"
        break
    fi

    if [[ $POLL_COUNT -ge $MAX_POLLS ]]; then
        warn "Timeout after $((MAX_POLLS * 5)) seconds. Proceeding with available data."
        break
    fi

    STATUS_MSG=""
    [[ "$RESULT_A_EXISTS" == true ]] && STATUS_MSG="A done" || STATUS_MSG="A running"
    [[ "$RESULT_B_EXISTS" == true ]] && STATUS_MSG="$STATUS_MSG, B done" || STATUS_MSG="$STATUS_MSG, B running"
    [[ $TMUX_ACTIVE -gt 0 ]] && STATUS_MSG="$STATUS_MSG | tmux sessions: $TMUX_ACTIVE"

    printf "\r  %s[%03d] Waiting for model completion... (%s)%s  " "$DIM" "$POLL_COUNT" "$STATUS_MSG" "$NC"
    POLL_COUNT=$((POLL_COUNT + 1))
    sleep 5
done

echo ""

# ==========================================================================
# PHASE 5A: EXTRACT DIFFS FROM WORKTREES
# ==========================================================================
echo -e "${BOLD}${CYAN}  ── Phase 5A: Extracting Diffs ──${NC}"
echo ""

WORKTREE_A=""
WORKTREE_B=""
cd "$REPO_DIR"

while IFS= read -r wt_line; do
    wt_path=$(echo "$wt_line" | awk '{print $1}')
    if [[ "$wt_path" == *"/A" ]]; then
        WORKTREE_A="$wt_path"
    elif [[ "$wt_path" == *"/B" ]]; then
        WORKTREE_B="$wt_path"
    fi
done < <(git worktree list 2>/dev/null)

# Fallback: check common HFI cache paths
if [[ -z "$WORKTREE_A" ]]; then
    for candidate in "$HOME/.cache/claude-hfi/$REPO_BASENAME/A" "$HOME/.cache/claude-hfi/"*"$REPO_BASENAME"*/A; do
        if [[ -d "$candidate" ]]; then
            WORKTREE_A="$candidate"
            break
        fi
    done
fi
if [[ -z "$WORKTREE_B" ]]; then
    for candidate in "$HOME/.cache/claude-hfi/$REPO_BASENAME/B" "$HOME/.cache/claude-hfi/"*"$REPO_BASENAME"*/B; do
        if [[ -d "$candidate" ]]; then
            WORKTREE_B="$candidate"
            break
        fi
    done
fi

DIFF_A=""
DIFF_B=""
FILES_A=""
FILES_B=""

if [[ -n "$WORKTREE_A" && -d "$WORKTREE_A" ]]; then
    DIFF_A=$(cd "$WORKTREE_A" && git diff HEAD~1..HEAD 2>/dev/null || git diff HEAD 2>/dev/null || echo "(no diff available)")
    FILES_A=$(cd "$WORKTREE_A" && git diff --name-only HEAD~1..HEAD 2>/dev/null || echo "")
    ok "Trajectory A diff extracted ($(echo "$DIFF_A" | wc -l | tr -d ' ') lines)"
    echo -e "    ${DIM}Worktree: $WORKTREE_A${NC}"
    if [[ -n "$FILES_A" ]]; then
        echo -e "    ${DIM}Files changed:${NC}"
        echo "$FILES_A" | while IFS= read -r f; do echo -e "      ${CYAN}$f${NC}"; done
    fi
else
    warn "Trajectory A worktree not found. Checking result JSON for path..."
fi

echo ""

if [[ -n "$WORKTREE_B" && -d "$WORKTREE_B" ]]; then
    DIFF_B=$(cd "$WORKTREE_B" && git diff HEAD~1..HEAD 2>/dev/null || git diff HEAD 2>/dev/null || echo "(no diff available)")
    FILES_B=$(cd "$WORKTREE_B" && git diff --name-only HEAD~1..HEAD 2>/dev/null || echo "")
    ok "Trajectory B diff extracted ($(echo "$DIFF_B" | wc -l | tr -d ' ') lines)"
    echo -e "    ${DIM}Worktree: $WORKTREE_B${NC}"
    if [[ -n "$FILES_B" ]]; then
        echo -e "    ${DIM}Files changed:${NC}"
        echo "$FILES_B" | while IFS= read -r f; do echo -e "      ${CYAN}$f${NC}"; done
    fi
else
    warn "Trajectory B worktree not found. Checking result JSON for path..."
fi

echo ""

# ==========================================================================
# PHASE 5B: EXTRACT MODEL TRACES
# ==========================================================================
echo -e "${BOLD}${CYAN}  ── Phase 5B: Extracting Model Traces ──${NC}"
echo ""

TRACE_A=""
TRACE_B=""
SESSION_FILE_A=""
SESSION_FILE_B=""

if [[ -n "$HFI_SESSION_DIR" ]]; then
    if [[ -f "$HFI_SESSION_DIR/result-0-A.json" ]]; then
        SESSION_FILE_A=$(python3 -c "
import json
d = json.load(open('$HFI_SESSION_DIR/result-0-A.json'))
print(d.get('sessionFilePath', ''))
" 2>/dev/null || true)
    fi
    if [[ -f "$HFI_SESSION_DIR/result-0-B.json" ]]; then
        SESSION_FILE_B=$(python3 -c "
import json
d = json.load(open('$HFI_SESSION_DIR/result-0-B.json'))
print(d.get('sessionFilePath', ''))
" 2>/dev/null || true)
    fi
fi

# Fallback: search for JSONL files
if [[ -z "$SESSION_FILE_A" ]]; then
    SESSION_FILE_A=$(ls -t "$HOME/.claude-hfi/projects/$REPO_BASENAME/"*.jsonl 2>/dev/null | head -1 || true)
fi

extract_trace() {
    local jsonl_file="$1"
    local label="$2"

    if [[ ! -f "$jsonl_file" ]]; then
        echo "(trace file not found: $jsonl_file)"
        return
    fi

    python3 - "$jsonl_file" "$label" << 'PYEOF'
import json, sys

jsonl_file = sys.argv[1]
label = sys.argv[2]

tool_calls = []
text_outputs = []
test_results = []
files_modified = set()

with open(jsonl_file, 'r') as f:
    for line_num, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        event_type = event.get('type', '')

        # Tool use events
        if event_type == 'tool_use' or 'tool' in event_type.lower():
            tool_name = event.get('name', event.get('tool', 'unknown'))
            tool_input = event.get('input', event.get('arguments', {}))
            if isinstance(tool_input, dict):
                cmd = tool_input.get('command', tool_input.get('content', ''))
                file_path = tool_input.get('file_path', tool_input.get('path', ''))
                if file_path:
                    files_modified.add(file_path)
            else:
                cmd = str(tool_input)[:200]
            tool_calls.append(f"[{tool_name}] {str(cmd)[:200]}")

        # Tool result events
        if event_type == 'tool_result' or 'result' in event_type.lower():
            output = event.get('output', event.get('content', ''))
            if isinstance(output, str) and ('PASS' in output or 'FAIL' in output or 'Error' in output):
                test_results.append(output[:500])

        # Text content
        if event_type == 'text' or event_type == 'assistant':
            content = event.get('text', event.get('content', ''))
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get('type') == 'text':
                        text_outputs.append(c.get('text', '')[:300])
            elif isinstance(content, str) and len(content) > 10:
                text_outputs.append(content[:300])

        # Content block with tool_use
        if isinstance(event.get('content'), list):
            for block in event['content']:
                if isinstance(block, dict):
                    if block.get('type') == 'tool_use':
                        name = block.get('name', 'unknown')
                        inp = block.get('input', {})
                        cmd = ''
                        if isinstance(inp, dict):
                            cmd = inp.get('command', inp.get('content', ''))
                            fp = inp.get('file_path', inp.get('path', ''))
                            if fp:
                                files_modified.add(fp)
                        tool_calls.append(f"[{name}] {str(cmd)[:200]}")
                    elif block.get('type') == 'tool_result':
                        out = block.get('content', '')
                        if isinstance(out, str) and ('PASS' in out or 'FAIL' in out or 'Error' in out):
                            test_results.append(out[:500])

out = {}
out['tool_call_count'] = len(tool_calls)
out['tool_calls_summary'] = tool_calls[:50]
out['text_output_count'] = len(text_outputs)
out['text_outputs_summary'] = text_outputs[:20]
out['test_results'] = test_results[:20]
out['files_modified'] = sorted(files_modified)
print(json.dumps(out, indent=2))
PYEOF
}

if [[ -n "$SESSION_FILE_A" && -f "$SESSION_FILE_A" ]]; then
    ok "Trace A found: $(basename "$SESSION_FILE_A")"
    TRACE_A=$(extract_trace "$SESSION_FILE_A" "A" 2>/dev/null || echo '{"error": "parse failed"}')
    TRACE_A_TOOL_COUNT=$(echo "$TRACE_A" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_call_count',0))" 2>/dev/null || echo "?")
    TRACE_A_FILES=$(echo "$TRACE_A" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('files_modified',[])))" 2>/dev/null || echo "?")
    echo -e "    ${DIM}Tool calls: $TRACE_A_TOOL_COUNT | Files modified: $TRACE_A_FILES${NC}"
else
    warn "Trace A session file not found."
    TRACE_A='{"error": "not found"}'
fi

echo ""

if [[ -n "$SESSION_FILE_B" && -f "$SESSION_FILE_B" ]]; then
    ok "Trace B found: $(basename "$SESSION_FILE_B")"
    TRACE_B=$(extract_trace "$SESSION_FILE_B" "B" 2>/dev/null || echo '{"error": "parse failed"}')
    TRACE_B_TOOL_COUNT=$(echo "$TRACE_B" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_call_count',0))" 2>/dev/null || echo "?")
    TRACE_B_FILES=$(echo "$TRACE_B" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('files_modified',[])))" 2>/dev/null || echo "?")
    echo -e "    ${DIM}Tool calls: $TRACE_B_TOOL_COUNT | Files modified: $TRACE_B_FILES${NC}"
else
    warn "Trace B session file not found."
    TRACE_B='{"error": "not found"}'
fi

echo ""

# ==========================================================================
# PHASE 5C: READ ORIGINAL PROMPT AND ACCEPTANCE CRITERIA
# ==========================================================================
echo -e "${BOLD}${CYAN}  ── Phase 5C: Gathering Context ──${NC}"
echo ""

ORIGINAL_PROMPT=""
ACCEPTANCE_CRITERIA=""

# Try to get prompt from bridge data
if [[ -f "$BRIDGE_DIR/live_bridge.json" ]]; then
    ORIGINAL_PROMPT=$(python3 -c "
import json
d = json.load(open('$BRIDGE_DIR/live_bridge.json'))
print(d.get('prompt', d.get('initial_prompt', '')))
" 2>/dev/null || true)
fi

# Try to get from survey answers
if [[ -z "$ORIGINAL_PROMPT" && -f "$BRIDGE_DIR/survey_answers.txt" ]]; then
    info "Prompt not found in bridge. Will include in review_data for manual entry."
fi

# Read CLAUDE.md for repo context
CLAUDE_MD_CONTENT=""
if [[ -f "$REPO_DIR/CLAUDE.md" ]]; then
    CLAUDE_MD_CONTENT=$(head -100 "$REPO_DIR/CLAUDE.md" 2>/dev/null || true)
    ok "CLAUDE.md content loaded ($(echo "$CLAUDE_MD_CONTENT" | wc -l | tr -d ' ') lines)"
fi

# Read the result JSONs for metadata
RESULT_A_META=""
RESULT_B_META=""
if [[ -n "$HFI_SESSION_DIR" ]]; then
    [[ -f "$HFI_SESSION_DIR/result-0-A.json" ]] && RESULT_A_META=$(cat "$HFI_SESSION_DIR/result-0-A.json" 2>/dev/null || true)
    [[ -f "$HFI_SESSION_DIR/result-0-B.json" ]] && RESULT_B_META=$(cat "$HFI_SESSION_DIR/result-0-B.json" 2>/dev/null || true)
fi

echo ""

# ==========================================================================
# PHASE 5D: WRITE REVIEW DATA
# ==========================================================================
echo -e "${BOLD}${CYAN}  ── Phase 5D: Writing Review Data ──${NC}"
echo ""

REVIEW_DATA_FILE="$BRIDGE_DIR/review_data.json"

# Write intermediate files so Python can read them safely (avoids heredoc escaping issues)
TMPDIR_REVIEW=$(mktemp -d)
echo "$DIFF_A"              > "$TMPDIR_REVIEW/diff_a.txt"
echo "$DIFF_B"              > "$TMPDIR_REVIEW/diff_b.txt"
echo "$FILES_A"             > "$TMPDIR_REVIEW/files_a.txt"
echo "$FILES_B"             > "$TMPDIR_REVIEW/files_b.txt"
echo "${TRACE_A:-{}}"       > "$TMPDIR_REVIEW/trace_a.json"
echo "${TRACE_B:-{}}"       > "$TMPDIR_REVIEW/trace_b.json"
echo "$ORIGINAL_PROMPT"     > "$TMPDIR_REVIEW/prompt.txt"
echo "$CLAUDE_MD_CONTENT"   > "$TMPDIR_REVIEW/claude_md.txt"

python3 - "$TMPDIR_REVIEW" "$REVIEW_DATA_FILE" \
    "$REPO_DIR" "$REPO_BASENAME" "${HFI_SESSION_DIR:-}" \
    "${WORKTREE_A:-}" "${SESSION_FILE_A:-}" \
    "${WORKTREE_B:-}" "${SESSION_FILE_B:-}" << 'PYEOF'
import json, sys, os
from datetime import datetime, timezone

tmp = sys.argv[1]
out_file = sys.argv[2]
repo_dir = sys.argv[3]
repo_name = sys.argv[4]
hfi_session = sys.argv[5]
wt_a = sys.argv[6]
sf_a = sys.argv[7]
wt_b = sys.argv[8]
sf_b = sys.argv[9]

def read_file(path, max_lines=500):
    try:
        with open(path, 'r') as f:
            lines = f.readlines()
        if len(lines) > max_lines:
            text = ''.join(lines[:max_lines])
            text += f"\n... [TRUNCATED: {len(lines)} total lines, showing first {max_lines}] ..."
            return text
        return ''.join(lines)
    except:
        return ""

def read_json(path):
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except:
        return {}

def file_lines(path):
    content = read_file(path).strip()
    return [l for l in content.split('\n') if l.strip()] if content else []

review_data = {
    "timestamp": datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    "repo_dir": repo_dir,
    "repo_name": repo_name,
    "hfi_session_dir": hfi_session,
    "original_prompt": read_file(os.path.join(tmp, "prompt.txt")).strip(),
    "trajectory_a": {
        "worktree_path": wt_a,
        "session_file": sf_a,
        "diff_lines": len(read_file(os.path.join(tmp, "diff_a.txt")).splitlines()),
        "files_changed": file_lines(os.path.join(tmp, "files_a.txt")),
        "diff": read_file(os.path.join(tmp, "diff_a.txt")),
        "trace": read_json(os.path.join(tmp, "trace_a.json")),
    },
    "trajectory_b": {
        "worktree_path": wt_b,
        "session_file": sf_b,
        "diff_lines": len(read_file(os.path.join(tmp, "diff_b.txt")).splitlines()),
        "files_changed": file_lines(os.path.join(tmp, "files_b.txt")),
        "diff": read_file(os.path.join(tmp, "diff_b.txt")),
        "trace": read_json(os.path.join(tmp, "trace_b.json")),
    },
    "claude_md_content": read_file(os.path.join(tmp, "claude_md.txt")).strip(),
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

if [[ -f "$REVIEW_DATA_FILE" ]]; then
    ok "Review data written to: $REVIEW_DATA_FILE"
    REVIEW_SIZE=$(wc -c < "$REVIEW_DATA_FILE" | tr -d ' ')
    echo -e "    ${DIM}Size: ${REVIEW_SIZE} bytes${NC}"
else
    err "Failed to write review data!"
    exit 1
fi

echo ""

# ==========================================================================
# PHASE 5E: TRIGGER CURSOR FOR EVALUATION GENERATION
# ==========================================================================
echo -e "${BOLD}${CYAN}  ── Phase 5E: Triggering Evaluation Generation ──${NC}"
echo ""

info "Sending generate_evaluation action to Cursor via bridge..."

python3 << PYEOF
import json

bridge_file = "$BRIDGE_DIR/live_bridge.json"

try:
    with open(bridge_file, 'r') as f:
        bridge = json.load(f)
except:
    bridge = {}

bridge["status"] = "waiting_for_cursor"
bridge["action"] = "generate_evaluation"
bridge["action_request"] = {
    "review_data_path": "$REVIEW_DATA_FILE",
    "output_path": "$BRIDGE_DIR/evaluation_answers.json",
    "repo_dir": "$REPO_DIR",
    "repo_name": "$REPO_BASENAME"
}
bridge["action_response"] = None

with open(bridge_file, 'w') as f:
    json.dump(bridge, f, indent=2)
PYEOF

ok "Bridge updated — action: generate_evaluation"
echo ""
echo -e "  ${YELLOW}${BOLD}ACTION REQUIRED:${NC}"
echo -e "  ${YELLOW}Switch to Cursor and send any message to trigger evaluation.${NC}"
echo -e "  ${YELLOW}Cursor will read the review data and generate all 19 answers.${NC}"
echo ""

# Wait for Cursor to generate evaluation
EVAL_POLL=0
EVAL_MAX=120  # 10 minutes at 5s intervals

info "Waiting for Cursor to generate evaluation answers..."

while true; do
    if [[ -f "$BRIDGE_DIR/evaluation_answers.json" ]]; then
        EVAL_STATUS=$(python3 -c "
import json
d = json.load(open('$BRIDGE_DIR/evaluation_answers.json'))
print(d.get('status', 'unknown'))
" 2>/dev/null || echo "unknown")

        if [[ "$EVAL_STATUS" == "done" || "$EVAL_STATUS" == "complete" ]]; then
            ok "Evaluation answers generated!"
            break
        fi
    fi

    # Also check bridge for response
    BRIDGE_STATUS=$(python3 -c "
import json
d = json.load(open('$BRIDGE_DIR/live_bridge.json'))
r = d.get('action_response', {})
if r and r.get('status') == 'done':
    print('done')
else:
    print('waiting')
" 2>/dev/null || echo "waiting")

    if [[ "$BRIDGE_STATUS" == "done" ]]; then
        ok "Cursor signaled completion."
        break
    fi

    if [[ $EVAL_POLL -ge $EVAL_MAX ]]; then
        warn "Timeout waiting for Cursor. Check $BRIDGE_DIR/evaluation_answers.json"
        break
    fi

    printf "\r  %s[%03d] Waiting for Cursor to generate evaluation...%s  " "$DIM" "$EVAL_POLL" "$NC"
    EVAL_POLL=$((EVAL_POLL + 1))
    sleep 5
done

echo ""

# ==========================================================================
# PHASE 6: DISPLAY EVALUATION ANSWERS
# ==========================================================================
echo -e "${BOLD}${CYAN}"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │   HFI FEEDBACK FORM — GENERATED ANSWERS     │"
echo "  └─────────────────────────────────────────────┘"
echo -e "${NC}"

EVAL_FILE="$BRIDGE_DIR/evaluation_answers.json"

if [[ -f "$EVAL_FILE" ]]; then
    python3 - "$EVAL_FILE" << 'PYEOF2'
import json, sys, textwrap

eval_file = sys.argv[1]

try:
    with open(eval_file, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f"  Could not read evaluation file: {e}")
    sys.exit(1)

answers = data.get('answers', data)

CYAN = '\033[0;36m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BOLD = '\033[1m'
DIM = '\033[2m'
NC = '\033[0m'

text_fields = [
    ('expected_model_response', 'What a senior engineer would do'),
    ('model_a_strengths', 'Model A — Strengths (what it did well)'),
    ('model_a_weaknesses', 'Model A — Weaknesses (what it did poorly)'),
    ('model_b_strengths', 'Model B — Strengths (what it did well)'),
    ('model_b_weaknesses', 'Model B — Weaknesses (what it did poorly)'),
]

scale_fields = [
    ('correctness', 'Correctness'),
    ('mergeability', 'Mergeability / Code Quality'),
    ('instruction_following', 'Instruction Following'),
    ('scope_calibration', 'Scope Calibration'),
    ('risk_management', 'Risk Management'),
    ('honesty', 'Honesty'),
    ('intellectual_independence', 'Intellectual Independence'),
    ('verification', 'Verification'),
    ('clarification_behavior', 'Clarification Behavior'),
    ('engineering_process', 'Engineering Process'),
    ('tone_understandability', 'Tone & Understandability'),
]

final_fields = [
    ('preference', 'Overall Preference (A or B)'),
    ('key_axes', 'Key Axes Driving Preference'),
    ('overall_preference_justification', 'Overall Preference Justification'),
]

def print_field(num, key, label, answers):
    val = answers.get(key, '(not generated)')
    print(f"\n  {BOLD}{GREEN}[{num}] {label}{NC}")
    print(f"  {DIM}Field: {key}{NC}")
    if isinstance(val, str) and len(val) > 80:
        wrapped = textwrap.fill(val, width=72, initial_indent='  ', subsequent_indent='  ')
        print(f"{CYAN}{wrapped}{NC}")
    else:
        print(f"  {CYAN}{val}{NC}")

num = 1
print(f"\n  {BOLD}{YELLOW}── Text Fields (copy-paste these) ──{NC}")
for key, label in text_fields:
    print_field(num, key, label, answers)
    num += 1

print(f"\n  {BOLD}{YELLOW}── Preference Axes (7-point scale: A much better <-> B much better) ──{NC}")
for key, label in scale_fields:
    print_field(num, key, label, answers)
    num += 1

print(f"\n  {BOLD}{YELLOW}── Final Fields ──{NC}")
for key, label in final_fields:
    print_field(num, key, label, answers)
    num += 1

print(f"\n  {DIM}All {num-1} answers displayed. Copy each into the HFI feedback form.{NC}")
PYEOF2

    echo ""

    # Copy all answers to a text file for easy copy-paste
    ANSWERS_TXT="$BRIDGE_DIR/evaluation_answers_formatted.txt"
    python3 - "$EVAL_FILE" "$ANSWERS_TXT" << 'PYEOF3'
import json, sys

eval_file = sys.argv[1]
out_file = sys.argv[2]

with open(eval_file, 'r') as f:
    data = json.load(f)

answers = data.get('answers', data)

fields = [
    'expected_model_response',
    'model_a_strengths', 'model_a_weaknesses',
    'model_b_strengths', 'model_b_weaknesses',
    'correctness', 'mergeability', 'instruction_following',
    'scope_calibration', 'risk_management', 'honesty',
    'intellectual_independence', 'verification',
    'clarification_behavior', 'engineering_process',
    'tone_understandability',
    'preference', 'key_axes', 'overall_preference_justification'
]

with open(out_file, 'w') as f:
    for i, key in enumerate(fields, 1):
        val = answers.get(key, '(not generated)')
        f.write(f"=== [{i}] {key} ===\n")
        f.write(f"{val}\n\n")

print(f"Saved to: {out_file}")
PYEOF3

    ok "Formatted answers also saved to: $ANSWERS_TXT"
    echo -e "  ${DIM}Open this file for easy copy-paste into the HFI form.${NC}"

else
    warn "Evaluation file not found at: $EVAL_FILE"
    echo ""
    echo -e "  ${YELLOW}Cursor may not have generated the answers yet.${NC}"
    echo -e "  ${YELLOW}Switch to Cursor, send a message, and re-run this script.${NC}"
    echo ""
    echo -e "  ${DIM}Or manually review the data at:${NC}"
    echo -e "  ${CYAN}$REVIEW_DATA_FILE${NC}"
fi

echo ""
divider
echo ""
echo -e "  ${GREEN}${BOLD}Review automation complete.${NC}"
echo ""
