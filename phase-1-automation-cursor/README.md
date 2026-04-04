# Cursor-Native Automation -- Phase 1 (PR Selection) + Phase 2 (Prompt Preparation)

> Requires Cursor IDE + gh CLI. Cursor fetches real data directly using GitHub's
> official CLI and handles analysis, prompt generation, and quality validation.

## Prerequisites

- **Python 3.10+** -- for clipboard watcher and prompt validator
- **macOS** or **Linux** (clipboard uses `pbpaste` / `xclip`)
- **GitHub CLI** -- install and authenticate:
  - macOS: `brew install gh && gh auth login`
  - Linux: [see gh install docs](https://github.com/cli/cli/blob/trunk/docs/install_linux.md) then `gh auth login`
- **Cursor IDE** -- with a capable model (claude-sonnet-4.6-high or above)

## Files

```
phase-1-automation-cursor/
|-- marlin_phase1.sh          # Orchestrator (clipboard + validate)
|-- clipboard_watcher.py      # Captures URLs from clipboard
|-- prompt_validator.py       # Checks prompt quality against Marlin rules
|-- cursor_instructions.md    # Cursor reads this -- Phase 1 + Phase 2 instructions
|-- data/
|   |-- live_repos.json       # Captured repo URLs
|   +-- live_prs.json         # Captured PR URLs
```

## Workflow

### Phase 1 -- PR Selection

```bash
# Step 1: Capture repo URLs from clipboard
./marlin_phase1.sh repos
# Copy URLs from Snorkel, type END when done

# Step 2: Ask Cursor
# "Read phase-1-automation-cursor/cursor_instructions.md then [analyze-repos]"

# Step 3: Capture PR URLs from clipboard
./marlin_phase1.sh prs
# Copy PR URLs from Snorkel, type END when done

# Step 4: Ask Cursor
# "Read phase-1-automation-cursor/cursor_instructions.md then [analyze-prs]"
```

### Phase 2 -- Prompt Preparation

After selecting a repo and PR, ask Cursor:

```
Read phase-1-automation-cursor/cursor_instructions.md then [prepare-prompt]
for dagster-io/dagster PR #24569
```

Cursor will:
1. Fetch full PR data via gh CLI (metadata, files, diff, review comments)
2. Analyze the code changes to understand what the PR does
3. Generate all Snorkel form fields:
   - Prompt Category
   - Repo Definition
   - PR Definition
   - Edge Cases
   - Acceptance Criteria
   - Testing Setup
   - Initial Prompt
4. Run quality validation on the generated prompt
5. Output everything in copy-paste-ready format

### Validate a prompt manually

```bash
# Check a prompt against quality rules
./marlin_phase1.sh validate "Your prompt text here"

# Or check from a file
./marlin_phase1.sh validate --file path/to/prompt.txt
```

The validator checks for:
- Em-dash characters (model signature, auto-rejection)
- PR references (#number, pull/number, "this PR")
- Role-based prompting ("You are a senior engineer...")
- Over-prescriptive patterns ("on line 47, change X to Y")
- LLM signature words (leverage, utilize, delve, etc.)
- Word count (target: 150-300 words)
- Sentence variety (natural human writing pattern)

### Utility commands

```bash
./marlin_phase1.sh status    # Check data state + gh auth
./marlin_phase1.sh clean     # Wipe data/ for fresh start
```

## Prompt Quality Rules (enforced by validator)

| Rule | Severity | What triggers rejection |
|---|---|---|
| Em-dashes | CRITICAL | Unicode U+2014 character anywhere in prompt |
| PR references | CRITICAL | #digits, pull/digits, "this PR", branch names |
| Role prompting | CRITICAL | "You are a", "Act as", "Imagine you are" |
| Over-prescriptive | WARNING | "on line N", "change X to Y in file.py" |
| LLM signatures | WARNING | "leverage", "utilize", "delve", "comprehensive" |
| Word count | INFO | Under 150 or over 300 words |
| Sentence variety | INFO | All sentences same length (robotic pattern) |

## Alternative Approach

For a terminal-only approach that works WITHOUT Cursor, see: **`phase-1-automation/`**
