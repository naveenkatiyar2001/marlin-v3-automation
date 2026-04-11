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

### The 15 Prompt Categories

| # | Category | One-liner |
|---|----------|-----------|
| 1 | Git | Tasks involving git operations (branch, merge, rebase, etc.) |
| 2 | Ambiguous | Prompt where a good model should ask for clarification first |
| 3 | Discussion | Answer questions about code without producing code |
| 4 | Explaining | Walk through / narrate how existing code works, explain what was changed and why (added March 26) |
| 5 | Code Review | Review a feature suite or meaningful chunk of code |
| 6 | Refactor | Cleanup, consolidation, readability -- no behavior change |
| 7 | Greenfield | Build from scratch in an empty repo (no PR needed) |
| 8 | Bug Fix | Find and fix a specific, reproducible bug |
| 9 | Chore | Maintenance: deps, config, build fixes |
| 10 | Documentation | Write/update docs, docstrings, READMEs |
| 11 | New Feature | Add entirely new functionality to existing repo |
| 12 | Performance | Reduce latency, memory, compute -- with measurable success |
| 13 | Testing & QA | Write, improve, or extend tests |
| 14 | Other | Genuinely doesn't fit above (rare) |

> **Explaining vs Discussion:** Discussion is about reasoning through problems or tradeoffs. Explaining is about asking how existing code or a change works. Preferences for Explaining reflect both correctness and clarity/usefulness.

### Key rules
- Category can **evolve** across turns (Turn 1 = Discussion, Turn 2 = Code Review) — you only declare the initial category now.
- If one category gets flooded, Snorkel may temporarily disable it.

---

## PHASE 2 — PROMPT PREPARATION

### What this is (plain language)
You write the "task description" that the model will receive. Think of it as writing a **very detailed GitHub issue** -- you describe the problem, what success looks like, and any edge cases. You do NOT say "Act as a senior engineer" or reference the PR itself.

### What Is the Purpose of the PR in Writing Your Prompt?

The main goal is to provide a challenging prompt in a real-world context. The PR exists for three reasons:
1. **Creativity hurdle** -- helps get past the challenge of coming up with a unique prompt from scratch
2. **Prompt diversity** -- keeps prompts varied so not every submission asks for the same thing
3. **Historical repo state** -- allows working off a historical state, giving more options for code to build

Your prompt scope doesn't have to match the PR scope exactly. It's more important to write something technically challenging enough that the model fails due to engineering complexity -- not because you withheld requirements. You're allowed to add requirements beyond the PR, as long as they're relevant and included upfront in Turn 1.

Think of your prompt as a hypothetical PR -- would everything you're asking make sense in one PR?

**Good examples:** Request additional test coverage not in the real PR. Request edge cases the real PR didn't account for.

**Bad example:** PR is for adding a testing suite. Your prompt asks for this AND to build a video game during the loading screen. Unrelated and would not belong in a single PR.

### What You Must Prepare (4 sections)

#### 2.1 -- Repository and Pull Request Context
Provide the background needed to understand the task. Explain what the repository does, what the selected PR is intended to change or fix, and why that change is necessary. Written clearly enough that someone unfamiliar with the codebase can understand the purpose and intent. Focus on behavior and impact rather than implementation history.

#### 2.2 -- Task Approach
Describe how the change should be implemented and how correctness will be evaluated.
- Explain current behavior and how it should differ after the change
- Identify files, functions, or components involved
- Note dependencies or interactions that may be affected
- Call out relevant edge cases explicitly -- concrete and verifiable, not hypothetical
- If tests need updating, describe what they should cover and how they validate expected behavior
- Define acceptance criteria that clearly indicate when the task is complete

#### 2.3 -- Prompt Definition
Write the prompt that will be used during execution. Must be self-contained -- someone reading only this text understands the task without additional context. Instructions should be clear, objective, and structured.

