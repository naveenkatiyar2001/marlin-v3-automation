#!/usr/bin/env bash
# ==========================================================================
# MARLIN V3 — PHASE 3: ENVIRONMENT & CLI SETUP
# ==========================================================================
# Interactive setup script that follows the exact Phase 3 structure
# from the Marlin V3 Master Guide (steps 3.1 through 3.10).
#
# Usage:
#   ./marlin_setup.sh              — start a new task
#   ./marlin_setup.sh --list       — list existing task workspaces
#   ./marlin_setup.sh --clean      — remove a task workspace
#   ./marlin_setup.sh --clean-all  — remove ALL task workspaces
#   ./marlin_setup.sh --help       — show this help
# ==========================================================================

set -uo pipefail

# --------------------------------------------------------------------------
# Colors and helpers
# --------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()      { echo -e "${GREEN}  ✓${NC} $1"; }
fail()    { echo -e "${RED}  ✗${NC} $1"; }
warn()    { echo -e "${YELLOW}  !${NC} $1"; }
step()    { echo -e "\n${BOLD}${CYAN}━━━ STEP $1 ━━━${NC}\n"; }
ask()     { echo -e "${YELLOW}▸${NC} $1"; }
divider() { echo -e "${DIM}──────────────────────────────────────────────────${NC}"; }

wait_enter() {
    echo ""
    read -rp "  Press Enter to continue..." _
}

wait_confirm() {
    echo ""
    read -rp "  $1 [y/n]: " yn
    [[ "$yn" =~ ^[Yy] ]]
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR/marlin-workspace"
BRIDGE_DIR="$SCRIPT_DIR/.marlin-bridge"

# --------------------------------------------------------------------------
# Cursor Bridge — real-time terminal <-> Cursor AI communication
# --------------------------------------------------------------------------
bridge_init() {
    mkdir -p "$BRIDGE_DIR"
    # Clean ALL stale data from previous tasks to prevent cross-contamination
    rm -f "$BRIDGE_DIR/request.json" \
          "$BRIDGE_DIR/response.json" \
          "$BRIDGE_DIR/CLAUDE_md_content.txt" \
          "$BRIDGE_DIR/repo_context.json" \
          "$BRIDGE_DIR/review_data.json" \
          "$BRIDGE_DIR/evaluation_answers.json" \
          "$BRIDGE_DIR/evaluation_answers_formatted.txt" \
          "$BRIDGE_DIR/last_error.txt" \
          "$BRIDGE_DIR/survey_answers.txt" 2>/dev/null || true
    # live_bridge.json is recreated by init-session below
}

bridge_noop() {
    true
}

live_update() {
    local field="$1"
    local value="$2"
    python3 -c "
import json
with open('$LIVE_JSON', 'r') as f:
    data = json.load(f)
data['$field'] = $value
with open('$LIVE_JSON', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
}

live_log() {
    local msg="$1"
    python3 -c "
import json
from datetime import datetime
with open('$LIVE_JSON', 'r') as f:
    data = json.load(f)
data['log'].append({
    'time': datetime.now().strftime('%H:%M:%S'),
    'msg': '''$msg'''
})
data['log'] = data['log'][-50:]
with open('$LIVE_JSON', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
}

# --------------------------------------------------------------------------
# Global Error Trap — catches ALL uncaught errors, prevents script death
# --------------------------------------------------------------------------
MARLIN_INSIDE_TRAP=false

global_error_handler() {
    local line_num="${1:-unknown}"
    local failed_cmd="${2:-unknown command}"
    local exit_code="${3:-1}"

    # Prevent recursive traps
    if [[ "$MARLIN_INSIDE_TRAP" == true ]]; then
        return 0
    fi
    MARLIN_INSIDE_TRAP=true

    echo ""
    echo -e "  ${RED}${BOLD}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${RED}${BOLD}║  ERROR CAUGHT (line $line_num, exit $exit_code)${NC}"
    echo -e "  ${RED}${BOLD}║  Command: ${failed_cmd:0:50}${NC}"
    echo -e "  ${RED}${BOLD}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Write error to bridge for Cursor
    if [[ -f "${LIVE_JSON:-/dev/null}" ]]; then
        python3 "${SCRIPT_DIR:-$(dirname "$0")}/marlin_bridge.py" write-heal \
            --desc "Script error at line $line_num" \
            --cmd "$failed_cmd" \
            --error-file <(echo "Line $line_num failed with exit code $exit_code: $failed_cmd") \
            --cwd "$(pwd)" \
            --hint "Global error trap caught this. The script will continue after fix." \
            --attempt 1 \
            --max-retries 1 2>/dev/null || true

        echo -e "  ${BLUE}Error written to live_bridge.json${NC}"
        echo -e "  ${YELLOW}${BOLD}Switch to Cursor and send any message to trigger auto-fix.${NC}"
        echo ""

        # Poll for fix (shorter timeout for global trap)
        local elapsed=0
        local trap_timeout=60
        while [[ $elapsed -lt $trap_timeout ]]; do
            local resp
            resp=$(python3 "${SCRIPT_DIR:-$(dirname "$0")}/marlin_bridge.py" read-response 2>/dev/null) && {
                echo ""
                echo -e "  ${GREEN}Cursor responded with a fix.${NC}"
                local num_fixes
                num_fixes=$(echo "$resp" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('fix_commands',[])))" 2>/dev/null) || num_fixes=0
                local i=0
                while [[ $i -lt $num_fixes ]]; do
                    local fix_cmd
                    fix_cmd=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['fix_commands'][$i])" 2>/dev/null) || true
                    if [[ -n "$fix_cmd" ]]; then
                        echo -e "    ${CYAN}→ $fix_cmd${NC}"
                        eval "$fix_cmd" 2>&1 | tail -5 || true
                    fi
                    i=$((i + 1))
                done
                python3 "${SCRIPT_DIR:-$(dirname "$0")}/marlin_bridge.py" clear-heal 2>/dev/null || true
                break
            }
            sleep 2
            elapsed=$((elapsed + 2))
            printf "\r  ⟳ Waiting for Cursor fix... (%ds / %ds)  " "$elapsed" "$trap_timeout"
        done
        echo ""
    fi

    echo -e "  ${YELLOW}The script will attempt to continue past this error.${NC}"
    echo ""

    MARLIN_INSIDE_TRAP=false
    return 0
}

trap 'global_error_handler "$LINENO" "$BASH_COMMAND" "$?"' ERR

# --------------------------------------------------------------------------
# Self-Healing — live JSON bridge with Cursor (no API keys)
# --------------------------------------------------------------------------
# Uses Cursor's subscription model directly via live_bridge.json.
# Terminal writes error → Cursor reads & diagnoses → writes fix → terminal applies.
HEAL_MAX_RETRIES=3
HEAL_TIMEOUT=120

bridge_update_step() {
    python3 "$SCRIPT_DIR/marlin_bridge.py" update-step --step "$1" --status "$2" 2>/dev/null || true
}

ensure_venv() {
    if [[ ! -d ".venv" ]]; then
        $PYTHON_CMD -m venv .venv || { warn "venv creation failed"; return 1; }
        ok "Created .venv (using $PYTHON_CMD)"
    fi
    source .venv/bin/activate || { warn "Could not activate venv"; return 1; }
    ok "Activated venv"
}

ensure_pkg_manager() {
    local manager="$1"

    if command -v "$manager" &>/dev/null; then
        ok "$manager already installed ($($manager --version 2>/dev/null | head -1 || echo 'unknown'))"
        return 0
    fi

    info "$manager not found. Attempting auto-install..."

    case "$manager" in
        yarn)
            if [[ "$(uname -s)" == "Darwin" ]] && command -v brew &>/dev/null; then
                brew install yarn 2>&1 | tail -3 && command -v yarn &>/dev/null && {
                    ok "$manager installed via brew"; return 0; }
            fi
            if command -v corepack &>/dev/null; then
                corepack enable 2>/dev/null && corepack prepare yarn@stable --activate 2>/dev/null && {
                    ok "$manager enabled via corepack"; return 0; }
            fi
            if command -v npm &>/dev/null; then
                npm install -g yarn 2>&1 | tail -3 && command -v yarn &>/dev/null && {
                    ok "$manager installed via npm"; return 0; }
            fi
            ;;
        pnpm)
            if command -v corepack &>/dev/null; then
                corepack enable 2>/dev/null && corepack prepare pnpm@latest --activate 2>/dev/null && {
                    ok "$manager enabled via corepack"; return 0; }
            fi
            if command -v npm &>/dev/null; then
                npm install -g pnpm 2>&1 | tail -3 && command -v pnpm &>/dev/null && {
                    ok "$manager installed via npm"; return 0; }
            fi
            if [[ "$(uname -s)" == "Darwin" ]] && command -v brew &>/dev/null; then
                brew install pnpm 2>&1 | tail -3 && command -v pnpm &>/dev/null && {
                    ok "$manager installed via brew"; return 0; }
            fi
            ;;
        pip|pip3)
            if command -v python3 &>/dev/null; then
                python3 -m ensurepip --upgrade 2>/dev/null && {
                    ok "pip bootstrapped via ensurepip"; return 0; }
            fi
            ;;
        cargo)
            if [[ "$(uname -s)" == "Darwin" ]] && command -v brew &>/dev/null; then
                brew install rust 2>&1 | tail -3 && command -v cargo &>/dev/null && {
                    ok "cargo installed via brew (rust)"; return 0; }
            fi
            echo -e "  ${CYAN}curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh${NC}"
            ;;
        go)
            if [[ "$(uname -s)" == "Darwin" ]] && command -v brew &>/dev/null; then
                brew install go 2>&1 | tail -3 && command -v go &>/dev/null && {
                    ok "go installed via brew"; return 0; }
            fi
            ;;
        *)
            if [[ "$(uname -s)" == "Darwin" ]] && command -v brew &>/dev/null; then
                brew install "$manager" 2>&1 | tail -3 && command -v "$manager" &>/dev/null && {
                    ok "$manager installed via brew"; return 0; }
            elif command -v apt-get &>/dev/null; then
                sudo apt-get install -y "$manager" 2>&1 | tail -3 && command -v "$manager" &>/dev/null && {
                    ok "$manager installed via apt"; return 0; }
            fi
            ;;
    esac

    if ! command -v "$manager" &>/dev/null; then
        err "Could not install $manager automatically."
        return 1
    fi
    return 0
}

detect_pkg_manager() {
    if [[ -f "bun.lockb" ]]; then echo "bun"
    elif [[ -f "yarn.lock" ]]; then echo "yarn"
    elif [[ -f "pnpm-lock.yaml" ]]; then echo "pnpm"
    elif [[ -f "package-lock.json" ]] || [[ -f "package.json" ]]; then echo "npm"
    elif [[ -f "Cargo.lock" ]] || [[ -f "Cargo.toml" ]]; then echo "cargo"
    elif [[ -f "go.sum" ]] || [[ -f "go.mod" ]]; then echo "go"
    elif [[ -f "Gemfile.lock" ]] || [[ -f "Gemfile" ]]; then echo "bundler"
    elif [[ -f "composer.lock" ]] || [[ -f "composer.json" ]]; then echo "composer"
    elif [[ -f "Pipfile.lock" ]]; then echo "pipenv"
    elif [[ -f "poetry.lock" ]]; then echo "poetry"
    elif [[ -f "requirements.txt" ]] || [[ -f "setup.py" ]] || [[ -f "pyproject.toml" ]]; then echo "pip"
    elif [[ -f "mix.exs" ]]; then echo "mix"
    elif [[ -f "pubspec.yaml" ]]; then echo "dart"
    elif [[ -f "Package.swift" ]]; then echo "swift"
    elif [[ -f "build.sbt" ]]; then echo "sbt"
    else echo "unknown"
    fi
}

run_install() {
    local manager="$1"
    local repo_dir="$2"
    local install_cmd=""

    case "$manager" in
        yarn)   install_cmd="yarn install" ;;
        pnpm)   install_cmd="pnpm install" ;;
        npm)    install_cmd="npm install" ;;
        cargo)  install_cmd="cargo build" ;;
        go)     install_cmd="go mod download" ;;
        pipenv) install_cmd="pipenv install --dev" ;;
        poetry) install_cmd="poetry install" ;;
        pip)
            if [[ -f "pyproject.toml" ]]; then
                install_cmd="pip install -e '.[dev]' 2>/dev/null || pip install -e '.[test]' 2>/dev/null || pip install -e '.'"
            elif [[ -f "setup.py" ]]; then
                install_cmd="pip install -e '.[dev]' 2>/dev/null || pip install -e '.'"
            elif [[ -f "requirements.txt" ]]; then
                install_cmd="pip install -r requirements.txt"
            fi
            ;;
        *) return 1 ;;
    esac

    if [[ -z "$install_cmd" ]]; then
        warn "No install command determined for $manager."
        return 1
    fi

    info "Running: $install_cmd"
    if eval "$install_cmd" 2>&1 | tail -15; then
        ok "Dependencies installed via $manager."
        return 0
    fi

    warn "Install failed in Cursor terminal."

    # macOS fallback: retry in Terminal.app (bypasses TCC restrictions)
    if [[ "$(uname -s)" == "Darwin" ]] && command -v osascript &>/dev/null; then
        info "Retrying via Terminal.app (has Full Disk Access)..."
        local install_script="/tmp/marlin_install_$$.sh"
        cat > "$install_script" << INSTALLEOF
#!/bin/bash
cd "$repo_dir"
echo "Running: $install_cmd in \$(basename "\$(pwd)")..."
$install_cmd
echo ""
echo "Install finished. Exit code: \$?"
echo "You can close this window."
INSTALLEOF
        chmod +x "$install_script"
        osascript -e "tell application \"Terminal\" to do script \"bash $install_script\"" 2>/dev/null && {
            ok "Install launched in Terminal.app window."
            echo -e "  ${DIM}Watch the Terminal.app window for progress.${NC}"
            echo -e "  ${DIM}Wait until it says 'Install finished' before continuing.${NC}"
            echo ""
            ask "Press Enter once install finishes in the Terminal window."
            wait_enter
            return 0
        }
    fi

    return 1
}

