#!/usr/bin/env bash
set -uo pipefail

# ==========================================================================
# Marlin V3 — Per-Turn Evidence Capture
# ==========================================================================
# Run after each turn completes to capture diffs, tmux output, screenshots,
# and metadata. Stores everything OUTSIDE the task folder.
#
# Usage:
#   bash capture_evidence.sh <turn-number>
#   bash capture_evidence.sh 1          # After Turn 1 completes
#   bash capture_evidence.sh 2          # After Turn 2 completes
#   bash capture_evidence.sh eval       # After all turns — capture evaluation
# ==========================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}  ✓${NC} $1"; }
warn()  { echo -e "${YELLOW}  !${NC} $1"; }
fail()  { echo -e "${RED}  ✗${NC} $1"; }

TURN="${1:-}"

if [[ -z "$TURN" ]]; then
    echo -e "${BOLD}Marlin V3 — Evidence Capture${NC}"
    echo ""
    echo "Usage:"
    echo -e "  ${CYAN}bash $0 <turn#>${NC}                    Capture turn evidence"
    echo -e "  ${CYAN}bash $0 <turn#> <prompt-file>${NC}      Capture with prompt from file (avoids truncation)"
    echo -e "  ${CYAN}bash $0 eval${NC}                       Capture evaluation answers"
    echo ""
    echo "Examples:"
    echo -e "  ${CYAN}bash $0 1${NC}                          # Interactive prompt paste"
    echo -e "  ${CYAN}bash $0 1 ~/turn1-prompt.txt${NC}       # Load prompt from file (recommended)"
    echo -e "  ${CYAN}bash $0 eval${NC}                       # After all turns"
    echo ""
    echo -e "${BOLD}For long prompts (avoids truncation):${NC}"
    echo -e "  ${CYAN}pbpaste > ~/turn1-prompt.txt${NC}       # Save clipboard to file"
    echo -e "  ${CYAN}bash $0 1 ~/turn1-prompt.txt${NC}       # Capture with full prompt"
    exit 1
fi

# ── Find evidence directory ──
EVIDENCE_DIR="${EVIDENCE_DIR:-}"

if [[ -z "$EVIDENCE_DIR" ]] && [[ -f "$HOME/marlin-evidence/.latest" ]]; then
    EVIDENCE_DIR=$(cat "$HOME/marlin-evidence/.latest" 2>/dev/null)
fi

if [[ -z "$EVIDENCE_DIR" || ! -d "$EVIDENCE_DIR" ]]; then
    # Find the most recent evidence folder
    EVIDENCE_DIR=$(ls -td "$HOME/marlin-evidence/"*/ 2>/dev/null | head -1)
fi

if [[ -z "$EVIDENCE_DIR" || ! -d "$EVIDENCE_DIR" ]]; then
    fail "No evidence directory found."
    echo "  Run the Phase 3 automation first — it creates the evidence folder."
    echo "  Or set EVIDENCE_DIR environment variable."
    exit 1
fi

ok "Evidence directory: $EVIDENCE_DIR"

# ── Detect repo directory from evidence metadata ──
REPO_DIR=""
if [[ -f "$EVIDENCE_DIR/metadata.md" ]]; then
    REPO_DIR=$(grep 'Repo path:' "$EVIDENCE_DIR/metadata.md" 2>/dev/null | head -1 | sed 's/.*Repo path: *//')
fi
if [[ -n "$REPO_DIR" && -d "$REPO_DIR" ]]; then
    cd "$REPO_DIR"
    ok "Repo directory: $REPO_DIR"
else
    warn "Could not detect repo directory from evidence metadata. CLAUDE.md root check may show MISSING."
    echo -e "  ${DIM}This is OK if worktrees A and B have CLAUDE.md.${NC}"
fi

