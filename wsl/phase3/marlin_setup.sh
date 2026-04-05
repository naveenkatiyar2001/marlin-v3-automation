#!/usr/bin/env bash
# ==========================================================================
# MARLIN V3 — PHASE 3: ENVIRONMENT & CLI SETUP (WSL-OPTIMIZED)
# ==========================================================================
# Windows/WSL version of the Phase 3 setup script.
# Key differences from macOS version:
#   - Uses apt instead of brew
#   - Uses clip.exe / powershell.exe for clipboard
#   - Uses wslview / cmd.exe for browser
#   - Uses Windows Terminal (wt.exe) or new WSL window for HFI launch
#   - No macOS EPERM issue — Cursor terminal works normally
#   - No xattr/Gatekeeper handling needed
#   - Expanded language support (17 languages)
#   - Per-task CLAUDE.md scoping (fixes cross-contamination bug)
#
# Usage:
#   ./marlin_setup.sh              — start a new task
#   ./marlin_setup.sh --list       — list existing task workspaces
#   ./marlin_setup.sh --clean      — remove a task workspace
#   ./marlin_setup.sh --clean-all  — remove ALL task workspaces
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
# WSL Platform Helpers
# --------------------------------------------------------------------------
wsl_copy() {
    if command -v clip.exe &>/dev/null; then
        echo -n "$1" | clip.exe
        return 0
    elif command -v xclip &>/dev/null; then
        echo -n "$1" | xclip -selection clipboard
        return 0
    fi
    return 1
}

wsl_open_url() {
    if command -v wslview &>/dev/null; then
        wslview "$1" 2>/dev/null
    elif command -v cmd.exe &>/dev/null; then
        cmd.exe /c start "" "$1" 2>/dev/null
    else
        echo "  Open manually: $1"
    fi
}

wsl_open_terminal() {
    local cmd_to_run="$1"
    if command -v wt.exe &>/dev/null; then
        wt.exe new-tab --title "Marlin HFI" bash -c "$cmd_to_run" 2>/dev/null && return 0
    fi
    if command -v cmd.exe &>/dev/null; then
        cmd.exe /c start wsl.exe bash -c "$cmd_to_run" 2>/dev/null && return 0
    fi
    return 1
}

# --------------------------------------------------------------------------
# Cursor Bridge
# --------------------------------------------------------------------------
bridge_init() {
    mkdir -p "$BRIDGE_DIR"
    rm -f "$BRIDGE_DIR/request.json" \
          "$BRIDGE_DIR/response.json" \
          "$BRIDGE_DIR/review_data.json" \
          "$BRIDGE_DIR/evaluation_answers.json" \
          "$BRIDGE_DIR/evaluation_answers_formatted.txt" \
          "$BRIDGE_DIR/last_error.txt" \
          "$BRIDGE_DIR/survey_answers.txt" 2>/dev/null || true
    # NOTE: CLAUDE_md_content.txt and repo_context.json are now per-task (stored in TASK_DIR)
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

# --------------------------------------------------------------------------
# Global Error Trap
# --------------------------------------------------------------------------
MARLIN_INSIDE_TRAP=false

global_error_handler() {
    local line_num="${1:-unknown}"
    local failed_cmd="${2:-unknown command}"
    local exit_code="${3:-1}"

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

    if [[ -f "${LIVE_JSON:-/dev/null}" ]]; then
        python3 "${SCRIPT_DIR}/marlin_bridge.py" write-heal \
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

        local elapsed=0
        local trap_timeout=60
        while [[ $elapsed -lt $trap_timeout ]]; do
            local resp
            resp=$(python3 "${SCRIPT_DIR}/marlin_bridge.py" read-response 2>/dev/null) && {
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
                python3 "${SCRIPT_DIR}/marlin_bridge.py" clear-heal 2>/dev/null || true
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
# Self-Healing
# --------------------------------------------------------------------------
HEAL_MAX_RETRIES=3
HEAL_TIMEOUT=120

self_heal() {
    local description="$1"
    local cmd="$2"
    local hint="${3:-}"
    local attempt=0

    while [[ $attempt -lt $HEAL_MAX_RETRIES ]]; do
        attempt=$((attempt + 1))
        [[ $attempt -gt 1 ]] && info "Retry $attempt/$HEAL_MAX_RETRIES: $description"

        local output
        output=$(eval "$cmd" 2>&1) || true
        local exit_code=${PIPESTATUS[0]:-$?}

        if [[ $exit_code -eq 0 ]]; then
            ok "$description"
            return 0
        fi

        echo "$output" | tail -10
        warn "$description — failed (attempt $attempt/$HEAL_MAX_RETRIES)"

        local err_file="$BRIDGE_DIR/last_error.txt"
        echo "$output" > "$err_file"

        python3 "$SCRIPT_DIR/marlin_bridge.py" write-heal \
            --desc "$description" \
            --cmd "$cmd" \
            --error-file "$err_file" \
            --cwd "$(pwd)" \
            --hint "$hint" \
            --attempt "$attempt" \
            --max-retries "$HEAL_MAX_RETRIES" 2>/dev/null || true

        local elapsed=0
        local resp=""
        while [[ $elapsed -lt $HEAL_TIMEOUT ]]; do
            resp=$(python3 "$SCRIPT_DIR/marlin_bridge.py" read-response 2>/dev/null) && break
            sleep 2
            elapsed=$((elapsed + 2))
            printf "\r  ⟳ Waiting for Cursor... (%ds / %ds)  " "$elapsed" "$HEAL_TIMEOUT"
        done
        echo ""

        if [[ -z "$resp" ]]; then
            warn "No response from Cursor within ${HEAL_TIMEOUT}s."
            continue
        fi

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

        python3 "$SCRIPT_DIR/marlin_bridge.py" clear-heal 2>/dev/null || true
    done

    warn "Self-healing exhausted $HEAL_MAX_RETRIES attempts for: $description"
    ask "Fix the issue manually, then press Enter to continue."
    wait_enter
    return 1
}

# --------------------------------------------------------------------------
# Node Version Management
# --------------------------------------------------------------------------
ensure_node_version() {
    local required_version=""
    if [[ -f ".nvmrc" ]]; then
        required_version=$(cat .nvmrc | tr -d 'v \n\r')
        info "Found .nvmrc requiring Node $required_version"
    elif [[ -f ".node-version" ]]; then
        required_version=$(cat .node-version | tr -d 'v \n\r')
        info "Found .node-version requiring Node $required_version"
    elif [[ -f "package.json" ]]; then
        required_version=$(python3 -c "
import json
try:
    d = json.load(open('package.json'))
    engines = d.get('engines', {}).get('node', '')
    if engines:
        import re
        m = re.search(r'(\d+)', engines)
        if m: print(m.group(1))
except: pass
" 2>/dev/null)
        [[ -n "$required_version" ]] && info "package.json engines.node requires v$required_version+"
    fi

    [[ -z "$required_version" ]] && return 0

    local current_major=""
    command -v node &>/dev/null && current_major=$(node --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
    local required_major=$(echo "$required_version" | grep -oE '^[0-9]+')

    if [[ "$current_major" == "$required_major" ]]; then
        ok "Node version matches: $(node --version) (need v$required_major)"
        return 0
    fi

    warn "Node mismatch: have v${current_major:-none}, need v$required_major"

    # Try nvm
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        source "$NVM_DIR/nvm.sh" 2>/dev/null
        if command -v nvm &>/dev/null; then
            info "Using nvm to switch to Node $required_version..."
            nvm install "$required_version" 2>&1 | tail -5
            nvm use "$required_version" 2>&1 | tail -3
            ok "Switched to Node $(node --version 2>/dev/null)"
            return 0
        fi
    fi

    # Try fnm
    if command -v fnm &>/dev/null; then
        fnm install "$required_version" 2>&1 | tail -3
        eval "$(fnm env)" 2>/dev/null
        fnm use "$required_version" 2>&1 | tail -3
        ok "Switched to Node $(node --version 2>/dev/null)"
        return 0
    fi

    # Try apt with NodeSource
    if command -v apt-get &>/dev/null; then
        info "Installing Node $required_major via NodeSource..."
        curl -fsSL "https://deb.nodesource.com/setup_${required_major}.x" 2>/dev/null | sudo -E bash - 2>&1 | tail -5
        sudo apt-get install -y nodejs 2>&1 | tail -3
        [[ -n "$(command -v node 2>/dev/null)" ]] && { ok "Installed Node $(node --version)"; return 0; }
    fi

    warn "Could not auto-switch Node version."
    echo -e "    Install nvm: ${CYAN}curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash${NC}"
    echo -e "    Then: ${CYAN}nvm install $required_version && nvm use $required_version${NC}"
    return 1
}

# --------------------------------------------------------------------------
# Package Management (WSL/Linux: apt-based)
# --------------------------------------------------------------------------
ensure_pkg_manager() {
    local manager="$1"

    if command -v "$manager" &>/dev/null; then
        ok "$manager already installed ($($manager --version 2>/dev/null | head -1 || echo 'unknown'))"
        return 0
    fi

    info "$manager not found. Installing..."

    case "$manager" in
        yarn)
            if command -v corepack &>/dev/null; then
                corepack enable 2>/dev/null && corepack prepare yarn@stable --activate 2>/dev/null && {
                    ok "$manager enabled via corepack"; return 0; }
            fi
            if command -v npm &>/dev/null; then
                npm install -g yarn 2>&1 | tail -3 && command -v yarn &>/dev/null && {
                    ok "$manager installed via npm"; return 0; }
            fi
            sudo apt-get install -y -qq yarn 2>&1 | tail -3 && command -v yarn &>/dev/null && {
                ok "$manager installed via apt"; return 0; }
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
            ;;
        pip|pip3)
            python3 -m ensurepip --upgrade 2>/dev/null && {
                ok "pip bootstrapped via ensurepip"; return 0; }
            sudo apt-get install -y -qq python3-pip 2>&1 | tail -3 && {
                ok "pip installed via apt"; return 0; }
            ;;
        cargo)
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>&1 | tail -3 && {
                source "$HOME/.cargo/env" 2>/dev/null
                ok "cargo installed via rustup"; return 0; }
            ;;
        go)
            sudo apt-get install -y -qq golang-go 2>&1 | tail -3 && command -v go &>/dev/null && {
                ok "go installed via apt"; return 0; }
            ;;
        mvn|maven)
            sudo apt-get install -y -qq maven 2>&1 | tail -3 && command -v mvn &>/dev/null && {
                ok "maven installed via apt"; return 0; }
            ;;
        gradle)
            sudo apt-get install -y -qq gradle 2>&1 | tail -3 && command -v gradle &>/dev/null && {
                ok "gradle installed via apt"; return 0; }
            ;;
        bundler|bundle)
            if command -v gem &>/dev/null; then
                gem install bundler 2>&1 | tail -3 && {
                    ok "bundler installed via gem"; return 0; }
            fi
            ;;
        composer)
            if command -v php &>/dev/null; then
                curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer 2>/dev/null && {
                    ok "composer installed"; return 0; }
            fi
            ;;
        *)
            sudo apt-get install -y -qq "$manager" 2>&1 | tail -3 && command -v "$manager" &>/dev/null && {
                ok "$manager installed via apt"; return 0; }
            ;;
    esac

    if ! command -v "$manager" &>/dev/null; then
        warn "Could not install $manager automatically."
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

