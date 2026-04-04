#!/usr/bin/env bash
# ==========================================================================
# MARLIN V3 — WSL PREREQUISITES INSTALLER
# ==========================================================================
# Installs and configures all tools needed for Marlin V3 on Windows/WSL.
# Run this ONCE before using any Phase 1/2/3 scripts.
#
# Usage:  bash setup_wsl.sh
# ==========================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
info() { echo -e "  ${CYAN}ℹ${NC} $1"; }

echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║   MARLIN V3 — WSL PREREQUISITES SETUP                   ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Verify we are in WSL
if ! grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
    warn "This does not appear to be WSL."
    echo "  This script is designed for Windows Subsystem for Linux."
    echo "  For macOS/Linux, use the standard scripts directly."
    echo ""
    read -rp "  Continue anyway? [y/n]: " cont
    [[ "$cont" =~ ^[Yy] ]] || exit 0
fi

echo -e "  ${BOLD}Installing prerequisites...${NC}"
echo ""

NEED_APT_UPDATE=false
MISSING=()

# --------------------------------------------------------------------------
# 1. Git
# --------------------------------------------------------------------------
if command -v git &>/dev/null; then
    ok "Git: $(git --version 2>&1)"
else
    MISSING+=("git")
    NEED_APT_UPDATE=true
fi

# --------------------------------------------------------------------------
# 2. Python 3
# --------------------------------------------------------------------------
if command -v python3 &>/dev/null; then
    ok "Python3: $(python3 --version 2>&1)"

    PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.minor}')" 2>/dev/null)
    if [[ "${PY_VER:-0}" -ge 13 ]]; then
        warn "Python 3.13+ detected. Some repos require Python < 3.13."
        if command -v python3.12 &>/dev/null; then
            ok "python3.12 also available (will auto-select when needed)."
        else
            info "Consider: sudo apt install python3.12"
        fi
    fi
else
    MISSING+=("python3" "python3-pip" "python3-venv")
    NEED_APT_UPDATE=true
fi

# --------------------------------------------------------------------------
# 3. tmux
# --------------------------------------------------------------------------
if command -v tmux &>/dev/null; then
    ok "tmux: $(tmux -V 2>&1)"
else
    MISSING+=("tmux")
    NEED_APT_UPDATE=true
fi

# --------------------------------------------------------------------------
# 4. curl / wget
# --------------------------------------------------------------------------
if command -v curl &>/dev/null; then
    ok "curl: available"
else
    MISSING+=("curl")
    NEED_APT_UPDATE=true
fi

# --------------------------------------------------------------------------
# 5. GitHub CLI (gh)
# --------------------------------------------------------------------------
if command -v gh &>/dev/null; then
    ok "gh CLI: $(gh --version 2>&1 | head -1)"
    if gh auth status &>/dev/null; then
        ok "gh CLI: authenticated"
    else
        warn "gh CLI: NOT authenticated — run: gh auth login"
    fi
else
    warn "gh CLI: not installed"
    info "Will install via apt..."
    NEED_APT_UPDATE=true
fi

# --------------------------------------------------------------------------
# 6. VS Code (code command via WSL integration)
# --------------------------------------------------------------------------
if command -v code &>/dev/null; then
    ok "VS Code CLI: $(code --version 2>&1 | head -1)"
else
    warn "VS Code CLI: not found in PATH"
    echo "    Install VS Code on Windows and enable WSL integration:"
    echo "    1. Install VS Code from https://code.visualstudio.com/"
    echo "    2. Install the 'WSL' extension in VS Code"
    echo "    3. The 'code' command will then be available in WSL"
fi

# --------------------------------------------------------------------------
# 7. Windows clipboard tools
# --------------------------------------------------------------------------
if command -v clip.exe &>/dev/null; then
    ok "clip.exe: available (Windows clipboard write)"
else
    warn "clip.exe: not found. Clipboard copy may not work."
fi

