#!/usr/bin/env python3
"""
MARLIN V3 — Cursor Analysis Prompt Generator

Takes the rich GitHub data fetched by github_fetcher.py and generates
a comprehensive analysis prompt file that Cursor can consume.

The prompt embeds:
  - All Marlin V3 criteria from the Master Guide
  - Full repo/PR data
  - Specific questions for Cursor to answer
  - Scoring rubric

Output: data/cursor_analysis_repos.md  or  data/cursor_analysis_prs.md
"""

import json
from datetime import datetime
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"


def generate_repo_analysis_prompt(repos_data: list) -> str:
    """Generate a Cursor-ready prompt to analyze repos for Marlin V3 suitability."""

    repos_block = ""
    for i, r in enumerate(repos_data, 1):
        if not r.get("fetch_ok"):
            repos_block += f"\n### REPO {i}: {r.get('full_name', 'unknown')} — FETCH FAILED\n"
            continue

        file_list = ""
        if r.get("changed_files"):
            for f in r["changed_files"][:20]:
                file_list += f"    {f['status']:10s} {f['path']}  (+{f['additions']}/−{f['deletions']})\n"

        repos_block += f"""
### REPO {i}: {r['full_name']}

**Basic info:**
- Language: {r['language']}
- Stars: {r['stars']} | Forks: {r['forks']} | Open issues: {r['open_issues']}
- Size: {r['size_kb']} KB | Total files: {r['total_files']} | Test files: {r['test_file_count']}
- Topics: {', '.join(r.get('topics', [])) or 'none'}
- License: {r.get('license', 'unknown')}
- Last updated: {r.get('updated_at', 'unknown')}
- Homepage: {r.get('homepage', 'none')}

**Description:** {r.get('description', 'none')}

**Top-level directories:** {', '.join(r.get('top_level_dirs', [])[:20]) or 'unknown'}

**Config/build files detected:** {', '.join(r.get('config_files', [])[:15]) or 'none'}

**Has tests:** {'Yes' if r.get('has_tests') else 'No'}

**README preview (first 1500 chars):**
```
{r.get('readme_preview', '(none)')[:1500]}
```

---
"""

    prompt = f"""# MARLIN V3 — REPO ANALYSIS REQUEST FOR CURSOR

> **Generated:** {datetime.now().isoformat()}
> **Purpose:** Analyze {len(repos_data)} repos against Marlin V3 criteria and recommend the best one.

---

## MARLIN V3 SELECTION CRITERIA (from the official guide)

A suitable repo for Marlin V3 must meet ALL of the following:

1. **Complexity:** A human engineer would need ~2+ hours to complete a task based on a PR from this repo.
2. **Model challenge:** A model like Claude Opus 4.6 / Sonnet would likely FAIL on the 1st or 2nd try.
3. **Supported language:** Python, JavaScript/TypeScript, Go, Rust, Java, or C++.
4. **Real engineering depth:** The repo should have enough architectural complexity that tasks require understanding multiple interacting components, not just single-file edits.
5. **Test infrastructure:** Repos WITH existing tests are preferred because:
   - The model can be asked to maintain/extend tests (harder)
   - You can verify if the model's output actually works
   - Reviewers check if the model ran tests
6. **Not overly memorized:** Very famous repos (100k+ stars) may be memorized by the model, making tasks artificially easier. Sweet spot: 500–15,000 stars.
7. **Active development:** Recently updated repos have more complex current state.

### What makes a model FAIL (what we want):
- **Cross-module refactors** where changes in one file require consistent changes in 5+ other files
- **Serialization/deserialization** work where data shapes must match across boundaries
- **State management** where the model must track multiple interacting pieces
- **Migration/deprecation** work where old and new code paths must coexist
- **Performance optimization** requiring deep understanding of data flow
- **Complex test setup** requiring mocks, fixtures, and integration scaffolding

### What does NOT make a model fail (avoid):
- Simple docs-only repos
- Single-file utility libraries
- Repos with no tests (can't verify anything)
- Very small repos (<100 files) with shallow structure
- Archived/unmaintained repos

---

## REPOS TO ANALYZE

{repos_block}

---

## WHAT I NEED FROM YOU

For EACH repo above, provide:

### 1. Brief Summary (2-3 sentences)
What does this repo do? What is its primary purpose and architecture?

### 2. Marlin Suitability Score (0-100)
Score based on the criteria above. Be specific about WHY.

### 3. Difficulty Assessment
- What types of PRs would be available here?
- Would tasks from this repo likely make Claude Opus 4.6 struggle? Why?
- What specific architectural patterns make this repo hard for models?

### 4. Best Prompt Categories
Which of the 14 Marlin categories would work best with this repo?
(Refactor, Bug Fix, New Feature, Performance, Testing, etc.)

### 5. Risk Factors
- Is the model likely to have memorized this repo?
- Are there setup/environment complications?
- Is the codebase too large to navigate effectively?

### FINAL OUTPUT
After analyzing all repos, give me a **ranked recommendation**:
1. Best repo for Marlin tasking and WHY
2. Second best and WHY
3. Any repos to definitely AVOID and WHY

Be brutally honest. The goal is to find a repo where a top model will genuinely struggle.
"""
    return prompt


