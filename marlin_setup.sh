#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# MARLIN V3 — AUTOMATED ENVIRONMENT SETUP
# ============================================================================
# Usage:  ./marlin_setup.sh <tarball-path> [cli-binary-path]
#
# Example:
#   ./marlin_setup.sh ~/Downloads/repo-snapshot.tar ~/Downloads/darwin-arm64
#
# What this does:
#   1. Verifies system prerequisites (git, code, tmux, python)
#   2. Unpacks the tarball
#   3. Initializes git with a single "Initial commit"
#   4. Detects the project language and installs dependencies
#   5. Runs baseline tests (if detectable)
#   6. Moves the CLI binary into the repo root
#   7. Generates a starter CLAUDE.md if one doesn't exist
#   8. Prints a ready-to-go summary
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# ── Arg parsing ──────────────────────────────────────────────────────────────
TARBALL="${1:-}"
CLI_BIN="${2:-}"

if [[ -z "$TARBALL" ]]; then
  echo "Usage: $0 <tarball-path> [cli-binary-path]"
  exit 1
fi

[[ -f "$TARBALL" ]] || fail "Tarball not found: $TARBALL"

# ── 1. Prerequisites ────────────────────────────────────────────────────────
info "Checking prerequisites..."

command -v git  >/dev/null 2>&1 || fail "git is not installed"
ok "git found: $(git --version)"

command -v code >/dev/null 2>&1 || fail "VS Code 'code' command not in PATH. Open VS Code → Cmd+Shift+P → 'Shell Command: Install code command in PATH'"
ok "VS Code CLI found: $(code --version | head -1)"

command -v tmux >/dev/null 2>&1 || fail "tmux is not installed. Run: brew install tmux (macOS) or sudo apt install tmux (Linux)"
ok "tmux found: $(tmux -V)"

PYTHON=""
for p in python3 python; do
  if command -v "$p" >/dev/null 2>&1; then
    PYTHON="$p"
    break
  fi
done
[[ -n "$PYTHON" ]] || fail "Python not found"
ok "Python found: $($PYTHON --version)"

# ── 2. Unpack tarball ────────────────────────────────────────────────────────
info "Unpacking tarball..."
WORK_DIR="$(pwd)/marlin_workspace"
mkdir -p "$WORK_DIR"

tar -xf "$TARBALL" -C "$WORK_DIR" 2>/dev/null || tar -xvf "$TARBALL" -C "$WORK_DIR"

REPO_DIR=$(find "$WORK_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
if [[ -z "$REPO_DIR" ]]; then
  REPO_DIR="$WORK_DIR"
fi

ok "Unpacked to: $REPO_DIR"
cd "$REPO_DIR"

# ── 3. Git init ──────────────────────────────────────────────────────────────
info "Initializing git..."
if [[ -d ".git" ]]; then
  warn ".git already exists — skipping init"
else
  git init
  git add .
  git commit -m "Initial commit" --quiet
  ok "Git initialized with 'Initial commit'"
fi

HEAD_SHA=$(git rev-parse HEAD)
info "HEAD commit (for Pre-Thread Survey): $HEAD_SHA"

# ── 4. Detect language & install deps ────────────────────────────────────────
info "Detecting project language..."

LANG_DETECTED="unknown"
TEST_CMD=""

if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "setup.cfg" ]] || [[ -f "requirements.txt" ]]; then
  LANG_DETECTED="python"
  info "Detected: Python project"

  if [[ ! -d ".venv" ]]; then
    info "Creating virtual environment..."
    $PYTHON -m venv .venv
  fi
  source .venv/bin/activate
  ok "Virtual environment activated"

  if [[ -f "requirements.txt" ]]; then
    info "Installing from requirements.txt..."
    pip install -r requirements.txt --quiet 2>/dev/null || warn "Some pip installs failed — check manually"
  fi
  if [[ -f "pyproject.toml" ]]; then
    info "Installing project (editable)..."
    pip install -e "." --quiet 2>/dev/null || pip install -e ".[dev]" --quiet 2>/dev/null || warn "pip install -e failed — check manually"
  fi
  if [[ -f "setup.py" ]]; then
    pip install -e "." --quiet 2>/dev/null || warn "setup.py install failed"
  fi

  if command -v pytest >/dev/null 2>&1; then
    TEST_CMD="pytest"
  elif [[ -f "tox.ini" ]]; then
    TEST_CMD="tox"
  fi

elif [[ -f "package.json" ]]; then
  LANG_DETECTED="javascript"
  info "Detected: JavaScript/TypeScript project"

  if command -v npm >/dev/null 2>&1; then
    info "Running npm install..."
    npm install --quiet 2>/dev/null || warn "npm install had issues"
    TEST_CMD="npm test"
  fi

elif [[ -f "go.mod" ]]; then
  LANG_DETECTED="go"
  info "Detected: Go project"

  if command -v go >/dev/null 2>&1; then
    info "Running go mod download..."
    go mod download 2>/dev/null || warn "go mod download had issues"
    TEST_CMD="go test ./..."
  fi

