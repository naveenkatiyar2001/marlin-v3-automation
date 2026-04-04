# Marlin V3 — Windows/WSL Automation

> Complete Marlin V3 automation optimized for Windows Subsystem for Linux (WSL).
> Self-contained — does **not** interfere with the macOS/Linux scripts.

## Quick Start

```bash
# 1. Run prerequisites installer (one-time)
bash setup_wsl.sh

# 2. Or use the universal launcher from project root
cd ..
bash marlin.sh --os wsl
```

## Structure

```
wsl/
├── setup_wsl.sh              # WSL prerequisites installer (one-time)
├── README.md                  # This file
├── phase1/
│   ├── marlin_phase1.sh       # Phase 1 + 2 orchestrator (WSL)
│   ├── clipboard_watcher.py   # Clipboard capture (powershell.exe/clip.exe)
│   └── data/                  # Captured URLs
└── phase3/
    ├── marlin_setup.sh        # Phase 3 environment setup (WSL)
    ├── marlin_bridge.py       # IPC bridge (Cursor ↔ terminal)
    ├── marlin_review.sh       # Post-model-run review (WSL)
    └── .marlin-bridge/        # Bridge data directory
```

## Key Differences from macOS

| Feature | macOS | WSL |
|---------|-------|-----|
| Package manager | `brew` | `apt` |
| Clipboard read | `pbpaste` | `powershell.exe Get-Clipboard` |
| Clipboard write | `pbcopy` | `clip.exe` |
| Open browser | `open` | `wslview` or `cmd.exe /c start` |
| Open terminal | `osascript` (Terminal.app) | `wt.exe` (Windows Terminal) |
| HFI binary | `darwin-arm64` / `darwin-amd64` | `linux-amd64` / `linux-arm64` |
| EPERM issue | Yes (Cursor TCC) | No |
| Gatekeeper | `xattr -d` needed | Not applicable |
| Python install | `brew install python@3.12` | `sudo apt install python3.12` |

## Prerequisites

These are installed automatically by `setup_wsl.sh`:

- **WSL2** (Ubuntu 22.04+ recommended)
- **git**, **python3**, **python3-venv**, **tmux**, **curl**
- **gh** (GitHub CLI) — for PR data fetching
- **VS Code** with WSL extension (for `code` command)
- **clip.exe** / **powershell.exe** — for clipboard (come with WSL)
- **wslu** — for `wslview` (open URLs in Windows browser)

## Usage

### Phase 1 — PR Selection

```bash
cd wsl/phase1
bash marlin_phase1.sh repos    # Capture repo URLs
bash marlin_phase1.sh prs      # Capture PR URLs
bash marlin_phase1.sh full     # Both steps
```

### Phase 2 — Prompt Preparation

```bash
bash marlin_phase1.sh validate "Your prompt text here"
bash marlin_phase1.sh validate --file path/to/prompt.txt
```

Then ask Cursor: `Read wsl/phase1/cursor_instructions.md then [prepare-prompt]`

### Phase 3 — Environment Setup

```bash
cd wsl/phase3
bash marlin_setup.sh           # Interactive setup
bash marlin_setup.sh --list    # List existing tasks
bash marlin_setup.sh --clean   # Remove a task
```

### Phase 3 Review — Post-Model Evaluation

```bash
bash marlin_review.sh /path/to/repo
```

## Language Support

The WSL scripts support 17 languages/ecosystems:

| Language | Detection | Package Manager | Test Command |
|----------|-----------|-----------------|--------------|
| Python | `setup.py`, `pyproject.toml` | pip/poetry/pipenv | `pytest` |
| Node.js | `package.json` | npm/yarn/pnpm/bun | `npm test` |
| Go | `go.mod` | go modules | `go test ./...` |
| Rust | `Cargo.toml` | cargo | `cargo test` |
| Java | `pom.xml`, `build.gradle` | maven/gradle | `mvn test` |
| C/C++ | `CMakeLists.txt`, `Makefile` | cmake/make | `ctest` / `make test` |
| Ruby | `Gemfile` | bundler | `bundle exec rspec` |
| PHP | `composer.json` | composer | `vendor/bin/phpunit` |
| Scala | `build.sbt` | sbt | `sbt test` |
| Swift | `Package.swift` | swift PM | `swift test` |
| Dart | `pubspec.yaml` | dart pub | `dart test` |
| Elixir | `mix.exs` | mix | `mix test` |
| Zig | `build.zig` | zig | `zig build test` |
| .NET | `*.csproj`, `*.sln` | dotnet | `dotnet test` |

## Self-Healing

The WSL scripts include the same self-healing bridge as macOS:

1. Script encounters an error → writes to `live_bridge.json`
2. Cursor reads the error and generates fix commands
3. Script applies the fix and continues

The bridge file is at `wsl/phase3/.marlin-bridge/live_bridge.json`.

## Troubleshooting

### Clipboard not working
```bash
# Test clipboard
echo "test" | clip.exe                              # Write
powershell.exe -NoProfile -Command "Get-Clipboard"  # Read
```

### VS Code CLI not found
Install VS Code on Windows, then install the WSL extension.
The `code` command auto-appears in WSL terminal.

### Python version issues
```bash
sudo apt install python3.12 python3.12-venv
```

### Permission denied on scripts
```bash
chmod +x wsl/phase3/marlin_setup.sh wsl/phase1/marlin_phase1.sh
```