ensure_venv() {
    if [[ ! -d ".venv" ]]; then
        $PYTHON_CMD -m venv .venv || { warn "venv creation failed"; return 1; }
        ok "Created .venv (using $PYTHON_CMD)"
    fi
    source .venv/bin/activate || { warn "Could not activate venv"; return 1; }
    ok "Activated venv"
}

run_install() {
    local manager="$1"
    local repo_dir="$2"
    local install_cmd=""

    case "$manager" in
        bun)    install_cmd="bun install" ;;
        yarn)   install_cmd="yarn install --frozen-lockfile 2>/dev/null || yarn install" ;;
        pnpm)   install_cmd="pnpm install --frozen-lockfile 2>/dev/null || pnpm install" ;;
        npm)    install_cmd="npm ci 2>/dev/null || npm install" ;;
        cargo)  install_cmd="cargo build" ;;
        go)     install_cmd="go mod download" ;;
        bundler) install_cmd="bundle install" ;;
        composer) install_cmd="composer install" ;;
        pipenv) install_cmd="pipenv install --dev" ;;
        poetry) install_cmd="poetry install" ;;
        mix)    install_cmd="mix deps.get" ;;
        dart)   install_cmd="dart pub get" ;;
        swift)  install_cmd="swift build" ;;
        sbt)    install_cmd="sbt compile" ;;
        pip)
            if [[ -f "pyproject.toml" ]]; then
                install_cmd="pip install -e '.[dev]' 2>/dev/null || pip install -e '.[test]' 2>/dev/null || pip install -e '.[tests]' 2>/dev/null || pip install -e '.'"
            elif [[ -f "setup.py" ]]; then
                install_cmd="pip install -e '.[dev]' 2>/dev/null || pip install -e '.'"
            elif [[ -f "requirements.txt" ]]; then
                install_cmd="pip install -r requirements.txt"
                [[ -f "requirements-dev.txt" ]] && install_cmd="$install_cmd && pip install -r requirements-dev.txt"
                [[ -f "requirements-test.txt" ]] && install_cmd="$install_cmd && pip install -r requirements-test.txt"
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

    warn "Install failed."
    return 1
}

# --------------------------------------------------------------------------
# CLI commands: --help, --list, --clean, --clean-all
# --------------------------------------------------------------------------
show_help() {
    echo ""
    echo -e "${BOLD}MARLIN V3 — Phase 3 Setup (WSL)${NC}"
    echo ""
    echo "Usage:"
    echo -e "  ${CYAN}./marlin_setup.sh${NC}              Start a new task"
    echo -e "  ${CYAN}./marlin_setup.sh --list${NC}       List existing tasks"
    echo -e "  ${CYAN}./marlin_setup.sh --clean${NC}      Remove a task"
    echo -e "  ${CYAN}./marlin_setup.sh --clean-all${NC}  Remove ALL tasks"
    echo ""
    exit 0
}

