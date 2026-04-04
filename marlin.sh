#!/usr/bin/env bash
# ==========================================================================
# MARLIN V3 — UNIVERSAL LAUNCHER
# ==========================================================================
# Single entry point for all Marlin V3 automation across all platforms.
# Detects or asks the user's OS, then routes to the correct scripts.
#
# Usage:
#   ./marlin.sh              — Interactive mode (asks OS + phase)
#   ./marlin.sh --os macos   — Skip OS selection
#   ./marlin.sh --os wsl     — Use Windows/WSL scripts
#   ./marlin.sh --os linux   — Use Linux scripts
# ==========================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------
# OS Detection
# --------------------------------------------------------------------------
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

# --------------------------------------------------------------------------
# Banner
# --------------------------------------------------------------------------
show_banner() {
    clear
    echo ""
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║                                                          ║"
    echo "  ║        MARLIN V3 — UNIVERSAL AUTOMATION LAUNCHER         ║"
    echo "  ║                                                          ║"
    echo "  ║   Phase 1: PR Selection                                  ║"
    echo "  ║   Phase 2: Prompt Preparation                            ║"
    echo "  ║   Phase 3: Environment & CLI Setup                       ║"
    echo "  ║                                                          ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# --------------------------------------------------------------------------
# OS Selection
# --------------------------------------------------------------------------
select_os() {
    local detected
    detected=$(detect_os)

    echo -e "  ${BOLD}Select your operating system:${NC}"
    echo ""

    local macos_tag="" linux_tag="" wsl_tag=""
    case "$detected" in
        macos) macos_tag=" ${GREEN}(detected)${NC}" ;;
        linux) linux_tag=" ${GREEN}(detected)${NC}" ;;
        wsl)   wsl_tag=" ${GREEN}(detected)${NC}" ;;
    esac

    echo -e "    ${CYAN}1${NC}) macOS${macos_tag}"
    echo -e "    ${CYAN}2${NC}) Linux${linux_tag}"
    echo -e "    ${CYAN}3${NC}) Windows (WSL)${wsl_tag}"
    echo ""

    if [[ "$detected" != "unknown" ]]; then
        local default_num=1
        case "$detected" in
            macos) default_num=1 ;;
            linux) default_num=2 ;;
            wsl)   default_num=3 ;;
        esac
        read -rp "  Choice [1/2/3] (default: $default_num): " os_choice
        os_choice="${os_choice:-$default_num}"
    else
        read -rp "  Choice [1/2/3]: " os_choice
    fi

    case "$os_choice" in
        1) MARLIN_OS="macos" ;;
        2) MARLIN_OS="linux" ;;
        3) MARLIN_OS="wsl" ;;
        *)
            echo -e "  ${RED}Invalid choice.${NC}"
            exit 1
            ;;
    esac

    echo ""
    echo -e "  ${GREEN}✓${NC} Platform: ${BOLD}${MARLIN_OS}${NC}"
    echo ""
}

# --------------------------------------------------------------------------
# Phase Selection
# --------------------------------------------------------------------------
select_phase() {
    echo -e "  ${BOLD}Select what you want to do:${NC}"
    echo ""
    echo -e "    ${CYAN}1${NC}) ${BOLD}Phase 1${NC} — PR Selection (capture repos & PRs from clipboard)"
    echo -e "    ${CYAN}2${NC}) ${BOLD}Phase 2${NC} — Prompt Preparation (validate prompt quality)"
    echo -e "    ${CYAN}3${NC}) ${BOLD}Phase 3${NC} — Environment & CLI Setup (download repo, install deps, launch HFI)"
    echo -e "    ${CYAN}4${NC}) ${BOLD}Phase 3 Review${NC} — Post-model-run evaluation (extract diffs, generate answers)"
    echo ""
    echo -e "    ${CYAN}5${NC}) ${DIM}Full pipeline (Phase 1 → 2 → 3 sequentially)${NC}"
    echo -e "    ${CYAN}6${NC}) ${DIM}WSL Setup (install prerequisites for Windows/WSL)${NC}"
    echo ""
    read -rp "  Choice [1-6]: " phase_choice
    echo ""
}