self_heal() {
    # Usage: self_heal "description" "command to run" [context_hint]
    local description="$1"
    local cmd="$2"
    local hint="${3:-}"
    local attempt=0

    while [[ $attempt -lt $HEAL_MAX_RETRIES ]]; do
        attempt=$((attempt + 1))

        if [[ $attempt -gt 1 ]]; then
            echo ""
            info "Retry $attempt/$HEAL_MAX_RETRIES: $description"
        fi

        # Run the command, capture output
        local output
        output=$(eval "$cmd" 2>&1) || true
        local exit_code=${PIPESTATUS[0]:-$?}

        if [[ $exit_code -eq 0 ]]; then
            ok "$description"
            return 0
        fi

        # Command failed
        echo "$output" | tail -10
        warn "$description — failed (attempt $attempt/$HEAL_MAX_RETRIES)"

        # Write error to file for bridge
        local err_file="$BRIDGE_DIR/last_error.txt"
        echo "$output" > "$err_file"

        # Write heal request to live_bridge.json via bridge
        local req_id
        req_id=$(python3 "$SCRIPT_DIR/marlin_bridge.py" write-heal \
            --desc "$description" \
            --cmd "$cmd" \
            --error-file "$err_file" \
            --cwd "$(pwd)" \
            --hint "$hint" \
            --attempt "$attempt" \
            --max-retries "$HEAL_MAX_RETRIES" 2>/dev/null) || true

        echo ""
        echo -e "  ${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${BLUE}║  SELF-HEAL: Error written to live_bridge.json        ║${NC}"
        echo -e "  ${BLUE}║  Cursor will read, diagnose, and write fix commands  ║${NC}"
        echo -e "  ${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${DIM}File: $LIVE_JSON${NC}"
        echo -e "  ${DIM}Request ID: ${req_id:-unknown}${NC}"

        # Poll for Cursor's response in the live JSON
        local elapsed=0
        while [[ $elapsed -lt $HEAL_TIMEOUT ]]; do
            # Check if Cursor wrote a response
            local resp
            resp=$(python3 "$SCRIPT_DIR/marlin_bridge.py" read-response 2>/dev/null) && break
            sleep 2
            elapsed=$((elapsed + 2))
            printf "\r  ⟳ Waiting for Cursor... (%ds / %ds)  " "$elapsed" "$HEAL_TIMEOUT"
        done
        echo ""

        # Check if we got a response
        if [[ -z "$resp" ]]; then
            warn "No response from Cursor within ${HEAL_TIMEOUT}s."
            continue
        fi

        # Parse Cursor's response
        local diagnosis num_fixes should_retry
        diagnosis=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('diagnosis','Unknown'))" 2>/dev/null || echo "Unknown")
        should_retry=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('should_retry',True))" 2>/dev/null || echo "True")
        num_fixes=$(echo "$resp" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('fix_commands',[])))" 2>/dev/null || echo "0")

        echo -e "  ${GREEN}Cursor responded${NC}"
        echo -e "  ${BOLD}Diagnosis:${NC} $diagnosis"

        if [[ "$num_fixes" -eq 0 || "$should_retry" == "False" ]]; then
            warn "Cursor says: not auto-fixable."
            break
        fi

        echo -e "  ${GREEN}Applying $num_fixes fix command(s):${NC}"
        echo ""

        local i=0
        while [[ $i -lt $num_fixes ]]; do
            local fix_cmd
            fix_cmd=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['fix_commands'][$i])" 2>/dev/null) || true

            if [[ -n "$fix_cmd" ]]; then
                echo -e "    ${CYAN}→ $fix_cmd${NC}"
                eval "$fix_cmd" 2>&1 | tail -5 || true
            fi
            i=$((i + 1))
        done

        echo ""
        info "Fix applied. Retrying original command..."

        # Clear heal state for next attempt
        python3 "$SCRIPT_DIR/marlin_bridge.py" clear-heal 2>/dev/null || true
    done

    # All retries exhausted
    echo ""
    warn "Self-healing exhausted $HEAL_MAX_RETRIES attempts for: $description"
    echo -e "  ${YELLOW}Manual intervention needed.${NC}"
    echo ""
    ask "Fix the issue manually, then press Enter to continue."
    wait_enter
    return 1
}

# --------------------------------------------------------------------------
# CLI commands: --help, --list, --clean, --clean-all
# --------------------------------------------------------------------------
show_help() {
    echo ""
    echo -e "${BOLD}MARLIN V3 — Phase 3 Setup Script${NC}"
    echo ""
    echo "Usage:"
    echo -e "  ${CYAN}./marlin_setup.sh${NC}              Start a new task"
    echo -e "  ${CYAN}./marlin_setup.sh --list${NC}       List existing task workspaces"
    echo -e "  ${CYAN}./marlin_setup.sh --clean${NC}      Remove a specific task workspace"
    echo -e "  ${CYAN}./marlin_setup.sh --clean-all${NC}  Remove ALL task workspaces"
    echo -e "  ${CYAN}./marlin_setup.sh --help${NC}       Show this help"
    echo ""
    exit 0
}

list_tasks() {
    echo ""
    echo -e "${BOLD}Existing task workspaces:${NC}"
    echo ""
    if [[ ! -d "$WORKSPACE_ROOT" ]]; then
        echo "  (none)"
        echo ""
        exit 0
    fi

    TASK_COUNT=0
    for task_dir in "$WORKSPACE_ROOT"/task-*/; do
        [[ -d "$task_dir" ]] || continue
        TASK_COUNT=$((TASK_COUNT + 1))
        task_name=$(basename "$task_dir")
        task_size=$(du -sh "$task_dir" 2>/dev/null | cut -f1)
        task_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$task_dir" 2>/dev/null || \
                    stat -c "%y" "$task_dir" 2>/dev/null | cut -d'.' -f1 || echo "unknown")

        # Check if git is initialized inside
        has_git=""
        for sub in "$task_dir"*/; do
            [[ -d "${sub}.git" ]] && has_git="✓ git" && break
        done

        echo -e "  ${CYAN}$task_name${NC}  ($task_size)  ${DIM}$task_date${NC}  ${GREEN}$has_git${NC}"
    done

    if [[ $TASK_COUNT -eq 0 ]]; then
        echo "  (none)"
    fi
    echo ""
    exit 0
}

clean_task() {
    echo ""
    echo -e "${BOLD}Clean task workspace${NC}"
    echo ""

    if [[ ! -d "$WORKSPACE_ROOT" ]]; then
        echo "  No workspaces found."
        exit 0
    fi

    # List available tasks
    TASKS=()
    for task_dir in "$WORKSPACE_ROOT"/task-*/; do
        [[ -d "$task_dir" ]] || continue
        TASKS+=("$(basename "$task_dir")")
    done

    if [[ ${#TASKS[@]} -eq 0 ]]; then
        echo "  No task workspaces to clean."
        exit 0
    fi

    echo "  Select a task to remove:"
    echo ""
    for i in "${!TASKS[@]}"; do
        task_size=$(du -sh "$WORKSPACE_ROOT/${TASKS[$i]}" 2>/dev/null | cut -f1)
        echo -e "    ${CYAN}$((i + 1))${NC}) ${TASKS[$i]}  ($task_size)"
    done
    echo ""
    read -rp "  Choice [number]: " clean_num

    if [[ "$clean_num" -ge 1 && "$clean_num" -le ${#TASKS[@]} ]] 2>/dev/null; then
        TARGET="${TASKS[$((clean_num - 1))]}"
        echo ""
        echo -e "  ${RED}${BOLD}This will permanently delete:${NC}"
        echo -e "  ${RED}$WORKSPACE_ROOT/$TARGET${NC}"
        echo ""
        read -rp "  Type the task name to confirm: " confirm_name
        if [[ "$confirm_name" == "$TARGET" ]]; then
            rm -rf "$WORKSPACE_ROOT/$TARGET"
            echo ""
            ok "Removed: $TARGET"
        else
            echo ""
            warn "Cancelled. Name didn't match."
        fi
    else
        warn "Invalid selection."
    fi
    echo ""
    exit 0
}

clean_all() {
    echo ""
    if [[ ! -d "$WORKSPACE_ROOT" ]]; then
        echo "  No workspaces found."
        exit 0
    fi

    TOTAL_SIZE=$(du -sh "$WORKSPACE_ROOT" 2>/dev/null | cut -f1)
    TASK_COUNT=$(find "$WORKSPACE_ROOT" -maxdepth 1 -type d -name "task-*" 2>/dev/null | wc -l | tr -d ' ')

    echo -e "  ${RED}${BOLD}This will permanently delete ALL $TASK_COUNT task workspace(s)${NC}"
    echo -e "  ${RED}Total size: $TOTAL_SIZE${NC}"
    echo -e "  ${RED}Path: $WORKSPACE_ROOT${NC}"
    echo ""
    read -rp "  Type 'DELETE ALL' to confirm: " confirm_all
    if [[ "$confirm_all" == "DELETE ALL" ]]; then
        rm -rf "$WORKSPACE_ROOT"
        echo ""
        ok "All task workspaces removed."
    else
        echo ""
        warn "Cancelled."
    fi
    echo ""
    exit 0
}

# Handle CLI flags
case "${1:-}" in
    --help|-h)     show_help ;;
    --list|-l)     list_tasks ;;
    --clean|-c)    clean_task ;;
    --clean-all)   clean_all ;;
esac

# --------------------------------------------------------------------------
# OS Detection & Selection
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

if [[ -z "${MARLIN_OS:-}" ]]; then
    DETECTED_OS=$(detect_os)
    echo ""
    echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}  ║   MARLIN V3 — SELECT YOUR PLATFORM                  ║${NC}"
    echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════════════════╝${NC}"
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
        *) echo -e "  ${RED}Invalid choice. Defaulting to detected: $DETECTED_OS${NC}"; MARLIN_OS="$DETECTED_OS" ;;
    esac

    echo ""
    ok "Platform: ${BOLD}${MARLIN_OS}${NC}"
    echo ""

    # If WSL selected, redirect to the WSL-optimized script
    if [[ "$MARLIN_OS" == "wsl" ]]; then
        WSL_SCRIPT="$(dirname "$SCRIPT_DIR")/wsl/phase3/marlin_setup.sh"
        if [[ -f "$WSL_SCRIPT" ]]; then
            info "Launching WSL-optimized Phase 3 script..."
            exec bash "$WSL_SCRIPT" "$@"
        else
            fail "WSL script not found at: $WSL_SCRIPT"
            echo "  Expected: wsl/phase3/marlin_setup.sh"
            echo "  Run setup_wsl.sh first or check your directory structure."
            exit 1
        fi
    fi
fi

# --------------------------------------------------------------------------
# Welcome
# --------------------------------------------------------------------------
clear 2>/dev/null || true
echo -e "${BOLD}${CYAN}"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │   MARLIN V3 — PHASE 3 SETUP                 │"
echo "  │   Environment & CLI Configuration            │"
echo "  └─────────────────────────────────────────────┘"
echo -e "${NC}"
echo "  This script follows the exact Phase 3 steps from"
echo "  the Marlin V3 Master Guide (3.1 through 3.10)."
echo "  It will automate what it can and guide you through"
echo "  the rest interactively."
echo ""

# --------------------------------------------------------------------------
# Task name
# --------------------------------------------------------------------------
echo -e "  ${BOLD}Give this task a short name${NC} (used for the workspace folder)."
echo -e "  ${DIM}Examples: dagster-airlift-refactor, react-hooks-fix, langchain-rag${NC}"
echo ""
read -rp "  Task name: " TASK_NAME