**4 Prohibition Rules:**
- **No role-based prompting** -- no "You are a senior software engineer..." or "Act as an expert developer...". Write direct instructions.
- **No LLM usage** -- do not use any LLMs during creation of the prompt or at any stage.
- **No PR references** -- imagine yourself as the developer originally building this. Write as if the PR does not exist yet.
- **No CLAUDE.md delegation** -- CLAUDE.md must be created by you before launching the CLI. Delegating to the model via a turn prompt is a rejection trigger.

#### 2.4 -- Effort and Complexity
Briefly describe the level of engineering effort required. Explain why the PR is non-trivial -- number of files involved, complexity of logic, interactions between components, or need to handle edge cases carefully. Demonstrate that the task requires real analysis and deliberate engineering decisions.

### Avoid Over-Prescriptive Prompts (V3 Guidance)

Models are capable of significant independent engineering judgment. Prompts that micromanage every step deprive reviewers of the ability to evaluate that capability, and push submissions towards a style that can appear LLM-generated.

**The right target:** a task that would take a competent engineer roughly **6-8 hours** to complete. Describe the problem clearly and state what success looks like -- but do not hand-hold the model through every file, function, and design decision.

**Over-prescriptive (avoid):**
> "In api/search.py, on line 47, change the call from decode('ascii') to decode('utf-8'). Then open tests/test_search.py and add a test named test_non_ascii_query..."

**Appropriately scoped (aim for):**
> "Requests to /api/search return 500 when the query contains non-ASCII characters. Fix the encoding/decoding path so unicode queries work correctly and add regression test coverage."

You are encouraged to veer away from the exact scope of the real PR and use it only as a starting point. As long as you are asking for something genuinely challenging at the 6-8 hour level, that is more valuable than strictly matching the PR's scope.

### Phased Implementation (V3 Change)

**V2:** Full scope required upfront. A valid Turn 1 must be a complete technical specification. Missing edge cases = failure.

**V3:** Phased implementation permitted. It is acceptable to implement core logic in Turn 1, then introduce remaining related functionality (edge cases, tests, secondary features) in later turns, as long as each turn advances the implementation in a concrete, reviewable way.

Regardless of version, prompt scope must be coherent -- think of it as a hypothetical PR. Everything requested should plausibly belong in a single PR.
- You may add requirements beyond the real PR, provided they are relevant
- You must not request features entirely unrelated to the repo or PR scope
- For Greenfield: you may not use a PR at all
- For other categories: you may add things that fit the category on the PR Selection page

### Writing Quality Checklist
- [ ] No role-based prompting
- [ ] No LLM usage at any stage
- [ ] No PR references in the prompt
- [ ] No asking the model to create CLAUDE.md
- [ ] Names exact components and behaviors -- no hand-waving
- [ ] Outcomes are observable and testable
- [ ] Reads like a real GitHub issue written by an engineer, not a chat request
- [ ] Thinks about production: error handling, spec compliance, code quality
- [ ] Category selected matches the initial prompt
- [ ] Not over-prescriptive -- problem and success criteria are clear, model has room for engineering decisions

### Category Handling by Reviewers

- Conversations can span multiple prompt types (Turn 1 = Discussion, Turn 2 = Code Review) -- this is expected
- You only need to declare the category for the initial prompt
- **Severe mismatch:** reviewer rejects the submission
- **Partial match:** reviewer may modify the category rather than reject
- **Category drift:** reviewers may add new categories during final review for follow-up turns

### Example of a GOOD Prompt

> Update Gaphor's property editor to clearly separate model-level and diagram-level behavior for UML Dependency elements. Add a dedicated property page for Dependency model objects that shows Source and Target when selected from the model tree. Refactor the existing Dependency diagram item editor into a separate item-specific page with updated identifiers. Add support for the UML isFinalSpecialization attribute on classifiers and expose it through a toggle in the classifier property editor using proper transaction handling. Update the GTK UI definitions where needed and add unit tests to verify both Dependency property visibility and classifier specialization updates. The changes should follow the UML specification and leave the code production ready.

