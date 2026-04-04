# MARLIN V3 — CURSOR-NATIVE AUTOMATION (PHASE 1 + PHASE 2)

> This file is the single source of truth for Phase 1 (PR Selection) and Phase 2 (Prompt Preparation).
> Cursor reads this file, fetches REAL data using `gh` CLI, and handles everything directly.
> Python is used only for clipboard capture and prompt validation. All GitHub data fetching and analysis is done by Cursor via `gh` CLI.

---

## HOW TO USE

Ask Cursor one of these:

| Trigger Prompt | Phase | What It Does |
|---|---|---|
| `[analyze-repos]` | 1 | Read `live_repos.json` -> fetch repo data via `gh` -> rank repos |
| `[analyze-prs]` | 1 | Read `live_prs.json` -> fetch PR data via `gh` -> rank PRs |
| `[full-analysis]` | 1 | Both repo + PR analysis sequentially |
| `[prepare-prompt]` | 2 | Fetch PR diff + code -> generate all Prompt Preparation fields |

---

## STEP 1: REPO ANALYSIS — `[analyze-repos]`

When triggered, follow these steps **exactly**:

### 1A. Read the clipboard data

```
Read file: phase-1-automation-cursor/data/live_repos.json
```

Extract all entries where `type == "repos"`. Each entry has `owner` and `repo` fields.

### 1B. Fetch real data for each repo using `gh` CLI

For EACH repo, run these shell commands:

```bash
# Repo metadata
gh repo view {owner}/{repo} --json name,description,primaryLanguage,stargazerCount,forkCount,defaultBranchRef,repositoryTopics,isArchived,licenseInfo,createdAt,updatedAt,diskUsage --jq '{
  name, description,
  language: .primaryLanguage.name,
  stars: .stargazerCount,
  forks: .forkCount,
  branch: .defaultBranchRef.name,
  topics: [.repositoryTopics[].name],
  archived: .isArchived,
  license: .licenseInfo.spdxId,
  created: .createdAt,
  updated: .updatedAt,
  sizeKB: .diskUsage
}'
```

```bash
# Count of open PRs (indicates activity)
gh pr list --repo {owner}/{repo} --state open --limit 1 --json number --jq 'length'
```

### 1C. Analyze each repo against MARLIN V3 CRITERIA

Apply these criteria to EACH repo:

**MUST HAVE:**
1. **Supported language:** Python, JavaScript/TypeScript, Go, Rust, Java, or C++
2. **Real engineering depth:** Complex architecture with multiple interacting components
3. **Test infrastructure:** Existing test suites (the model must maintain/extend them)
4. **Active development:** Recently updated

**SCORING FACTORS (weight 1-10):**

| Factor | Weight | What to check |
|---|---|---|
| Architectural complexity | 10 | Multi-module structure, deep abstractions |
| Test coverage | 8 | Existing tests that the model must work with |
| Cross-module coupling | 9 | Changes in one area cascade to others |
| Memorization risk | 7 | Stars > 80k = high risk, 1k-15k = sweet spot |
| Active PR volume | 6 | Recent complex PRs available |
| Setup complexity | 4 | Can be set up locally without exotic deps |

**What makes a model FAIL (we WANT this):**
- Cross-module refactors (change one file → must update 5+ others)
- Serialization/deserialization work (data shapes must match across boundaries)
- State management (tracking multiple interacting pieces)
- Migration/deprecation (old + new code paths coexisting)
- Complex test setup (mocks, fixtures, integration scaffolding)

**AVOID:**
- Docs-only repos
- Single-file utility libraries
- Repos with no tests
- Very small repos (< 100 files)
- Archived/unmaintained repos
- Repos with 100k+ stars (too memorized)

### 1D. Output format

```
## REPO ANALYSIS RESULTS

### 1. {owner}/{repo} — Score: {X}/100
**Summary:** {2-3 sentences}
**Language:** {lang} | **Stars:** {N} | **Memorization Risk:** {Low/Medium/High}
**Why good for Marlin:** {specific architectural patterns}
**Why model would fail:** {specific failure modes}
**Best prompt categories:** {from the 14 Marlin categories}
**Risk factors:** {any concerns}

... repeat for each repo ...

## FINAL RANKING
1. **BEST:** {repo} — {reason}
2. **Second:** {repo} — {reason}
3. **Avoid:** {repo} — {reason}
```

