#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# MARLIN V3 — PHASE 1 ORCHESTRATOR (TERMINAL-BASED)
# ============================================================================
#
# Pure terminal approach — uses Python scripts to fetch data from GitHub API
# and generate analysis. Works WITHOUT Cursor or any IDE.
#
# Usage:
#   ./marlin_phase1.sh new-task-select-repo
#       → Clipboard watcher (repos) → GitHub fetch → Analysis prompt
#
#   ./marlin_phase1.sh select-pr
#       → Clipboard watcher (PRs) → GitHub fetch → Analysis prompt
#
#   ./marlin_phase1.sh full
#       → Both steps sequentially
#
#   ./marlin_phase1.sh analyze-repos
#       → Re-run analysis on already-captured repos (skip clipboard step)
#
#   ./marlin_phase1.sh analyze-prs
#       → Re-run analysis on already-captured PRs (skip clipboard step)
#
#   ./marlin_phase1.sh status
#       → Show current data state
#
#   ./marlin_phase1.sh clean
#       → Wipe data/ for fresh start
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
  echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}MARLIN V3 — PHASE 1: PR SELECTION (TERMINAL)${NC}             ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${DIM}Clipboard → GitHub API (Python) → Analysis File${NC}          ${CYAN}║${NC}"
  echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

check_python() {
  if ! command -v "$PYTHON" >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} Python3 not found."
    exit 1
  fi
}

run_repo_clipboard() {
  echo -e "${BOLD}STEP 1a: COLLECT REPOS FROM CLIPBOARD${NC}"
  echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
  echo ""
  echo "  1. Open Snorkel PR Selection page in your browser."
  echo "  2. Copy each repo name or GitHub URL one by one."
  echo "  3. This tool captures each copy automatically."
  echo "  4. Type END and press Enter when done."
  echo ""
  echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
  echo ""

  "$PYTHON" "$SCRIPT_DIR/clipboard_watcher.py" --mode repos
}