# Sanitize task name
TASK_NAME=$(echo "$TASK_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-_')

if [[ -z "$TASK_NAME" ]]; then
    TASK_NAME="task-$(date +%Y%m%d-%H%M%S)"
fi

TASK_DIR="$WORKSPACE_ROOT/task-$TASK_NAME"

if [[ -d "$TASK_DIR" ]]; then
    echo ""
    warn "Task workspace already exists: $TASK_DIR"
    echo ""
    echo -e "    ${CYAN}1${NC}) Resume this task (continue where you left off)"
    echo -e "    ${CYAN}2${NC}) Start fresh (delete and recreate)"
    echo ""
    read -rp "  Choice [1/2]: " resume_choice
    if [[ "$resume_choice" == "2" ]]; then
        rm -rf "$TASK_DIR"
        ok "Cleaned previous workspace."
    fi
fi

mkdir -p "$TASK_DIR"
ok "Task workspace: $TASK_DIR"

# Initialize the live bridge (terminal <-> Cursor communication)
bridge_init
LIVE_JSON="$BRIDGE_DIR/live_bridge.json"

python3 "$SCRIPT_DIR/marlin_bridge.py" init-session --task "$TASK_NAME" 2>/dev/null || true

ok "Live bridge: $LIVE_JSON"
echo -e "  ${DIM}Terminal writes errors here. Cursor reads and fixes automatically.${NC}"
echo -e "  ${DIM}No API keys needed — uses your Cursor subscription.${NC}"
echo ""
divider

REPO_DIR=""
LANG_DETECTED="unknown"
TEST_CMD=""
HEAD_COMMIT=""

# ==========================================================================
# STEP 3.1 — System Prerequisites
# ==========================================================================
step "3.1 — System Prerequisites"
echo "  Checking: Git, VS Code (in PATH), Python, tmux, Internet"
echo ""

PREREQ_OK=true

# Git
if command -v git &>/dev/null; then
    ok "Git: $(git --version 2>&1)"
else
    fail "Git: NOT INSTALLED"
    echo "     Install: brew install git (macOS) / sudo apt install git (Linux)"
    PREREQ_OK=false
fi

# Python
if command -v python3 &>/dev/null; then
    ok "Python: $(python3 --version 2>&1)"
else
    fail "Python3: NOT INSTALLED"
    echo "     Install: brew install python3 (macOS) / sudo apt install python3 (Linux)"
    PREREQ_OK=false
fi

# VS Code CLI
if command -v code &>/dev/null; then
    ok "VS Code CLI: $(code --version 2>&1 | head -1)"
else
    fail "VS Code CLI: NOT IN PATH"
    PREREQ_OK=false
fi

# tmux
if command -v tmux &>/dev/null; then
    ok "tmux: $(tmux -V 2>&1)"
else
    fail "tmux: NOT INSTALLED"
    PREREQ_OK=false
fi

# Internet
if curl -s --max-time 5 https://github.com > /dev/null 2>&1; then
    ok "Internet: Connected"
else
    warn "Internet: Cannot reach github.com"
fi

if [[ "$PREREQ_OK" == false ]]; then
    echo ""
    echo -e "${RED}  Some prerequisites are missing.${NC}"
    echo ""
fi

# ==========================================================================
# STEP 3.2 — Add VS Code to PATH (if needed)
# ==========================================================================
if command -v code &>/dev/null; then
    step "3.2 — Add VS Code to PATH"
    ok "VS Code CLI already in PATH. Skipping."
else
    step "3.2 — Add VS Code to PATH"
    echo "  VS Code CLI not found. Fixing automatically..."
    echo ""

    VSCODE_BIN=""
    for candidate in \
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin" \
        "/Applications/Cursor.app/Contents/Resources/app/bin" \
        "/usr/share/code/bin" \
        "/snap/code/current/usr/share/code/bin"; do
        if [[ -d "$candidate" ]]; then
            VSCODE_BIN="$candidate"
            break
        fi
    done

    if [[ -n "$VSCODE_BIN" ]]; then
        # Detect shell config file
        SHELL_RC=""
        case "$(basename "$SHELL")" in
            zsh)  SHELL_RC="$HOME/.zshrc" ;;
            bash)
                if [[ -f "$HOME/.bash_profile" ]]; then
                    SHELL_RC="$HOME/.bash_profile"
                else
                    SHELL_RC="$HOME/.bashrc"
                fi
                ;;
            *)    SHELL_RC="$HOME/.profile" ;;
        esac

        EXPORT_LINE="export PATH=\"$VSCODE_BIN:\$PATH\""

        # Only add if not already present
        if ! grep -qF "$VSCODE_BIN" "$SHELL_RC" 2>/dev/null; then
            echo "" >> "$SHELL_RC"
            echo "# VS Code / Cursor CLI (added by marlin_setup)" >> "$SHELL_RC"
            echo "$EXPORT_LINE" >> "$SHELL_RC"
            ok "Added to $SHELL_RC:"
            echo -e "    ${CYAN}$EXPORT_LINE${NC}"
        else
            ok "PATH entry already in $SHELL_RC"
        fi

        # Apply immediately for this session
        export PATH="$VSCODE_BIN:$PATH"

        if command -v code &>/dev/null; then
            ok "VS Code CLI now working: $(code --version 2>&1 | head -1)"
        else
            warn "PATH updated but 'code' still not found. Restart terminal after setup."
        fi
    else
        warn "Could not find VS Code or Cursor installation."
        echo "  If you installed it in a custom location, add it manually:"
        echo -e "    ${CYAN}echo 'export PATH=\"/path/to/vscode/bin:\$PATH\"' >> ~/.zshrc${NC}"
        echo -e "    ${CYAN}source ~/.zshrc${NC}"
    fi
fi

# ==========================================================================
# STEP 3.3 — Install tmux (if needed)
# ==========================================================================
if command -v tmux &>/dev/null; then
    step "3.3 — Install tmux"
    ok "tmux already installed ($(tmux -V 2>&1)). Skipping."
else
    step "3.3 — Install tmux"
    echo "  tmux is required for the CLI tool to manage model sessions."
    echo ""

    if [[ "$(uname -s)" == "Darwin" ]]; then
        ask "Install tmux with Homebrew? (brew install tmux)"
        if wait_confirm "Install now?"; then
            echo ""
            brew install tmux 2>&1 | tail -5
            if command -v tmux &>/dev/null; then
                ok "tmux installed: $(tmux -V)"
            else
                fail "Installation failed. Try manually: brew install tmux"
            fi
        fi
    else
        echo "  Linux: ${CYAN}sudo apt update && sudo apt install tmux${NC}"
        echo "  Run this in another terminal, then press Enter."
        wait_enter
    fi
fi

# ==========================================================================
# STEP 3.4 — Download & Unpack Tarball + Initialize Git
# ==========================================================================
step "3.4 — Download Repository & Initialize Git"

# Auto-detect if repo already exists in the task workspace (resume scenario)
EXISTING_REPO=$(find "$TASK_DIR" -mindepth 1 -maxdepth 1 -type d -not -name '.git' -not -name '.venv' 2>/dev/null | head -1)
if [[ -n "$EXISTING_REPO" && -d "$EXISTING_REPO/.git" ]]; then
    ok "Repo already unpacked and git initialized (resuming)."
    REPO_DIR="$EXISTING_REPO"
    cd "$REPO_DIR"
    HEAD_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "N/A")
    echo ""
    echo -e "  ${BOLD}HEAD commit (save for Pre-Thread Survey):${NC}"
    echo -e "  ${CYAN}$HEAD_COMMIT${NC}"
    echo ""
    echo -e "  ${RED}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "  ${RED}${BOLD}║  WARNING: Do NOT run 'git commit' after this.   ║${NC}"
    echo -e "  ${RED}${BOLD}║  The CLI manages all git state.                 ║${NC}"
    echo -e "  ${RED}${BOLD}║  Manual commits CORRUPT trajectory tracking.    ║${NC}"
    echo -e "  ${RED}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    wait_enter

    # Skip to step 3.5 — set tarball_choice to a skip sentinel
    tarball_choice="__resumed__"
else

echo "  After Prompt Preparation approval, you receive an email with a"
echo "  tarball link. This is the repo at its PRE-PR state (before the"
echo "  PR changes existed)."
echo ""
divider
echo ""

ask "Do you have the Cleansed Repository link from your approval email?"
echo ""
echo -e "    ${CYAN}1${NC}) ${GREEN}Yes${NC} — I have the tarball URL (paste it)"
echo -e "    ${CYAN}2${NC}) ${YELLOW}N/A${NC} — My email shows N/A (I'll provide the PR URL instead)"
echo -e "    ${CYAN}3${NC}) ${BLUE}Already unpacked${NC} — I already have the repo directory"
echo ""
read -rp "  Choice [1/2/3]: " tarball_choice
echo ""

case $tarball_choice in
    1)
        read -rp "  Paste the tarball URL: " TARBALL_URL
        echo ""

        WORK_DIR="$TASK_DIR"

        info "Downloading tarball..."
        TARBALL_FILE="$WORK_DIR/repo.tar.gz"
        if curl -L --progress-bar -o "$TARBALL_FILE" "$TARBALL_URL"; then
            FILE_SIZE=$(wc -c < "$TARBALL_FILE" | tr -d ' ')
            if [[ "$FILE_SIZE" -lt 1000 ]]; then
                fail "Downloaded file is too small ($FILE_SIZE bytes). Check the URL."
                exit 1
            fi
            ok "Downloaded: $(du -h "$TARBALL_FILE" | cut -f1)"
        else
            fail "Download failed. Check your URL and internet connection."
            exit 1
        fi

        info "Unpacking..."
        tar -xzf "$TARBALL_FILE" -C "$WORK_DIR" 2>/dev/null || tar -xf "$TARBALL_FILE" -C "$WORK_DIR"
        REPO_DIR=$(find "$WORK_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1 || true)
        ok "Unpacked to: $REPO_DIR"

        rm -f "$TARBALL_FILE" 2>/dev/null || true
        ok "Removed tarball (no longer needed)"
        ;;

    2)
        echo "  We'll construct the tarball URL from your PR."
        echo ""

        if ! command -v gh &>/dev/null; then
            fail "gh CLI is required for this. Install: brew install gh"
            echo "  After installing, authenticate: gh auth login"
            exit 1
        fi

        read -rp "  Paste the PR URL (e.g. https://github.com/owner/repo/pull/123): " PR_URL

        if [[ "$PR_URL" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
            PR_OWNER="${BASH_REMATCH[1]}"
            PR_REPO="${BASH_REMATCH[2]}"
            PR_NUMBER="${BASH_REMATCH[3]}"
            ok "Parsed: $PR_OWNER/$PR_REPO #$PR_NUMBER"
        else
            fail "Cannot parse PR URL. Expected: https://github.com/owner/repo/pull/NUMBER"
            exit 1
        fi

        info "Fetching base commit hash..."
        BASE_COMMIT=$(gh pr view "$PR_NUMBER" --repo "$PR_OWNER/$PR_REPO" --json baseRefOid --jq '.baseRefOid' 2>/dev/null)

        if [[ -z "$BASE_COMMIT" ]]; then
            fail "Could not fetch base commit. Is gh authenticated? Try: gh auth login"
            exit 1
        fi

        TARBALL_URL="https://github.com/$PR_OWNER/$PR_REPO/archive/$BASE_COMMIT.tar.gz"
        ok "Constructed tarball URL from PR base commit"
        info "URL: $TARBALL_URL"
        info "Base commit: $BASE_COMMIT"
        echo ""

        WORK_DIR="$TASK_DIR"

        info "Downloading tarball..."
        TARBALL_FILE="$WORK_DIR/repo.tar.gz"
        curl -L --progress-bar -o "$TARBALL_FILE" "$TARBALL_URL"
        ok "Downloaded: $(du -h "$TARBALL_FILE" | cut -f1)"

        info "Unpacking..."
        tar -xzf "$TARBALL_FILE" -C "$WORK_DIR" 2>/dev/null || tar -xf "$TARBALL_FILE" -C "$WORK_DIR"
        REPO_DIR=$(find "$WORK_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1 || true)
        ok "Unpacked to: $REPO_DIR"

        rm -f "$TARBALL_FILE" 2>/dev/null || true
        ok "Removed tarball (no longer needed)"
        ;;

    3)
        read -rp "  Path to your repo directory: " REPO_DIR
        if [[ ! -d "$REPO_DIR" ]]; then
            fail "Directory does not exist: $REPO_DIR"
            exit 1
        fi
        ok "Using existing directory: $REPO_DIR"
        ;;

    *)
        fail "Invalid choice."
        exit 1
        ;;
esac

# Initialize git
echo ""
cd "$REPO_DIR"

if [[ -d ".git" ]]; then
    warn "Git already initialized in this directory."
    HEAD_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "N/A")
else
    info "Initializing git..."
    git init -q
    git add .
    git commit -q -m "Initial commit"
    HEAD_COMMIT=$(git rev-parse HEAD)
    ok "Git initialized with initial commit"
fi

echo ""
echo -e "  ${BOLD}HEAD commit (save for Pre-Thread Survey):${NC}"
echo -e "  ${CYAN}$HEAD_COMMIT${NC}"
echo ""
echo -e "  ${RED}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "  ${RED}${BOLD}║  WARNING: Do NOT run 'git commit' after this.   ║${NC}"
echo -e "  ${RED}${BOLD}║  The CLI manages all git state.                 ║${NC}"
echo -e "  ${RED}${BOLD}║  Manual commits CORRUPT trajectory tracking.    ║${NC}"
echo -e "  ${RED}${BOLD}╚══════════════════════════════════════════════════╝${NC}"

wait_enter

fi  # end of else block for resume detection

# ==========================================================================
# STEP 3.5 — Set Up Dev Environment
# ==========================================================================
step "3.5 — Set Up Dev Environment"
echo "  Detecting language and installing dependencies."
echo "  If the environment is broken, the model cannot run tests."
echo -e "  ${YELLOW}That's YOUR fault, not the model's.${NC}"
echo ""

# --------------------------------------------------------------------------
# Pick the right Python version (some repos need < 3.13)
# --------------------------------------------------------------------------
PYTHON_CMD="python3"