# ── Detect tmux sessions ──
SESSION_A=""
SESSION_B=""
TMUX_SESSIONS=$(tmux ls 2>/dev/null || true)
if [[ -n "$TMUX_SESSIONS" ]]; then
    SESSION_A=$(echo "$TMUX_SESSIONS" | grep -oE '^[^:]+' | grep -E '[-_]A$' | head -1)
    SESSION_B=$(echo "$TMUX_SESSIONS" | grep -oE '^[^:]+' | grep -E '[-_]B$' | head -1)
fi

# ── Detect worktree paths ──
WT_A=""
WT_B=""
for d in "$HOME/.cache/claude-hfi/"*/A; do
    [[ -d "$d" ]] && WT_A="$d" && break
done
for d in "$HOME/.cache/claude-hfi/"*/B; do
    [[ -d "$d" ]] && WT_B="$d" && break
done

# Also try git worktree list
if [[ -z "$WT_A" || -z "$WT_B" ]]; then
    while IFS= read -r wt_line; do
        wt_path=$(echo "$wt_line" | awk '{print $1}')
        [[ -z "$wt_path" ]] && continue
        bname=$(basename "$wt_path")
        [[ "$bname" == "A" || "$wt_path" =~ -A$ ]] && WT_A="$wt_path"
        [[ "$bname" == "B" || "$wt_path" =~ -B$ ]] && WT_B="$wt_path"
    done < <(git worktree list 2>/dev/null)
fi

echo ""
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}"