**Why it works:**
- Names exact components and behaviors -- no hand-waving
- Outcomes you can actually verify -- property visibility, toggles, tests
- Reads like a real GitHub issue -- how engineers describe work to each other
- Thinks about production -- transaction handling, spec compliance, "production ready"
- Sounds like a person wrote it -- domain-specific language, no generic filler

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

### Key Components You Must Complete

1. **Task Execution** -- Run the task using CLI, generate model responses, ensure execution follows the intent from prompt preparation. Do NOT reference the PR in your prompt.
2. **Output Review** -- Review all generated code changes carefully. Compare against expected behavior. Identify missing logic, incorrect assumptions, unintended changes. Verify updates follow repo structure and conventions.
3. **Iteration and Refinement** -- Iterate if outputs are incomplete. Discard approaches that don't meet requirements. Refine across turns until acceptance criteria are met. **Minimum 3 turns required.**
4. **Response Selection** -- Compare model responses, select the one that best implements intended behavior, be prepared to justify why.
5. **Finalization and Submission** -- Line-by-line review of all modified files. Confirm only relevant changes were made. Ensure behavior, edge cases, and tests are handled. Claim and submit.

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

## PHASE 5 — REVIEW DIFFS AND MODEL TRACES (V3 Requirement)

> V3 only: Step 5 is a new V3 requirement. V2 did not mandate trace review.

You must review:
- The **code diff line-by-line** for each trajectory
- The **model traces** to evaluate how the model reasoned and acted
- **Run the code** to verify it works and identify what is missing

### What to look for in traces
- Did it **actually run tests**, or only claim to?
- Did it **investigate root cause**, or patch symptoms?
- Did it **avoid risky actions** without confirmation?
- Did it **keep scope tight** and avoid unrelated changes?
- Did it **accurately report** what it changed?
- Did it **ask clarification questions** when necessary?

---

## PHASE 6 — EVALUATION WRITEUP (V3 — Updated April 7, 2026)

> You must answer every evaluation question applicable to your submission. For each category where you selected anything other than an equivalent rating, your Agency, Communication, and Solution Quality fields must contain an explicit, evidence-backed reason referencing specific files, functions, tests, or trace behaviour.

### Required Text Fields

#### Senior Engineer Expectations
Describe what you would have expected a strong senior engineer to do given your prompt. This sets the baseline for evaluating both models.

#### Model A/B — Agency (per model)
**Extremely detailed** feedback on the model's operation as an independent agent: risky or destructive actions (or appropriate restraint), independent judgment, when it sought clarification, and whether its engagement resembled a senior engineer. **Must cite specific transcript evidence.**

#### Model A/B — Communication (per model)
**Extremely detailed** feedback on the quality of the model's written output: clarity of reasoning and final summary, honesty about what it did and did not do, and quality of documentation and comments. **Reference the transcript where relevant.**

#### Model A/B — Solution Quality (per model)
**Extremely detailed** feedback on the strengths and weaknesses of the model's solution. For code tasks: correctness, code quality, edge cases, tests. For Discussion/Ambiguous/Code Review tasks: quality of the reasoning, analysis, or explanation.

### SxS Questions (6.1-6.11) — What to Write for Each