pick_python() {
    # Find all available python versions
    local candidates=()
    for v in python3.12 python3.11 python3.10 python3.9 python3; do
        if command -v "$v" &>/dev/null; then
            candidates+=("$v")
        fi
    done

    if [[ ${#candidates[@]} -eq 0 ]]; then
        warn "No Python 3 found."
        return
    fi

    # Check if current python3 version is compatible
    local py_ver
    py_ver=$($PYTHON_CMD --version 2>&1 | grep -oE '[0-9]+\.[0-9]+')
    local py_major py_minor
    py_major=$(echo "$py_ver" | cut -d. -f1)
    py_minor=$(echo "$py_ver" | cut -d. -f2)

    # If python is 3.13+ and we have a lower version available, offer it
    if [[ "$py_major" -eq 3 && "$py_minor" -ge 13 ]]; then
        warn "Default Python is $py_ver. Some repos need Python < 3.13."

        # Try to find a compatible version automatically
        for v in python3.12 python3.11 python3.10; do
            if command -v "$v" &>/dev/null; then
                PYTHON_CMD="$v"
                ok "Auto-selected: $PYTHON_CMD ($($v --version 2>&1))"
                return
            fi
        done

        echo ""
        echo "  No Python < 3.13 found. Install one:"
        echo -e "    ${CYAN}brew install python@3.12${NC}"
        echo ""
        echo "  Or if you already have one, enter the command:"
        read -rp "  Python command (or Enter to use $PYTHON_CMD): " custom_py
        [[ -n "$custom_py" ]] && PYTHON_CMD="$custom_py"
    fi

    ok "Using: $PYTHON_CMD ($($PYTHON_CMD --version 2>&1))"
}

# Detect language (17 languages supported)
if [[ -f "setup.py" || -f "setup.cfg" || -f "pyproject.toml" ]]; then
    LANG_DETECTED="python"
elif [[ -f "package.json" ]]; then
    LANG_DETECTED="node"
elif [[ -f "go.mod" ]]; then
    LANG_DETECTED="go"
elif [[ -f "Cargo.toml" ]]; then
    LANG_DETECTED="rust"
elif [[ -f "pom.xml" || -f "build.gradle" || -f "build.gradle.kts" ]]; then
    LANG_DETECTED="java"
elif [[ -f "CMakeLists.txt" || -f "Makefile" ]]; then
    LANG_DETECTED="cpp"
elif [[ -f "Gemfile" ]]; then
    LANG_DETECTED="ruby"
elif [[ -f "composer.json" ]]; then
    LANG_DETECTED="php"
elif [[ -f "build.sbt" ]]; then
    LANG_DETECTED="scala"
elif [[ -f "Package.swift" ]]; then
    LANG_DETECTED="swift"
elif [[ -f "pubspec.yaml" ]]; then
    LANG_DETECTED="dart"
elif [[ -f "mix.exs" ]]; then
    LANG_DETECTED="elixir"
elif [[ -f "build.zig" ]]; then
    LANG_DETECTED="zig"
elif ls *.csproj &>/dev/null || ls *.sln &>/dev/null; then
    LANG_DETECTED="dotnet"
fi

ok "Detected language: $LANG_DETECTED"
echo ""

# --------------------------------------------------------------------------
# Known monorepo detection
# --------------------------------------------------------------------------
KNOWN_REPO=""
SUBPKG_PATH=""
INSTALL_OK=false

REPO_NAME_LOWER=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')
README_HEAD=""
[[ -f "README.md" ]] && README_HEAD=$(head -5 README.md 2>/dev/null | tr '[:upper:]' '[:lower:]')

# dagster-io/dagster
if [[ -d "python_modules/dagster" && -d "examples/experimental" ]]; then
    KNOWN_REPO="dagster"
# facebook/react
elif [[ -d "packages/react" && -d "packages/react-dom" ]]; then
    KNOWN_REPO="react"
# huggingface/transformers
elif [[ -d "src/transformers" && -f "setup.py" ]] && echo "$README_HEAD" | grep -q "transformers"; then
    KNOWN_REPO="transformers"
# huggingface/diffusers
elif [[ -d "src/diffusers" && -f "setup.py" ]] && echo "$README_HEAD" | grep -q "diffusers"; then
    KNOWN_REPO="diffusers"
# langchain-ai/langchain
elif [[ -d "libs/langchain" || -d "libs/core" ]] && echo "$README_HEAD" | grep -qi "langchain"; then
    KNOWN_REPO="langchain"
# microsoft/vscode
elif [[ -d "src/vs" && -f "product.json" ]]; then
    KNOWN_REPO="vscode"
# PrefectHQ/prefect
elif [[ -d "src/prefect" ]] && echo "$README_HEAD" | grep -qi "prefect"; then
    KNOWN_REPO="prefect"
# rust-lang/rust
elif [[ -f "x.py" && -d "compiler" && -d "library" ]]; then
    KNOWN_REPO="rust-lang"
fi

if [[ -n "$KNOWN_REPO" ]]; then
    ok "Recognized repo: ${BOLD}$KNOWN_REPO${NC}"
    echo ""
fi

# --------------------------------------------------------------------------
# Repo-specific install logic
# --------------------------------------------------------------------------
case "$KNOWN_REPO" in
    dagster)
        pick_python
        info "Dagster monorepo detected. Need to know which sub-package you're working on."
        echo ""
        echo "  Common sub-packages:"
        echo -e "    ${CYAN}1${NC}) dagster-airlift  (examples/experimental/dagster-airlift)"
        echo -e "    ${CYAN}2${NC}) dagster core     (python_modules/dagster)"
        echo -e "    ${CYAN}3${NC}) dagster-webserver (python_modules/dagster-webserver)"
        echo -e "    ${CYAN}4${NC}) Other (I'll type the path)"
        echo ""
        read -rp "  Which sub-package? [1/2/3/4]: " dagster_choice

        case "$dagster_choice" in
            1) SUBPKG_PATH="examples/experimental/dagster-airlift" ;;
            2) SUBPKG_PATH="python_modules/dagster" ;;
            3) SUBPKG_PATH="python_modules/dagster-webserver" ;;
            4)
                read -rp "  Path to sub-package (relative to repo root): " SUBPKG_PATH
                ;;
        esac

        ensure_venv

        self_heal "Install dagster core" \
            "pip install -e \"python_modules/dagster[test]\"" \
            "dagster monorepo, Python=$($PYTHON_CMD --version 2>&1)"

        if [[ -n "$SUBPKG_PATH" && -d "$SUBPKG_PATH" ]]; then
            cd "$SUBPKG_PATH"
            self_heal "Install $SUBPKG_PATH" \
                "pip install -e '.[dev]' 2>/dev/null || pip install -e '.[core,test]' 2>/dev/null || pip install -e '.[test]' 2>/dev/null || pip install -e '.'" \
                "dagster sub-package at $SUBPKG_PATH"
            cd "$REPO_DIR"
        fi

        TEST_CMD="pytest"
        [[ -n "$SUBPKG_PATH" ]] && TEST_CMD="pytest $SUBPKG_PATH"
        INSTALL_OK=true
        ;;

    react)
        info "React monorepo (yarn workspaces)."
        PKG_MGR=$(detect_pkg_manager)
        if ensure_pkg_manager "$PKG_MGR"; then
            run_install "$PKG_MGR" "$(pwd)" && INSTALL_OK=true
        fi
        TEST_CMD="yarn test"
        ;;

    transformers)
        pick_python
        ensure_venv

        info "Installing transformers with dev extras..."
        pip install -e ".[dev]" 2>&1 | tail -5 && INSTALL_OK=true || \
        pip install -e ".[testing]" 2>&1 | tail -5 && INSTALL_OK=true || \
        pip install -e "." 2>&1 | tail -5 && INSTALL_OK=true || \
        warn "Auto-install failed."

        TEST_CMD="pytest tests/"
        ;;

    diffusers)
        pick_python
        ensure_venv

        info "Installing diffusers with dev extras..."
        pip install -e ".[dev]" 2>&1 | tail -5 && INSTALL_OK=true || \
        pip install -e ".[test]" 2>&1 | tail -5 && INSTALL_OK=true || \
        pip install -e "." 2>&1 | tail -5 && INSTALL_OK=true || \
        warn "Auto-install failed."

        TEST_CMD="pytest tests/"
        ;;

    langchain)
        pick_python
        info "LangChain monorepo detected. Need to know which sub-package."
        echo ""
        echo "  Common sub-packages:"
        echo -e "    ${CYAN}1${NC}) langchain-core     (libs/core)"
        echo -e "    ${CYAN}2${NC}) langchain           (libs/langchain)"
        echo -e "    ${CYAN}3${NC}) langchain-community (libs/community)"
        echo -e "    ${CYAN}4${NC}) Other (I'll type the path)"
        echo ""
        read -rp "  Which sub-package? [1/2/3/4]: " lc_choice

        case "$lc_choice" in
            1) SUBPKG_PATH="libs/core" ;;
            2) SUBPKG_PATH="libs/langchain" ;;
            3) SUBPKG_PATH="libs/community" ;;
            4) read -rp "  Path to sub-package: " SUBPKG_PATH ;;
        esac

        ensure_venv

        if [[ -d "libs/core" && "$SUBPKG_PATH" != "libs/core" ]]; then
            info "Installing langchain-core first..."
            pip install -e "libs/core[test]" 2>&1 | tail -3
        fi

        if [[ -n "$SUBPKG_PATH" && -d "$SUBPKG_PATH" ]]; then
            info "Installing $SUBPKG_PATH..."
            pip install -e "$SUBPKG_PATH[test]" 2>/dev/null || \
            pip install -e "$SUBPKG_PATH[dev]" 2>/dev/null || \
            pip install -e "$SUBPKG_PATH" 2>/dev/null || \
            warn "Auto-install of sub-package failed."
        fi

        TEST_CMD="pytest"
        [[ -n "$SUBPKG_PATH" ]] && TEST_CMD="pytest $SUBPKG_PATH/tests"
        INSTALL_OK=true
        ;;

    vscode)
        info "VS Code repo (TypeScript)."
        PKG_MGR=$(detect_pkg_manager)
        if ensure_pkg_manager "$PKG_MGR"; then
            run_install "$PKG_MGR" "$(pwd)" && INSTALL_OK=true
        fi
        TEST_CMD="yarn test"
        ;;

    prefect)
        pick_python
        ensure_venv

        info "Installing prefect with dev extras..."
        pip install -e ".[dev]" 2>&1 | tail -5 && INSTALL_OK=true || \
        pip install -e "." 2>&1 | tail -5 && INSTALL_OK=true || \
        warn "Auto-install failed."

        TEST_CMD="pytest tests/"
        ;;

    rust-lang)
        info "Rust compiler repo. Uses x.py build system."
        echo ""
        echo "  This repo uses a custom build system:"
        echo -e "    ${CYAN}./x.py build${NC}   — build the compiler"
        echo -e "    ${CYAN}./x.py test${NC}    — run tests"
        echo -e "    ${CYAN}./x.py check${NC}   — quick type-check"
        echo ""
        info "Running initial check (faster than full build)..."
        python3 x.py check 2>&1 | tail -10 && INSTALL_OK=true || \
        warn "x.py check failed. You may need to configure config.toml first."

        TEST_CMD="python3 x.py test"
        ;;

    *)
        # -----------------------------------------------------------
        # Generic install (not a known repo)
        # -----------------------------------------------------------
        case $LANG_DETECTED in
            python)
                pick_python
                PKG_MGR=$(detect_pkg_manager)

                if [[ "$PKG_MGR" == "poetry" ]]; then
                    ensure_pkg_manager "poetry" || true
                    if command -v poetry &>/dev/null; then
                        info "Installing via poetry..."
                        poetry install 2>&1 | tail -10 && INSTALL_OK=true
                    fi
                elif [[ "$PKG_MGR" == "pipenv" ]]; then
                    ensure_pkg_manager "pipenv" || true
                    if command -v pipenv &>/dev/null; then
                        info "Installing via pipenv..."
                        pipenv install --dev 2>&1 | tail -10 && INSTALL_OK=true
                    fi
                else
                    ensure_venv
                    info "Installing dependencies (this may take a few minutes)..."
                    if [[ -f "pyproject.toml" ]]; then
                        self_heal "Install Python package (pyproject.toml)" \
                            "pip install -e '.[dev]' 2>/dev/null || pip install -e '.[test]' 2>/dev/null || pip install -e '.'" \
                            "Generic Python project" && INSTALL_OK=true || INSTALL_OK=false
                    elif [[ -f "setup.py" ]]; then
                        self_heal "Install Python package (setup.py)" \
                            "pip install -e '.[dev]' 2>/dev/null || pip install -e '.'" \
                            "Generic Python project" && INSTALL_OK=true || INSTALL_OK=false
                    elif [[ -f "requirements.txt" ]]; then
                        self_heal "Install requirements.txt" \
                            "pip install -r requirements.txt" \
                            "requirements.txt based project" && INSTALL_OK=true || INSTALL_OK=false
                    fi
                fi

                if command -v pytest &>/dev/null || pip show pytest &>/dev/null 2>/dev/null; then
                    TEST_CMD="pytest"
                elif [[ -f "tox.ini" ]]; then
                    TEST_CMD="tox"
                fi
                ;;

            node)
                PKG_MGR=$(detect_pkg_manager)
                if ensure_pkg_manager "$PKG_MGR"; then
                    run_install "$PKG_MGR" "$(pwd)" && INSTALL_OK=true
                fi

                if [[ -f "package.json" ]] && grep -q '"test"' package.json 2>/dev/null; then
                    case "$PKG_MGR" in
                        yarn) TEST_CMD="yarn test" ;;
                        pnpm) TEST_CMD="pnpm test" ;;
                        *)    TEST_CMD="npm test" ;;
                    esac
                fi
                ;;

            go)
                if ensure_pkg_manager "go"; then
                    info "Downloading Go modules..."
                    go mod download 2>/dev/null && INSTALL_OK=true || warn "go mod download failed."
                fi
                TEST_CMD="go test ./..."
                ;;

            rust)
                if ensure_pkg_manager "cargo"; then
                    info "Building Rust project..."
                    cargo build 2>/dev/null && INSTALL_OK=true || warn "cargo build failed."
                fi
                TEST_CMD="cargo test"
                ;;

            java)
                if [[ -f "pom.xml" ]]; then
                    ensure_pkg_manager "mvn" || true
                    if command -v mvn &>/dev/null; then
                        info "Compiling with Maven..."
                        mvn compile -q 2>/dev/null && INSTALL_OK=true || warn "mvn compile failed."
                        TEST_CMD="mvn test"
                    fi
                elif [[ -f "build.gradle" ]]; then
                    ensure_pkg_manager "gradle" || true
                    if command -v gradle &>/dev/null; then
                        info "Building with Gradle..."
                        gradle build -q 2>/dev/null && INSTALL_OK=true || warn "gradle build failed."
                        TEST_CMD="gradle test"
                    fi
                fi
                ;;

            ruby)
                if ensure_pkg_manager "bundler"; then
                    info "Installing Ruby dependencies..."
                    bundle install 2>&1 | tail -5 && INSTALL_OK=true || warn "bundle install failed."
                fi
                TEST_CMD="bundle exec rspec"
                ;;

            php)
                if ensure_pkg_manager "composer"; then
                    info "Installing PHP dependencies..."
                    composer install 2>&1 | tail -5 && INSTALL_OK=true || warn "composer install failed."
                fi
                TEST_CMD="vendor/bin/phpunit"
                ;;

            scala)
                if ensure_pkg_manager "sbt"; then
                    info "Compiling Scala project..."
                    sbt compile 2>&1 | tail -10 && INSTALL_OK=true || warn "sbt compile failed."
                fi
                TEST_CMD="sbt test"
                ;;

            swift)
                info "Building Swift project..."
                swift build 2>&1 | tail -5 && INSTALL_OK=true || warn "swift build failed."
                TEST_CMD="swift test"
                ;;

            dart)
                if command -v dart &>/dev/null; then
                    info "Getting Dart dependencies..."
                    dart pub get 2>&1 | tail -5 && INSTALL_OK=true || warn "dart pub get failed."
                fi
                TEST_CMD="dart test"
                ;;

            elixir)
                if command -v mix &>/dev/null; then
                    info "Getting Elixir dependencies..."
                    mix deps.get 2>&1 | tail -5 && INSTALL_OK=true || warn "mix deps.get failed."
                fi
                TEST_CMD="mix test"
                ;;

            dotnet)
                if command -v dotnet &>/dev/null; then
                    info "Restoring .NET dependencies..."
                    dotnet restore 2>&1 | tail -5 && INSTALL_OK=true || warn "dotnet restore failed."
                fi
                TEST_CMD="dotnet test"
                ;;

            zig)
                if command -v zig &>/dev/null; then
                    info "Building Zig project..."
                    zig build 2>&1 | tail -5 && INSTALL_OK=true || warn "zig build failed."
                fi
                TEST_CMD="zig build test"
                ;;

            *)
                warn "Could not auto-detect language."
                ;;
        esac
        ;;