# ── EVALUATION MODE ──
if [[ "$TURN" == "eval" ]]; then
    echo -e "${BOLD}  Capturing Evaluation Answers${NC}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}"
    echo ""

    read_multiline() {
        local prompt="$1"
        echo -e "  ${BOLD}$prompt${NC}"
        echo -e "  ${DIM}(Type/paste text, then press Enter twice to finish)${NC}"
        local lines=()
        while IFS= read -r line; do
            if [[ -z "$line" && ${#lines[@]} -gt 0 && -z "${lines[-1]}" ]]; then
                unset 'lines[-1]'
                break
            fi
            lines+=("$line")
        done
        printf '%s\n' "${lines[@]}"
    }

    echo -e "  ${BOLD}Rating:${NC}"
    read -rp "  Overall rating (A1/A2/A3/A4/B4/B3/B2/B1): " EVAL_RATING

    echo ""
    echo -e "  ${DIM}April 7 format: Solution Quality / Agency / Communication per model${NC}"
    echo ""
    EVAL_SQ_A=$(read_multiline "Model A -- Solution Quality (correctness, code quality, tests):")
    echo ""
    EVAL_AG_A=$(read_multiline "Model A -- Agency (trace evidence: investigation, judgment, safety):")
    echo ""
    EVAL_CM_A=$(read_multiline "Model A -- Communication (honesty, self-reporting accuracy):")
    echo ""
    EVAL_SQ_B=$(read_multiline "Model B -- Solution Quality (correctness, code quality, tests):")
    echo ""
    EVAL_AG_B=$(read_multiline "Model B -- Agency (trace evidence: investigation, judgment, safety):")
    echo ""
    EVAL_CM_B=$(read_multiline "Model B -- Communication (honesty, self-reporting accuracy):")
    echo ""
    EVAL_KEY_AXIS=$(read_multiline "Key Axis (true driver of preference -- NOT just 'correctness'):")
    echo ""
    EVAL_JUSTIFICATION=$(read_multiline "Overall Preference Justification:")
    echo ""
    EVAL_EXPECTED=$(read_multiline "Expected Model Response (senior engineer baseline):")

    cat >> "$EVIDENCE_DIR/metadata.md" << EVALEOF

## Evaluation (April 7 format)
- Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
- Rating: $EVAL_RATING

### Model A
- Solution Quality: |
$(echo "$EVAL_SQ_A" | sed 's/^/    /')
- Agency: |
$(echo "$EVAL_AG_A" | sed 's/^/    /')
- Communication: |
$(echo "$EVAL_CM_A" | sed 's/^/    /')

### Model B
- Solution Quality: |
$(echo "$EVAL_SQ_B" | sed 's/^/    /')
- Agency: |
$(echo "$EVAL_AG_B" | sed 's/^/    /')
- Communication: |
$(echo "$EVAL_CM_B" | sed 's/^/    /')

### Overall
- Key Axis: |
$(echo "$EVAL_KEY_AXIS" | sed 's/^/    /')
- Justification: |
$(echo "$EVAL_JUSTIFICATION" | sed 's/^/    /')
- Expected Response: |
$(echo "$EVAL_EXPECTED" | sed 's/^/    /')

EVALEOF

    ok "Evaluation saved to metadata.md"

    # Copy session JSONL files
    REPO_BASENAME=$(basename "$(pwd)" 2>/dev/null || echo "unknown")
    for jsonl in "$HOME/.claude-hfi/projects/$REPO_BASENAME/"*.jsonl; do
        [[ -f "$jsonl" ]] && cp "$jsonl" "$EVIDENCE_DIR/session/" 2>/dev/null && \
            ok "Session trace: $(basename "$jsonl")"
    done

    # Also check /var/folders for result files
    for result in /var/folders/*/*/T/claude-hfi/*/result-*.json; do
        [[ -f "$result" ]] && cp "$result" "$EVIDENCE_DIR/session/" 2>/dev/null && \
            ok "Result file: $(basename "$result")"
    done 2>/dev/null

    echo ""
    ok "Evaluation evidence captured."
    echo -e "  ${CYAN}$EVIDENCE_DIR/metadata.md${NC}"
    exit 0
fi

# ── TURN CAPTURE MODE ──
echo -e "${BOLD}  Capturing Turn $TURN Evidence${NC}"
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

# 1. Screenshot (macOS)
if [[ "$(uname -s)" == "Darwin" ]] && command -v screencapture &>/dev/null; then
    screencapture -x "$EVIDENCE_DIR/screenshots/turn${TURN}-terminal.png" 2>/dev/null && \
        ok "Screenshot: screenshots/turn${TURN}-terminal.png" || true
fi

# 2. tmux text captures (full scrollback)
if [[ -n "$SESSION_A" ]]; then
    tmux capture-pane -t "$SESSION_A" -p -S -10000 > "$EVIDENCE_DIR/tmux-captures/turn${TURN}-trajectory-A.txt" 2>/dev/null && \
        ok "tmux capture A: $(wc -l < "$EVIDENCE_DIR/tmux-captures/turn${TURN}-trajectory-A.txt" | tr -d ' ') lines" || \
        warn "Could not capture tmux session A"
else
    warn "tmux Session A not detected"
fi

if [[ -n "$SESSION_B" ]]; then
    tmux capture-pane -t "$SESSION_B" -p -S -10000 > "$EVIDENCE_DIR/tmux-captures/turn${TURN}-trajectory-B.txt" 2>/dev/null && \
        ok "tmux capture B: $(wc -l < "$EVIDENCE_DIR/tmux-captures/turn${TURN}-trajectory-B.txt" | tr -d ' ') lines" || \
        warn "Could not capture tmux session B"
else
    warn "tmux Session B not detected"
fi

# 3. Git diffs from worktrees
DIFF_A_LINES=0
DIFF_B_LINES=0

if [[ -n "$WT_A" && -d "$WT_A" ]]; then
    (cd "$WT_A" && git diff HEAD~1..HEAD 2>/dev/null || git diff HEAD 2>/dev/null) \
        > "$EVIDENCE_DIR/diffs/turn${TURN}-diff-A.patch" 2>/dev/null
    DIFF_A_LINES=$(wc -l < "$EVIDENCE_DIR/diffs/turn${TURN}-diff-A.patch" 2>/dev/null | tr -d ' ')
    ok "Diff A: $DIFF_A_LINES lines → diffs/turn${TURN}-diff-A.patch"
else
    warn "Worktree A not found — cannot capture diff"
fi

if [[ -n "$WT_B" && -d "$WT_B" ]]; then
    (cd "$WT_B" && git diff HEAD~1..HEAD 2>/dev/null || git diff HEAD 2>/dev/null) \
        > "$EVIDENCE_DIR/diffs/turn${TURN}-diff-B.patch" 2>/dev/null
    DIFF_B_LINES=$(wc -l < "$EVIDENCE_DIR/diffs/turn${TURN}-diff-B.patch" 2>/dev/null | tr -d ' ')
    ok "Diff B: $DIFF_B_LINES lines → diffs/turn${TURN}-diff-B.patch"
else
    warn "Worktree B not found — cannot capture diff"
fi

# 4. CLAUDE.md visual proof (exists in all 3 locations with timestamps)
echo ""
info "CLAUDE.md verification + visual proof:"

PROOF_FILE="$EVIDENCE_DIR/screenshots/turn${TURN}-claude-md-proof.txt"
{
    echo "============================================================"
    echo "  CLAUDE.md PROOF — Turn $TURN — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================"
    echo ""
    if [[ -f "CLAUDE.md" ]]; then
        echo "  [EXISTS] Root: $(pwd)/CLAUDE.md"
        ls -la "CLAUDE.md" 2>/dev/null | sed 's/^/    /'
    else
        echo "  [MISSING] Root: CLAUDE.md"
    fi
    echo ""
    if [[ -n "$WT_A" && -f "$WT_A/CLAUDE.md" ]]; then
        echo "  [EXISTS] Worktree A: $WT_A/CLAUDE.md"
        ls -la "$WT_A/CLAUDE.md" 2>/dev/null | sed 's/^/    /'
    else
        echo "  [MISSING] Worktree A"
    fi
    echo ""
    if [[ -n "$WT_B" && -f "$WT_B/CLAUDE.md" ]]; then
        echo "  [EXISTS] Worktree B: $WT_B/CLAUDE.md"
        ls -la "$WT_B/CLAUDE.md" 2>/dev/null | sed 's/^/    /'
    else
        echo "  [MISSING] Worktree B"
    fi
    echo ""
    echo "============================================================"
} > "$PROOF_FILE"

cat "$PROOF_FILE"

[[ -f "CLAUDE.md" ]] && ok "Root: EXISTS ($(wc -c < CLAUDE.md | tr -d ' ') bytes)" || fail "Root: MISSING"
[[ -n "$WT_A" && -f "$WT_A/CLAUDE.md" ]] && ok "Worktree A: EXISTS" || fail "Worktree A: MISSING"
[[ -n "$WT_B" && -f "$WT_B/CLAUDE.md" ]] && ok "Worktree B: EXISTS" || fail "Worktree B: MISSING"

# Screenshot showing the proof (macOS)
if [[ "$(uname -s)" == "Darwin" ]] && command -v screencapture &>/dev/null; then
    sleep 1
    screencapture -x "$EVIDENCE_DIR/screenshots/turn${TURN}-claude-md-visual-proof.png" 2>/dev/null && \
        ok "CLAUDE.md visual proof screenshot: turn${TURN}-claude-md-visual-proof.png" || true
fi

# 5. Prompt — ask user to paste or load from file
PROMPT_FILE="${2:-}"
TURN_PROMPT=""

if [[ -n "$PROMPT_FILE" && -f "$PROMPT_FILE" ]]; then
    TURN_PROMPT=$(cat "$PROMPT_FILE")
    ok "Prompt loaded from file: $PROMPT_FILE ($(wc -c < "$PROMPT_FILE" | tr -d ' ') bytes)"
else
    echo ""
    echo -e "  ${BOLD}How to provide the Turn $TURN prompt:${NC}"
    echo -e "  ${CYAN}  1)${NC} Paste here (press Enter twice to finish)"
    echo -e "  ${CYAN}  2)${NC} Skip (add later to metadata.md manually)"
    echo -e ""
    echo -e "  ${DIM}Tip: For long prompts, save to a file and run:${NC}"
    echo -e "  ${DIM}  bash $0 $TURN /path/to/prompt.txt${NC}"
    echo ""
    read -rp "  Choice [1/2]: " PROMPT_CHOICE

    if [[ "$PROMPT_CHOICE" == "2" ]]; then
        TURN_PROMPT="(skipped — add manually or re-run with: bash $0 $TURN /path/to/prompt.txt)"
        warn "Prompt skipped."
    else
        echo -e "  ${DIM}(Type/paste the prompt text, then press Enter twice to finish)${NC}"
        PROMPT_LINES=()
        while IFS= read -r -n 4096 line; do
            if [[ -z "$line" && ${#PROMPT_LINES[@]} -gt 0 && -z "${PROMPT_LINES[-1]}" ]]; then
                unset 'PROMPT_LINES[-1]'
                break
            fi
            PROMPT_LINES+=("$line")
        done
        TURN_PROMPT=$(printf '%s\n' "${PROMPT_LINES[@]}")
    fi
fi

# 6. Append to metadata.md
CL_ROOT_NOW="MISSING"
CL_A_NOW="MISSING"
CL_B_NOW="MISSING"
[[ -f "CLAUDE.md" ]] && CL_ROOT_NOW="$(wc -c < CLAUDE.md | tr -d ' ') bytes"
[[ -n "$WT_A" && -f "$WT_A/CLAUDE.md" ]] && CL_A_NOW="$(wc -c < "$WT_A/CLAUDE.md" | tr -d ' ') bytes"
[[ -n "$WT_B" && -f "$WT_B/CLAUDE.md" ]] && CL_B_NOW="$(wc -c < "$WT_B/CLAUDE.md" | tr -d ' ') bytes"

cat >> "$EVIDENCE_DIR/metadata.md" << TURNEOF

## Turn $TURN
- Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
- Prompt: |
$(echo "$TURN_PROMPT" | sed 's/^/    /')
- Diff A: diffs/turn${TURN}-diff-A.patch ($DIFF_A_LINES lines)
- Diff B: diffs/turn${TURN}-diff-B.patch ($DIFF_B_LINES lines)
- tmux A: tmux-captures/turn${TURN}-trajectory-A.txt
- tmux B: tmux-captures/turn${TURN}-trajectory-B.txt
- CLAUDE.md root: $CL_ROOT_NOW
- CLAUDE.md worktree A: $CL_A_NOW
- CLAUDE.md worktree B: $CL_B_NOW

TURNEOF

ok "Turn $TURN evidence appended to metadata.md"

# 7. Copy session traces (update each turn)
REPO_BASENAME=$(basename "$(pwd)" 2>/dev/null || echo "unknown")
SESSION_COPIED=0
for jsonl in "$HOME/.claude-hfi/projects/$REPO_BASENAME/"*.jsonl; do
    [[ -f "$jsonl" ]] && cp "$jsonl" "$EVIDENCE_DIR/session/" 2>/dev/null && \
        ((SESSION_COPIED++))
done
[[ $SESSION_COPIED -gt 0 ]] && ok "Session traces updated ($SESSION_COPIED files)"

echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  Turn $TURN evidence captured successfully${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Evidence: ${CYAN}$EVIDENCE_DIR${NC}"
echo -e "  Metadata: ${CYAN}$EVIDENCE_DIR/metadata.md${NC}"
echo ""

if [[ "$TURN" -lt 3 ]] 2>/dev/null; then
    NEXT=$((TURN + 1))
    echo -e "  ${DIM}Next: bash $0 $NEXT  (after Turn $NEXT completes)${NC}"
else
    echo -e "  ${DIM}Next: bash $0 eval  (capture evaluation answers)${NC}"
fi
