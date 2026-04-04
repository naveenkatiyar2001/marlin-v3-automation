#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# MARLIN V3 — PHASE 1 + PHASE 2 ORCHESTRATOR (WSL-OPTIMIZED)
# ============================================================================
# Windows/WSL version of the Cursor-native Phase 1 & 2 automation.
# Uses powershell.exe/clip.exe for clipboard, apt for packages.
#
# Usage:
#   ./marlin_phase1.sh repos      -> Capture repo URLs from clipboard
#   ./marlin_phase1.sh prs        -> Capture PR URLs from clipboard
#   ./marlin_phase1.sh full       -> Both steps sequentially
#   ./marlin_phase1.sh validate   -> Run prompt quality validator
#   ./marlin_phase1.sh status     -> Show current data state
#   ./marlin_phase1.sh clean      -> Wipe data/ for fresh start
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
PYTHON="${PYTHON:-python3}"

# Try to find the prompt validator — check local, then original location
VALIDATOR="$SCRIPT_DIR/prompt_validator.py"
if [[ ! -f "$VALIDATOR" ]]; then
    VALIDATOR="$(dirname "$SCRIPT_DIR")/../phase-1-automation-cursor/prompt_validator.py"
fi

# Cursor instructions — check local, then original
CURSOR_INSTRUCTIONS="$SCRIPT_DIR/cursor_instructions.md"
if [[ ! -f "$CURSOR_INSTRUCTIONS" ]]; then
    CURSOR_INSTRUCTIONS="$(dirname "$SCRIPT_DIR")/../phase-1-automation-cursor/cursor_instructions.md"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --------------------------------------------------------------------------
# WSL Platform Helpers
# --------------------------------------------------------------------------
wsl_copy_to_clipboard() {
    if command -v clip.exe &>/dev/null; then
        echo -n "$1" | clip.exe
    elif command -v xclip &>/dev/null; then
        echo -n "$1" | xclip -selection clipboard
    fi
}

wsl_open_url() {
    if command -v wslview &>/dev/null; then
        wslview "$1" 2>/dev/null
    elif command -v cmd.exe &>/dev/null; then
        cmd.exe /c start "" "$1" 2>/dev/null
    else
        echo "  Open this URL manually: $1"
    fi
}

# --------------------------------------------------------------------------
# Banner & Preflight
# --------------------------------------------------------------------------
banner() {
    echo ""
    echo -e "${CYAN}+============================================================+${NC}"
    echo -e "${CYAN}|${NC}  ${BOLD}MARLIN V3 — WSL AUTOMATION (P1 + P2)${NC}                   ${CYAN}|${NC}"
    echo -e "${CYAN}|${NC}  ${DIM}Phase 1: PR Selection | Phase 2: Prompt Preparation${NC}     ${CYAN}|${NC}"
    echo -e "${CYAN}|${NC}  ${DIM}Platform: Windows / WSL${NC}                                  ${CYAN}|${NC}"
    echo -e "${CYAN}+============================================================+${NC}"
    echo ""
}

preflight() {
    local ok=true

    if ! "$PYTHON" --version &>/dev/null; then
        echo -e "  ${RED}✗${NC} Python3 not found — install: sudo apt install python3"
        ok=false
    else
        echo -e "  ${GREEN}✓${NC} Python3: $($PYTHON --version 2>&1)"
    fi

    if ! command -v gh &>/dev/null; then
        echo -e "  ${RED}✗${NC} GitHub CLI (gh) not found"
        echo "    Install: https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
        ok=false
    else
        if ! gh auth status &>/dev/null; then
            echo -e "  ${RED}✗${NC} gh CLI not authenticated — run: gh auth login"
            ok=false
        else
            local user
            user=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
            echo -e "  ${GREEN}✓${NC} gh CLI authenticated as ${BOLD}${user}${NC}"
        fi
    fi

    if [[ -f "$CURSOR_INSTRUCTIONS" ]]; then
        echo -e "  ${GREEN}✓${NC} cursor_instructions.md found"
    else
        echo -e "  ${YELLOW}!${NC} cursor_instructions.md not found (will need to reference original)"
    fi

    # WSL-specific checks
    if command -v clip.exe &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} clip.exe available (WSL clipboard)"
    else
        echo -e "  ${YELLOW}!${NC} clip.exe not found — clipboard copy may not work"
    fi

    if command -v powershell.exe &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} powershell.exe available (WSL clipboard read)"
    else
        echo -e "  ${YELLOW}!${NC} powershell.exe not found — clipboard paste may not work"
    fi

    echo ""
    if [[ "$ok" == false ]]; then
        exit 1
    fi
}

