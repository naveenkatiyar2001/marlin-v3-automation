# Marlin V3 — Phase 3: Environment & CLI Setup Automation

Automates the environment setup after your Prompt Preparation is approved.

## Quick Start

```bash
# If you have the tarball URL from the approval email:
./marlin_setup.sh --tarball-url "https://github.com/owner/repo/archive/COMMIT.tar.gz"

# If the email shows N/A for the tarball, construct from PR URL:
./marlin_setup.sh --pr-url "https://github.com/owner/repo/pull/123"

# Interactive mode (prompts you for input):
./marlin_setup.sh
```

## What It Automates

| Step | Action | Automated? |
|------|--------|------------|
| Prerequisites | Checks git, VS Code, Python, tmux | Fully |
| Tarball | Downloads + unpacks (or constructs from PR) | Fully |
| Git Init | `git init` + initial commit | Fully |
| Language Detection | Scans for setup.py, package.json, etc. | Fully |
| Dependencies | Creates venv, pip install, npm install, etc. | Best-effort |
| Baseline Tests | Runs pytest / npm test / go test / etc. | Best-effort |
| CLAUDE.md | Generates a draft from repo structure | Draft only |
| CLI Binary | Detects OS/arch, prints download instructions | Instructions |
| HEAD Commit | Extracts and displays for Pre-Thread Survey | Fully |

## What You Still Do Manually

1. **Download tarball** from the approval email link
2. **Authenticate with Anthropic** (browser + Alias email)
3. **Download CLI binary** from Anthropic site
4. **Enter Interface Code**: `cc_agentic_coding_next`
5. **Review CLAUDE.md** draft for accuracy
6. **Attach to tmux sessions** in VS Code windows

## Options

```
--tarball-url <URL>    Tarball URL from approval email
--pr-url <PR_URL>      Construct tarball from PR (gh CLI required)
--work-dir <DIR>       Where to unpack (default: ./marlin-workspace)
--skip-deps            Skip dependency installation
--help                 Show help
```

## Requirements

- bash 4+
- git, python3, tmux, VS Code (in PATH)
- `gh` CLI (only needed for `--pr-url` option)
- Internet connection

## Critical Warnings

- **ONE git commit only.** The script makes the initial commit. Never run `git commit` again.
- **CLAUDE.md after HFI.** The script generates a draft. Copy it to `CLAUDE.md` only after launching the CLI.
- **Environment must work.** If tests fail, fix before launching CLI. Broken env = your fault, not the model's.