elif [[ -f "Cargo.toml" ]]; then
  LANG_DETECTED="rust"
  info "Detected: Rust project"

  if command -v cargo >/dev/null 2>&1; then
    info "Running cargo build..."
    cargo build 2>/dev/null || warn "cargo build had issues"
    TEST_CMD="cargo test"
  fi

elif [[ -f "pom.xml" ]] || [[ -f "build.gradle" ]] || [[ -f "build.gradle.kts" ]]; then
  LANG_DETECTED="java"
  info "Detected: Java project"

  if [[ -f "pom.xml" ]] && command -v mvn >/dev/null 2>&1; then
    info "Running mvn install..."
    mvn install -DskipTests --quiet 2>/dev/null || warn "mvn install had issues"
    TEST_CMD="mvn test"
  elif command -v gradle >/dev/null 2>&1; then
    info "Running gradle build..."
    gradle build -x test --quiet 2>/dev/null || warn "gradle build had issues"
    TEST_CMD="gradle test"
  fi

elif [[ -f "CMakeLists.txt" ]] || [[ -f "Makefile" ]]; then
  LANG_DETECTED="cpp"
  info "Detected: C++ project"
  TEST_CMD="make test"
fi

ok "Language: $LANG_DETECTED"

# ── 5. Run baseline tests ───────────────────────────────────────────────────
if [[ -n "$TEST_CMD" ]]; then
  info "Running baseline tests: $TEST_CMD"
  if eval "$TEST_CMD" 2>/dev/null; then
    ok "Baseline tests PASSED"
  else
    warn "Baseline tests had failures — review before starting CLI"
  fi
else
  warn "Could not detect test command — run tests manually before starting"
fi

# ── 6. Move CLI binary ──────────────────────────────────────────────────────
if [[ -n "$CLI_BIN" ]]; then
  if [[ -f "$CLI_BIN" ]]; then
    info "Installing CLI binary..."
    cp "$CLI_BIN" ./claude-hfi
    chmod +x ./claude-hfi
    ok "CLI binary ready at ./claude-hfi"
  else
    warn "CLI binary not found at: $CLI_BIN — copy it manually"
  fi
else
  warn "No CLI binary path provided — copy it manually: mv ~/Downloads/<binary> claude-hfi && chmod +x claude-hfi"
fi

# ── 7. Generate CLAUDE.md ───────────────────────────────────────────────────
if [[ ! -f "CLAUDE.md" ]]; then
  info "Generating starter CLAUDE.md..."

  TREE_OUTPUT=$(find . -maxdepth 2 -type f \
    ! -path './.git/*' \
    ! -path './.venv/*' \
    ! -path './node_modules/*' \
    ! -path './target/*' \
    ! -name 'claude-hfi' \
    | head -40 | sort)

  cat > CLAUDE.md << 'CLAUDEEOF'
# CLAUDE.md — Repository Context

## Repository Overview
[FILL IN: What this repository does, its primary purpose]

## Project Structure
CLAUDEEOF

  echo '```' >> CLAUDE.md
  echo "$TREE_OUTPUT" >> CLAUDE.md
  echo '```' >> CLAUDE.md

  cat >> CLAUDE.md << 'CLAUDEEOF'

## Dev Setup
```bash
# [FILL IN: How to set up the development environment]
```

## Testing
```bash
# [FILL IN: How to run the test suite]
```

## Code Conventions
- [FILL IN: Naming conventions, patterns used, error handling style]

## Architecture Notes
- [FILL IN: Key modules and how they interact]
- [FILL IN: Any important design patterns or constraints]

## Things to Avoid
- Do not modify unrelated files
- Do not add unnecessary dependencies
- Follow existing code style and conventions
CLAUDEEOF

  ok "CLAUDE.md created — EDIT IT before starting the CLI"
  warn "Remember: Launch HFI first, then copy CLAUDE.md to the HFI cache"
else
  ok "CLAUDE.md already exists"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "============================================================================"
echo -e "${GREEN}MARLIN SETUP COMPLETE${NC}"
echo "============================================================================"
echo ""
echo "  Repo directory : $REPO_DIR"
echo "  Language        : $LANG_DETECTED"
echo "  HEAD commit     : $HEAD_SHA"
echo "  Test command    : ${TEST_CMD:-'(not detected)'}"
echo "  CLI binary      : $([ -f ./claude-hfi ] && echo 'Ready' || echo 'NOT INSTALLED')"
echo "  CLAUDE.md       : $([ -f ./CLAUDE.md ] && echo 'Present (edit before use)' || echo 'Missing')"
echo ""
echo "NEXT STEPS:"
echo "  1. cd $REPO_DIR"
echo "  2. Edit CLAUDE.md with repo-specific details"
echo "  3. ./claude-hfi --vscode"
echo "  4. Interface code: cc_agentic_coding_next"
echo "  5. Attach tmux sessions in each VS Code window"
echo "  6. Paste your approved Turn 1 prompt"
echo ""
echo "============================================================================"