if command -v powershell.exe &>/dev/null; then
    ok "powershell.exe: available (Windows clipboard read)"
else
    warn "powershell.exe: not found. Clipboard paste may not work."
fi

# --------------------------------------------------------------------------
# 8. wslview (open URLs in Windows browser)
# --------------------------------------------------------------------------
if command -v wslview &>/dev/null; then
    ok "wslview: available (opens Windows browser)"
else
    warn "wslview: not found"
    info "Install: sudo apt install wslu"
    MISSING+=("wslu")
    NEED_APT_UPDATE=true
fi

# --------------------------------------------------------------------------
# 9. xclip (Linux-side clipboard fallback)
# --------------------------------------------------------------------------
if command -v xclip &>/dev/null; then
    ok "xclip: available"
else
    MISSING+=("xclip")
    NEED_APT_UPDATE=true
fi

# --------------------------------------------------------------------------
# Install missing packages
# --------------------------------------------------------------------------
echo ""

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "  ${BOLD}Installing missing packages: ${MISSING[*]}${NC}"
    echo ""

    if [[ "$NEED_APT_UPDATE" == true ]]; then
        info "Running apt update..."
        sudo apt-get update -qq 2>&1 | tail -3
    fi

    for pkg in "${MISSING[@]}"; do
        info "Installing $pkg..."
        sudo apt-get install -y -qq "$pkg" 2>&1 | tail -2
        if command -v "$pkg" &>/dev/null 2>/dev/null || dpkg -l "$pkg" &>/dev/null 2>/dev/null; then
            ok "$pkg installed"
        else
            warn "$pkg may not have installed correctly"
        fi
    done

    # gh CLI needs special repo
    if ! command -v gh &>/dev/null; then
        info "Installing GitHub CLI from official repo..."
        (
            type -p curl >/dev/null || sudo apt install curl -y
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
            sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
            sudo apt update -qq 2>/dev/null
            sudo apt install gh -y -qq 2>&1 | tail -2
        )
        if command -v gh &>/dev/null; then
            ok "gh CLI installed"
            echo ""
            info "Authenticate now: gh auth login"
        else
            warn "gh CLI installation failed. Install manually:"
            echo "    https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
        fi
    fi
fi

# --------------------------------------------------------------------------
# Node.js / yarn / npm (common deps for many repos)
# --------------------------------------------------------------------------
echo ""
echo -e "  ${BOLD}Optional tools (for Node.js repos):${NC}"
echo ""

if command -v node &>/dev/null; then
    ok "Node.js: $(node --version 2>&1)"
else
    warn "Node.js: not installed"
    info "Install: curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt install -y nodejs"
fi

if command -v yarn &>/dev/null; then
    ok "yarn: $(yarn --version 2>&1)"
elif command -v npm &>/dev/null; then
    ok "npm: $(npm --version 2>&1)"
    info "yarn not installed. Install if needed: npm install -g yarn"
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo -e "  ${DIM}──────────────────────────────────────────────────────${NC}"
echo ""
echo -e "  ${BOLD}${GREEN}WSL Setup Complete${NC}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "    1. If gh is not authenticated: ${CYAN}gh auth login${NC}"
echo -e "    2. Start Marlin automation:    ${CYAN}bash ../marlin.sh --os wsl${NC}"
echo ""
echo -e "  ${BOLD}Key WSL differences from macOS:${NC}"
echo -e "    • Clipboard: ${CYAN}clip.exe${NC} (write) / ${CYAN}powershell.exe Get-Clipboard${NC} (read)"
echo -e "    • Browser:   ${CYAN}wslview${NC} or ${CYAN}cmd.exe /c start${NC}"
echo -e "    • Packages:  ${CYAN}apt${NC} instead of ${CYAN}brew${NC}"
echo -e "    • No macOS EPERM issue — Cursor terminal works normally"
echo -e "    • HFI binary: use ${CYAN}linux-amd64${NC} or ${CYAN}linux-arm64${NC} build"
echo ""