esac

# --------------------------------------------------------------------------
# Fallback: if install failed, ask user for sub-package path or repo URL
# --------------------------------------------------------------------------
if [[ "$INSTALL_OK" != true ]]; then
    echo ""
    warn "Dependency install failed or could not be auto-detected."
    echo ""
    echo "  This usually means it's a monorepo and the root-level install"
    echo "  doesn't work. You need to install from a specific sub-package."
    echo ""
    echo -e "  ${BOLD}Options:${NC}"
    echo -e "    ${CYAN}1${NC}) I know the sub-package path (I'll type it)"
    echo -e "    ${CYAN}2${NC}) Tell me the GitHub repo URL (I'll look it up)"
    echo -e "    ${CYAN}3${NC}) Skip — I'll install manually later"
    echo ""
    read -rp "  Choice [1/2/3]: " fallback_choice

    case "$fallback_choice" in
        1)
            read -rp "  Sub-package path (relative to repo root): " SUBPKG_PATH
            if [[ -d "$SUBPKG_PATH" ]]; then
                info "Installing from $SUBPKG_PATH..."
                cd "$SUBPKG_PATH"

                if [[ -f "setup.py" || -f "pyproject.toml" || -f "setup.cfg" ]]; then
                    source "$REPO_DIR/.venv/bin/activate" 2>/dev/null
                    pip install -e ".[dev]" 2>/dev/null || \
                    pip install -e ".[test]" 2>/dev/null || \
                    pip install -e "." 2>/dev/null || \
                    warn "Install from sub-package also failed."
                elif [[ -f "package.json" ]]; then
                    npm install 2>/dev/null || yarn install 2>/dev/null || \
                    warn "npm/yarn install failed."
                elif [[ -f "Cargo.toml" ]]; then
                    cargo build 2>/dev/null || warn "cargo build failed."
                fi

                cd "$REPO_DIR"
                ok "Attempted install from $SUBPKG_PATH"

                # Detect test command for sub-package
                if [[ -z "$TEST_CMD" ]]; then
                    if pip show pytest &>/dev/null 2>/dev/null; then
                        TEST_CMD="pytest $SUBPKG_PATH"
                    elif [[ -f "$SUBPKG_PATH/package.json" ]]; then
                        TEST_CMD="cd $SUBPKG_PATH && npm test"
                    fi
                fi
            else
                fail "Directory not found: $SUBPKG_PATH"
            fi
            ;;

        2)
            read -rp "  GitHub repo URL: " FALLBACK_REPO_URL
            echo ""
            info "Checking repo structure..."
            echo ""
            echo "  Scanning for installable sub-packages..."
            echo ""

            # Find all directories with setup.py/pyproject.toml
            INSTALLABLE=$(find . -maxdepth 4 \( -name "setup.py" -o -name "pyproject.toml" \) \
                -not -path './.venv/*' -not -path './node_modules/*' -not -path './.git/*' \
                2>/dev/null | sort | head -20)

            if [[ -n "$INSTALLABLE" ]]; then
                echo "  Found installable packages:"
                echo ""
                IDX=1
                declare -a PKG_PATHS=()
                while IFS= read -r pkg_file; do
                    pkg_dir=$(dirname "$pkg_file" | sed 's|^\./||')
                    PKG_PATHS+=("$pkg_dir")
                    echo -e "    ${CYAN}$IDX${NC}) $pkg_dir"
                    IDX=$((IDX + 1))
                done <<< "$INSTALLABLE"
                echo ""
                read -rp "  Which package to install? [number]: " pkg_num

                if [[ "$pkg_num" -ge 1 && "$pkg_num" -le ${#PKG_PATHS[@]} ]] 2>/dev/null; then
                    SUBPKG_PATH="${PKG_PATHS[$((pkg_num - 1))]}"
                    info "Installing from $SUBPKG_PATH..."
                    source "$REPO_DIR/.venv/bin/activate" 2>/dev/null
                    cd "$SUBPKG_PATH"
                    pip install -e ".[dev]" 2>/dev/null || \
                    pip install -e ".[test]" 2>/dev/null || \
                    pip install -e "." 2>/dev/null || \
                    warn "Install failed."
                    cd "$REPO_DIR"

                    if [[ -z "$TEST_CMD" ]] && pip show pytest &>/dev/null 2>/dev/null; then
                        TEST_CMD="pytest $SUBPKG_PATH"
                    fi
                fi
            else
                warn "No installable packages found. Install manually."
            fi
            ;;

        3)
            info "Skipping auto-install. Set up dependencies manually before running the CLI."
            ;;
    esac
fi

# Run baseline tests
TESTS_PASSED=false
echo ""
if [[ -n "$TEST_CMD" ]]; then
    ask "Run baseline tests? ($TEST_CMD)"
    if wait_confirm "Run tests now?"; then
        echo ""
        info "Running: $TEST_CMD"
        divider

        if [[ "$INSTALL_OK" != true ]]; then
            warn "Dependencies were NOT installed. Tests will likely fail."
            echo ""
        fi

        TEST_OUTPUT=$(eval "$TEST_CMD" 2>&1 || true)

        # macOS EPERM fallback: if tests fail with permission error, retry via Terminal.app
        if echo "$TEST_OUTPUT" | grep -qi "EPERM\|operation not permitted" && [[ "$(uname -s)" == "Darwin" ]]; then
            warn "macOS EPERM detected. Retrying tests via Terminal.app..."
            OSASCRIPT_TEST_CMD="cd '$(pwd)' && $TEST_CMD > /tmp/marlin_test_output.txt 2>&1"
            osascript -e "tell application \"Terminal\" to do script \"$OSASCRIPT_TEST_CMD\"" 2>/dev/null || true
            echo "  Waiting for Terminal.app test run..."
            sleep 10
            local wait_tests=0
            while [[ $wait_tests -lt 120 ]]; do
                if [[ -f "/tmp/marlin_test_output.txt" ]] && ! lsof /tmp/marlin_test_output.txt &>/dev/null; then
                    TEST_OUTPUT=$(cat /tmp/marlin_test_output.txt 2>/dev/null || true)
                    rm -f /tmp/marlin_test_output.txt 2>/dev/null
                    break
                fi
                sleep 5; wait_tests=$((wait_tests + 5))
            done
        fi

        echo "$TEST_OUTPUT" | tail -30

        if echo "$TEST_OUTPUT" | tail -5 | grep -qiE "passed|ok|success"; then
            echo ""
            ok "Baseline tests completed."
            TESTS_PASSED=true
        else
            echo ""
            warn "Some tests may have failed."
            echo ""
            echo "  This is common for monorepos — collection errors from"
            echo "  sub-packages with missing optional dependencies (dbt, mwaa, etc.)"
            echo "  are usually pre-existing and NOT your fault."
            echo ""
            if [[ -n "${SUBPKG_PATH:-}" ]]; then
                test_dirs=$(find "$SUBPKG_PATH" -maxdepth 3 -type d -name "unit_tests" -o -name "core_tests" 2>/dev/null | head -3 || true)
                if [[ -n "$test_dirs" ]]; then
                    echo "  Try running a narrower test scope:"
                    while IFS= read -r td; do
                        echo -e "    ${CYAN}pytest $td${NC}"
                    done <<< "$test_dirs"
                fi
            fi
        fi
        divider
    fi
else
    warn "Could not detect test command."
    echo "  Common commands:"
    echo "    Python: pytest / python -m pytest"
    echo "    Node:   npm test"
    echo "    Go:     go test ./..."
    echo "    Rust:   cargo test"
    echo ""
    ask "Run tests manually, then press Enter."
    wait_enter
fi

# NOTE: CLAUDE.md creation is deferred to AFTER HFI launch (step 3.6 below)
# per the Master Guide's "Critical workflow order":
#   1. Clean main branch  2. Launch HFI  3. THEN create CLAUDE.md

# ==========================================================================
# STEP 3.7 — Authenticate with Anthropic
# ==========================================================================
step "3.7 — Authenticate with Anthropic"

# Detect if already authenticated (HFI session dirs exist or auth token is set)
AUTH_DETECTED=false
HFI_TEMP_DIRS=$(find /tmp/claude-hfi 2>/dev/null -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || true)
HFI_TEMP_DIRS="${HFI_TEMP_DIRS:-0}"
HFI_VAR_DIRS=$(find /var/folders -maxdepth 5 -type d -name "claude-hfi" 2>/dev/null | head -1 || true)
HFI_VAR_DIRS="${HFI_VAR_DIRS:-}"

if [[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    AUTH_DETECTED=true
    ok "ANTHROPIC_AUTH_TOKEN is set. Already authenticated."
elif [[ -n "$HFI_VAR_DIRS" ]] && [[ $(find "$HFI_VAR_DIRS" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || echo "0") -gt 1 ]]; then
    AUTH_DETECTED=true
    ok "HFI session history found. Already authenticated."
elif [[ -d "$HOME/.claude" ]] || [[ -d "$HOME/.config/claude-hfi" ]]; then
    AUTH_DETECTED=true
    ok "Auth config directory found. Already authenticated."
fi

if [[ "$AUTH_DETECTED" == true ]]; then
    ok "Skipping authentication (already done)."
else
    echo "  This step requires a browser. The script cannot do this for you."
    echo ""
    echo "  Steps:"
    echo "    1. Open this URL:"
    echo -e "       ${CYAN}https://feedback.anthropic.com/claude_code?email_login=true${NC}"
    echo ""
    echo "    2. Login with your ${BOLD}Alias email${NC}"
    echo -e "       ${RED}Do NOT use 'Sign in with Google'${NC}"
    echo ""
    echo "    3. Enter the verification code from your Alias inbox"
    echo ""

    if [[ "$(uname -s)" == "Darwin" ]]; then
        ask "Open the authentication page in your browser?"
        if wait_confirm "Open browser?"; then
            open "https://feedback.anthropic.com/claude_code?email_login=true"
            ok "Opened in browser."
        fi
    fi

    echo ""
    ask "Complete the authentication, then press Enter."
    wait_enter
fi

# ==========================================================================
# STEP 3.8 — Download & Install CLI Binary
# ==========================================================================
step "3.8 — Download & Install CLI Binary"

MARLIN_TOOLS_DIR="$HOME/marlin-tools"

if [[ -f "claude-hfi" && -x "claude-hfi" ]]; then
    ok "CLI binary already exists and is executable: ./claude-hfi"
elif [[ -f "$MARLIN_TOOLS_DIR/claude-hfi" && -x "$MARLIN_TOOLS_DIR/claude-hfi" ]]; then
    # Found a cached copy from a previous task
    ok "Found cached CLI binary at $MARLIN_TOOLS_DIR/claude-hfi"
    cp "$MARLIN_TOOLS_DIR/claude-hfi" "$(pwd)/claude-hfi"
    chmod +x claude-hfi
    xattr -d com.apple.quarantine claude-hfi 2>/dev/null || true
    ok "Copied to repo root: ./claude-hfi"
    echo ""
    echo -e "  ${DIM}(Each repo needs its own copy. The cached version saves you${NC}"
    echo -e "  ${DIM} from re-downloading every time.)${NC}"
else
    echo "  The CLI binary needs to be in every repo root."
    echo "  You only download it ONCE, then reuse for future tasks."
    echo ""

    # Detect OS/architecture
    OS=$(uname -s)
    ARCH=$(uname -m)
    RECOMMENDED=""
    case "$OS-$ARCH" in
        Darwin-arm64)  RECOMMENDED="macOS (ARM) — darwin-arm64" ;;
        Darwin-x86_64) RECOMMENDED="macOS (Intel) — darwin-x86_64" ;;
        Linux-*)       RECOMMENDED="Linux" ;;
    esac

    echo "  Steps:"
    echo "    1. On the Anthropic page, download the CLI build"
    if [[ -n "$RECOMMENDED" ]]; then
        echo -e "       ${GREEN}Your machine: ${BOLD}$RECOMMENDED${NC}"
    fi
    echo "    2. The script will find it and set it up for you"
    echo ""

    ask "Download the binary from the Anthropic page, then press Enter."
    wait_enter

    # Search for the binary in common locations
    FOUND_BINARY=""
    for f in ~/Downloads/darwin-arm64 ~/Downloads/darwin-x86_64 \
             ~/Downloads/linux-amd64 ~/Downloads/linux-arm64 \
             ~/Downloads/claude-hfi ~/Downloads/claude-hfi-*; do
        if [[ -f "$f" ]]; then
            FOUND_BINARY="$f"
            break
        fi
    done

    if [[ -n "$FOUND_BINARY" ]]; then
        ok "Found: $FOUND_BINARY"

        # Copy to repo root
        cp "$FOUND_BINARY" "$(pwd)/claude-hfi"
        chmod +x claude-hfi
        xattr -d com.apple.quarantine claude-hfi 2>/dev/null || true
        ok "Installed to repo root: ./claude-hfi"

        # Cache it for future tasks
        mkdir -p "$MARLIN_TOOLS_DIR"
        cp "$(pwd)/claude-hfi" "$MARLIN_TOOLS_DIR/claude-hfi"
        chmod +x "$MARLIN_TOOLS_DIR/claude-hfi"
        xattr -d com.apple.quarantine "$MARLIN_TOOLS_DIR/claude-hfi" 2>/dev/null || true
        ok "Cached at ~/marlin-tools/claude-hfi for future tasks"
        echo ""
        echo -e "  ${DIM}Next time you run this script for a new task, it will${NC}"
        echo -e "  ${DIM}automatically copy the binary from ~/marlin-tools/.${NC}"

    elif [[ -f "claude-hfi" ]]; then
        chmod +x claude-hfi 2>/dev/null || true
        xattr -d com.apple.quarantine claude-hfi 2>/dev/null || true
        ok "CLI binary found in repo: ./claude-hfi"
    else
        warn "Could not find the binary automatically."
        echo ""
        echo "  Move it manually:"
        echo -e "    ${CYAN}mv ~/Downloads/darwin-arm64 $(pwd)/claude-hfi${NC}"
        echo -e "    ${CYAN}chmod +x claude-hfi${NC}"
        echo ""
        echo "  To cache for future tasks:"
        echo -e "    ${CYAN}mkdir -p ~/marlin-tools${NC}"
        echo -e "    ${CYAN}cp claude-hfi ~/marlin-tools/claude-hfi${NC}"
    fi
fi

# ==========================================================================
# STEP 3.9 — Launch the CLI
# ==========================================================================

# Gate: warn if dev environment is not ready (Master Guide 3.5 must complete before 3.9)
if [[ "${INSTALL_OK:-false}" != true ]]; then
    echo ""
    echo -e "  ${RED}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${RED}${BOLD}║  WARNING: Dev environment is NOT set up!                  ║${NC}"
    echo -e "  ${RED}${BOLD}║                                                            ║${NC}"
    echo -e "  ${RED}${BOLD}║  Master Guide 3.5: \"If the environment is broken, the     ║${NC}"
    echo -e "  ${RED}${BOLD}║  model cannot run tests. That is YOUR fault.\"             ║${NC}"
    echo -e "  ${RED}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}Options:${NC}"
    echo -e "    ${CYAN}1${NC}) Continue anyway (risky — model can't run tests)"
    echo -e "    ${CYAN}2${NC}) Abort — I'll fix deps manually and re-run"
    echo ""
    read -rp "  Choice [1/2]: " dep_gate_choice
    if [[ "$dep_gate_choice" == "2" ]]; then
        echo ""
        echo -e "  ${YELLOW}Fix dependencies, then re-run:${NC}"
        echo -e "    ${CYAN}bash $(realpath "$0")${NC}"
        echo ""
        exit 1
    fi
    echo ""
    warn "Proceeding without dependencies. The model may not be able to run tests."
    echo ""
fi

step "3.9 — Launch the CLI"

INTERFACE_CODE="cc_agentic_coding_next"
HFI_REPO_DIR="$(pwd)"

# Unset conflicting env var for HFI
unset ANTHROPIC_API_KEY 2>/dev/null || true

# Copy interface code to clipboard
if command -v pbcopy &>/dev/null; then
    echo -n "$INTERFACE_CODE" | pbcopy
    ok "Interface code copied to clipboard: $INTERFACE_CODE"
elif command -v xclip &>/dev/null; then
    echo -n "$INTERFACE_CODE" | xclip -selection clipboard
    ok "Interface code copied to clipboard: $INTERFACE_CODE"
elif command -v xsel &>/dev/null; then
    echo -n "$INTERFACE_CODE" | xsel --clipboard
    ok "Interface code copied to clipboard: $INTERFACE_CODE"
else
    info "Interface code: ${BOLD}$INTERFACE_CODE${NC}"
fi

# Auto-launch HFI in a new terminal window
HFI_LAUNCHED=false

if [[ "$(uname -s)" == "Darwin" ]] && command -v osascript &>/dev/null; then
    echo ""
    info "Launching HFI in a new Terminal window..."
    echo ""

    # Write launch commands to a temp script (avoids osascript quoting issues)
    HFI_LAUNCH_SCRIPT="/tmp/marlin_hfi_launch_$$.sh"
    cat > "$HFI_LAUNCH_SCRIPT" << LAUNCH_EOF
#!/bin/bash
cd '$HFI_REPO_DIR'
unset ANTHROPIC_API_KEY 2>/dev/null
echo ''
echo '============================================='
echo '  Interface code: $INTERFACE_CODE'
echo '  Paste it when prompted (Cmd+V)'
echo '============================================='
echo ''
./claude-hfi --vscode
LAUNCH_EOF
    chmod +x "$HFI_LAUNCH_SCRIPT"

    # Use heredoc for osascript to avoid nested quote escaping
    if osascript << OSASCRIPT_EOF 2>/dev/null
tell application "Terminal"
    do script "$HFI_LAUNCH_SCRIPT"
    activate
end tell
OSASCRIPT_EOF
    then
        HFI_LAUNCHED=true
        ok "HFI launched in a new Terminal window."
        echo ""
        echo -e "  ${GREEN}${BOLD}A new Terminal window opened with HFI starting.${NC}"
        echo -e "  ${YELLOW}When it asks for Interface Code, press ${BOLD}Cmd+V${NC}${YELLOW} to paste.${NC}"
        echo -e "  ${DIM}(Interface code: $INTERFACE_CODE)${NC}"
    else
        warn "osascript failed. Falling back to manual launch."
    fi
fi

if [[ "$HFI_LAUNCHED" == false ]]; then
    echo ""
    echo "  Launch the CLI from the repo root in a new terminal:"
    echo ""
    echo -e "    ${CYAN}cd ${HFI_REPO_DIR}${NC}"
    echo -e "    ${CYAN}unset ANTHROPIC_API_KEY 2>/dev/null${NC}"
    echo -e "    ${CYAN}./claude-hfi --vscode${NC}"
    echo ""
    echo -e "  When prompted for Interface Code, just ${BOLD}${GREEN}Cmd+V / Ctrl+V${NC} to paste."
    echo -e "  ${DIM}(Already in your clipboard: $INTERFACE_CODE)${NC}"
    echo ""
    echo "  To resume a previous session:"
    echo -e "    ${CYAN}./claude-hfi --vscode --continue${NC}"
    echo ""
fi

# Wait for HFI to start by polling tmux sessions
echo ""
info "Waiting for HFI to create tmux sessions..."
echo -e "  ${DIM}(This usually takes 10-30 seconds after HFI starts)${NC}"
echo ""

HFI_READY=false
HFI_WAIT=0
HFI_MAX_WAIT=120

while [[ $HFI_WAIT -lt $HFI_MAX_WAIT ]]; do
    TMUX_CHECK=$(tmux ls 2>/dev/null || true)
    if [[ -n "$TMUX_CHECK" ]]; then
        HFI_READY=true
        ok "HFI tmux sessions detected."
        break
    fi
    sleep 3
    HFI_WAIT=$((HFI_WAIT + 3))
    printf "\r  ⟳ Waiting for tmux sessions... (%ds / %ds)  " "$HFI_WAIT" "$HFI_MAX_WAIT"
done
echo ""

if [[ "$HFI_READY" == false ]]; then
    warn "No tmux sessions detected after ${HFI_MAX_WAIT}s."
    echo "  HFI may still be starting. You can check manually:"
    echo -e "    ${CYAN}tmux ls${NC}"
    echo ""
    ask "Press Enter to continue anyway."
    wait_enter
fi

# ==========================================================================
# STEP 3.6 — CLAUDE.md (V3 Requirement)
# ==========================================================================
# Per the Master Guide's "Critical workflow order":
#   1. Clean main branch (no pending changes)
#   2. Launch HFI (done above in 3.9)
#   3. THEN create CLAUDE.md
#   4. Copy CLAUDE.md from local path (A) to HFI cache path (B)
step "3.6 — CLAUDE.md (V3 Requirement — created AFTER HFI launch)"

echo "  The Master Guide requires CLAUDE.md to be created AFTER HFI is running."
echo "  HFI reads this file to understand the repo structure."
echo ""

CLAUDE_TARGET="CLAUDE.md"
CLAUDE_EXISTS=false
CLAUDE_COMPLETE=false
# Per-task draft scoping prevents cross-contamination between tasks
TASK_BRIDGE_DIR="$TASK_DIR/.task-bridge"
mkdir -p "$TASK_BRIDGE_DIR" 2>/dev/null || true
CLAUDE_DRAFT_FILE="$TASK_BRIDGE_DIR/CLAUDE_md_content.txt"

# --- Check 1: Prebuilt CLAUDE.md in repo root ---
if [[ -f "CLAUDE.md" ]]; then
    CLAUDE_EXISTS=true
    ok "CLAUDE.md already exists in this repo (prebuilt)."
    echo ""

    MISSING_SECTIONS=()
    grep -qi "repository overview\|## overview" CLAUDE.md 2>/dev/null || MISSING_SECTIONS+=("Repository Overview")
    grep -qi "dev setup\|## setup\|## install" CLAUDE.md 2>/dev/null || MISSING_SECTIONS+=("Dev Setup")
    grep -qi "testing\|## test" CLAUDE.md 2>/dev/null || MISSING_SECTIONS+=("Testing")
    grep -qi "conventions\|## code style\|## style" CLAUDE.md 2>/dev/null || MISSING_SECTIONS+=("Code Conventions")
    grep -qi "architecture\|## structure\|## modules" CLAUDE.md 2>/dev/null || MISSING_SECTIONS+=("Architecture")

    if [[ ${#MISSING_SECTIONS[@]} -eq 0 ]]; then
        CLAUDE_COMPLETE=true
        ok "CLAUDE.md has all required sections. Using as-is."
        echo ""
        echo "  Sections found:"
        echo -e "    ${GREEN}✓${NC} Repository Overview"
        echo -e "    ${GREEN}✓${NC} Dev Setup"
        echo -e "    ${GREEN}✓${NC} Testing"
        echo -e "    ${GREEN}✓${NC} Code Conventions"
        echo -e "    ${GREEN}✓${NC} Architecture"
    else
        warn "CLAUDE.md is missing some recommended sections:"
        for section in "${MISSING_SECTIONS[@]}"; do
            echo -e "    ${RED}✗${NC} $section"
        done
        echo ""
        ask "Regenerate via Cursor? (y = regenerate, n = keep current)"
        if wait_confirm "Regenerate CLAUDE.md?"; then
            CLAUDE_EXISTS=false
        fi
    fi

# --- Check 2: Draft from a previous bridge run ---
elif [[ -f "$CLAUDE_DRAFT_FILE" ]] && [[ $(wc -c < "$CLAUDE_DRAFT_FILE" 2>/dev/null || echo 0) -gt 50 ]]; then
    DRAFT_VALID=false

    DRAFT_HEAD=$(head -20 "$CLAUDE_DRAFT_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    CURRENT_REPO_LOWER=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')

    if [[ "$LANG_DETECTED" == "python" ]] && echo "$DRAFT_HEAD" | grep -qiE "pip install|pytest|python|venv"; then
        DRAFT_LANG="python"
    elif [[ "$LANG_DETECTED" == "node" ]] && echo "$DRAFT_HEAD" | grep -qiE "npm|yarn|typescript|node"; then
        DRAFT_LANG="node"
    else
        DRAFT_LANG="unknown"
    fi

    if [[ -n "${KNOWN_REPO:-}" ]]; then
        if echo "$DRAFT_HEAD" | grep -qi "$KNOWN_REPO"; then
            DRAFT_VALID=true
        else
            warn "CLAUDE.md draft is for a DIFFERENT repo (doesn't mention '$KNOWN_REPO')."
            echo -e "  ${DIM}Draft starts with: $(head -3 "$CLAUDE_DRAFT_FILE" 2>/dev/null | tr '\n' ' ' | cut -c1-80)...${NC}"
            echo -e "  ${RED}Discarding stale draft. Will generate fresh CLAUDE.md.${NC}"
        fi
    elif [[ "$DRAFT_LANG" == "$LANG_DETECTED" ]]; then
        DRAFT_VALID=true
    else
        warn "CLAUDE.md draft language ($DRAFT_LANG) doesn't match current repo ($LANG_DETECTED)."
        echo -e "  ${RED}Discarding stale draft. Will generate fresh CLAUDE.md.${NC}"
    fi

    if [[ "$DRAFT_VALID" == true ]]; then
        ok "Found valid CLAUDE.md draft from previous Cursor generation."
        cp "$CLAUDE_DRAFT_FILE" "$CLAUDE_TARGET"
        CLAUDE_EXISTS=true
        CLAUDE_COMPLETE=true
        ok "Copied draft to CLAUDE.md."
    fi
fi

# --- Generate if needed: fully automated via bridge ---
if [[ "$CLAUDE_EXISTS" == false ]]; then
    echo ""
    info "Generating CLAUDE.md automatically via Cursor bridge..."
    echo ""

    # Gather repo context
    python3 "$SCRIPT_DIR/marlin_bridge.py" repo-context --path "$(pwd)" > "$TASK_BRIDGE_DIR/repo_context.json" 2>/dev/null || true

    # Write action request to live_bridge.json for Cursor
    python3 -c "
import json
bridge_path = '$LIVE_JSON'
try:
    with open(bridge_path, 'r') as f:
        data = json.load(f)
except Exception:
    data = {}
data['action'] = 'generate_claude_md'
data['action_request'] = {
    'repo_context_path': '$TASK_BRIDGE_DIR/repo_context.json',
    'output_path': '$(pwd)/CLAUDE.md',
    'draft_path': '$CLAUDE_DRAFT_FILE',
    'repo_path': '$(pwd)',
    'status': 'pending'
}
data['action_response'] = None
data['status'] = 'waiting_for_cursor'
with open(bridge_path, 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

    echo -e "  ${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${BLUE}║  CLAUDE.md generation request sent to Cursor         ║${NC}"
    echo -e "  ${BLUE}║  Cursor will read repo context and write CLAUDE.md   ║${NC}"
    echo -e "  ${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}${BOLD}Switch to Cursor and send any message to trigger generation.${NC}"
    echo -e "  ${DIM}(e.g. type: \"generate CLAUDE.md\" or just press Enter in chat)${NC}"
    echo ""

    # Poll for the result
    CLAUDE_WAIT=0
    CLAUDE_MAX_WAIT=180
    CLAUDE_GENERATED=false

    while [[ $CLAUDE_WAIT -lt $CLAUDE_MAX_WAIT ]]; do
        # Check if CLAUDE.md appeared (written directly by Cursor)
        if [[ -f "$CLAUDE_TARGET" ]] && [[ $(wc -c < "$CLAUDE_TARGET" 2>/dev/null || echo 0) -gt 50 ]]; then
            CLAUDE_GENERATED=true
            break
        fi
        # Check if draft file appeared
        if [[ -f "$CLAUDE_DRAFT_FILE" ]] && [[ $(wc -c < "$CLAUDE_DRAFT_FILE" 2>/dev/null || echo 0) -gt 50 ]]; then
            cp "$CLAUDE_DRAFT_FILE" "$CLAUDE_TARGET"
            CLAUDE_GENERATED=true
            break
        fi
        # Check bridge for action_response
        action_done=$(python3 -c "
import json
with open('$LIVE_JSON') as f:
    d = json.load(f)
r = d.get('action_response') or {}
print('yes' if r.get('status') == 'done' else 'no')
" 2>/dev/null) || action_done="no"
        if [[ "$action_done" == "yes" ]]; then
            if [[ -f "$CLAUDE_TARGET" ]]; then
                CLAUDE_GENERATED=true
                break
            fi
        fi

        sleep 3
        CLAUDE_WAIT=$((CLAUDE_WAIT + 3))
        printf "\r  ⟳ Waiting for Cursor to generate CLAUDE.md... (%ds / %ds)  " "$CLAUDE_WAIT" "$CLAUDE_MAX_WAIT"
    done
    echo ""

    if [[ "$CLAUDE_GENERATED" == true ]]; then
        ok "CLAUDE.md generated by Cursor."
    fi

    # Fallback to quick-scan if Cursor didn't generate in time
    if [[ "$CLAUDE_GENERATED" != true ]]; then
        warn "Cursor did not generate CLAUDE.md within ${CLAUDE_MAX_WAIT}s."
        echo ""
        info "Falling back to quick-scan generation..."
        echo ""

        QS_REPO_NAME=$(basename "${REPO_DIR:-$(pwd)}")
        QS_FILE_COUNT=$(find . -type f -not -path './.git/*' -not -path './.venv/*' -not -path './node_modules/*' 2>/dev/null | wc -l | tr -d ' ')

        QS_TOP_DIRS=$(find . -maxdepth 1 -type d \
            -not -name '.' -not -name '.git' -not -name '.venv' \
            -not -name 'node_modules' -not -name '__pycache__' \
            -not -name '.mypy_cache' -not -name '.pytest_cache' \
            -not -name '.tox' -not -name '.eggs' -not -name '*.egg-info' \
            2>/dev/null | sort | sed 's|^\./||' | head -20)

        QS_TEST_DIRS=$(find . -type d -name 'test*' \
            -not -path './.git/*' -not -path './.venv/*' \
            -not -path './node_modules/*' \
            2>/dev/null | head -10 | sed 's|^\./||')

        QS_README_DESC=""
        if [[ -f "README.md" ]]; then
            QS_README_DESC=$(head -10 README.md 2>/dev/null | grep -v '^#' | grep -v '^$' | head -3 | tr '\n' ' ')
        elif [[ -f "README.rst" ]]; then
            QS_README_DESC=$(head -10 README.rst 2>/dev/null | grep -v '^=' | grep -v '^$' | head -3 | tr '\n' ' ')
        fi

        QS_INSTALL_CMD="[Fill in install command]"
        case ${LANG_DETECTED:-unknown} in
            python)
                QS_INSTALL_CMD="python -m venv .venv && source .venv/bin/activate"
                if [[ -f "pyproject.toml" ]]; then
                    QS_INSTALL_CMD="$QS_INSTALL_CMD && pip install -e '.[dev]'"
                elif [[ -f "setup.py" ]]; then
                    QS_INSTALL_CMD="$QS_INSTALL_CMD && pip install -e '.[dev]'"
                elif [[ -f "requirements.txt" ]]; then
                    QS_INSTALL_CMD="$QS_INSTALL_CMD && pip install -r requirements.txt"
                fi
                ;;
            node) QS_INSTALL_CMD="npm install" ;;
            go)   QS_INSTALL_CMD="go mod download" ;;
            rust) QS_INSTALL_CMD="cargo build" ;;
        esac

        QS_TEST_CMD_DISPLAY="${TEST_CMD:-[Fill in test command]}"

        QS_TEST_DIRS_BLOCK=""
        if [[ -n "$QS_TEST_DIRS" ]]; then
            QS_TEST_DIRS_BLOCK=$(printf "\nTest directories:\n%s" "$(echo "$QS_TEST_DIRS" | sed 's/^/- /')")
        fi
        QS_TOP_DIRS_BLOCK=""
        if [[ -n "$QS_TOP_DIRS" ]]; then
            QS_TOP_DIRS_BLOCK=$(echo "$QS_TOP_DIRS" | sed 's/^/- /')
        fi

        {
            echo "# CLAUDE.md"
            echo ""
            echo "## Repository Overview"
            echo "$QS_REPO_NAME"
            echo "${QS_README_DESC:-[Brief description of what this repository does]}"
            echo "Language: ${LANG_DETECTED:-unknown}"
            echo "Approximate size: $QS_FILE_COUNT files"
            echo ""
            echo "## Dev Setup"
            echo '```bash'
            echo "$QS_INSTALL_CMD"
            echo '```'
            echo ""
            echo "## Testing"
            echo '```bash'
            echo "$QS_TEST_CMD_DISPLAY"
            echo '```'
            [[ -n "$QS_TEST_DIRS_BLOCK" ]] && echo "$QS_TEST_DIRS_BLOCK"
            echo ""
            echo "## Code Conventions"
            echo "[Naming conventions, import style, error handling patterns used in this repo]"
            echo ""
            echo "## Architecture"
            echo "Key modules:"
            [[ -n "$QS_TOP_DIRS_BLOCK" ]] && echo "$QS_TOP_DIRS_BLOCK"
        } > "$CLAUDE_TARGET"

        ok "Generated: $CLAUDE_TARGET (quick-scan fallback)"
    fi
fi

# Display CLAUDE.md contents (works for both prebuilt and newly generated)
if [[ -f "$CLAUDE_TARGET" ]]; then
    echo ""
    echo -e "  ${BOLD}Contents:${NC}"
    divider
    sed 's/^/  /' "$CLAUDE_TARGET" || true
    divider
fi

# Fix .gitignore blocking CLAUDE.md (HFI won't see it otherwise)
if [[ -f ".gitignore" ]] && grep -qE '^\s*CLAUDE\.md\s*$|^\s*CLAUDE\*|^\s*\*\.md\s*$' .gitignore 2>/dev/null; then
    warn "CLAUDE.md is listed in .gitignore — HFI will NOT see it."
    echo ""
    info "Removing CLAUDE.md entry from .gitignore..."

    # Back up CLAUDE.md, remove gitignore entry, recommit, restore
    cp CLAUDE.md /tmp/CLAUDE_md_backup_$$ 2>/dev/null || true
    rm -f CLAUDE.md 2>/dev/null || true

    # Remove the gitignore entry (handle CLAUDE.md, CLAUDE*, *.md patterns)
    sed -i.bak '/^\s*CLAUDE\.md\s*$/d' .gitignore 2>/dev/null || \
    sed -i '' '/^\s*CLAUDE\.md\s*$/d' .gitignore 2>/dev/null || true
    rm -f .gitignore.bak 2>/dev/null || true

    # Commit the gitignore fix (this is the one exception to "no commits after init")
    git add .gitignore 2>/dev/null || true
    git commit -q -m "Remove CLAUDE.md from .gitignore (required for HFI)" 2>/dev/null || true
    ok "Committed .gitignore fix."

    # Restore CLAUDE.md
    cp /tmp/CLAUDE_md_backup_$$ CLAUDE.md 2>/dev/null || true
    rm -f /tmp/CLAUDE_md_backup_$$ 2>/dev/null || true
    ok "CLAUDE.md restored. HFI will now detect it."
    echo ""
fi

# Copy CLAUDE.md to HFI worktrees (A and B)
# HFI uses git worktrees at ~/.cache/claude-hfi/<project>/A and /B.
# Since CLAUDE.md is untracked, it does NOT appear in worktrees automatically.
# Worktrees may take a few seconds to appear after HFI creates tmux sessions.
copy_claude_to_worktrees() {
    local copied=0
    while IFS= read -r wt_line; do
        local wt_path
        wt_path=$(echo "$wt_line" | awk '{print $1}')
        if [[ -n "$wt_path" && "$wt_path" != "$(pwd)" && -d "$wt_path" ]]; then
            cp CLAUDE.md "$wt_path/CLAUDE.md" 2>/dev/null && {
                ok "Copied CLAUDE.md to worktree: $(basename "$wt_path")"
                copied=$((copied + 1))
            }
        fi
    done < <(git worktree list 2>/dev/null)

    # Also check ~/.cache/claude-hfi/ directly as a fallback
    local repo_base
    repo_base="$(basename "$(pwd)")"
    for cache_dir in "$HOME/.cache/claude-hfi/"*; do
        if [[ -d "$cache_dir/A" ]]; then
            cp CLAUDE.md "$cache_dir/A/CLAUDE.md" 2>/dev/null && {
                ok "Copied CLAUDE.md to HFI cache: $(basename "$cache_dir")/A"
                copied=$((copied + 1))
            }
        fi
        if [[ -d "$cache_dir/B" ]]; then
            cp CLAUDE.md "$cache_dir/B/CLAUDE.md" 2>/dev/null && {
                ok "Copied CLAUDE.md to HFI cache: $(basename "$cache_dir")/B"
                copied=$((copied + 1))
            }
        fi
    done 2>/dev/null

    return $copied
}

if [[ -f "CLAUDE.md" ]]; then
    info "Waiting for HFI to create worktrees (A/B) so CLAUDE.md can be distributed..."
    WT_POLL=0
    WT_MAX=60
    WT_FOUND=false

    while [[ $WT_POLL -lt $WT_MAX ]]; do
        WT_COUNT=$(git worktree list 2>/dev/null | grep -cE '/[AB] ' || true)
        CACHE_COUNT=$(ls -d "$HOME/.cache/claude-hfi/"*/A 2>/dev/null | wc -l | tr -d ' ')

        if [[ $WT_COUNT -ge 2 || $CACHE_COUNT -ge 1 ]]; then
            WT_FOUND=true
            break
        fi

        sleep 3
        WT_POLL=$((WT_POLL + 3))
        printf "\r  ${DIM}⟳ Waiting for worktrees... (%ds / %ds)${NC}  " "$WT_POLL" "$WT_MAX"
    done
    echo ""

    if [[ "$WT_FOUND" == true ]]; then
        copy_claude_to_worktrees || true
    else
        warn "HFI worktrees not detected after ${WT_MAX}s."
        echo -e "  ${DIM}CLAUDE.md is in repo root. Will retry after tmux attach step.${NC}"
        echo -e "  ${DIM}If still missing, copy manually:${NC}"
        echo -e "  ${CYAN}  cp CLAUDE.md ~/.cache/claude-hfi/<project>/A/${NC}"
        echo -e "  ${CYAN}  cp CLAUDE.md ~/.cache/claude-hfi/<project>/B/${NC}"
    fi
fi

echo ""
echo -e "  ${YELLOW}The CLI reads CLAUDE.md to understand the repo. Review it${NC}"
echo -e "  ${YELLOW}for accuracy — inaccurate content hurts model performance.${NC}"

wait_enter

# ==========================================================================
# STEP 3.10 — Understanding A/B Trajectories + Attach to tmux
# ==========================================================================
step "3.10 — Trajectories & tmux Sessions"

echo -e "  ${BOLD}${YELLOW}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "  ${BOLD}${YELLOW}│  WHAT ARE TRAJECTORY A AND B?                               │${NC}"
echo -e "  ${BOLD}${YELLOW}├─────────────────────────────────────────────────────────────┤${NC}"
echo -e "  ${YELLOW}│${NC}                                                             ${YELLOW}│${NC}"
echo -e "  ${YELLOW}│${NC}  HFI runs your prompt through TWO independent models:       ${YELLOW}│${NC}"
echo -e "  ${YELLOW}│${NC}                                                             ${YELLOW}│${NC}"
echo -e "  ${YELLOW}│${NC}    ${CYAN}Trajectory A${NC} = Model instance 1 (own git worktree)      ${YELLOW}│${NC}"
echo -e "  ${YELLOW}│${NC}    ${CYAN}Trajectory B${NC} = Model instance 2 (own git worktree)      ${YELLOW}│${NC}"
echo -e "  ${YELLOW}│${NC}                                                             ${YELLOW}│${NC}"
echo -e "  ${YELLOW}│${NC}  Both get the SAME prompt but work independently.           ${YELLOW}│${NC}"
echo -e "  ${YELLOW}│${NC}  After they finish, you compare outputs and pick the best.  ${YELLOW}│${NC}"
echo -e "  ${YELLOW}│${NC}                                                             ${YELLOW}│${NC}"
echo -e "  ${YELLOW}│${NC}  Each has its own VS Code window where you can watch live.  ${YELLOW}│${NC}"
echo -e "  ${BOLD}${YELLOW}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""

# Show worktree paths
WORKTREE_A_PATH=""
WORKTREE_B_PATH=""
while IFS= read -r wt_line; do
    wt_path=$(echo "$wt_line" | awk '{print $1}')
    if [[ "$wt_path" == *"/A" ]]; then
        WORKTREE_A_PATH="$wt_path"
    elif [[ "$wt_path" == *"/B" ]]; then
        WORKTREE_B_PATH="$wt_path"
    fi
done < <(git worktree list 2>/dev/null)

if [[ -n "$WORKTREE_A_PATH" ]]; then
    echo -e "  ${DIM}Worktree A: ${WORKTREE_A_PATH}${NC}"
fi
if [[ -n "$WORKTREE_B_PATH" ]]; then
    echo -e "  ${DIM}Worktree B: ${WORKTREE_B_PATH}${NC}"
fi
echo ""

echo "  Detecting active tmux sessions..."
echo ""

TMUX_SESSIONS=$(tmux ls 2>/dev/null || true)

if [[ -n "$TMUX_SESSIONS" ]]; then
    SESSION_A=$(echo "$TMUX_SESSIONS" | grep -oE '^[^:]+' | grep -E '[-_]A$' | head -1)
    SESSION_B=$(echo "$TMUX_SESSIONS" | grep -oE '^[^:]+' | grep -E '[-_]B$' | head -1)

    if [[ -n "$SESSION_A" && -n "$SESSION_B" ]]; then
        ok "Found HFI tmux sessions:"
        echo ""
        echo -e "  ${BOLD}┌─────────────────────────────────────────────────────────────┐${NC}"
        echo -e "  ${BOLD}│${NC}  ${GREEN}Trajectory A:${NC} ${CYAN}tmux attach -t $SESSION_A${NC}"
        echo -e "  ${BOLD}│${NC}  ${GREEN}Trajectory B:${NC} ${CYAN}tmux attach -t $SESSION_B${NC}"
        echo -e "  ${BOLD}└─────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BOLD}HOW TO WATCH THE MODELS WORK:${NC}"
        echo ""
        echo -e "  HFI opened two VS Code windows. In each one:"
        echo -e "    1. Open the integrated terminal: ${BOLD}Ctrl+\`${NC} (backtick)"
        echo -e "    2. Paste the tmux attach command for that trajectory"
        echo -e "    3. You'll see the model's live output (commands, edits, reasoning)"
        echo ""

        # Auto-attach via osascript (opens two new Terminal.app tabs)
        if [[ "$(uname -s)" == "Darwin" ]] && command -v osascript &>/dev/null; then
            cat > /tmp/marlin_tmux_A_$$.sh << TMUX_SCRIPT_A
#!/bin/bash
echo "Attaching to Trajectory A..."
tmux attach -t $SESSION_A
TMUX_SCRIPT_A
            cat > /tmp/marlin_tmux_B_$$.sh << TMUX_SCRIPT_B
#!/bin/bash
echo "Attaching to Trajectory B..."
tmux attach -t $SESSION_B
TMUX_SCRIPT_B
            chmod +x /tmp/marlin_tmux_A_$$.sh /tmp/marlin_tmux_B_$$.sh

            osascript -e "tell application \"Terminal\" to do script \"bash /tmp/marlin_tmux_A_$$.sh\"" 2>/dev/null && \
                ok "Opened Terminal tab attached to Trajectory A." || true
            sleep 1
            osascript -e "tell application \"Terminal\" to do script \"bash /tmp/marlin_tmux_B_$$.sh\"" 2>/dev/null && \
                ok "Opened Terminal tab attached to Trajectory B." || true
            echo ""
            echo -e "  ${GREEN}Two Terminal tabs opened, each attached to a trajectory.${NC}"
            echo -e "  ${DIM}You can also attach from VS Code terminals if you prefer.${NC}"
        else
            if command -v pbcopy &>/dev/null; then
                echo -n "tmux attach -t $SESSION_A" | pbcopy
                ok "Trajectory A command copied to clipboard."
                echo -e "  ${DIM}Paste in VS Code Window A's terminal (Ctrl+\`), then come back.${NC}"
                wait_enter
                echo -n "tmux attach -t $SESSION_B" | pbcopy
                ok "Trajectory B command copied to clipboard."
                echo -e "  ${DIM}Paste in VS Code Window B's terminal (Ctrl+\`).${NC}"
            fi
        fi
    else
        ok "Active tmux sessions:"
        echo ""
        echo "$TMUX_SESSIONS" | while IFS= read -r line; do
            echo -e "    ${CYAN}$line${NC}"
        done
        echo ""
        echo "  Open terminal in each VS Code window (Ctrl+\`) and attach:"
        echo "$TMUX_SESSIONS" | grep -oE '^[^:]+' | while IFS= read -r sess; do
            echo -e "    ${CYAN}tmux attach -t $sess${NC}"
        done
    fi
else
    warn "No tmux sessions detected yet."
    echo "  This is normal if HFI is still starting up."
    echo "  Wait a moment, then check manually:"
    echo -e "    ${CYAN}tmux ls${NC}"
    echo ""
    echo "  Then in each VS Code window, open terminal (Ctrl+\`) and run:"
    echo -e "    ${CYAN}tmux attach -t <session-id>-A${NC}   (VS Code window 1)"
    echo -e "    ${CYAN}tmux attach -t <session-id>-B${NC}   (VS Code window 2)"
fi

# Deferred CLAUDE.md re-copy: by now worktrees should exist
if [[ -f "CLAUDE.md" ]]; then
    info "Re-checking worktrees for CLAUDE.md distribution..."
    copy_claude_to_worktrees >/dev/null 2>&1 || true
fi

# ==========================================================================
# PRE-THREAD SURVEY PREPARATION
# ==========================================================================
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │   PRE-THREAD SURVEY ANSWERS                  │"
echo "  └─────────────────────────────────────────────┘"
echo -e "${NC}"
echo "  When HFI asks the pre-thread survey, use these answers:"
echo ""

SURVEY_OS="$(uname -s) $(uname -m)"
SURVEY_PY_VER=$(python3 --version 2>&1 || echo "N/A")
SURVEY_REPO_PATH="$(pwd)"
SURVEY_COMMIT="${HEAD_COMMIT:-N/A}"
SURVEY_INTERFACE="cc_agentic_coding_next"
SURVEY_TASK_TYPE="agentic_coding"

echo -e "  ${BOLD}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "  ${BOLD}│${NC}  Initial commit hash:  ${CYAN}$SURVEY_COMMIT${NC}"
echo -e "  ${BOLD}│${NC}  Workspace path:       ${CYAN}$SURVEY_REPO_PATH${NC}"
echo -e "  ${BOLD}│${NC}  Operating system:     ${CYAN}$SURVEY_OS${NC}"
echo -e "  ${BOLD}│${NC}  Python version:       ${CYAN}$SURVEY_PY_VER${NC}"
echo -e "  ${BOLD}│${NC}  Task type:            ${CYAN}$SURVEY_TASK_TYPE${NC}"
echo -e "  ${BOLD}│${NC}  Interface code:       ${CYAN}$SURVEY_INTERFACE${NC}"
echo -e "  ${BOLD}│${NC}  Language detected:    ${CYAN}${LANG_DETECTED:-unknown}${NC}"
echo -e "  ${BOLD}│${NC}  Test command:         ${CYAN}${TEST_CMD:-N/A}${NC}"
echo -e "  ${BOLD}└──────────────────────────────────────────────────────────────┘${NC}"
echo ""

# Save survey answers to a file for easy reference
SURVEY_FILE="$BRIDGE_DIR/survey_answers.txt"
{
    echo "PRE-THREAD SURVEY ANSWERS"
    echo "========================"
    echo "Initial commit hash:  $SURVEY_COMMIT"
    echo "Workspace path:       $SURVEY_REPO_PATH"
    echo "Operating system:     $SURVEY_OS"
    echo "Python version:       $SURVEY_PY_VER"
    echo "Task type:            $SURVEY_TASK_TYPE"
    echo "Interface code:       $SURVEY_INTERFACE"
    echo "Language detected:    ${LANG_DETECTED:-unknown}"
    echo "Test command:         ${TEST_CMD:-N/A}"
} > "$SURVEY_FILE" 2>/dev/null || true

ok "Survey answers saved to: $SURVEY_FILE"
echo ""

# Copy commit hash to clipboard (most commonly needed for survey)
if command -v pbcopy &>/dev/null; then
    echo -n "$SURVEY_COMMIT" | pbcopy
    ok "Commit hash copied to clipboard (most frequently asked survey field)."
elif command -v xclip &>/dev/null; then
    echo -n "$SURVEY_COMMIT" | xclip -selection clipboard
    ok "Commit hash copied to clipboard."
fi

echo ""
echo -e "  ${DIM}Tip: Survey answers also saved at${NC}"
echo -e "  ${DIM}$SURVEY_FILE${NC}"
echo -e "  ${DIM}You can open it anytime to copy values.${NC}"

# ==========================================================================
# FINAL SUMMARY
# ==========================================================================
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │   SETUP COMPLETE — SUMMARY                  │"
echo "  └─────────────────────────────────────────────┘"
echo -e "${NC}"

echo -e "  ${GREEN}Completed:${NC}"
echo "    ✓ System prerequisites checked"
command -v code &>/dev/null && echo "    ✓ VS Code CLI in PATH"
echo "    ✓ Repository downloaded and unpacked"
echo "    ✓ Git initialized (initial commit only)"

if [[ "${INSTALL_OK:-false}" == true ]]; then
    echo -e "    ${GREEN}✓${NC} Dependencies installed ($LANG_DETECTED)"
else
    echo -e "    ${RED}✗ Dependencies NOT installed ($LANG_DETECTED)${NC}"
    echo -e "      ${YELLOW}⚠ The model CANNOT run tests. Fix this before pasting your prompt.${NC}"
fi

if [[ "${TESTS_PASSED:-false}" == true ]]; then
    echo -e "    ${GREEN}✓${NC} Baseline tests passed ($TEST_CMD)"
elif [[ -n "${TEST_CMD:-}" ]]; then
    echo -e "    ${YELLOW}⚠${NC} Baseline tests ran but may have failed ($TEST_CMD)"
else
    echo -e "    ${DIM}— Tests not run (no test command detected)${NC}"
fi

[[ -f "CLAUDE.md" ]] && echo "    ✓ CLAUDE.md in place"
[[ -f "claude-hfi" && -x "claude-hfi" ]] && echo "    ✓ CLI binary installed"
echo "    ✓ HFI launched in new terminal"
echo "    ✓ Interface code (clipboard)"
[[ -n "${SESSION_A:-}" ]] && echo "    ✓ tmux sessions detected"
echo "    ✓ Pre-thread survey answers prepared"

echo ""
echo -e "  ${BOLD}Key info:${NC}"
echo -e "    HEAD commit:   ${CYAN}${HEAD_COMMIT:-N/A}${NC}"
echo -e "    Repo path:     ${CYAN}$(pwd)${NC}"
echo -e "    Language:      ${CYAN}${LANG_DETECTED:-unknown}${NC}"
[[ -n "${TEST_CMD:-}" ]] && echo -e "    Test command:   ${CYAN}$TEST_CMD${NC}"

echo ""
echo -e "  ${YELLOW}Remaining (human-only):${NC}"
[[ -f "CLAUDE.md" ]] && echo "    ○ Review CLAUDE.md for accuracy"
echo "    ○ Attach to tmux sessions in each VS Code window"
echo "    ○ Fill pre-thread survey (answers above)"
echo "    ○ Paste your approved prompt and press Enter"

echo ""
echo -e "  ${RED}${BOLD}REMINDER: Never run 'git commit' after this point.${NC}"

# ==========================================================================
# POST-RUN: HOW TO VIEW MODEL DIFFS AND TRACES
# ==========================================================================
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │   AFTER MODEL COMPLETES — VIEWING RESULTS   │"
echo "  └─────────────────────────────────────────────┘"
echo -e "${NC}"

REPO_DIR="$(pwd)"
REPO_BASENAME="$(basename "$REPO_DIR")"

echo -e "  ${BOLD}View model diffs:${NC}"
echo ""

if [[ -n "${WORKTREE_A_PATH:-}" ]]; then
    echo -e "    ${CYAN}cd $WORKTREE_A_PATH && git diff HEAD~1..HEAD${NC}  # Trajectory A"
else
    echo -e "    ${CYAN}cd ~/.cache/claude-hfi/$REPO_BASENAME/A && git diff HEAD~1..HEAD${NC}  # Trajectory A"
fi
if [[ -n "${WORKTREE_B_PATH:-}" ]]; then
    echo -e "    ${CYAN}cd $WORKTREE_B_PATH && git diff HEAD~1..HEAD${NC}  # Trajectory B"
else
    echo -e "    ${CYAN}cd ~/.cache/claude-hfi/$REPO_BASENAME/B && git diff HEAD~1..HEAD${NC}  # Trajectory B"
fi

echo ""
echo -e "  ${BOLD}View model traces (JSONL session logs):${NC}"
echo ""
echo -e "    ${CYAN}ls ~/.claude-hfi/projects/$REPO_BASENAME/*.jsonl${NC}"
echo -e "    ${DIM}Each line is a JSON event: tool calls, text outputs, test results.${NC}"
echo ""
echo -e "  ${BOLD}View HFI result files:${NC}"
echo ""
echo -e "    ${CYAN}ls /var/folders/*/*/T/claude-hfi/*/result-0-*.json${NC}"
echo -e "    ${DIM}Contains sessionFilePath pointing to the trace JSONL.${NC}"
echo ""
echo -e "  ${BOLD}Automated review:${NC}"
echo ""
echo -e "    ${CYAN}bash $(dirname "$0")/marlin_review.sh $REPO_DIR${NC}"
echo -e "    ${DIM}Waits for model completion, extracts diffs & traces,${NC}"
echo -e "    ${DIM}and generates answers for all 19 HFI feedback questions.${NC}"

echo ""
divider
echo ""
