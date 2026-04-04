# Marlin V3 — Complete Automation Suite

> End-to-end automation for the Marlin V3 coding assessment pipeline.
> Cross-platform: **macOS**, **Linux**, and **Windows (WSL)**.

## What This Does

Automates all phases of the Marlin V3 workflow:

| Phase | What | Status |
|-------|------|--------|
| **Phase 1** | PR Selection — capture & analyze repos/PRs from Snorkel | Automated |
| **Phase 2** | Prompt Preparation — generate & validate prompts | Automated |
| **Phase 3** | Environment & CLI Setup — download repo, install deps, launch HFI | Automated |
| **Phase 3 Review** | Post-model evaluation — extract diffs, generate feedback | Automated |

## Quick Start

```bash
# Universal launcher (asks your OS, then which phase to run)
./marlin.sh

# Or run phases directly:
./phase-1-automation-cursor/marlin_phase1.sh repos   # Phase 1
./phase-3-automation/marlin_setup.sh                  # Phase 3
```

Every script asks you to **select your platform** (macOS / Linux / WSL) on startup. If you pick WSL, it automatically redirects to the WSL-optimized version.

## Platform Support

| Feature | macOS | Linux | Windows (WSL) |
|---------|-------|-------|---------------|
| Phase 1 (PR Selection) | Yes | Yes | Yes |
| Phase 2 (Prompt Prep) | Yes | Yes | Yes |
| Phase 3 (Env Setup) | Yes | Yes | Yes |
| Phase 3 Review | Yes | Yes | Yes |
| Package Manager | `brew` | `apt` | `apt` |
| Clipboard | `pbcopy`/`pbpaste` | `xclip` | `clip.exe`/`powershell.exe` |
| Self-Healing Bridge | Yes | Yes | Yes |

## Project Structure

```
marlin-v3-automation/
├── marlin.sh                          # Universal launcher (OS + phase selection)
├── Marlin_V3_Master_Guide.md          # Complete project guide (ground truth)
├── Marlin_V3_Project_Guide/           # Original 7 reference guides
│
├── phase-1-automation-cursor/         # Phase 1 + 2: Cursor-native (macOS/Linux)
│   ├── marlin_phase1.sh               #   Orchestrator (clipboard + validate)
│   ├── clipboard_watcher.py           #   Captures URLs from clipboard
│   ├── prompt_validator.py            #   Checks prompt quality (1300+ rules)
│   ├── cursor_instructions.md         #   Cursor reads this for analysis
│   └── data/                          #   Runtime output (gitignored)
│
├── phase-1-automation/                # Phase 1: Terminal-only (no IDE needed)
│   ├── marlin_phase1.sh               #   Orchestrator
│   ├── clipboard_watcher.py           #   Clipboard capture
│   ├── github_fetcher.py              #   GitHub API data fetching
│   ├── repo_analyzer.py               #   Repo scoring
│   ├── pr_analyzer.py                 #   PR scoring
│   └── prompt_generator.py            #   Analysis markdown generator
│
├── phase-3-automation/                # Phase 3: Environment setup (macOS/Linux)
│   ├── marlin_setup.sh                #   Interactive setup (steps 3.1-3.10)
│   ├── marlin_bridge.py               #   IPC bridge (Cursor ↔ terminal)
│   ├── marlin_review.sh               #   Post-model-run review
│   └── .marlin-bridge/                #   Bridge data directory
│
└── wsl/                               # Windows/WSL optimized (self-contained)
    ├── setup_wsl.sh                   #   WSL prerequisites installer
    ├── README.md                      #   WSL-specific documentation
    ├── phase1/                        #   WSL Phase 1 + 2
    │   ├── marlin_phase1.sh
    │   ├── clipboard_watcher.py       #   Uses powershell.exe/clip.exe
    │   └── prompt_validator.py
    └── phase3/                        #   WSL Phase 3
        ├── marlin_setup.sh            #   WSL-optimized setup
        ├── marlin_bridge.py           #   Cross-platform bridge
        └── marlin_review.sh           #   WSL-optimized review
```

## Prerequisites

### All Platforms
- **Python 3.10+**
- **Git**
- **GitHub CLI** (`gh`) — authenticated