---

## STEP 2: PR ANALYSIS — `[analyze-prs]`

When triggered, follow these steps **exactly**:

### 2A. Read the clipboard data

```
Read file: phase-1-automation-cursor/data/live_prs.json
```

Extract all entries where `type == "prs"`. Each entry has `owner`, `repo`, and `pr_number`.

### 2B. Fetch real data for each PR using `gh` CLI

For EACH PR, run these shell commands:

```bash
# PR metadata
gh pr view {pr_number} --repo {owner}/{repo} --json title,author,state,additions,deletions,changedFiles,commits,reviews,labels,baseRefName,headRefName,body,createdAt,mergedAt,mergedBy,comments --jq '{
  title, author: .author.login, state, additions, deletions, changedFiles,
  commits: (.commits | length),
  reviews: (.reviews | length),
  labels: [.labels[].name],
  base: .baseRefName, head: .headRefName,
  body: .body,
  created: .createdAt, merged: .mergedAt,
  mergedBy: .mergedBy.login,
  comments: (.comments | length)
}'
```

```bash
# Changed files with paths and per-file stats
gh pr view {pr_number} --repo {owner}/{repo} --json files --jq '.files[] | "\(.path) [\(.additions)+/\(.deletions)-]"'
```

```bash
# Commit messages
gh pr view {pr_number} --repo {owner}/{repo} --json commits --jq '.commits[] | .messageHeadline'
```

```bash
# Review comments (what reviewers flagged)
gh pr view {pr_number} --repo {owner}/{repo} --json reviews --jq '.reviews[] | "\(.author.login): \(.body[0:200])"'
```

```bash
# OPTIONAL: Full diff (only for top 3 candidates after initial screening)
gh pr diff {pr_number} --repo {owner}/{repo}
```

### 2C. Analyze each PR against MARLIN V3 CRITERIA

**MUST HAVE (hard requirements):**
1. **Merged PR** — state must be MERGED (we need the "correct answer")
2. **~2+ hour human effort** — complex enough for a senior engineer to spend 2+ hours
3. **Multiple files** — PRs touching 5+ files across multiple directories preferred
4. **Both additions AND deletions** — refactors (add + delete) are MUCH harder than pure additions
5. **Clear description** — PR body must be detailed enough to write a Marlin prompt WITHOUT referencing the PR

**SCORING FACTORS:**

| Factor | Weight | What to check |
|---|---|---|
| Cross-module changes | 10 | Files in 3+ different directories |
| Refactor ratio | 9 | Balanced additions AND deletions (not just adds) |
| Review discussion | 8 | Reviewers flagged nuanced issues |
| Serialization/type work | 9 | Data shapes, schema changes, type alignment |
| Test changes included | 7 | PR modifies test files (model must handle both) |
| Clear PR description | 6 | Can derive a prompt without referencing the PR |
| Commit coherence | 5 | Single logical change (not multiple unrelated fixes) |

**What specific aspects make models FAIL:**
- **Cross-file consistency:** Model changes file A but forgets to update file B
- **Serialization boundaries:** Data format in producer doesn't match consumer
- **Removal + replacement:** Model adds new code but forgets to remove old code
- **Test updates:** Model fixes implementation but breaks/forgets tests
- **Import chain updates:** Moving code between modules breaks import paths
- **Edge case handling:** Reviewers caught edge cases the model would miss