list_tasks() {
    echo ""
    echo -e "${BOLD}Existing task workspaces:${NC}"
    echo ""
    if [[ ! -d "$WORKSPACE_ROOT" ]]; then
        echo "  (none)"; echo ""; exit 0
    fi
    local count=0
    for task_dir in "$WORKSPACE_ROOT"/task-*/; do
        [[ -d "$task_dir" ]] || continue
        count=$((count + 1))
        local name=$(basename "$task_dir")
        local size=$(du -sh "$task_dir" 2>/dev/null | cut -f1)
        echo -e "  ${CYAN}$name${NC}  ($size)"
    done
    [[ $count -eq 0 ]] && echo "  (none)"
    echo ""
    exit 0
}

clean_task() {
    echo -e "${BOLD}Clean task workspace${NC}"
    [[ ! -d "$WORKSPACE_ROOT" ]] && { echo "  No workspaces found."; exit 0; }
    local tasks=()
    for d in "$WORKSPACE_ROOT"/task-*/; do
        [[ -d "$d" ]] && tasks+=("$(basename "$d")")
    done
    [[ ${#tasks[@]} -eq 0 ]] && { echo "  No tasks to clean."; exit 0; }
    for i in "${!tasks[@]}"; do
        echo -e "    ${CYAN}$((i+1))${NC}) ${tasks[$i]}"
    done
    read -rp "  Choice: " num
    if [[ "$num" -ge 1 && "$num" -le ${#tasks[@]} ]] 2>/dev/null; then
        local target="${tasks[$((num-1))]}"
        read -rp "  Type '$target' to confirm: " confirm
        if [[ "$confirm" == "$target" ]]; then
            rm -rf "$WORKSPACE_ROOT/$target"
            ok "Removed: $target"
        fi
    fi
    exit 0
}

case "${1:-}" in
    --help|-h)    show_help ;;
    --list|-l)    list_tasks ;;
    --clean|-c)   clean_task ;;
    --clean-all)
        [[ -d "$WORKSPACE_ROOT" ]] && {
            read -rp "  Type 'DELETE ALL' to confirm: " confirm
            [[ "$confirm" == "DELETE ALL" ]] && rm -rf "$WORKSPACE_ROOT" && ok "All tasks removed."
        }
        exit 0
        ;;
esac

# ==========================================================================
# Welcome
# ==========================================================================
clear
echo -e "${BOLD}${CYAN}"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │   MARLIN V3 — PHASE 3 SETUP (WSL)           │"
echo "  │   Environment & CLI Configuration            │"
echo "  └─────────────────────────────────────────────┘"
echo -e "${NC}"
echo "  This script follows the Phase 3 steps from the"
echo "  Marlin V3 Master Guide (3.1 through 3.10)."
echo -e "  ${DIM}Platform: Windows / WSL${NC}"
echo ""

# Task name
read -rp "  Task name: " TASK_NAME
TASK_NAME=$(echo "$TASK_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-_')
[[ -z "$TASK_NAME" ]] && TASK_NAME="task-$(date +%Y%m%d-%H%M%S)"

TASK_DIR="$WORKSPACE_ROOT/task-$TASK_NAME"

if [[ -d "$TASK_DIR" ]]; then
    warn "Task workspace already exists: $TASK_DIR"
    echo -e "    ${CYAN}1${NC}) Resume  ${CYAN}2${NC}) Start fresh"
    read -rp "  Choice [1/2]: " rc
    [[ "$rc" == "2" ]] && rm -rf "$TASK_DIR" && ok "Cleaned."
fi

mkdir -p "$TASK_DIR"
ok "Task workspace: $TASK_DIR"

# Per-task CLAUDE.md storage (prevents cross-task contamination)
TASK_BRIDGE_DIR="$TASK_DIR/.task-bridge"
mkdir -p "$TASK_BRIDGE_DIR"

bridge_init
LIVE_JSON="$BRIDGE_DIR/live_bridge.json"
python3 "$SCRIPT_DIR/marlin_bridge.py" init-session --task "$TASK_NAME" 2>/dev/null || true
ok "Live bridge: $LIVE_JSON"
divider

REPO_DIR=""
LANG_DETECTED="unknown"
TEST_CMD=""
HEAD_COMMIT=""

# ==========================================================================
# STEP 3.1 — System Prerequisites
# ==========================================================================
step "3.1 — System Prerequisites"
echo "  Checking: Git, Python, VS Code CLI, tmux, Internet"
echo ""

PREREQ_OK=true

command -v git &>/dev/null && ok "Git: $(git --version 2>&1)" || { fail "Git: NOT INSTALLED (sudo apt install git)"; PREREQ_OK=false; }

if command -v python3 &>/dev/null; then
    ok "Python: $(python3 --version 2>&1)"
else
    fail "Python3: NOT INSTALLED (sudo apt install python3)"
    PREREQ_OK=false
fi

command -v code &>/dev/null && ok "VS Code CLI: $(code --version 2>&1 | head -1)" || warn "VS Code CLI: not in PATH (install WSL extension in VS Code)"
command -v tmux &>/dev/null && ok "tmux: $(tmux -V 2>&1)" || { fail "tmux: NOT INSTALLED (sudo apt install tmux)"; PREREQ_OK=false; }

if curl -s --max-time 5 https://github.com > /dev/null 2>&1; then
    ok "Internet: Connected"
else
    warn "Internet: Cannot reach github.com"
fi

[[ "$PREREQ_OK" == false ]] && {
    fail "Install missing prerequisites and re-run."
    echo -e "  ${CYAN}sudo apt install git python3 python3-venv tmux curl${NC}"
    exit 1
}

# ==========================================================================
# STEP 3.2 — VS Code CLI (via WSL integration)
# ==========================================================================
step "3.2 — VS Code to PATH"
if command -v code &>/dev/null; then
    ok "VS Code CLI in PATH. Skipping."
else
    warn "VS Code CLI not found."
    echo "  On Windows/WSL, VS Code is accessed via WSL integration:"
    echo "  1. Install VS Code on Windows"
    echo "  2. Install the 'WSL' extension (ms-vscode-remote.remote-wsl)"
    echo "  3. The 'code' command auto-appears in WSL"
    echo ""
    echo -e "  ${CYAN}Alternatively, add Cursor to PATH:${NC}"
    echo "  export PATH=\"/mnt/c/Users/<YourName>/AppData/Local/Programs/cursor/resources/app/bin:\$PATH\""
fi

# ==========================================================================
# STEP 3.3 — Install tmux
# ==========================================================================
step "3.3 — Install tmux"
if command -v tmux &>/dev/null; then
    ok "tmux already installed ($(tmux -V 2>&1)). Skipping."
else
    info "Installing tmux..."
    sudo apt-get install -y -qq tmux 2>&1 | tail -3
    command -v tmux &>/dev/null && ok "tmux installed: $(tmux -V)" || fail "tmux installation failed"
fi

# ==========================================================================
# STEP 3.4 — Download & Unpack Tarball + Initialize Git
# ==========================================================================
step "3.4 — Download Repository & Initialize Git"

EXISTING_REPO=$(find "$TASK_DIR" -mindepth 1 -maxdepth 1 -type d -not -name '.git' -not -name '.venv' -not -name '.task-bridge' 2>/dev/null | head -1)
if [[ -n "$EXISTING_REPO" && -d "$EXISTING_REPO/.git" ]]; then
    ok "Repo already unpacked (resuming)."
    REPO_DIR="$EXISTING_REPO"
    cd "$REPO_DIR"
    HEAD_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "N/A")
    echo -e "  HEAD commit: ${CYAN}$HEAD_COMMIT${NC}"
    wait_enter
else

echo "  Paste the tarball URL or PR URL to get the pre-PR repo state."
echo ""
echo -e "    ${CYAN}1${NC}) I have the tarball URL"
echo -e "    ${CYAN}2${NC}) I have the PR URL (will construct tarball from it)"
echo -e "    ${CYAN}3${NC}) Already unpacked"
echo ""
read -rp "  Choice [1/2/3]: " tarball_choice
echo ""

case $tarball_choice in
    1)
        read -rp "  Tarball URL: " TARBALL_URL
        TARBALL_FILE="$TASK_DIR/repo.tar.gz"
        info "Downloading..."
        curl -L --progress-bar -o "$TARBALL_FILE" "$TARBALL_URL"
        ok "Downloaded: $(du -h "$TARBALL_FILE" | cut -f1)"
        info "Unpacking..."
        tar -xzf "$TARBALL_FILE" -C "$TASK_DIR" 2>/dev/null || tar -xf "$TARBALL_FILE" -C "$TASK_DIR"
        REPO_DIR=$(find "$TASK_DIR" -mindepth 1 -maxdepth 1 -type d -not -name '.task-bridge' 2>/dev/null | head -1)
        ok "Unpacked to: $REPO_DIR"
        rm -f "$TARBALL_FILE" 2>/dev/null || true
        ;;
    2)
        if ! command -v gh &>/dev/null; then
            fail "gh CLI required. Install: https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
            exit 1
        fi
        read -rp "  PR URL: " PR_URL
        if [[ "$PR_URL" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
            PR_OWNER="${BASH_REMATCH[1]}"
            PR_REPO="${BASH_REMATCH[2]}"
            PR_NUMBER="${BASH_REMATCH[3]}"
            ok "Parsed: $PR_OWNER/$PR_REPO #$PR_NUMBER"
        else
            fail "Cannot parse PR URL."
            exit 1
        fi
        info "Fetching base commit..."
        BASE_COMMIT=$(gh pr view "$PR_NUMBER" --repo "$PR_OWNER/$PR_REPO" --json baseRefOid --jq '.baseRefOid' 2>/dev/null)
        [[ -z "$BASE_COMMIT" ]] && { fail "Could not fetch base commit. Run: gh auth login"; exit 1; }
        TARBALL_URL="https://github.com/$PR_OWNER/$PR_REPO/archive/$BASE_COMMIT.tar.gz"
        ok "Tarball URL constructed"
        TARBALL_FILE="$TASK_DIR/repo.tar.gz"
        curl -L --progress-bar -o "$TARBALL_FILE" "$TARBALL_URL"
        ok "Downloaded: $(du -h "$TARBALL_FILE" | cut -f1)"
        tar -xzf "$TARBALL_FILE" -C "$TASK_DIR" 2>/dev/null || tar -xf "$TARBALL_FILE" -C "$TASK_DIR"
        REPO_DIR=$(find "$TASK_DIR" -mindepth 1 -maxdepth 1 -type d -not -name '.task-bridge' 2>/dev/null | head -1)
        ok "Unpacked to: $REPO_DIR"
        rm -f "$TARBALL_FILE" 2>/dev/null || true
        ;;
    3)
        read -rp "  Path to repo directory: " REPO_DIR
        [[ ! -d "$REPO_DIR" ]] && { fail "Not found: $REPO_DIR"; exit 1; }
        ok "Using: $REPO_DIR"
        ;;
esac

cd "$REPO_DIR"
if [[ -d ".git" ]]; then
    warn "Git already initialized."
    HEAD_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "N/A")