# --------------------------------------------------------------------------
# Clipboard Capture
# --------------------------------------------------------------------------
run_clipboard() {
    local mode="$1"
    local label
    [[ "$mode" == "repos" ]] && label="REPOSITORIES" || label="PULL REQUESTS"

    echo -e "${BOLD}CAPTURE ${label} FROM CLIPBOARD${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo "  1. Open Snorkel PR Selection page in your browser."
    echo "  2. Copy each ${mode} name or GitHub URL one by one."
    echo "  3. This tool captures each copy automatically."
    echo "  4. Type END and press Enter when done."
    echo ""
    echo -e "  ${DIM}WSL clipboard: using powershell.exe Get-Clipboard${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
    echo ""

    "$PYTHON" "$SCRIPT_DIR/clipboard_watcher.py" --mode "$mode"

    local json_file="$DATA_DIR/live_${mode}.json"
    local count
    count=$("$PYTHON" -c "
import json
from pathlib import Path
d = json.loads(Path('$json_file').read_text())
print(len(d.get('entries', [])))
" 2>/dev/null || echo "0")

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  CAPTURE COMPLETE — ${count} ${mode} collected${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}NEXT STEP:${NC} Open Cursor and type:"
    echo ""

    if [[ "$mode" == "repos" ]]; then
        echo -e "    ${CYAN}Read wsl/phase1/cursor_instructions.md${NC}"
        echo -e "    ${CYAN}then [analyze-repos]${NC}"
    else
        echo -e "    ${CYAN}Read wsl/phase1/cursor_instructions.md${NC}"
        echo -e "    ${CYAN}then [analyze-prs]${NC}"
    fi

    echo ""
}

# --------------------------------------------------------------------------
# Status & Clean
# --------------------------------------------------------------------------
show_status() {
    echo -e "${BOLD}CURRENT DATA STATUS:${NC}"
    echo ""
    for f in live_repos.json live_prs.json; do
        filepath="$DATA_DIR/$f"
        if [[ -f "$filepath" ]]; then
            local count
            count=$("$PYTHON" -c "
import json
from pathlib import Path
d = json.loads(Path('$filepath').read_text())
entries = d.get('entries', [])
status = d.get('status', 'unknown')
print(f'{len(entries)} entries | status: {status}')
" 2>/dev/null || echo "unknown")
            echo -e "  ${GREEN}✓${NC}  $f  ($count)"
        else
            echo -e "  ${RED}✗${NC}  $f"
        fi
    done
    echo ""
}

clean_data() {
    echo -e "${YELLOW}Cleaning data directory...${NC}"
    rm -rf "$DATA_DIR"
    mkdir -p "$DATA_DIR"
    echo -e "${GREEN}Done. Ready for a fresh run.${NC}"
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
COMMAND="${1:-help}"

banner
preflight

case "$COMMAND" in
    repos|new-task-select-repo|repo)
        mkdir -p "$DATA_DIR"
        run_clipboard repos
        ;;
    prs|select-pr|pr)
        mkdir -p "$DATA_DIR"
        run_clipboard prs
        ;;
    full|all)
        mkdir -p "$DATA_DIR"
        run_clipboard repos
        echo ""
        echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
        echo -e "  ${BOLD}Repo capture done. Now collect PRs.${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
        echo ""
        run_clipboard prs
        ;;
    status)
        show_status
        ;;
    clean)
        clean_data
        ;;
    validate)
        echo -e "${BOLD}PHASE 2: PROMPT QUALITY VALIDATOR${NC}"
        echo -e "${YELLOW}------------------------------------------------------------${NC}"
        echo ""
        if [[ ! -f "$VALIDATOR" ]]; then
            echo -e "  ${RED}✗${NC} Validator not found at: $VALIDATOR"
            echo "  Copy prompt_validator.py into wsl/phase1/ or ensure phase-1-automation-cursor/ exists."
            exit 1
        fi
        if [[ "${2:-}" == "--file" ]] && [[ -n "${3:-}" ]]; then
            "$PYTHON" "$VALIDATOR" --file "$3"
        elif [[ -n "${2:-}" ]]; then
            "$PYTHON" "$VALIDATOR" "$2"
        else
            echo "  Usage:"
            echo "    $0 validate \"Your prompt text here\""
            echo "    $0 validate --file path/to/prompt.txt"
        fi
        echo ""
        ;;
    *)
        echo "Usage: $0 <command>"
        echo ""
        echo -e "${BOLD}Phase 1 — PR Selection:${NC}"
        echo "  repos       Capture repo URLs from clipboard"
        echo "  prs         Capture PR URLs from clipboard"
        echo "  full        Both steps sequentially"
        echo ""
        echo -e "${BOLD}Phase 2 — Prompt Preparation:${NC}"
        echo "  validate    Run prompt quality validator"
        echo ""
        echo -e "${BOLD}Utility:${NC}"
        echo "  status      Show current data state"
        echo "  clean       Wipe data for fresh start"
        echo ""
        echo -e "${DIM}WSL-optimized. Uses powershell.exe for clipboard, apt for packages.${NC}"
        echo ""
        ;;
esac
