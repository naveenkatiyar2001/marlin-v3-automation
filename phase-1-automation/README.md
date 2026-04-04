# Phase 1 Automation -- Terminal-Based (Python + GitHub API)

> **Works without Cursor.** Uses Python scripts to fetch data from GitHub's REST API
> and generates analysis files you can review in any text editor or terminal.

## When to Use This

- You don't have access to Cursor IDE
- You want to run everything from the terminal
- You need the raw data saved as JSON/Markdown files for later reference
- You're working on a machine without `gh` CLI

## Prerequisites

- **Python 3.10+** (uses modern type syntax)
- **macOS** or **Linux** (clipboard uses `pbpaste` / `xclip`)
- Internet connection (for GitHub API calls)
- Optional: `pip install certifi` for verified SSL (falls back to unverified if missing)

## Files

```
phase-1-automation/
├── marlin_phase1.sh          # Main orchestrator
├── clipboard_watcher.py      # Captures URLs from clipboard
├── github_fetcher.py         # Fetches repo/PR data from GitHub REST API
├── prompt_generator.py       # Generates analysis markdown from fetched data
├── repo_analyzer.py          # Standalone repo scoring (legacy)
├── pr_analyzer.py            # Standalone PR scoring (legacy)
├── data/
│   ├── live_repos.json       # Captured repo URLs
│   ├── live_prs.json         # Captured PR URLs
│   ├── fetched_repos.json    # Raw API data for repos
│   ├── fetched_prs.json      # Raw API data for PRs
│   ├── cursor_analysis_repos.md  # Generated analysis (repos)
│   └── cursor_analysis_prs.md    # Generated analysis (PRs)
```

## Usage

```bash
# Step 1: Collect repo URLs from clipboard
./marlin_phase1.sh repos
# Copy URLs from Snorkel, type END when done

# Step 2: Collect PR URLs from clipboard  
./marlin_phase1.sh prs
# Copy PR URLs from Snorkel, type END when done

# Or run both steps sequentially
./marlin_phase1.sh full

# Re-run analysis on already captured data
./marlin_phase1.sh analyze-repos
./marlin_phase1.sh analyze-prs

# Check status / clean up
./marlin_phase1.sh status
./marlin_phase1.sh clean
```

## How It Works

```
You copy URLs → clipboard_watcher.py captures them → live_*.json
                                                        ↓
                                               github_fetcher.py
                                          (Python urllib → api.github.com)
                                                        ↓
                                              fetched_*.json (raw data)
                                                        ↓
                                             prompt_generator.py
                                        (formats data + Marlin V3 criteria)
                                                        ↓
                                          cursor_analysis_*.md (analysis file)
                                                        ↓
                                   Review manually OR feed to Cursor/any LLM
```

## Output

The generated `cursor_analysis_*.md` files contain:
- Full repo/PR metadata from GitHub API
- Marlin V3 selection criteria embedded
- Specific analysis questions to answer
- Can be read by any text editor, terminal, or fed to any LLM

## Platform Support

| OS | Clipboard | Status |
|----|-----------|--------|
| macOS | `pbpaste` (built-in) | Works out of the box |
| Linux | `xclip` (install: `sudo apt install xclip`) | Works after install |
| Windows | Not supported | Use WSL or the cursor-native approach |

## Alternative Approach

For a smarter, Cursor-native approach that uses `gh` CLI and Cursor's intelligence
directly (no Python API code), see: **`phase-1-automation-cursor/`**