else
    info "Initializing git..."
    git init -q && git add . && git commit -q -m "Initial commit"
    HEAD_COMMIT=$(git rev-parse HEAD)
    ok "Git initialized with initial commit"
fi

echo -e "  HEAD commit: ${CYAN}$HEAD_COMMIT${NC}"
echo ""
echo -e "  ${RED}${BOLD}WARNING: Do NOT run 'git commit' after this.${NC}"
wait_enter

fi  # end resume check

# ==========================================================================
# STEP 3.5 — Dev Environment (expanded language support)
# ==========================================================================
step "3.5 — Set Up Dev Environment"
echo "  Detecting language and installing dependencies."
echo ""

PYTHON_CMD="python3"

pick_python() {
    local py_ver
    py_ver=$($PYTHON_CMD --version 2>&1 | grep -oE '[0-9]+\.[0-9]+')
    local py_minor=$(echo "$py_ver" | cut -d. -f2)

    if [[ "${py_minor:-0}" -ge 13 ]]; then
        warn "Python $py_ver detected. Some repos need < 3.13."
        for v in python3.12 python3.11 python3.10; do
            if command -v "$v" &>/dev/null; then
                PYTHON_CMD="$v"
                ok "Auto-selected: $PYTHON_CMD ($($v --version 2>&1))"
                return
            fi
        done
        info "No Python < 3.13 found. Install: sudo apt install python3.12"
    fi
    ok "Using: $PYTHON_CMD ($($PYTHON_CMD --version 2>&1))"
}

# Language detection (17 languages)
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

# Monorepo detection
KNOWN_REPO=""
SUBPKG_PATH=""
INSTALL_OK=false

REPO_NAME_LOWER=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')
README_HEAD=""
[[ -f "README.md" ]] && README_HEAD=$(head -5 README.md 2>/dev/null | tr '[:upper:]' '[:lower:]')

if [[ -d "python_modules/dagster" && -d "examples/experimental" ]]; then
    KNOWN_REPO="dagster"
elif [[ -d "packages/react" && -d "packages/react-dom" ]]; then
    KNOWN_REPO="react"
elif [[ -d "src/transformers" && -f "setup.py" ]]; then
    KNOWN_REPO="transformers"
elif [[ -d "src/diffusers" && -f "setup.py" ]]; then
    KNOWN_REPO="diffusers"
elif [[ -d "libs/langchain" || -d "libs/core" ]] && echo "$README_HEAD" | grep -qi "langchain"; then
    KNOWN_REPO="langchain"
elif [[ -d "src/vs" && -f "product.json" ]]; then
    KNOWN_REPO="vscode"
