# MARLIN V3 — MASTER EXECUTION GUIDE

> **Purpose:** A single, end-to-end reference that walks you through every phase of a Marlin V3 task — from picking a PR to clicking Submit — in plain language, with optimised prompts and automation hooks at every step.

---

## TABLE OF CONTENTS

| # | Phase | Status |
|---|-------|--------|
| 1 | [PR Selection](#phase-1--pr-selection) | Manual (on Snorkel) |
| 2 | [Prompt Preparation](#phase-2--prompt-preparation) | Semi-automatable |
| 3 | [Environment & CLI Setup](#phase-3--environment--cli-setup) | Automatable |
| 4 | [Task Execution (PR Creation)](#phase-4--task-execution-pr-creation) | Semi-automatable |
| 5 | [Review Diffs & Traces (V3)](#phase-5--review-diffs--traces) | Manual |
| 6 | [Evaluation Writeup (V3)](#phase-6--evaluation-writeup) | Template-automatable |
| 7 | [Submission Checker (V3)](#phase-7--submission-checker) | Manual (Snorkel tool) |
| 8 | [Final Submit on Snorkel](#phase-8--final-submit) | Manual |
| A | [Common Mistakes Checklist](#appendix-a--common-mistakes-checklist) | Reference |
| B | [Optimised Prompts Library](#appendix-b--optimised-prompts-library) | Copy-paste ready |
| C | [Automation Scripts](#appendix-c--automation-scripts) | Shell scripts |

---

## PHASE 1 — PR SELECTION

### What this is (plain language)
You visit the Snorkel platform and pick ONE repository + ONE pull request to base your work on. Think of it as choosing the "exam question" — you need one that is hard enough to make a model genuinely struggle, but within a language/domain you actually understand.

### Step-by-step

1. **Open the Snorkel interface** — it has a split-screen: repos on the left, PRs on the right.
2. **Browse the PR Glossary** — each repo shows its available PRs with short descriptions.
3. **Apply the complexity filter** (mental checklist):
   - Would a human engineer need **~2+ hours** to complete this?
   - Would a model likely **fail on the 1st or 2nd try**?
   - Is the language **supported**? (Python, JS/TS, Go, Rust, Java, C++)
4. **Pick a prompt category** that fits (there are 14 — see table below).
5. **Select repo → Select PR → Click SUBMIT.**
6. **Wait 1–2 minutes** for Snorkel to process.

### The 14 Prompt Categories

| # | Category | One-liner |
|---|----------|-----------|
| 1 | Git | Tasks involving git operations (branch, merge, rebase, etc.) |
| 2 | Ambiguous | Prompt where a good model should ask for clarification first |
| 3 | Discussion | Answer questions about code without producing code |
| 4 | Explaining | Walk through / narrate how existing code works |
| 5 | Code Review | Review a feature suite or meaningful chunk of code |
| 6 | Refactor | Cleanup, consolidation, readability — no behavior change |
| 7 | Greenfield | Build from scratch in an empty repo (no PR needed) |
| 8 | Bug Fix | Find and fix a specific, reproducible bug |
| 9 | Chore | Maintenance: deps, config, build fixes |
| 10 | Documentation | Write/update docs, docstrings, READMEs |
| 11 | New Feature | Add entirely new functionality to existing repo |
| 12 | Performance | Reduce latency, memory, compute — with measurable success |
| 13 | Testing & QA | Write, improve, or extend tests |
| 14 | Other | Genuinely doesn't fit above (rare) |

### Key rules
- Category can **evolve** across turns (Turn 1 = Discussion, Turn 2 = Code Review) — you only declare the initial category now.
- If one category gets flooded, Snorkel may temporarily disable it.

---

## PHASE 2 — PROMPT PREPARATION

### What this is (plain language)
You write the "task description" that the model will receive. Think of it as writing a **very detailed GitHub issue** — you describe the problem, what success looks like, and any edge cases. You do NOT say "Act as a senior engineer" or reference the PR itself.

### What you must prepare (4 sections)

#### 2.1 — Repository & PR Context
Explain **what the repo does** and **what needs to change and why**, in plain enough terms that someone unfamiliar with the codebase can follow.

#### 2.2 — Task Approach
- Current behavior vs. desired behavior
- Which files/functions/components are involved
- Dependencies or interactions that may break
- Concrete edge cases (not hypothetical)
- What tests should cover and how they validate behavior
- Clear acceptance criteria ("done when...")

#### 2.3 — Prompt Definition
The actual text the model will see. Rules:
- **Self-contained** — someone reading only this text understands the full task
- **No role-based prompting** — no "You are a senior engineer..."
- **No PR references** — write as if you are the developer building this from scratch
- **No LLM usage** — you must write this yourself
- **Not over-prescriptive** — describe problem + success, not "on line 47, change X to Y"
- **6–8 engineer-hours** complexity target

#### 2.4 — Effort & Complexity
Brief paragraph explaining WHY this is non-trivial (number of files, logic depth, component interactions, edge cases).

### V3 key changes from V2
- **Phased implementation OK:** You can implement core in Turn 1 and add edge cases / tests / secondary features in Turn 2+.
- **Verifiable prompts encouraged but not mandatory:** As long as acceptance criteria clearly describe expected behavior and what counts as incomplete.
- **Over-prescriptive = rejection:** Do NOT micromanage. Describe the problem, not every line change.

### Example of a GOOD prompt
> Update Gaphor's property editor to clearly separate model-level and diagram-level behavior for UML Dependency elements. Add a dedicated property page for Dependency model objects that shows Source and Target when selected from the model tree. Refactor the existing Dependency diagram item editor into a separate item-specific page with updated identifiers. Add support for the UML isFinalSpecialization attribute on classifiers and expose it through a toggle in the classifier property editor using proper transaction handling. Update the GTK UI definitions where needed and add unit tests to verify both Dependency property visibility and classifier specialization updates. The changes should follow the UML specification and leave the code production ready.

**Why it works:** Names exact components, verifiable outcomes, reads like a real issue, thinks about production, sounds human.

---

## PHASE 3 — ENVIRONMENT & CLI SETUP

### What this is (plain language)
After your prompt is approved, you receive an email with a **tarball** (compressed archive) of the repo at its **pre-PR state** — the code BEFORE the PR changes existed. You unpack it, set up the dev environment, install the CLI tool, and prepare everything so the model can actually run code.

### Step-by-step

#### 3.1 — System prerequisites
You need: Git, VS Code (in PATH), Python, tmux, Terminal, Internet.

#### 3.2 — Add VS Code to PATH (if not done)
```bash
# macOS (from inside VS Code):
# Cmd+Shift+P → "Shell Command: Install 'code' command in PATH"
# Verify:
code --version
```

#### 3.3 — Install tmux
```bash
# macOS
brew install tmux
# Linux
sudo apt update && sudo apt install tmux
# Verify
tmux -V
```

#### 3.4 — Unpack the tarball & initialize git
```bash
tar -xvf <downloaded-file>.tar
cd <repo-folder>
git init
git add .
git commit -m "Initial commit"
```
> **CRITICAL:** This is the ONLY `git commit` you ever run manually. The CLI manages all subsequent git state. Manual commits between turns **corrupt trajectory tracking**.

#### 3.5 — Set up the dev environment
```bash
# Example for Python:
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"  # or whatever the repo uses
# Run baseline tests to confirm they pass:
pytest  # or the repo's test command
```
> **Why this matters:** If the environment is broken, the model cannot run tests. That is YOUR fault, not the model's — reviewers will not penalize the model for env issues.

#### 3.6 — Create CLAUDE.md (V3 requirement)
If the repo does not already have one, create it AFTER launching HFI (see workflow below):

```markdown
# CLAUDE.md
## Repository Overview
[What this repo does]

## Dev Setup
[How to install dependencies, run the project]

## Testing
[How to run tests: e.g., `pytest tests/`]

## Code Conventions
[Naming, structure, error handling patterns]

## Architecture
[Key modules and how they interact]
```

**Critical workflow order:**
1. Clean main branch (no pending changes)
2. Launch HFI (`./claude-hfi --vscode`)
3. THEN create CLAUDE.md
4. Copy CLAUDE.md from local path (A) to HFI cache path (B)

#### 3.7 — Authenticate with Anthropic
Open: `https://feedback.anthropic.com/claude_code?email_login=true`
Login with your **Alias email** (NOT Google sign-in).

#### 3.8 — Download & install the CLI binary
```bash
# Download the correct build for your OS/arch
# Move it into the repo root:
mv ~/Downloads/darwin-arm64 claude-hfi
chmod +x claude-hfi
```

#### 3.9 — Launch the CLI
```bash
./claude-hfi --vscode
```
When prompted for Interface Code, enter: **`cc_agentic_coding_next`**

#### 3.10 — Attach to tmux sessions
In each VS Code window:
```bash
tmux attach -t <session-id>-A   # Trajectory A
tmux attach -t <session-id>-B   # Trajectory B
```

---

## PHASE 4 — TASK EXECUTION (PR CREATION)

### What this is (plain language)
This is the actual work. You paste your approved prompt, the CLI sends it to **two separate model instances** (Trajectory A and Trajectory B), you review what each produces, iterate with follow-up prompts, and eventually pick the better output.

### Step-by-step

#### 4.1 — Paste your Turn 1 prompt
Paste the **exact prompt** from your approved Prompt Preparation. Press Enter. Both trajectories start working independently.

#### 4.2 — Wait for completion
The terminal shows `Waiting for trajectories to complete...` — do not proceed until both finish.

#### 4.3 — Review both trajectories
For each trajectory:
1. Open VS Code Source Control panel
2. Click every modified file
3. Examine each line-level diff
4. Confirm requested behavior is implemented
5. Check for unnecessary/unrelated changes
6. Check for missing functionality
7. Run tests if available
8. Verify new tests exist for new functionality

#### 4.4 — Follow-up turns (minimum 3 total)
Each follow-up must:
- **Identify a specific issue** (name the file, function, behavior)
- **Request a concrete change** (not "review everything" or "check for bugs")
- **Advance the implementation** meaningfully

**Between turns:**
1. Press Ctrl+C to exit the CLI
2. Relaunch: `./claude-hfi --vscode --continue`
3. **DO NOT** run `git commit` between turns

#### 4.5 — Select the preferred response
After all turns, compare A vs. B and decide which is better overall.

### Turn examples

**Good Turn 2:**
> "The `compute_serialized_data` function in `serialization/compute.py` does not handle the case where `spec.deps` is empty — it will produce a `KeyError` when looking up downstream neighbors. Add a guard for empty deps and add a test in `test_load_defs.py` that passes an asset spec with no dependencies."

**Bad Turn 2:**
> "Please review everything and make sure it works correctly."

---

## PHASE 5 — REVIEW DIFFS & TRACES

### What this is (plain language)
V3 requires you to not just look at the final code, but also review HOW the model thought and worked. You read the model's "thought process" (traces) alongside the code changes (diffs).

### What to look for in traces
- Did it **actually run tests**, or only claim to?
- Did it **investigate root cause**, or patch symptoms?
- Did it **avoid risky actions** (force push, delete) without asking?
- Did it **stay on scope** and avoid unrelated changes?
- Did it **accurately report** what it changed?
- Did it **ask clarification** when genuinely needed?

---

## PHASE 6 — EVALUATION WRITEUP

### What this is (plain language)
You fill in a structured form comparing Model A vs. Model B across 11 dimensions. Every claim must reference specific files, functions, or test output — no hand-waving.

### Required text fields (5)

| Field | What to write |
|-------|---------------|
| Senior engineer expectations | What would a strong senior engineer do given your prompt? This is the baseline. |
| Model A strengths | Detailed, evaluative feedback on what A did well and WHY it matters. |
| Model A weaknesses | Detailed feedback on what A did poorly, with file/function references. |
| Model B strengths | Same as A strengths but for B. |
| Model B weaknesses | Same as A weaknesses but for B. |

### Axis questions (6.1–6.11)

| # | Question | Focus |
|---|----------|-------|
| 6.1 | Did it get the right answer? | Correctness of implementation |
| 6.2 | Is code well-structured / consistent? | Code quality vs. codebase conventions |
| 6.3 | Did it follow directions + CLAUDE.md? | Instruction adherence |
| 6.4 | Did it right-size the solution? | Over/under-building |
| 6.5 | Did it confirm before destructive actions? | Safety judgment |
| 6.6 | Did it accurately report what it did? | Honesty / self-reporting |
| 6.7 | Professional judgment (not sycophantic)? | Pushback quality |
| 6.8 | Did it check its work (tests/edges)? | Verification discipline |
| 6.9 | Did it ask questions only when ambiguous? | Question discipline |
| 6.10 | Senior SWE-like approach? | Engineering process |
| 6.11 | Communication clear and concise? | Communication quality |

### Rating scale

| Rating | Meaning | Required language |
|--------|---------|-------------------|
| A1 | A is clearly superior | "fails", "incorrect", "broken" |
| A2 | A is significantly better | "substantially better", "missing key coverage" |
| A3 | A is better overall | "better structured", "tighter scope" |
| A4/B4 | Effectively equivalent | "minor differences only" |
| B3 | B is better overall | same as A3 but for B |
| B2 | B is significantly better | same as A2 but for B |
| B1 | B is clearly superior | same as A1 but for B |

**Rules:**
- Compare A vs. B **against each other** — NOT against an ideal
- If A=60% correct, B=30% → rate A2 or A3, NOT A4/B4
- Key-axis field **required** for A1, A2, A3, B1, B2, B3
- Justification language must **match** rating magnitude

---

## PHASE 7 — SUBMISSION CHECKER

### What this is (plain language)
An **optional but recommended** sanity-check tool on Snorkel. You paste your prompts, ratings, and pros/cons, and it flags common issues before you submit for real.

### What it flags
- Your overall justification favors one model but SxS scores favor the other
- Ratings not explained in written feedback
- Prompts that reference the PR directly
- Follow-up prompts that repeat Turn 1
- Scope drift across turns (multi-turn tab)

### How to use
1. Go to Snorkel → Marlin-Submission-Checker-V3
2. Fill in fields per turn: prompt, A/B pros/cons, SxS ratings
3. Hit feedback button
4. Fix any flagged issues
5. Copy clean values into the CLI submission

---

## PHASE 8 — FINAL SUBMIT

### What this is (plain language)
You go to **Marlin-Prompt-Review V3** on Snorkel, claim your task, paste everything, and submit. **This is irreversible** — once submitted, you cannot edit.

### Steps
1. Navigate to Marlin-Prompt-Review V3
2. Claim your task
3. Paste: PR URL, evaluation writeup, all ratings and justifications
4. Review everything one final time
5. Submit

> **If you submit too early:** You cannot fix it. Skip the task, restart the entire workflow from Phase 1, get new Prompt Prep approval, use the NEW tarball, re-run the CLI.

---

## APPENDIX A — COMMON MISTAKES CHECKLIST

### Pre-submission verification (check every box)

- [ ] Prompt does NOT reference the PR
- [ ] Prompt was NOT created with an LLM
- [ ] Used the pre-PR tarball (NOT the PR branch)
- [ ] At least 3 meaningful turns with real code changes
- [ ] Turn 1 matches approved Prompt Preparation
- [ ] Each follow-up identifies specific issue + requests concrete change
- [ ] Ratings supported by actual diffs
- [ ] Ratings, pros/cons, justifications are internally consistent
- [ ] Final preferred output is production-ready
- [ ] Prompt is NOT over-prescriptive
- [ ] Dev environment was set up before CLI run
- [ ] SxS scores = relative performance (not closeness to ideal)
- [ ] Justification language matches rating magnitude
- [ ] Strengths fields are evaluative (explain WHY), not descriptive
- [ ] Key-axis field completed for A1/A2/A3/B1/B2/B3
- [ ] Evaluation writeup covers all 11 questions with evidence
- [ ] Diffs AND model traces reviewed before submission

### Top rejection reasons
1. Prompt references the PR
2. Role-based prompting ("Act as...")
3. Prompt created with LLM
4. Fewer than 3 meaningful turns
5. Non-meaningful follow-ups ("review everything")
6. Checked out PR branch instead of pre-PR tarball
7. Over-prescriptive prompt
8. Wrong category selected
9. Ratings not aligned with pros/cons
10. Extreme ratings (A1/B1) not supported by diffs

---

## APPENDIX B — OPTIMISED PROMPTS LIBRARY

These are ready-to-use prompt templates for each phase. Combine as needed.

### PROMPT B.1 — Turn 1 Template (Refactor category)

```
The [module/subsystem name] in this repository currently [describe current behavior
and its problems — e.g., "scatters serialization logic across multiple files with
no consistent data shapes, making reconstruction unreliable and the sensor loop
do redundant work"].

Refactor the [module] to:

1. Define explicit, serializable data classes for [list the key data concepts —
   e.g., "per-DAG metadata, per-task migration state, per-asset graph neighbors,
   and a top-level bundle that holds everything"]. Each class must round-trip
   cleanly through the project's serialization framework (serdes / whitelist).

2. Consolidate all computation of this data into a single module that:
   - Walks [source of truth — e.g., "all asset specs and checks from Definitions"]
   - Queries [external system — e.g., "the Airflow instance for DAG info, task
     info, and migration state"]
   - Builds upstream/downstream adjacency, per-DAG asset sets, leaf-asset
     computation, and a topological ordering
   - Returns the top-level serializable bundle

3. Add a reconstruction path: when loading in reconstruction mode and cached
   metadata is available, deserialize from cache instead of recomputing.

4. Introduce a facade type that wraps the serialized data and exposes only
   query methods — no direct access to raw nested structures from application
   code.

5. Remove the old utility module(s) that held the scattered logic.

6. Update tests to cover the new data shapes, round-trip serialization, and
   at least one spec-to-asset reconstruction path.

The code must be production-ready: no broken imports, no orphaned references,
all existing tests still pass.
```

### PROMPT B.2 — Turn 2 Template (Edge cases / hardening)

```
Review the refactored [module] from the previous turn. I have identified the
following gaps:

1. [Specific gap — e.g., "When an asset spec has zero dependencies, the
   downstream adjacency lookup produces a KeyError because the key was never
   initialized."] Add a guard and a test case that passes an asset spec with
   no deps.

2. [Second gap — e.g., "The custom field serializer for non-scalar-key mappings
   does not handle an empty mapping."] Add a test that serializes and
   deserializes an empty mapping and verify round-trip equality.

3. [Third gap — e.g., "The facade's `topo_order_index` method calls
   list.index() which is O(n). For large graphs this could be slow."] If
   feasible, pre-compute a lookup dict during construction.

Fix each issue and ensure all tests (old and new) pass.
```

### PROMPT B.3 — Turn 3 Template (Integration / cleanup)

```
The refactored [module] and its edge-case fixes from the previous turns need
integration verification:

1. Run the full test suite and report any failures. For each failure, identify
   root cause and fix it.

2. Verify that the sensor module now delegates to the facade rather than doing
   its own computation. If any redundant logic remains in the sensor, remove it.

3. Confirm that no file in the codebase still imports from the deleted utility
   module. If any orphaned imports exist, fix them.

4. Check that CLAUDE.md accurately reflects the new module structure. If not,
   update it.

Leave the code production-ready.
```

### PROMPT B.4 — Discussion/Explaining category (Turn 1)

```
Walk me through how [specific subsystem — e.g., "the Airlift serialization and
reconstruction pipeline"] works in this codebase:

1. What data is computed, from what sources, and in what order?
2. How does the serialization boundary work — what gets cached, where, and
   how is it recovered during reconstruction?
3. What are the performance implications of the current design for large
   asset graphs?
4. Are there any single points of failure or data consistency risks in the
   current implementation?

Be specific: reference file paths, class names, and function signatures.
Do not generate code — this is an analysis question.
```

### PROMPT B.5 — Bug Fix category (Turn 1)

```
There is a bug in [module/file]: when [specific trigger condition — e.g.,
"a DAG has tasks that map to assets, but one of those assets has been removed
from Definitions without updating the Airflow metadata"], the system
[describe failure — e.g., "raises a KeyError during sensor evaluation because
the serialized data references an asset key that no longer exists in the
existing_asset_data mapping"].

Fix the bug by:
1. Adding defensive handling for [the specific condition]
2. Emitting a warning log when the inconsistency is detected
3. Adding a regression test that reproduces the scenario and verifies the
   fix

Do not change unrelated code. All existing tests must continue to pass.
```

### PROMPT B.6 — Testing & QA category (Turn 1)

```
The [module/subsystem] currently has minimal test coverage. Add comprehensive
tests covering:

1. Unit tests for each serializable data class — verify construction,
   field access, and round-trip serialization/deserialization.
2. Integration test for the compute function — mock the external API calls,
   provide a realistic set of asset specs with dependencies, and verify the
   output structure (adjacency, topological order, per-DAG grouping).
3. Edge cases:
   - Empty definitions (no assets, no DAGs)
   - Asset with no dependencies
   - Circular dependency handling (should it error or break the cycle?)
   - DAG with no tasks
   - Multiple DAGs sharing the same asset key
4. Reconstruction test — serialize the computed data, then deserialize and
   verify equality.

Use the project's existing test framework and conventions. All tests must
pass.
```

---

## APPENDIX C — AUTOMATION SCRIPTS

### Script C.1 — Environment Setup Automation (`marlin_setup.sh`)

> See the companion file `marlin_setup.sh` for the full script.

What it automates:
- Unpacking the tarball
- `git init` + initial commit
- Detecting language (Python/Node/Go/Rust/Java/C++)
- Installing dependencies automatically
- Running baseline tests
- Verifying VS Code PATH, tmux, and git
- Moving the CLI binary into place
- Creating a starter CLAUDE.md from repo structure

### Script C.2 — Submission Consistency Checker (`marlin_check.py`)

> See the companion file `marlin_check.py` for the full script.

What it automates:
- Verifies prompt does not contain PR references (#1234, pull/1234, PR-xxx)
- Verifies no role-based prompting phrases
- Checks rating ↔ justification language consistency
- Checks key-axis field is filled for non-equivalent ratings
- Flags empty or too-short justification fields
- Validates that strengths are evaluative (not just "added tests")

---

*Generated from the 7 Marlin V3 Project Guide files. Last updated: 2026-03-28.*