run_repo_analysis() {
  echo ""
  echo -e "${BOLD}STEP 1b: FETCHING RICH DATA FROM GITHUB API${NC}"
  echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
  echo ""

  "$PYTHON" -c "
import json, sys
sys.path.insert(0, '$SCRIPT_DIR')
from pathlib import Path
from github_fetcher import fetch_all_repos
from prompt_generator import generate_repo_analysis_prompt, write_analysis_file

data_dir = Path('$DATA_DIR')
live = json.loads((data_dir / 'live_repos.json').read_text())
entries = live.get('entries', [])

if not entries:
    print('  No repos to analyze.')
    sys.exit(0)

print(f'  Fetching detailed data for {len(entries)} repos...\n')
repos_data = fetch_all_repos(entries)

# Save raw fetched data
(data_dir / 'fetched_repos.json').write_text(json.dumps(repos_data, indent=2, default=str))

print(f'\n  Generating analysis prompt...')
prompt = generate_repo_analysis_prompt(repos_data)
filepath = write_analysis_file(prompt, 'cursor_analysis_repos.md')
print(f'  Written to: {filepath}')
print(f'  Size: {len(prompt)} chars')
"

  ANALYSIS_FILE="$DATA_DIR/cursor_analysis_repos.md"

  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  REPO ANALYSIS READY${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  File: ${BOLD}$ANALYSIS_FILE${NC}"
  echo ""
  echo "  OPTIONS:"
  echo "    a) Open the file and review the analysis manually"
  echo "    b) If Cursor is available, ask it to read & analyze:"
  echo ""
  echo -e "       ${CYAN}\"Read and analyze the file at${NC}"
  echo -e "       ${CYAN} phase-1-automation/data/cursor_analysis_repos.md\"${NC}"
  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo ""
}

run_pr_clipboard() {
  echo -e "${BOLD}STEP 2a: COLLECT PRs FROM CLIPBOARD${NC}"
  echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
  echo ""

  SELECTED_REPO=""
  if [ -f "$DATA_DIR/fetched_repos.json" ]; then
    SELECTED_REPO=$("$PYTHON" -c "
import json
from pathlib import Path
data = json.loads(Path('$DATA_DIR/fetched_repos.json').read_text())
valid = [r for r in data if r.get('fetch_ok')]
if valid:
    best = sorted(valid, key=lambda x: x.get('stars', 0), reverse=True)[0]
    print(f\"{best['owner']}/{best['repo']}\")
" 2>/dev/null || echo "")
  fi

  if [ -n "$SELECTED_REPO" ]; then
    echo -e "  Selected repo: ${GREEN}${SELECTED_REPO}${NC}"
  fi

  echo ""
  echo "  1. On Snorkel, look at PRs for your selected repo."
  echo "  2. Copy each PR name, number, or GitHub URL one by one."
  echo "  3. Type END and press Enter when done."
  echo ""
  echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
  echo ""

  "$PYTHON" "$SCRIPT_DIR/clipboard_watcher.py" --mode prs
}

run_pr_analysis() {
  echo ""
  echo -e "${BOLD}STEP 2b: FETCHING RICH PR DATA FROM GITHUB API${NC}"
  echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
  echo ""

  "$PYTHON" -c "
import json, sys
sys.path.insert(0, '$SCRIPT_DIR')
from pathlib import Path
from github_fetcher import fetch_all_prs
from prompt_generator import generate_pr_analysis_prompt, write_analysis_file

data_dir = Path('$DATA_DIR')
live = json.loads((data_dir / 'live_prs.json').read_text())
entries = live.get('entries', [])

if not entries:
    print('  No PRs to analyze.')
    sys.exit(0)

# Determine default owner/repo
default_owner, default_repo = '', ''
fetched_repos_path = data_dir / 'fetched_repos.json'
if fetched_repos_path.exists():
    repos = json.loads(fetched_repos_path.read_text())
    valid = [r for r in repos if r.get('fetch_ok')]
    if valid:
        best = sorted(valid, key=lambda x: x.get('stars', 0), reverse=True)[0]
        default_owner = best['owner']
        default_repo = best['repo']

selected_repo = f'{default_owner}/{default_repo}' if default_owner else 'unknown'

print(f'  Fetching detailed data for {len(entries)} PRs from {selected_repo}...\n')
prs_data = fetch_all_prs(entries, default_owner, default_repo)

# Save raw fetched data
(data_dir / 'fetched_prs.json').write_text(json.dumps(prs_data, indent=2, default=str))

print(f'\n  Generating analysis prompt...')
prompt = generate_pr_analysis_prompt(prs_data, selected_repo)
filepath = write_analysis_file(prompt, 'cursor_analysis_prs.md')
print(f'  Written to: {filepath}')
print(f'  Size: {len(prompt)} chars')
"

  ANALYSIS_FILE="$DATA_DIR/cursor_analysis_prs.md"

  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  PR ANALYSIS READY${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  File: ${BOLD}$ANALYSIS_FILE${NC}"
  echo ""
  echo "  OPTIONS:"
  echo "    a) Open the file and review the analysis manually"
  echo "    b) If Cursor is available, ask it to read & analyze:"
  echo ""
  echo -e "       ${CYAN}\"Read and analyze the file at${NC}"
  echo -e "       ${CYAN} phase-1-automation/data/cursor_analysis_prs.md\"${NC}"
  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo ""
}

show_status() {
  echo -e "${BOLD}CURRENT DATA STATUS:${NC}"
  echo ""

  for f in live_repos.json fetched_repos.json cursor_analysis_repos.md live_prs.json fetched_prs.json cursor_analysis_prs.md; do
    filepath="$DATA_DIR/$f"
    if [ -f "$filepath" ]; then
      size=$(wc -c < "$filepath" | tr -d ' ')
      echo -e "  ${GREEN}✓${NC}  $f  (${size} bytes)"
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

# ── Main ─────────────────────────────────────────────────────────────────────

COMMAND="${1:-help}"

banner
check_python

case "$COMMAND" in
  new-task-select-repo|repo|repos)
    mkdir -p "$DATA_DIR"
    run_repo_clipboard
    run_repo_analysis
    ;;
  select-pr|pr|prs)
    mkdir -p "$DATA_DIR"
    run_pr_clipboard
    run_pr_analysis
    ;;
  analyze-repos)
    run_repo_analysis
    ;;
  analyze-prs)
    run_pr_analysis
    ;;
  full|all)
    mkdir -p "$DATA_DIR"
    run_repo_clipboard
    run_repo_analysis
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}Repo analysis done. Now collect PRs.${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    run_pr_clipboard
    run_pr_analysis
    ;;
  status)
    show_status
    ;;
  clean)
    clean_data
    ;;
  *)
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  new-task-select-repo   Collect repos via clipboard → fetch → generate analysis"
    echo "  select-pr              Collect PRs via clipboard → fetch → generate analysis"
    echo "  full                   Run both steps sequentially"
    echo "  analyze-repos          Re-generate repo analysis (skip clipboard)"
    echo "  analyze-prs            Re-generate PR analysis (skip clipboard)"
    echo "  status                 Show current data state"
    echo "  clean                  Wipe data for fresh start"
    echo ""
    echo -e "${DIM}This is the TERMINAL-BASED approach (Python + GitHub API).${NC}"
    echo -e "${DIM}For the CURSOR-NATIVE approach, see: phase-1-automation-cursor/${NC}"
    echo ""
    ;;
esac