elif [[ -d "src/prefect" ]]; then
    KNOWN_REPO="prefect"
elif [[ -f "x.py" && -d "compiler" && -d "library" ]]; then
    KNOWN_REPO="rust-lang"
# Generic monorepo detection
elif [[ -f "lerna.json" || -f "nx.json" || -f "turbo.json" || -f "pnpm-workspace.yaml" ]]; then
    KNOWN_REPO="node-monorepo"
fi

[[ -n "$KNOWN_REPO" ]] && ok "Recognized repo: ${BOLD}$KNOWN_REPO${NC}"

# Install dependencies based on language + repo
case "$KNOWN_REPO" in
    dagster)
        pick_python
        ensure_venv
        self_heal "Install dagster core" \
            "pip install -e \"python_modules/dagster[test]\"" \
            "dagster monorepo, Python=$($PYTHON_CMD --version 2>&1)"
        TEST_CMD="pytest"
        INSTALL_OK=true
        ;;
    vscode)
        ensure_node_version || true
        PKG_MGR=$(detect_pkg_manager)
        ensure_pkg_manager "$PKG_MGR" || true
        run_install "$PKG_MGR" "$(pwd)" && INSTALL_OK=true
        TEST_CMD="yarn test"
        ;;
    react|node-monorepo)
        PKG_MGR=$(detect_pkg_manager)
        ensure_pkg_manager "$PKG_MGR" || true
        run_install "$PKG_MGR" "$(pwd)" && INSTALL_OK=true
        TEST_CMD="${PKG_MGR} test"
        ;;
    transformers|diffusers|prefect)
        pick_python
        ensure_venv
        pip install -e ".[dev]" 2>&1 | tail -5 && INSTALL_OK=true || \
        pip install -e ".[test]" 2>&1 | tail -5 && INSTALL_OK=true || \
        pip install -e "." 2>&1 | tail -5 && INSTALL_OK=true
        TEST_CMD="pytest tests/"
        ;;
    langchain)
        pick_python
        ensure_venv
        echo "  Sub-packages: 1) core  2) langchain  3) community  4) other"
        read -rp "  Choice [1/2/3/4]: " lc_choice
        case "$lc_choice" in
            1) SUBPKG_PATH="libs/core" ;; 2) SUBPKG_PATH="libs/langchain" ;;
            3) SUBPKG_PATH="libs/community" ;; 4) read -rp "  Path: " SUBPKG_PATH ;;
        esac
        [[ -d "libs/core" && "$SUBPKG_PATH" != "libs/core" ]] && pip install -e "libs/core[test]" 2>&1 | tail -3
        [[ -n "$SUBPKG_PATH" && -d "$SUBPKG_PATH" ]] && pip install -e "$SUBPKG_PATH[test]" 2>/dev/null || true
        TEST_CMD="pytest ${SUBPKG_PATH}/tests"
        INSTALL_OK=true
        ;;
    rust-lang)
        info "Rust compiler repo. Uses x.py build system."
        python3 x.py check 2>&1 | tail -10 && INSTALL_OK=true
        TEST_CMD="python3 x.py test"
        ;;
    *)
        # Generic install for all languages
        case $LANG_DETECTED in
            python)
                pick_python
                PKG_MGR=$(detect_pkg_manager)
                case "$PKG_MGR" in
                    poetry)  ensure_pkg_manager "poetry" && poetry install 2>&1 | tail -10 && INSTALL_OK=true ;;
                    pipenv)  ensure_pkg_manager "pipenv" && pipenv install --dev 2>&1 | tail -10 && INSTALL_OK=true ;;
                    *)
                        ensure_venv
                        run_install "$PKG_MGR" "$(pwd)" && INSTALL_OK=true
                        ;;
                esac
                command -v pytest &>/dev/null && TEST_CMD="pytest" || [[ -f "tox.ini" ]] && TEST_CMD="tox"
                ;;
            node)
                ensure_node_version || true
                PKG_MGR=$(detect_pkg_manager)
                ensure_pkg_manager "$PKG_MGR" && run_install "$PKG_MGR" "$(pwd)" && INSTALL_OK=true
                [[ -f "package.json" ]] && grep -q '"test"' package.json 2>/dev/null && TEST_CMD="${PKG_MGR} test"
                ;;
            go)     ensure_pkg_manager "go" && go mod download 2>/dev/null && INSTALL_OK=true; TEST_CMD="go test ./..." ;;
            rust)   ensure_pkg_manager "cargo" && cargo build 2>/dev/null && INSTALL_OK=true; TEST_CMD="cargo test" ;;
            ruby)   ensure_pkg_manager "bundler" && bundle install 2>&1 | tail -5 && INSTALL_OK=true; TEST_CMD="bundle exec rspec" ;;
            php)    ensure_pkg_manager "composer" && composer install 2>&1 | tail -5 && INSTALL_OK=true; TEST_CMD="vendor/bin/phpunit" ;;
            java)
                if [[ -f "pom.xml" ]]; then
                    ensure_pkg_manager "mvn" && mvn compile -q 2>/dev/null && INSTALL_OK=true; TEST_CMD="mvn test"
                elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
                    ensure_pkg_manager "gradle" && gradle build -q 2>/dev/null && INSTALL_OK=true; TEST_CMD="gradle test"
                fi
                ;;
            scala)  ensure_pkg_manager "sbt" && sbt compile 2>&1 | tail -10 && INSTALL_OK=true; TEST_CMD="sbt test" ;;
            swift)  swift build 2>&1 | tail -5 && INSTALL_OK=true; TEST_CMD="swift test" ;;
            dart)   command -v dart &>/dev/null && dart pub get 2>&1 | tail -5 && INSTALL_OK=true; TEST_CMD="dart test" ;;
            elixir) command -v mix &>/dev/null && mix deps.get 2>&1 | tail -5 && INSTALL_OK=true; TEST_CMD="mix test" ;;
            dotnet) command -v dotnet &>/dev/null && dotnet restore 2>&1 | tail -5 && INSTALL_OK=true; TEST_CMD="dotnet test" ;;
            cpp)
                if [[ -f "CMakeLists.txt" ]]; then
                    cmake -B build 2>&1 | tail -5 && cmake --build build 2>&1 | tail -5 && INSTALL_OK=true
                    TEST_CMD="cd build && ctest"
                elif [[ -f "Makefile" ]]; then
                    make 2>&1 | tail -5 && INSTALL_OK=true
                    TEST_CMD="make test"
                fi
                ;;
            zig)    command -v zig &>/dev/null && zig build 2>&1 | tail -5 && INSTALL_OK=true; TEST_CMD="zig build test" ;;
            *)      warn "Could not auto-detect language." ;;
        esac
        ;;
esac