# --------------------------------------------------------------------------
# Route to correct scripts based on OS + Phase
# --------------------------------------------------------------------------
run_phase() {
    local os="$1"
    local phase="$2"

    case "$os" in
        macos|linux)
            case "$phase" in
                1)
                    echo -e "  ${CYAN}→ Running Phase 1 (PR Selection)...${NC}"
                    echo ""
                    local p1_script="$SCRIPT_DIR/phase-1-automation-cursor/marlin_phase1.sh"
                    if [[ ! -f "$p1_script" ]]; then
                        echo -e "  ${RED}✗ Script not found: $p1_script${NC}"
                        exit 1
                    fi
                    echo -e "  ${DIM}Commands:${NC}"
                    echo -e "    ${CYAN}repos${NC}  — Capture repo URLs from clipboard"
                    echo -e "    ${CYAN}prs${NC}    — Capture PR URLs from clipboard"
                    echo -e "    ${CYAN}full${NC}   — Both steps sequentially"
                    echo ""
                    read -rp "  Sub-command [repos/prs/full]: " p1_cmd
                    bash "$p1_script" "${p1_cmd:-full}"
                    ;;
                2)
                    echo -e "  ${CYAN}→ Running Phase 2 (Prompt Validator)...${NC}"
                    echo ""
                    local p1_script="$SCRIPT_DIR/phase-1-automation-cursor/marlin_phase1.sh"
                    echo -e "  ${DIM}Options:${NC}"
                    echo -e "    ${CYAN}1${NC}) Paste prompt text inline"
                    echo -e "    ${CYAN}2${NC}) Read from a file"
                    echo ""
                    read -rp "  Choice [1/2]: " val_choice
                    if [[ "$val_choice" == "2" ]]; then
                        read -rp "  File path: " prompt_file
                        bash "$p1_script" validate --file "$prompt_file"
                    else
                        echo "  Paste your prompt (press Ctrl+D when done):"
                        local prompt_text
                        prompt_text=$(cat)
                        bash "$p1_script" validate "$prompt_text"
                    fi
                    ;;
                3)
                    echo -e "  ${CYAN}→ Running Phase 3 (Environment Setup)...${NC}"
                    echo ""
                    local p3_script="$SCRIPT_DIR/phase-3-automation/marlin_setup.sh"
                    if [[ ! -f "$p3_script" ]]; then
                        echo -e "  ${RED}✗ Script not found: $p3_script${NC}"
                        exit 1
                    fi
                    bash "$p3_script"
                    ;;
                4)
                    echo -e "  ${CYAN}→ Running Phase 3 Review...${NC}"
                    echo ""
                    local review_script="$SCRIPT_DIR/phase-3-automation/marlin_review.sh"
                    if [[ ! -f "$review_script" ]]; then
                        echo -e "  ${RED}✗ Script not found: $review_script${NC}"
                        exit 1
                    fi
                    bash "$review_script" "$@"
                    ;;
                5)
                    echo -e "  ${CYAN}→ Running Full Pipeline (Phase 1 → 2 → 3)...${NC}"
                    echo ""
                    run_phase "$os" 1
                    echo ""
                    echo -e "  ${GREEN}Phase 1 complete. Proceeding to Phase 3 setup.${NC}"
                    echo -e "  ${YELLOW}(Phase 2 runs inside Cursor — ask Cursor to [prepare-prompt])${NC}"
                    echo ""
                    read -rp "  Press Enter when Phase 2 is done in Cursor..." _
                    run_phase "$os" 3
                    ;;
                6)
                    echo -e "  ${YELLOW}WSL Setup is only needed on Windows/WSL.${NC}"
                    echo -e "  ${GREEN}Your macOS/Linux system already has the required tools.${NC}"
                    echo ""
                    echo -e "  Just ensure these are installed:"
                    echo -e "    ${CYAN}git${NC}, ${CYAN}python3${NC}, ${CYAN}tmux${NC}, ${CYAN}gh${NC} (GitHub CLI)"
                    ;;
            esac
            ;;
        wsl)
            local wsl_dir="$SCRIPT_DIR/wsl"
            if [[ ! -d "$wsl_dir" ]]; then
                echo -e "  ${RED}✗ WSL directory not found: $wsl_dir${NC}"
                echo -e "  ${YELLOW}Run the WSL setup first.${NC}"
                exit 1
            fi

            case "$phase" in
                1)
                    echo -e "  ${CYAN}→ Running Phase 1 for WSL...${NC}"
                    echo ""
                    local p1_script="$wsl_dir/phase1/marlin_phase1.sh"
                    if [[ ! -f "$p1_script" ]]; then
                        echo -e "  ${RED}✗ Script not found: $p1_script${NC}"
                        exit 1
                    fi
                    echo -e "  ${DIM}Commands:${NC}"
                    echo -e "    ${CYAN}repos${NC}  — Capture repo URLs from clipboard"
                    echo -e "    ${CYAN}prs${NC}    — Capture PR URLs from clipboard"
                    echo -e "    ${CYAN}full${NC}   — Both steps sequentially"
                    echo ""
                    read -rp "  Sub-command [repos/prs/full]: " p1_cmd
                    bash "$p1_script" "${p1_cmd:-full}"
                    ;;
                2)
                    echo -e "  ${CYAN}→ Running Phase 2 for WSL...${NC}"
                    echo ""
                    local p1_script="$wsl_dir/phase1/marlin_phase1.sh"
                    echo -e "  ${DIM}Options:${NC}"
                    echo -e "    ${CYAN}1${NC}) Paste prompt text inline"
                    echo -e "    ${CYAN}2${NC}) Read from a file"
                    echo ""
                    read -rp "  Choice [1/2]: " val_choice
                    if [[ "$val_choice" == "2" ]]; then
                        read -rp "  File path: " prompt_file
                        bash "$p1_script" validate --file "$prompt_file"
                    else
                        echo "  Paste your prompt (press Ctrl+D when done):"
                        local prompt_text
                        prompt_text=$(cat)
                        bash "$p1_script" validate "$prompt_text"
                    fi
                    ;;
                3)
                    echo -e "  ${CYAN}→ Running Phase 3 for WSL...${NC}"
                    echo ""
                    local p3_script="$wsl_dir/phase3/marlin_setup.sh"
                    if [[ ! -f "$p3_script" ]]; then
                        echo -e "  ${RED}✗ Script not found: $p3_script${NC}"
                        exit 1
                    fi
                    bash "$p3_script"
                    ;;
                4)
                    echo -e "  ${CYAN}→ Running Phase 3 Review for WSL...${NC}"
                    echo ""
                    local review_script="$wsl_dir/phase3/marlin_review.sh"
                    if [[ ! -f "$review_script" ]]; then
                        echo -e "  ${RED}✗ Script not found: $review_script${NC}"
                        exit 1
                    fi
                    bash "$review_script" "$@"
                    ;;
                5)
                    echo -e "  ${CYAN}→ Running Full Pipeline for WSL...${NC}"
                    echo ""
                    run_phase wsl 1
                    echo ""
                    echo -e "  ${GREEN}Phase 1 complete. Proceeding to Phase 3 setup.${NC}"
                    echo -e "  ${YELLOW}(Phase 2 runs inside Cursor — ask Cursor to [prepare-prompt])${NC}"
                    echo ""
                    read -rp "  Press Enter when Phase 2 is done in Cursor..." _
                    run_phase wsl 3
                    ;;
                6)
                    echo -e "  ${CYAN}→ Running WSL Prerequisites Setup...${NC}"
                    echo ""
                    local setup_script="$wsl_dir/setup_wsl.sh"
                    if [[ ! -f "$setup_script" ]]; then
                        echo -e "  ${RED}✗ Script not found: $setup_script${NC}"
                        exit 1
                    fi
                    bash "$setup_script"
                    ;;
            esac
            ;;
    esac
}

# --------------------------------------------------------------------------
# CLI argument handling
# --------------------------------------------------------------------------
MARLIN_OS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --os)
            MARLIN_OS="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: ./marlin.sh [--os macos|linux|wsl]"
            echo ""
            echo "Options:"
            echo "  --os <platform>   Skip OS selection (macos, linux, wsl)"
            echo "  --help            Show this help"
            echo ""
            echo "Without arguments, runs interactively."
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# --------------------------------------------------------------------------
# Main flow
# --------------------------------------------------------------------------
show_banner

if [[ -z "$MARLIN_OS" ]]; then
    select_os
fi

echo -e "  ${DIM}────────────────────────────────────────────────────────${NC}"
echo ""

select_phase
run_phase "$MARLIN_OS" "$phase_choice"
