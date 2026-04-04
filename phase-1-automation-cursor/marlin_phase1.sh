#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# MARLIN V3 -- PHASE 1 + PHASE 2 ORCHESTRATOR (CURSOR-NATIVE)
# ============================================================================
#
# Cursor-native approach for PR Selection (Phase 1) and Prompt Preparation
# (Phase 2). Clipboard watcher captures URLs, then Cursor fetches data via
# gh CLI and handles analysis + prompt generation directly.
#
# Prerequisites:
#   - gh CLI installed and authenticated (brew install gh && gh auth login)
#   - Python3 (for clipboard watcher + prompt validator)
#   - Cursor IDE with a capable model
#
# Phase 1 (PR Selection):
#   ./marlin_phase1.sh repos      -> Capture repo URLs from clipboard
#   ./marlin_phase1.sh prs        -> Capture PR URLs from clipboard
#   ./marlin_phase1.sh full       -> Both steps sequentially
#
# Phase 2 (Prompt Preparation):
#   ./marlin_phase1.sh validate   -> Run prompt quality validator
#
# Utility:
#   ./marlin_phase1.sh status     -> Show current data state
#   ./marlin_phase1.sh clean      -> Wipe data/ for fresh start
#
# After capture, ask Cursor:
#   [analyze-repos]  or  [analyze-prs]  or  [prepare-prompt]
#
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
PYTHON="${PYTHON:-python3}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

banner() {
  echo ""
  echo -e "${CYAN}+============================================================+${NC}"
  echo -e "${CYAN}|${NC}  ${BOLD}MARLIN V3 -- CURSOR-NATIVE AUTOMATION (P1 + P2)${NC}          ${CYAN}|${NC}"
  echo -e "${CYAN}|${NC}  ${DIM}Phase 1: PR Selection | Phase 2: Prompt Preparation${NC}     ${CYAN}|${NC}"
  echo -e "${CYAN}+============================================================+${NC}"
  echo ""
}

preflight() {
  local ok=true

  if ! command -v "$PYTHON" >/dev/null 2>&1; then
    echo -e "  ${RED}✗${NC} Python3 not found"
    ok=false
  else
    echo -e "  ${GREEN}✓${NC} Python3 available"
  fi

  if ! command -v gh >/dev/null 2>&1; then
    echo -e "  ${RED}✗${NC} GitHub CLI (gh) not found — install: brew install gh"
    ok=false
  else
    if ! gh auth status >/dev/null 2>&1; then
      echo -e "  ${RED}✗${NC} gh CLI not authenticated — run: gh auth login"
      ok=false
    else
      local user
      user=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
      echo -e "  ${GREEN}✓${NC} gh CLI authenticated as ${BOLD}${user}${NC}"
    fi
  fi

  if [ -f "$SCRIPT_DIR/cursor_instructions.md" ]; then
    echo -e "  ${GREEN}✓${NC} cursor_instructions.md present"
  else
    echo -e "  ${RED}✗${NC} cursor_instructions.md MISSING"
    ok=false
  fi

  echo ""

  if [ "$ok" = false ]; then
    exit 1
  fi
}

run_clipboard() {
  local mode="$1"
  local label
  if [ "$mode" = "repos" ]; then
    label="REPOSITORIES"
  else
    label="PULL REQUESTS"
  fi

  echo -e "${BOLD}CAPTURE ${label} FROM CLIPBOARD${NC}"
  echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
  echo ""
  echo "  1. Open Snorkel PR Selection page in your browser."
  echo "  2. Copy each ${mode} name or GitHub URL one by one."
  echo "  3. This tool captures each copy automatically."
  echo "  4. Type END and press Enter when done."
  echo ""
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

  if [ "$mode" = "repos" ]; then
    echo -e "    ${CYAN}Read phase-1-automation-cursor/cursor_instructions.md${NC}"
    echo -e "    ${CYAN}then [analyze-repos]${NC}"
  else
    echo -e "    ${CYAN}Read phase-1-automation-cursor/cursor_instructions.md${NC}"
    echo -e "    ${CYAN}then [analyze-prs]${NC}"
  fi

  echo ""
  echo "  Cursor will:"
  echo "    1. Read the captured URLs from live JSON"
  echo "    2. Fetch real data using gh CLI (authenticated, 5000 req/hr)"
  echo "    3. Analyze against Marlin V3 criteria"
  echo "    4. Output ranked recommendations with scores"
  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo ""
}

show_status() {
  echo -e "${BOLD}CURRENT DATA STATUS:${NC}"
  echo ""

  for f in live_repos.json live_prs.json; do
    filepath="$DATA_DIR/$f"
    if [ -f "$filepath" ]; then
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
  echo -e "  ${BOLD}gh CLI:${NC}"
  gh auth status 2>&1 | head -3 | sed 's/^/  /'
  echo ""
}