# Fallback if install failed
if [[ "$INSTALL_OK" != true ]]; then
    warn "Dependency install failed."
    echo -e "    ${CYAN}1${NC}) Sub-package path  ${CYAN}2${NC}) GitHub URL lookup  ${CYAN}3${NC}) Skip"
    read -rp "  Choice [1/2/3]: " fb
    case "$fb" in
        1)
            read -rp "  Sub-package path: " SUBPKG_PATH
            [[ -d "$SUBPKG_PATH" ]] && {
                cd "$SUBPKG_PATH"
                PKG_MGR=$(detect_pkg_manager)
                run_install "$PKG_MGR" "$(pwd)" || true
                cd "$REPO_DIR"
            }
            ;;
        3) info "Skipping. Install manually before running the CLI." ;;
    esac
fi

# Run baseline tests
TESTS_PASSED=false
if [[ -n "$TEST_CMD" ]]; then
    ask "Run baseline tests? ($TEST_CMD)"
    if wait_confirm "Run tests now?"; then
        info "Running: $TEST_CMD"
        divider
        TEST_OUTPUT=$(eval "$TEST_CMD" 2>&1 || true)
        echo "$TEST_OUTPUT" | tail -30
        echo "$TEST_OUTPUT" | tail -5 | grep -qiE "passed|ok|success" && TESTS_PASSED=true
        [[ "$TESTS_PASSED" == true ]] && ok "Baseline tests passed." || warn "Some tests may have failed."
        divider
    fi
fi

# ==========================================================================
# STEP 3.7 — Authenticate with Anthropic
# ==========================================================================
step "3.7 — Authenticate with Anthropic"

AUTH_DETECTED=false
# Guard find commands with || true to prevent ERR trap
HFI_TEMP_COUNT=$(find /tmp/claude-hfi 2>/dev/null -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || echo "0")
HFI_HOME_DIR=""
[[ -d "$HOME/.claude" ]] && HFI_HOME_DIR="$HOME/.claude"
[[ -d "$HOME/.config/claude-hfi" ]] && HFI_HOME_DIR="$HOME/.config/claude-hfi"