def generate_pr_analysis_prompt(prs_data: list, selected_repo: str = "") -> str:
    """Generate a Cursor-ready prompt to analyze PRs for Marlin V3 suitability."""

    prs_block = ""
    for i, pr in enumerate(prs_data, 1):
        if not pr.get("fetch_ok"):
            prs_block += f"\n### PR {i}: #{pr.get('pr_number', '?')} — FETCH FAILED\n"
            continue

        files_table = ""
        for f in pr.get("changed_files", []):
            files_table += f"    {f['status']:10s} +{f['additions']:4d} −{f['deletions']:4d}  {f['path']}\n"

        commits_list = ""
        for msg in pr.get("commit_messages", []):
            first_line = msg.split("\n")[0][:120]
            commits_list += f"    - {first_line}\n"

        reviews_list = ""
        for rev in pr.get("review_comment_previews", []):
            reviews_list += f"    [{rev['author']}] on {rev['path']}: {rev['body'][:150]}\n"

        prs_block += f"""
### PR {i}: #{pr['pr_number']} — "{pr['title']}"

**Author:** {pr.get('author', '?')} | **State:** {pr.get('state', '?')} | **Merged:** {pr.get('merged', False)}
**Branch:** {pr.get('head_branch', '?')} → {pr.get('base_branch', '?')}
**Stats:** {pr.get('changed_files_count', 0)} files | +{pr.get('additions', 0)} −{pr.get('deletions', 0)} lines | {pr.get('commits_count', 0)} commits
**Comments:** {pr.get('comments_count', 0)} general + {pr.get('review_comments_count', 0)} review
**Labels:** {', '.join(pr.get('labels', [])) or 'none'}
**Created:** {pr.get('created_at', '?')} | **Merged:** {pr.get('merged_at', 'not merged')}

**PR Description:**
```
{pr.get('body', '(empty)')[:1500]}
```

**Directories touched:** {', '.join(pr.get('directories_touched', [])) or 'single directory'}
**Cross-module:** {'Yes' if pr.get('cross_module') else 'No'}

**Files changed:**
```
{files_table or '(none)'}
```

**Commit messages:**
```
{commits_list or '(none)'}
```

**Review comments (preview):**
```
{reviews_list or '(none)'}
```

---
"""

    prompt = f"""# MARLIN V3 — PR ANALYSIS REQUEST FOR CURSOR

> **Generated:** {datetime.now().isoformat()}
> **Repo:** {selected_repo}
> **Purpose:** Analyze {len(prs_data)} PRs and recommend the best one for breaking a model.

---

## MARLIN V3 PR SELECTION CRITERIA

A suitable PR must meet ALL of the following:

1. **~2+ hour human effort:** The task derived from this PR should take a competent engineer at least 2 hours.
2. **Model will struggle on 1st/2nd try:** The PR's changes are complex enough that Claude Opus 4.6 will likely produce incomplete or incorrect output.
3. **Merged PR:** We need a PR that was actually merged (so the "correct answer" exists).
4. **Multiple files:** PRs that touch 5+ files across multiple directories are preferred.
5. **Both additions AND deletions:** Pure additions are easier; refactors (add + delete) are much harder.
6. **Review comments exist:** PRs with reviewer feedback indicate nuanced decisions the model must replicate.
7. **Clear description:** The PR must be well-described enough that you can write a Marlin prompt from it WITHOUT referencing the PR.

### Ideal PR characteristics for making models FAIL:
- **Refactors** with cross-file consistency requirements
- **Serialization/data-shape changes** where types must align across boundaries
- **Removal + replacement** of old code paths with new ones
- **Performance work** requiring understanding of data flow and bottlenecks
- **Test changes** that require understanding both the code AND the test framework
- **Multiple interacting concerns** in a single PR (e.g., schema + API + tests)

### PRs to AVOID for Marlin:
- Docs/README-only changes
- Single-file, single-function fixes (too easy)
- Dependency bumps or config-only changes (too mechanical)
- PRs with no description (can't write a good prompt from them)
- Very old PRs where the codebase has changed drastically since

### Prompt category matching:
The PR should naturally fit one of the 14 Marlin categories:
1=Git, 2=Ambiguous, 3=Discussion, 4=Explaining, 5=Code Review,
6=Refactor, 7=Greenfield, 8=Bug Fix, 9=Chore, 10=Documentation,
11=New Feature, 12=Performance, 13=Testing/QA, 14=Other

---

## PRs TO ANALYZE

{prs_block}

---

## WHAT I NEED FROM YOU

For EACH PR above, provide:

### 1. Brief Summary (2-3 sentences)
What does this PR do? What problem does it solve? What is the scope?

### 2. Marlin Difficulty Score (0-100)
Based on the criteria above. Be specific about WHY.

### 3. Will It Break the Model?
- What specific aspects would make Claude Opus 4.6 / Sonnet struggle?
- What would the model likely get WRONG?
- What edge cases exist that the model might miss?

### 4. Prompt Feasibility
- Can you write a clear Marlin prompt from this PR WITHOUT referencing the PR?
- What Marlin category fits best?
- Is the PR description clear enough to derive acceptance criteria?

### 5. Risk Assessment
- Is this PR too simple (model finishes easily)?
- Is this PR too complex (impossible to scope into a Marlin task)?
- Any setup/environment concerns?

### FINAL OUTPUT

After analyzing all PRs, give me:

1. **BEST PR** for Marlin tasking — the one most likely to make the model fail for ENGINEERING reasons (not ambiguity)
2. **Second best** and why
3. **Suggested Marlin category** for the best PR
4. **Draft prompt direction** — 2-3 sentences describing what the Marlin prompt should ask for (without referencing the PR)
5. **PRs to avoid** and why

Be specific, reference file paths and code patterns from the PR data above.
"""
    return prompt


def write_analysis_file(prompt: str, filename: str):
    """Write the analysis prompt to a markdown file."""
    filepath = DATA_DIR / filename
    filepath.write_text(prompt)
    return filepath


if __name__ == "__main__":
    print("Use via the orchestrator or import directly.")
    print("  generate_repo_analysis_prompt(repos_data) -> str")
    print("  generate_pr_analysis_prompt(prs_data) -> str")