**AVOID these PR types:**
- Docs/README-only changes
- Single-file, single-function fixes (too easy for model)
- Dependency bumps / config-only changes (too mechanical)
- PRs with no description (can't write a good prompt)
- Very old PRs where codebase has changed drastically since

### 2D. Prompt category matching

The PR should naturally fit one of the 14 Marlin categories:

| ID | Category | Best PR Type |
|---|---|---|
| 1 | Git | Version control operations |
| 2 | Ambiguous | Under-specified requirements |
| 3 | Discussion | Architecture decisions |
| 4 | Explaining | Code explanation tasks |
| 5 | Code Review | Review and critique |
| 6 | Refactor | **Restructuring existing code** |
| 7 | Greenfield | Building from scratch |
| 8 | Bug Fix | **Fixing broken behavior** |
| 9 | Chore | Maintenance tasks |
| 10 | Documentation | Writing docs |
| 11 | New Feature | **Adding new capability** |
| 12 | Performance | **Optimization work** |
| 13 | Testing/QA | **Writing/fixing tests** |
| 14 | Other | Anything else |

Categories in **bold** are the hardest for models and thus best for Marlin.

### 2E. Output format

```
## PR ANALYSIS RESULTS

### PR #{number} — "{title}" — Score: {X}/100
**Summary:** {2-3 sentences on what this PR does}
**Stats:** {files} files | +{additions} −{deletions} | {commits} commits | {reviews} reviews
**Directories touched:** {list}
**Cross-module:** Yes/No

**Why model would fail:**
- {specific reason 1, referencing actual file paths}
- {specific reason 2}
- {specific reason 3}

**Prompt feasibility:** {Can a clear Marlin prompt be written from this?}
**Best Marlin category:** {category name}
**Risk:** {too easy / too hard / setup issues / etc.}

... repeat for each PR ...

## FINAL RANKING

1. **BEST PR:** #{number} — "{title}"
   - **Score:** {X}/100
   - **Why:** {specific engineering reasons}
   - **Marlin category:** {category}
   - **Draft prompt direction:** {2-3 sentences describing what the prompt should ask, WITHOUT referencing the PR}

2. **Second best:** #{number} — {brief reason}

3. **Avoid:** #{number} — {brief reason}
```

---

## PHASE 1 NOTES

- ALL data must be fetched LIVE using `gh` CLI -- never use cached/memorized data
- Run commands with `--repo {owner}/{repo}` to target the correct repository
- If a `gh` command fails, note it and move on (don't block the whole analysis)
- For the BEST PR candidate, optionally fetch the full diff to understand code-level complexity
- The goal is to find a PR that will make Claude Opus 4.6 / Sonnet genuinely FAIL for engineering reasons, not due to ambiguity or unfair prompting

---
---

# PHASE 2 -- PROMPT PREPARATION -- `[prepare-prompt]`

> Phase 2 takes the selected repo + PR from Phase 1 and generates all the fields
> needed for the Snorkel Prompt Preparation form. Cursor fetches the actual PR diff,
> analyzes the code changes, and produces each form field.

## BEFORE YOU START

The user must provide:
- **owner/repo** (e.g. `dagster-io/dagster`)
- **PR number** (e.g. `24569`)

If not provided, check `phase-1-automation-cursor/data/live_prs.json` for the most recent entries.

---

## 3A. Fetch deep PR data

Run ALL of these commands for the selected PR. You need every piece of data to write accurate form fields.

```bash
# Full PR metadata including body
gh pr view {pr_number} --repo {owner}/{repo} --json title,author,state,additions,deletions,changedFiles,commits,reviews,labels,baseRefName,headRefName,body,createdAt,mergedAt,comments --jq '{
  title, author: .author.login, state, additions, deletions, changedFiles,
  commits: (.commits | length),
  reviews: (.reviews | length),
  labels: [.labels[].name],
  base: .baseRefName, head: .headRefName,
  body: .body,
  created: .createdAt, merged: .mergedAt,
  comments: (.comments | length)
}'
```

```bash
# Changed files with per-file stats
gh pr view {pr_number} --repo {owner}/{repo} --json files --jq '.files[] | "\(.path) (+\(.additions) -\(.deletions))"'
```

```bash
# Full diff (REQUIRED for Phase 2 -- you need to see the actual code changes)
gh pr diff {pr_number} --repo {owner}/{repo}
```

```bash
# Review comments (what reviewers flagged -- useful for edge cases)
gh pr view {pr_number} --repo {owner}/{repo} --json reviews --jq '.reviews[] | "\(.author.login): \(.body[0:300])"'
```

```bash
# Repo description (for Repo Definition field)
gh repo view {owner}/{repo} --json name,description,primaryLanguage,repositoryTopics --jq '{name, description, language: .primaryLanguage.name, topics: [.repositoryTopics[].name]}'
```

---

## 3B. Analyze the diff

After fetching all data, study the diff carefully to understand:

1. **What changed and why** -- what problem does this PR solve?
2. **Which modules/files interact** -- what are the dependency chains?
3. **What edge cases exist** -- what could go wrong if done incorrectly?
4. **What tests cover this** -- are there test files modified?
5. **What the reviewers flagged** -- what nuances did humans catch?

---

## 3C. Generate all Prompt Preparation form fields

Produce EACH of the following sections. Each section maps to a specific field on the Snorkel form.

### FIELD 1: Prompt Category

Select the SINGLE best-fit category from:

    Greenfield, Ambiguous, Git, Discussion, Explaining, Code Review,
    Refactor, Bug Fix, Chore, Documentation, New Feature, Performance,
    Testing and Quality Assurance, Other

Rules:
- Pick the category that matches the INITIAL prompt (Turn 1 only)
- Categories can evolve across later turns, but the initial one must be accurate
- If "Other", provide a short description in the next field

### FIELD 2: Prompt Category - Other (optional)

Only fill this if you selected "Other" above. One sentence describing the prompt type.

### FIELD 3: Repo Definition

Write 3-5 sentences explaining what this repository does. Cover:
- What the project is and its primary purpose
- The core architecture (what are the main modules/packages)
- What language and frameworks it uses
- Who uses it and why it matters

Write as if explaining to a colleague who has never seen this repo.

### FIELD 4: PR Definition

Write 3-5 sentences explaining what this specific PR changes and why. Cover:
- What problem or limitation existed before this PR
- What the PR does to address it
- Which parts of the codebase are affected
- What the impact is on the rest of the system

Do NOT reference the PR number or URL. Write as if describing the planned work, not a completed PR.

### FIELD 5: Edge Cases

List 3-6 concrete, specific edge cases the model needs to handle. Each edge case must:
- Name the specific file, function, or data path involved
- Describe what happens under that condition
- Explain why it is tricky (not obvious)

Bad edge case: "Handle empty input"
Good edge case: "When an asset spec has zero dependencies, the downstream adjacency lookup in the compute function produces a KeyError because the key was never initialized in the mapping -- the model needs to add a guard and initialize empty sets for assets with no deps."

### FIELD 6: Acceptance Criteria

List 4-8 concrete acceptance criteria. Each one must be:
- Verifiable (you can check if it is done or not)
- Specific (names files, functions, behaviors)
- Production-focused (not just "it works")

Format each as: "Done when [specific observable outcome]"

Example:
- "Done when all serializable data classes round-trip cleanly through the serdes framework without data loss"
- "Done when the sensor module delegates to the facade instead of computing its own data"
- "Done when the old utility module is fully removed and no imports reference it"
- "Done when existing tests pass and new tests cover the restructured data shapes"

### FIELD 7: Testing Setup

Output: "Yes" or "No"

This depends on whether the user has actually set up the repo locally. If unknown, output "Yes" with a note that the user must verify this before submitting.

### FIELD 8: Initial Prompt (THE CRITICAL FIELD)

This is the actual prompt text that will be given to the model. This is the most important field.

#### WRITING RULES (MANDATORY -- VIOLATION = REJECTION)

**ABSOLUTE PROHIBITIONS:**
1. NO em-dashes (U+2014, U+2013) and NO double-dashes ("--"). Use a comma, period, or split the sentence.
2. NO PR references. No PR numbers, branch names, or "this PR".
3. NO role-based prompting. No "You are a senior engineer" or "Act as".
4. NO over-prescriptive instructions. Describe the problem and success criteria, not "on line 47 change X to Y".
5. NO hand-holding. Do not walk through every step.
6. NO generic filler. No "ensure code quality" or "follow best practices" without specifics.

---

#### MARLIN V3 WRITING STYLE (from the official guide)

The prompt must read like a **real GitHub issue** written by an engineer. It should be:
- Clear, objective, and structured
- NOT conversational (avoid Slack-speak, slang, excessive informality)
- Imperative style is fine ("Update X. Add Y. Refactor Z.")
- Uses domain-specific vocabulary (name exact components, classes, files)
- Ends with production-readiness: **"Leave the code production ready."** or similar

**REFERENCE -- the official good prompt example:**
> Update Gaphor's property editor to clearly separate model-level and
> diagram-level behavior for UML Dependency elements. Add a dedicated
> property page for Dependency model objects that shows Source and Target
> when selected from the model tree. Refactor the existing Dependency
> diagram item editor into a separate item-specific page with updated
> identifiers. Add support for the UML isFinalSpecialization attribute
> on classifiers and expose it through a toggle in the classifier property
> editor using proper transaction handling. Update the GTK UI definitions
> where needed and add unit tests to verify both Dependency property
> visibility and classifier specialization updates. The changes should
> follow the UML specification and leave the code production ready.

Words like "clearly", "dedicated", "proper" ARE allowed (used in the example above).

---

#### ANTI-AI-DETECTION RULES (apply ON TOP of Marlin style)

These rules reduce AI detection scores WITHOUT breaking Marlin's style requirements.

**RULE 1: FORBIDDEN WORDS (instant AI flags)**
NEVER use: leverage, utilize, delve, holistic, synergy, paradigm, multifaceted,
tapestry, cutting-edge, state-of-the-art, at its core, plays a crucial role,
a testament to, in today's landscape, it's worth noting, it should be noted

Avoid (max 1 total): comprehensive, robust, seamless, facilitate, enhance,
streamline, optimize, foster, elevate, empower, harness, bolster, underscore,
encompasses, intricate, nuanced, overarching, aforementioned, subsequently,
meticulously, functionality, demonstrates, corresponding, straightforward

**RULE 2: FORBIDDEN TRANSITIONS**
Never: Additionally, Furthermore, Moreover, Consequently, In addition,
As a result, In light of, With that said, It is essential/crucial/vital,
Moving forward, This ensures, This enables, Not only...but also

**RULE 3: NO "THAT/WHICH" CLAUSE CHAINS**
BAD: "The computation that produces the records that get cached across..."
GOOD: "The computation produces records. Those get cached across..."
Max 2 sentences with "that [verb]" or "which [verb]" in the entire prompt.

**RULE 4: NO PREPOSITION STACKING (max 3 per sentence)**
BAD: "Move the logic out of load_defs.py into a module within the new package under core."
GOOD: "Move the logic out of load_defs.py. Put it in its own module in the new package."

**RULE 5: MIX SENTENCE LENGTHS**
Include at least 1 short sentence (under 10 words) and at least 1 longer one (20+ words).
Do not make every sentence 15-20 words. The Marlin good example ranges from 10 to 30.

**RULE 6: ADD HUMAN TEXTURE (without being conversational)**
Include at least 2 of these natural touches that keep the text from reading as robotic:
  - Conditional phrasing: "where needed", "when available", "if applicable"
  - A closing statement: "Leave the code production ready." or "The changes should follow..."
  - Parenthetical specificity: "(e.g. AssetKey, TaskHandle)"
  - "The changes should..." or "The code should..." declarative sentences
  - Domain-specific terms from the actual codebase

**RULE 7: NO EM-DASHES, EN-DASHES, OR DOUBLE-DASHES**
Use commas, periods, or split the sentence. No --, no —, no –.

**RULE 8: STRUCTURAL GUIDANCE**
- Open with 1-2 sentences describing what needs to change and why.
- Follow with specific instructions, organized by logical concern.
- End with verification and production-readiness.
- Use prose paragraphs, not bullet lists.
- Total length: 150-300 words.

---

**REQUIRED QUALITIES (from Marlin V3 guide):**
1. Names exact components, modules, classes, or subsystems from the codebase.
2. Outcomes are observable and testable (verifiable criteria).
3. Targets 6-8 engineer-hours of complexity.
4. Self-contained: someone reading only this text understands the full task.
5. Reads like a real GitHub issue, not a chat request to an AI.
6. Thinks about production: transaction handling, spec compliance, error handling.
7. No role-based prompting, no PR references, no LLM usage.

**SELF-CHECK BEFORE SUBMITTING:**
  [ ] Does it name exact components and behaviors?
  [ ] Are outcomes observable and testable?
  [ ] Does it read like a real GitHub issue?
  [ ] Does it end with production readiness ("Leave the code production ready.")?
  [ ] No em-dashes, double-dashes, or AI transition phrases?
  [ ] No more than 2 "that [verb]" clauses in the whole text?
  [ ] Sentence lengths vary (some short, some long)?
  [ ] No forbidden AI words (leverage, utilize, delve, etc.)?

---

## 3D. Post-generation quality check

After generating all fields, run the validator (v3 with deep structural AI detection):

**Step 1: Auto-humanize first** (fixes contractions, formal words, transitions, dashes):
```bash
python3 phase-1-automation-cursor/prompt_validator.py --humanize "PASTE_THE_PROMPT_TEXT_HERE"
```

**Step 2: Validate the result** (21 checks including deep structural analysis):
```bash
python3 phase-1-automation-cursor/prompt_validator.py "PASTE_THE_HUMANIZED_TEXT"
```

The v3 validator checks 21 dimensions:
- Marlin V3 rules (em-dashes, double-dashes, PR refs, role prompting, over-prescriptive, word count)
- Surface AI signals (signature words, transitions, adverbs, starters, passive voice, contractions, variety, commas, lists, gerunds)
- Deep structural signals (that/which clause density, imperative parallelism, preposition stacking, formality uniformity, sentence template uniformity, AI qualifier words)
- Estimates an AI detection score (0-100). Target: below 10.

If the score is above 10 after auto-humanize, the problem is structural (sentence parallelism, template repetition). You must manually restructure, not just swap words. Follow the Human Voice Protocol rules above.

---

## 3E. Output format

Present all fields in this exact structure (ready to copy-paste into Snorkel):

```
============================================================
MARLIN V3 -- PROMPT PREPARATION (READY TO SUBMIT)
============================================================

PROMPT CATEGORY: [category name]

PROMPT CATEGORY - OTHER: [only if "Other" was selected, otherwise leave blank]

------------------------------------------------------------
CONTEXT SETTING
------------------------------------------------------------

REPO DEFINITION:
[3-5 sentences about the repository]

PR DEFINITION:
[3-5 sentences about the PR's purpose and impact]

------------------------------------------------------------
TASK APPROACH
------------------------------------------------------------

EDGE CASES:
1. [specific edge case with file/function reference]
2. [specific edge case]
3. [specific edge case]
...

ACCEPTANCE CRITERIA:
1. [verifiable criterion]
2. [verifiable criterion]
3. [verifiable criterion]
...

TESTING SETUP: [Yes/No]

------------------------------------------------------------
PROMPT DEFINITION
------------------------------------------------------------

INITIAL PROMPT:
[The actual prompt text -- 150-300 words, human-sounding, no em-dashes,
no PR references, no role prompting, not over-prescriptive]

============================================================
QUALITY CHECK RESULTS
============================================================
- Em-dashes found: [Yes/No -- if Yes, list and fix them]
- PR references found: [Yes/No -- if Yes, list and fix them]
- Role-based prompting: [Yes/No -- if Yes, list and fix them]
- Over-prescriptive: [Yes/No -- assessment]
- Word count: [N words]
- Reads like human-written issue: [Yes/No -- assessment]
============================================================
```

---

## PHASE 2 NOTES

- The Initial Prompt is the MOST CRITICAL field. Spend the most effort here.
- You MUST read the full PR diff before writing the prompt. Do not write from metadata alone.
- The prompt must be something you could plausibly find as a real GitHub issue in this repo.
- When in doubt about word choice, pick the simpler, more direct phrasing.
- Never use the word "leverage" -- use "use" instead. Never use "utilize" -- use "use". These are LLM signature words.
- Vary your sentence length. Real engineers write a mix of short declarative sentences and longer explanatory ones.
- Use technical terms from the actual codebase, not generic CS terms.