if [[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    AUTH_DETECTED=true; ok "ANTHROPIC_AUTH_TOKEN set."
elif [[ "${HFI_TEMP_COUNT:-0}" -gt 1 ]]; then
    AUTH_DETECTED=true; ok "HFI session history found."
elif [[ -n "$HFI_HOME_DIR" ]]; then
    AUTH_DETECTED=true; ok "Auth config directory found."
fi

if [[ "$AUTH_DETECTED" == true ]]; then
    ok "Skipping authentication."
else
    echo "  Open this URL in your browser:"
    echo -e "    ${CYAN}https://feedback.anthropic.com/claude_code?email_login=true${NC}"
    echo ""
    echo "  Login with your ${BOLD}Alias email${NC} (NOT Google sign-in)."
    echo ""
    wsl_open_url "https://feedback.anthropic.com/claude_code?email_login=true" 2>/dev/null || true
    ask "Complete authentication, then press Enter."
    wait_enter
fi

# ==========================================================================
# STEP 3.8 — CLI Binary
# ==========================================================================
step "3.8 — Download & Install CLI Binary"

MARLIN_TOOLS_DIR="$HOME/marlin-tools"

# Detect Windows username for path resolution
WIN_USER=""
if command -v cmd.exe &>/dev/null; then
    WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || true)
fi
if [[ -z "$WIN_USER" ]]; then
    # Fallback: scan /mnt/c/Users for directories
    for d in /mnt/c/Users/*/; do
        local uname=$(basename "$d")
        [[ "$uname" != "Public" && "$uname" != "Default" && "$uname" != "Default User" && "$uname" != "All Users" ]] && {
            WIN_USER="$uname"; break; }
    done
fi

WIN_DOWNLOADS=""
[[ -n "$WIN_USER" ]] && WIN_DOWNLOADS="/mnt/c/Users/$WIN_USER/Downloads"

if [[ -f "claude-hfi" && -x "claude-hfi" ]]; then
    ok "CLI binary exists: ./claude-hfi"
elif [[ -f "$MARLIN_TOOLS_DIR/claude-hfi" && -x "$MARLIN_TOOLS_DIR/claude-hfi" ]]; then
    cp "$MARLIN_TOOLS_DIR/claude-hfi" "$(pwd)/claude-hfi"
    chmod +x claude-hfi
    ok "Copied from cache: ~/marlin-tools/claude-hfi"
else
    ARCH=$(uname -m)
    RECOMMENDED="linux-amd64"
    [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && RECOMMENDED="linux-arm64"

    echo ""
    echo "  Download the CLI binary for: ${BOLD}$RECOMMENDED${NC}"
    echo ""
    echo -e "  ${BOLD}WSL path note:${NC}"
    echo "  Your Windows Downloads folder is accessible at:"
    if [[ -n "$WIN_DOWNLOADS" ]]; then
        echo -e "    ${CYAN}$WIN_DOWNLOADS${NC}"
    else
        echo -e "    ${CYAN}/mnt/c/Users/<YourWindowsUsername>/Downloads${NC}"
    fi
    echo ""
    echo "  After downloading in your browser, press Enter."
    wait_enter

    # Search for binary in all possible locations
    FOUND=""
    SEARCH_PATHS=(
        # WSL home Downloads
        "$HOME/Downloads/linux-amd64"
        "$HOME/Downloads/linux-arm64"
        "$HOME/Downloads/claude-hfi"
        # Current directory
        "./linux-amd64"
        "./linux-arm64"
    )

    # Add Windows Downloads paths
    if [[ -n "$WIN_DOWNLOADS" && -d "$WIN_DOWNLOADS" ]]; then
        SEARCH_PATHS+=(
            "$WIN_DOWNLOADS/linux-amd64"
            "$WIN_DOWNLOADS/linux-arm64"
            "$WIN_DOWNLOADS/claude-hfi"
            "$WIN_DOWNLOADS/linux-amd64.exe"
            "$WIN_DOWNLOADS/linux-arm64.exe"
        )
    fi

    # Also scan all Windows user Downloads as fallback
    for win_dl in /mnt/c/Users/*/Downloads; do
        [[ -d "$win_dl" ]] && SEARCH_PATHS+=(
            "$win_dl/linux-amd64"
            "$win_dl/linux-arm64"
            "$win_dl/claude-hfi"
        )
    done

    # Also check Desktop (some people save there)
    if [[ -n "$WIN_USER" ]]; then
        SEARCH_PATHS+=(
            "/mnt/c/Users/$WIN_USER/Desktop/linux-amd64"
            "/mnt/c/Users/$WIN_USER/Desktop/linux-arm64"
            "/mnt/c/Users/$WIN_USER/Desktop/claude-hfi"
        )
    fi

    for f in "${SEARCH_PATHS[@]}"; do
        if [[ -f "$f" ]]; then
            FOUND="$f"
            ok "Found binary at: $f"
            break
        fi
    done

    if [[ -n "$FOUND" ]]; then
        cp "$FOUND" "$(pwd)/claude-hfi"
        chmod +x claude-hfi
        ok "Installed: ./claude-hfi"
        mkdir -p "$MARLIN_TOOLS_DIR"
        cp claude-hfi "$MARLIN_TOOLS_DIR/claude-hfi"
        chmod +x "$MARLIN_TOOLS_DIR/claude-hfi"
        ok "Cached at ~/marlin-tools/"
    else
        warn "Binary not found automatically."
        echo ""
        echo "  Searched in:"
        [[ -n "$WIN_DOWNLOADS" ]] && echo -e "    ${DIM}$WIN_DOWNLOADS${NC}"
        echo -e "    ${DIM}$HOME/Downloads${NC}"
        echo -e "    ${DIM}/mnt/c/Users/*/Downloads${NC}"
        echo ""
        echo "  Option 1 — paste the full path to the binary:"
        read -rp "    Path (or press Enter to skip): " MANUAL_PATH
        if [[ -n "$MANUAL_PATH" && -f "$MANUAL_PATH" ]]; then
            cp "$MANUAL_PATH" "$(pwd)/claude-hfi"
            chmod +x claude-hfi
            ok "Installed from: $MANUAL_PATH"
            mkdir -p "$MARLIN_TOOLS_DIR"
            cp claude-hfi "$MARLIN_TOOLS_DIR/claude-hfi"
            chmod +x "$MARLIN_TOOLS_DIR/claude-hfi"
        else
            echo ""
            echo "  Option 2 — copy it manually:"
            echo -e "    ${CYAN}cp /mnt/c/Users/$WIN_USER/Downloads/$RECOMMENDED ./claude-hfi${NC}"
            echo -e "    ${CYAN}chmod +x claude-hfi${NC}"
        fi
    fi
fi

# ==========================================================================
# STEP 3.9 — Launch CLI
# ==========================================================================
if [[ "${INSTALL_OK:-false}" != true ]]; then
    echo ""
    echo -e "  ${RED}${BOLD}WARNING: Dev environment NOT set up. Model can't run tests.${NC}"
    echo -e "    ${CYAN}1${NC}) Continue anyway  ${CYAN}2${NC}) Abort"
    read -rp "  Choice [1/2]: " dep_gate
    [[ "$dep_gate" == "2" ]] && exit 1
fi

step "3.9 — Launch the CLI"

INTERFACE_CODE="cc_agentic_coding_next"
HFI_REPO_DIR="$(pwd)"
unset ANTHROPIC_API_KEY 2>/dev/null || true

wsl_copy "$INTERFACE_CODE" && ok "Interface code copied to clipboard: $INTERFACE_CODE" || info "Interface code: $INTERFACE_CODE"

HFI_LAUNCHED=false

# Try Windows Terminal first, then a new WSL terminal
LAUNCH_CMD="cd '$HFI_REPO_DIR' && unset ANTHROPIC_API_KEY 2>/dev/null; echo 'Interface code: $INTERFACE_CODE'; ./claude-hfi --vscode"

if wsl_open_terminal "$LAUNCH_CMD" 2>/dev/null; then
    HFI_LAUNCHED=true
    ok "HFI launched in new terminal window."
fi

if [[ "$HFI_LAUNCHED" == false ]]; then
    echo "  Launch the CLI manually in a new terminal:"
    echo -e "    ${CYAN}cd $HFI_REPO_DIR${NC}"
    echo -e "    ${CYAN}./claude-hfi --vscode${NC}"
    echo ""
    echo -e "  Interface code: ${BOLD}$INTERFACE_CODE${NC}"
fi

# Poll for tmux sessions
info "Waiting for HFI tmux sessions..."
HFI_READY=false
HFI_WAIT=0
while [[ $HFI_WAIT -lt 120 ]]; do
    TMUX_CHECK=$(tmux ls 2>/dev/null || true)
    if [[ -n "$TMUX_CHECK" ]]; then
        HFI_READY=true; ok "HFI tmux sessions detected."; break
    fi
    sleep 3; HFI_WAIT=$((HFI_WAIT + 3))
    printf "\r  ⟳ Waiting... (%ds / 120s)  " "$HFI_WAIT"
done
echo ""

# ==========================================================================
# STEP 3.6 — CLAUDE.md (after HFI launch, per-task scoped)
# ==========================================================================
step "3.6 — CLAUDE.md (V3 Requirement)"

CLAUDE_TARGET="CLAUDE.md"
CLAUDE_DRAFT_FILE="$TASK_BRIDGE_DIR/CLAUDE_md_content.txt"  # Per-task, not shared!
CLAUDE_EXISTS=false

if [[ -f "CLAUDE.md" ]]; then
    CLAUDE_EXISTS=true
    ok "CLAUDE.md already exists."
    # Validate sections
    MISSING_SECTIONS=()
    grep -qi "repository overview\|## overview" CLAUDE.md 2>/dev/null || MISSING_SECTIONS+=("Repository Overview")
    grep -qi "dev setup\|## setup\|## install" CLAUDE.md 2>/dev/null || MISSING_SECTIONS+=("Dev Setup")
    grep -qi "testing\|## test" CLAUDE.md 2>/dev/null || MISSING_SECTIONS+=("Testing")
    grep -qi "conventions\|## code style" CLAUDE.md 2>/dev/null || MISSING_SECTIONS+=("Code Conventions")
    grep -qi "architecture\|## structure" CLAUDE.md 2>/dev/null || MISSING_SECTIONS+=("Architecture")

    if [[ ${#MISSING_SECTIONS[@]} -eq 0 ]]; then
        ok "All sections present."
    else
        warn "Missing sections: ${MISSING_SECTIONS[*]}"
        ask "Regenerate? [y/n]"
        wait_confirm "Regenerate CLAUDE.md?" && CLAUDE_EXISTS=false
    fi
fi

if [[ "$CLAUDE_EXISTS" == false ]]; then
    info "Generating CLAUDE.md via Cursor bridge..."
    python3 "$SCRIPT_DIR/marlin_bridge.py" repo-context --path "$(pwd)" > "$TASK_BRIDGE_DIR/repo_context.json" 2>/dev/null || true

    python3 -c "
import json
try:
    with open('$LIVE_JSON', 'r') as f:
        data = json.load(f)
except: data = {}
data['action'] = 'generate_claude_md'
data['action_request'] = {
    'repo_context_path': '$TASK_BRIDGE_DIR/repo_context.json',
    'output_path': '$(pwd)/CLAUDE.md',
    'draft_path': '$CLAUDE_DRAFT_FILE',
    'repo_path': '$(pwd)',
    'status': 'pending'
}
data['status'] = 'waiting_for_cursor'
with open('$LIVE_JSON', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

    echo -e "  ${YELLOW}Switch to Cursor and send a message to trigger generation.${NC}"

    CLAUDE_WAIT=0
    while [[ $CLAUDE_WAIT -lt 180 ]]; do
        if [[ -f "$CLAUDE_TARGET" && $(wc -c < "$CLAUDE_TARGET" 2>/dev/null || echo 0) -gt 50 ]]; then
            ok "CLAUDE.md generated."; break
        fi
        sleep 3; CLAUDE_WAIT=$((CLAUDE_WAIT + 3))
        printf "\r  ⟳ Waiting for CLAUDE.md... (%ds / 180s)  " "$CLAUDE_WAIT"
    done
    echo ""

    # Quick-scan fallback
    if [[ ! -f "$CLAUDE_TARGET" || $(wc -c < "$CLAUDE_TARGET" 2>/dev/null || echo 0) -lt 50 ]]; then
        warn "Cursor didn't generate in time. Using quick-scan fallback."
        QS_NAME=$(basename "$(pwd)")
        QS_INSTALL="[Fill in install command]"
        case ${LANG_DETECTED:-unknown} in
            python) QS_INSTALL="python -m venv .venv && source .venv/bin/activate && pip install -e '.[dev]'" ;;
            node)   QS_INSTALL="npm install" ;;
            go)     QS_INSTALL="go mod download" ;;
            rust)   QS_INSTALL="cargo build" ;;
            ruby)   QS_INSTALL="bundle install" ;;
            php)    QS_INSTALL="composer install" ;;
        esac
        {
            echo "# CLAUDE.md"
            echo ""
            echo "## Repository Overview"
            echo "$QS_NAME — ${LANG_DETECTED:-unknown} project"
            echo ""
            echo "## Dev Setup"
            echo '```bash'
            echo "$QS_INSTALL"
            echo '```'
            echo ""
            echo "## Testing"
            echo '```bash'
            echo "${TEST_CMD:-[Fill in test command]}"
            echo '```'
            echo ""
            echo "## Code Conventions"
            echo "[Describe naming, style, error handling patterns]"
            echo ""
            echo "## Architecture"
            echo "[Describe key modules and how they interact]"
        } > "$CLAUDE_TARGET"
        ok "Generated quick-scan CLAUDE.md"
    fi
