# Marlin V3 — Commands Cheat Sheet

## Setup

```bash
git clone https://github.com/naveenkatiyar2001/marlin-v3-automation.git
cd marlin-v3-automation
```

## WSL Only (one-time)

```bash
bash wsl/setup_wsl.sh
```

## Phase 1 — PR Selection

```bash
bash phase-1-automation-cursor/marlin_phase1.sh repos
```
> Then in Cursor: "Read phase-1-automation-cursor/cursor_instructions.md then [analyze-repos]"

```bash
bash phase-1-automation-cursor/marlin_phase1.sh prs
```
> Then in Cursor: "Read phase-1-automation-cursor/cursor_instructions.md then [analyze-prs]"

## Phase 2 — Prompt Preparation

> In Cursor: "Read phase-1-automation-cursor/cursor_instructions.md then [prepare-prompt] for owner/repo PR #number"

```bash
bash phase-1-automation-cursor/marlin_phase1.sh validate "your prompt text here"
```

## Phase 3 — Environment & CLI Setup

```bash
bash phase-3-automation/marlin_setup.sh
```

## Phase 3 — Review (after models finish)

```bash
bash phase-3-automation/marlin_review.sh /path/to/repo
```

## Universal Launcher (alternative)

```bash
bash marlin.sh
```

## Utility

```bash
bash phase-3-automation/marlin_setup.sh --list
bash phase-3-automation/marlin_setup.sh --clean
bash phase-1-automation-cursor/marlin_phase1.sh status
bash phase-1-automation-cursor/marlin_phase1.sh clean
```