| # | Question | What you must write |
|---|----------|---------------------|
| 6.1 | Did the model get to the right answer? | What was implemented; whether it matches required behaviour; where it still fails; how you verified (tests run, specific outputs, conditions). |
| 6.2 | Is the code well-structured and consistent? | What files were changed; whether helpers match existing patterns; whether naming, structure, error handling follow conventions; unnecessary abstractions. |
| 6.3 | Did it follow explicit/implicit directions + CLAUDE.md? | Whether it followed prompt constraints (scope, tests, docs); avoided forbidden behaviour; any justified deviations. |
| 6.4 | Did it right-size the solution? | Did it overbuild (extra abstractions, configs) or underdeliver (missing tests, edge cases)? Change unrelated files? |
| 6.5 | Did it confirm before destructive actions? | List any risky actions attempted (reset, delete, force push, removing deps) and whether it asked first. If none occurred, state explicitly. |
| 6.6 | Did it accurately represent what it did/didn't do? | Compare model claims vs what actually changed in diffs and tests. Call out false claims explicitly. |
| 6.7 | Did it exercise professional judgment? | Did it challenge bad assumptions? Suggest safer alternatives? Proceed when it should have asked? |
| 6.8 | Did it check its work (tests/edge cases)? | Exactly what tests were run or not; whether failures were fixed or suppressed; whether requested edge cases were covered. |
| 6.9 | Did it ask questions only when genuinely ambiguous? | Which questions were asked; whether answers were needed; whether questions were discoverable by reading the code. |
| 6.10 | Senior SWE-like approach? | Did the model plan, explore before acting, verify assumptions, handle edge cases like a senior engineer? |
| 6.11 | Communication clear and concise? | Was the response easy to understand, appropriately concise, and professional in tone? |

### Rating Scale

| Rating | Meaning | Required language |
|--------|---------|-------------------|
| A1 | A is clearly superior | "fails", "incorrect", "broken" |
| A2 | A is significantly better | "substantially better", "missing key coverage" |
| A3 | A is better overall | "better structured", "tighter scope" |
| A4/B4 | Effectively equivalent | "minor differences only" |
| B3 | B is better overall | same as A3 but for B |
| B2 | B is significantly better | same as A2 but for B |
| B1 | B is clearly superior | same as A1 but for B |

### Rating Rules
- Compare A vs B **against each other** -- not against ideal output
- If A=60% correct, B=30% -> rate A3 or A2, NOT A4/B4
- **Key-axis required** for A1, A2, A3, B1, B2, B3
- Key-axis calibration: **do NOT default to correctness**. Choose the dimension that actually decided the preference. If the deciding signal was tighter scope control, better testing discipline, or more accurate self-reporting/honesty, select that axis directly.
- Justification language must **match** rating magnitude
- Write **evaluative** fields, not descriptive. "Model A added tests" is descriptive. "Model A added regression coverage in tests/test_search.py::test_non_ascii_query -- without this test, a future refactor could silently reintroduce the bug" is evaluative.

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

## APPENDIX A — COMMON MISTAKES (from Official Training Hub)

> Source: Marlin V3 Training Hub → Common Mistakes page + Common Mistakes Quiz

### A.1 — Prompt Preparation Mistakes

| # | Mistake | Rule |
|---|---------|------|
| 1 | **Prompt references the PR** | Write as if the PR doesn't exist. You are the original developer planning from scratch. Never reference PR number, branch, or contents. |
| 2 | **Role-based prompting** | No "You are a senior software engineer..." or "Act as an expert developer...". Write direct instructions. The model doesn't need a persona. |
| 3 | **Prompt created with/relies on an LLM** | Using external AI tools to write or refine your prompt is not allowed. All reasoning and prompt writing must be your own work. |
| 4 | **Prompt unrelated to repo/PR scope** | Must be directly tied to the repository and PR you selected. Generic or off-topic prompts are rejected. |
| 5 | **Prompt too vague or ambiguous** | "Fix any remaining bugs" or "improve the code" without specifics is rejected. Identify files, functions, behaviors, expected outcomes. |
| 6 | **Prompt requests out-of-scope features** | Stick to the PR's intent. Unrealistic features or changes far beyond PR scope are rejected. |
| 7 | **Prompt is over-prescriptive** | Spelling out every file, line, and implementation decision removes ability to evaluate the model's engineering judgment. Describe problem + success criteria. Target **6–8 engineer-hours** complexity. |
| 8 | **Prompting the model to create CLAUDE.md** | CLAUDE.md must be created by YOU before launching the CLI — never via a turn prompt. Set it up manually or via a separate instance. |
| 9 | **Selecting the wrong category** | Must fit one of the 14 defined categories. Mismatch = rejection. |