clean_data() {
  echo -e "${YELLOW}Cleaning data directory...${NC}"
  rm -rf "$DATA_DIR"
  mkdir -p "$DATA_DIR"
  echo -e "${GREEN}Done. Ready for a fresh run.${NC}"
}

# ── OS Detection & Selection ──────────────────────────────────────────────────
detect_os() {
    if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
        echo "wsl"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        echo "macos"
    elif [[ "$(uname -s)" == "Linux" ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

if [[ -z "${MARLIN_OS:-}" ]]; then
    DETECTED_OS=$(detect_os)
    echo ""
    echo -e "${CYAN}+============================================================+${NC}"
    echo -e "${CYAN}|${NC}  ${BOLD}SELECT YOUR PLATFORM${NC}                                      ${CYAN}|${NC}"
    echo -e "${CYAN}+============================================================+${NC}"
    echo ""

    MACOS_TAG="" LINUX_TAG="" WSL_TAG=""
    case "$DETECTED_OS" in
        macos) MACOS_TAG=" ${GREEN}(detected)${NC}" ;;
        linux) LINUX_TAG=" ${GREEN}(detected)${NC}" ;;
        wsl)   WSL_TAG=" ${GREEN}(detected)${NC}" ;;
    esac

    echo -e "    ${CYAN}1${NC}) macOS${MACOS_TAG}"
    echo -e "    ${CYAN}2${NC}) Linux${LINUX_TAG}"
    echo -e "    ${CYAN}3${NC}) Windows (WSL)${WSL_TAG}"
    echo ""

    DEFAULT_NUM=1
    case "$DETECTED_OS" in
        macos) DEFAULT_NUM=1 ;; linux) DEFAULT_NUM=2 ;; wsl) DEFAULT_NUM=3 ;;
    esac
    read -rp "  Choice [1/2/3] (default: $DEFAULT_NUM): " os_choice
    os_choice="${os_choice:-$DEFAULT_NUM}"

    case "$os_choice" in
        1) MARLIN_OS="macos" ;;
        2) MARLIN_OS="linux" ;;
        3) MARLIN_OS="wsl" ;;
        *) MARLIN_OS="$DETECTED_OS" ;;
    esac

    echo ""
    echo -e "  ${GREEN}✓${NC} Platform: ${BOLD}${MARLIN_OS}${NC}"
    echo ""

    if [[ "$MARLIN_OS" == "wsl" ]]; then
        WSL_SCRIPT="$(dirname "$SCRIPT_DIR")/wsl/phase1/marlin_phase1.sh"
        if [[ -f "$WSL_SCRIPT" ]]; then
            echo -e "  ${BLUE}[INFO]${NC} Launching WSL-optimized Phase 1 script..."
            exec bash "$WSL_SCRIPT" "$@"
        else
            echo -e "  ${RED}  ✗${NC} WSL script not found at: $WSL_SCRIPT"
            exit 1
        fi
    fi
fi

# ── Main ─────────────────────────────────────────────────────────────────────

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
    if [ "${2:-}" = "--file" ] && [ -n "${3:-}" ]; then
      "$PYTHON" "$SCRIPT_DIR/prompt_validator.py" --file "$3"
    elif [ -n "${2:-}" ]; then
      "$PYTHON" "$SCRIPT_DIR/prompt_validator.py" "$2"
    else
      echo "  Usage:"
      echo "    $0 validate \"Your prompt text here\""
      echo "    $0 validate --file path/to/prompt.txt"
      echo ""
      echo "  This checks your prompt against Marlin V3 quality rules:"
      echo "    - No em-dashes (model signature)"
      echo "    - No PR references (#number, pull/number)"
      echo "    - No role-based prompting (You are a senior...)"
      echo "    - No over-prescriptive patterns (on line 47...)"
      echo "    - No LLM signature words (leverage, utilize, delve...)"
      echo "    - Word count in 150-300 range"
      echo "    - Sentence variety (natural writing)"
    fi
    echo ""
    ;;
  *)
    echo "Usage: $0 <command>"
    echo ""
    echo -e "${BOLD}Phase 1 -- PR Selection:${NC}"
    echo "  repos       Capture repo URLs from clipboard"
    echo "  prs         Capture PR URLs from clipboard"
    echo "  full        Both steps sequentially"
    echo ""
    echo -e "${BOLD}Phase 2 -- Prompt Preparation:${NC}"
    echo "  validate    Run prompt quality validator"
    echo ""
    echo -e "${BOLD}Utility:${NC}"
    echo "  status      Show current data state"
    echo "  clean       Wipe data for fresh start"
    echo ""
    echo "After clipboard capture, ask Cursor:"
    echo "  [analyze-repos]  or  [analyze-prs]  or  [prepare-prompt]"
    echo ""
    echo -e "${DIM}This is the CURSOR-NATIVE approach (gh CLI + Cursor intelligence).${NC}"
    echo -e "${DIM}For the TERMINAL-ONLY approach, see: phase-1-automation/${NC}"
    echo ""
    ;;
esac