### macOS
- **Homebrew** — `brew install gh tmux`
- **Cursor IDE** — for Phase 2 analysis and self-healing

### Linux
- **apt** — `sudo apt install gh tmux python3`

### Windows (WSL)
- **WSL2** with Ubuntu 22.04+
- Run `bash wsl/setup_wsl.sh` to install all prerequisites automatically

## How It Works

### Phase 1 — PR Selection
1. Run clipboard watcher to capture repo/PR URLs from Snorkel
2. Ask Cursor to analyze and rank candidates using `gh` CLI data
3. Select the best repo + PR combination

### Phase 2 — Prompt Preparation
1. Ask Cursor to generate all Snorkel form fields
2. Validate prompt quality (em-dashes, LLM signatures, word count, etc.)
3. Submit for approval

### Phase 3 — Environment Setup
1. **System prerequisites** — checks git, python, tmux, VS Code
2. **Download repo** — from tarball URL or PR URL
3. **Git initialization** — single initial commit (never commit again)
4. **Dev environment** — detects language (17 supported), installs dependencies
5. **Baseline tests** — runs test suite to verify environment works
6. **Anthropic auth** — authenticates with HFI
7. **CLI binary** — downloads and installs the HFI binary
8. **CLAUDE.md** — generates repo documentation via Cursor bridge
9. **Launch CLI** — starts HFI with tmux sessions
10. **Pre-thread survey** — prepares answers for submission

### Self-Healing Bridge
When the script encounters an error:
1. Writes the error to `live_bridge.json`
2. Cursor reads the error and generates fix commands
3. Script applies the fix and continues automatically

No API keys needed — uses your Cursor subscription directly.

## Language Support (17 Languages)

| Language | Detection | Package Manager | Test Command |
|----------|-----------|-----------------|--------------|
| Python | `setup.py`, `pyproject.toml` | pip / poetry / pipenv | `pytest` |
| Node.js | `package.json` | npm / yarn / pnpm / bun | `npm test` |
| Go | `go.mod` | go modules | `go test ./...` |
| Rust | `Cargo.toml` | cargo | `cargo test` |
| Java | `pom.xml`, `build.gradle` | maven / gradle | `mvn test` |
| C/C++ | `CMakeLists.txt`, `Makefile` | cmake / make | `ctest` |
| Ruby | `Gemfile` | bundler | `bundle exec rspec` |
| PHP | `composer.json` | composer | `vendor/bin/phpunit` |
| Scala | `build.sbt` | sbt | `sbt test` |
| Swift | `Package.swift` | swift PM | `swift test` |
| Dart | `pubspec.yaml` | dart pub | `dart test` |
| Elixir | `mix.exs` | mix | `mix test` |
| Zig | `build.zig` | zig | `zig build test` |
| .NET | `*.csproj`, `*.sln` | dotnet | `dotnet test` |

Plus known monorepo support: **dagster**, **vscode**, **react**, **transformers**, **diffusers**, **langchain**, **prefect**, **rust-lang**.

## Commands Reference

```bash
# Universal launcher
./marlin.sh                              # Interactive (OS + phase selection)
./marlin.sh --os macos                   # Skip OS selection
./marlin.sh --os wsl                     # Use WSL scripts

# Phase 1 — PR Selection
./phase-1-automation-cursor/marlin_phase1.sh repos     # Capture repo URLs
./phase-1-automation-cursor/marlin_phase1.sh prs       # Capture PR URLs
./phase-1-automation-cursor/marlin_phase1.sh full      # Both steps
./phase-1-automation-cursor/marlin_phase1.sh status    # Show data state

# Phase 2 — Prompt Validation
./phase-1-automation-cursor/marlin_phase1.sh validate "prompt text"
./phase-1-automation-cursor/marlin_phase1.sh validate --file prompt.txt

# Phase 3 — Environment Setup
./phase-3-automation/marlin_setup.sh                   # Interactive setup
./phase-3-automation/marlin_setup.sh --list            # List tasks
./phase-3-automation/marlin_setup.sh --clean           # Remove a task

# Phase 3 — Review
./phase-3-automation/marlin_review.sh /path/to/repo

# WSL Setup (one-time)
bash wsl/setup_wsl.sh
```

## License

Private — internal tooling for Marlin V3 assessments.