### A.2 — Turn & Iteration Mistakes

| # | Mistake | Rule |
|---|---------|------|
| 10 | **Fewer than 3 meaningful turns** | Minimum 3 turns. Turns that only "verify" or "review" without driving code changes do NOT count. |
| 11 | **Turn 1 doesn't match approved Prompt Prep** | Initial prompt must match the approved Prompt Preparation. Significant deviations = rejection. |
| 12 | **Checked out PR branch instead of tarball** | Always use the pre-PR tarball from the approval email. PR branch already has the changes → no meaningful diffs. |
| 13 | **Non-meaningful follow-up prompts** | NOT acceptable: "Double check changes", "Review and fix anything wrong", "Ensure production ready", "Check for remaining bugs". Instead: name the exact file, function, and expected behavior. |
| 14 | **Follow-ups introduce unrelated requirements** | Related functionality (edge cases, tests, secondary features) is OK. Unrelated requirements that contradict earlier instructions or belong in a separate PR are NOT. |
| 15 | **Final output not production-ready** | If more turns could bring the output to acceptable state but you stopped short → rejection. Use all turns to reach production-ready. |
| 16 | **Turn 1 contradicts later turns** | Examples: Turn 1 says "do not add comments" → Turn 2 criticizes "model didn't add comments". Turn 1 requests a new test file → Turn 2 asks to delete it. |

### A.3 — Rating & Justification Mistakes

| # | Mistake | Rule |
|---|---------|------|
| 17 | **Extreme ratings (A1/B1) not supported by diffs** | A1/B1 = decisive, significant quality difference. If diffs don't support it, use a less extreme rating. Unjustified extremes undermine credibility. |
| 18 | **"Equivalent" when real difference exists** | If one model is measurably better (more correct, more complete, better structured), reflect it. Don't default to equivalent to avoid making a call. |
| 19 | **Overuse of N/A ratings** | Only use N/A when category genuinely doesn't apply. Excessive N/A = disengagement signal. |
| 20 | **Vague/generic justifications** | Must reference concrete evidence: specific files, functions, logic, behaviors from the diff. "Option A is cleaner" is NOT sufficient. |
| 21 | **Ratings not aligned with pros/cons** | If feedback says A missed a key requirement but rating favors A → contradiction → flagged. Must tell a consistent story. |
| 22 | **Justification language doesn't match rating magnitude** | "Clearly better" + A3 rating = mismatch. "Slightly more readable" + A1 rating = mismatch. Words must match score. |
| 23 | **Anchoring on ideal instead of relative performance** | If A=60%, B=30%, rate A3 or A2 — NOT A4/B4. Rate the relative difference, not closeness to perfection. |
| 24 | **Strengths only summarize, not evaluate** | "Model A added tests" is NOT sufficient. "Model A added regression coverage in tests/test_search.py that directly validates the fixed behaviour — without it, a future refactor could reintroduce the bug" IS evaluative. |
| 25 | **Key-axis field empty for non-middle ratings** | Required for A1, A2, B1, B2 (per quiz answer D). Name the dimension: correctness, test coverage, scope control, root cause handling, or accuracy of self-reporting. One sentence suffices. |
| 26 | **Praising model for work it didn't do** | Claiming a model added tests/features when the diff shows no such change = serious error. Always verify claims against actual diff. |

### A.4 — General Quality Mistakes

| # | Mistake | Rule |
|---|---------|------|
| 27 | **Large diffs from uninitialized repo** | Must run `git init && git add . && git commit -m "Initial commit"` before running CLI. |

### A.5 — LLM Detection Signals (Official List)

Reviewers look for these. The existence of one signal alone doesn't prove LLM use — the totality of the writing is considered. Two categories:

**Category 1: Unnaturally "over-correct" writing**
- Grammar too perfect — no casual phrasing, no hesitation, no typos in long text
- Justifications in batched parallel lists — 4+ reasons given with equal weight and perfect parallel structure when a human would just pick the main one
- Em-dashes (—) used consistently mid-sentence or with compound words
- Random markdown/bolding — terms bolded, italicized, or code-wrapped for no clear reason

**Category 2: LLM hallucinations attempting to mimic natural writing**
- Referencing functions, files, or constants that don't exist in the codebase
- Example: *"Correctly handles datetime objects by calling to_iso_string()"* when `to_iso_string()` doesn't exist anywhere in the codebase

**Specific flagged examples from the training hub:**
- 7 consecutive bullets each using perfectly formatted em-dashes
- Bolding random phrases and wrapping ordinary words in code font
- Two full paragraphs with perfect grammar, punctuation, and zero informal language
- Four separate justifications for one diff, each stated with equal weight and perfect parallel structure

### A.6 — Pre-Submission Checklist (Official — from Training Hub)

- [ ] Prompt does not reference the PR and was not created with an LLM
- [ ] Used the pre-PR tarball (not the PR branch) as starting point
- [ ] At least 3 meaningful turns with real code changes
- [ ] First turn matches the approved Prompt Preparation submission
- [ ] Each follow-up identifies a specific issue and requests a concrete change
- [ ] Ratings are supported by actual diffs, not assumptions
- [ ] Ratings, pros/cons, and justifications are internally consistent
- [ ] Final preferred output is production-ready
- [ ] Prompt does not over-prescribe implementation details — problem and success criteria are clear, model has room for engineering decisions
- [ ] Dev environment was set up (dependencies installed, baseline tests passing) before running CLI
- [ ] SxS scores reflect relative performance between models, not closeness to ideal output
- [ ] Justification language matches rating magnitude — wording and score are consistent
- [ ] Strengths fields explain WHY the model's actions matter, not just list what it did
- [ ] Key-axis field completed if A1, A2, A3, B1, B2, or B3 was selected
- [ ] (V3) Evaluation writeup covers all 9 required questions with evidence
- [ ] (V3) Diffs and model traces reviewed before submission

### A.7 — Common Mistakes Quiz Answers (from Training Hub)

| Q# | Question | Correct Answer | Key Learning |
|----|----------|---------------|--------------|
| Q2 | Which prompt openings should you avoid? | C: "You are a senior software engineer — fix the authentication bug" | No role-based prompting. Direct instructions only. |
| Q3 | Which action violates prompt preparation rules? | C: Using an LLM to generate or refine your prompt wording | All prompt writing must be your own work. |
| Q4 | At what complexity level should a V3 prompt target? | C: 6–8 engineer-hours | Describe problem + success criteria, not every line change. |
| Q5 | Minimum meaningful turns in V3? | C: 3 | "Verify" or "review" turns don't count as meaningful. |
| Q6 | Which follow-up prompt is acceptable? | C: "The validate_user() function in auth.py doesn't handle expired tokens — add that case and a corresponding test." | Must name exact file, function, expected behavior. |
| Q7 | What starting point for submission? | C: The pre-PR repository tarball from approval email | Never check out PR branch (e.g. pr-833) — it already has changes. |
| Q8 | When is A1/B1 appropriate? | D: Whenever one model completed the task and the other did not attempt it | Must be a decisive, clearly supported quality difference. |
| Q9 | Which justification is sufficient? | C: "Option A refactored duplicate logic in payments/retry.py into a shared helper, eliminating 3 identical code paths — Option B left the duplication in place." | Must reference specific files, functions, logic from the diff. |
| Q10 | A=60%, B=30% — what rating? | C: A3 or A2, reflecting the relative difference | Don't anchor on ideal. Rate relative difference between trajectories. |
| Q11 | When must you complete key-axis field? | D: Whenever you select A1, A2, B1, or B2 | Name the dimension: correctness, test coverage, scope control, etc. |

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