fi

[[ -f "$CLAUDE_TARGET" ]] && {
    echo ""; echo -e "  ${BOLD}Contents:${NC}"; divider
    sed 's/^/  /' "$CLAUDE_TARGET" || true
    divider
}

# Copy CLAUDE.md to worktrees
if [[ -f "CLAUDE.md" ]]; then
    while IFS= read -r wt_line; do
        wt_path=$(echo "$wt_line" | awk '{print $1}')
        [[ -n "$wt_path" && "$wt_path" != "$(pwd)" && -d "$wt_path" ]] && \
            cp CLAUDE.md "$wt_path/CLAUDE.md" 2>/dev/null && ok "Copied CLAUDE.md to worktree: $(basename "$wt_path")"
    done < <(git worktree list 2>/dev/null)
fi

wait_enter

# ==========================================================================
# STEP 3.10 — Attach tmux
# ==========================================================================
step "3.10 — Attach to tmux Sessions"

TMUX_SESSIONS=$(tmux ls 2>/dev/null || true)
if [[ -n "$TMUX_SESSIONS" ]]; then
    SESSION_A=$(echo "$TMUX_SESSIONS" | grep -oE '^[^:]+' | grep -E '[-_]A$' | head -1)
    SESSION_B=$(echo "$TMUX_SESSIONS" | grep -oE '^[^:]+' | grep -E '[-_]B$' | head -1)

    if [[ -n "$SESSION_A" && -n "$SESSION_B" ]]; then
        ok "Found HFI sessions:"
        echo -e "    Trajectory A: ${CYAN}tmux attach -t $SESSION_A${NC}"
        echo -e "    Trajectory B: ${CYAN}tmux attach -t $SESSION_B${NC}"
        echo ""
        echo "  Open VS Code terminal (Ctrl+\`) in each window and paste."
        wsl_copy "tmux attach -t $SESSION_A" && ok "Trajectory A command copied to clipboard."
        wait_enter
        wsl_copy "tmux attach -t $SESSION_B" && ok "Trajectory B command copied to clipboard."
    else
        echo "$TMUX_SESSIONS" | while IFS= read -r line; do echo -e "    ${CYAN}$line${NC}"; done
    fi
else
    warn "No tmux sessions yet. Check: tmux ls"
fi

# ==========================================================================
# Pre-Thread Survey
# ==========================================================================
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │   PRE-THREAD SURVEY ANSWERS                  │"
echo "  └─────────────────────────────────────────────┘"
echo -e "${NC}"

SURVEY_OS="WSL ($(uname -s) $(uname -m))"
SURVEY_PY=$(python3 --version 2>&1 || echo "N/A")

echo -e "  Initial commit hash:  ${CYAN}${HEAD_COMMIT:-N/A}${NC}"
echo -e "  Workspace path:       ${CYAN}$(pwd)${NC}"
echo -e "  Operating system:     ${CYAN}$SURVEY_OS${NC}"
echo -e "  Python version:       ${CYAN}$SURVEY_PY${NC}"
echo -e "  Task type:            ${CYAN}agentic_coding${NC}"
echo -e "  Interface code:       ${CYAN}$INTERFACE_CODE${NC}"
echo -e "  Language:             ${CYAN}${LANG_DETECTED:-unknown}${NC}"
echo -e "  Test command:         ${CYAN}${TEST_CMD:-N/A}${NC}"

{
    echo "PRE-THREAD SURVEY ANSWERS"
    echo "========================"
    echo "Initial commit hash:  ${HEAD_COMMIT:-N/A}"
    echo "Workspace path:       $(pwd)"
    echo "Operating system:     $SURVEY_OS"
    echo "Python version:       $SURVEY_PY"
    echo "Task type:            agentic_coding"
    echo "Interface code:       $INTERFACE_CODE"
    echo "Language:             ${LANG_DETECTED:-unknown}"
    echo "Test command:         ${TEST_CMD:-N/A}"
} > "$BRIDGE_DIR/survey_answers.txt" 2>/dev/null || true

wsl_copy "${HEAD_COMMIT:-N/A}" && ok "Commit hash copied to clipboard."

# ==========================================================================
# Summary
# ==========================================================================
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │   SETUP COMPLETE — SUMMARY                  │"
echo "  └─────────────────────────────────────────────┘"
echo -e "${NC}"

echo "    ✓ System prerequisites checked"
echo "    ✓ Repository downloaded and unpacked"
echo "    ✓ Git initialized (initial commit only)"

if [[ "${INSTALL_OK:-false}" == true ]]; then
    echo -e "    ${GREEN}✓${NC} Dependencies installed ($LANG_DETECTED)"
else
    echo -e "    ${RED}✗ Dependencies NOT installed${NC}"
    echo -e "      ${YELLOW}⚠ Fix before pasting prompt!${NC}"
fi

if [[ "${TESTS_PASSED:-false}" == true ]]; then
    echo -e "    ${GREEN}✓${NC} Baseline tests passed"
elif [[ -n "${TEST_CMD:-}" ]]; then
    echo -e "    ${YELLOW}⚠${NC} Tests ran but may have failed"
fi

[[ -f "CLAUDE.md" ]] && echo "    ✓ CLAUDE.md in place"
[[ -f "claude-hfi" ]] && echo "    ✓ CLI binary installed"
echo "    ✓ Pre-thread survey prepared"

echo ""
echo -e "  ${RED}${BOLD}REMINDER: Never run 'git commit' after this point.${NC}"
echo ""
divider
