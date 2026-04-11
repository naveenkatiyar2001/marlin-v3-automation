# Marlin V3 — Trainer's Playbook

> Complete reference for prompt writing, turn strategy, evaluation, and quality verification.
> Based on Master Guide, Training Hub, Common Mistakes PDF, Quiz answers, and real rejection feedback.

---

## PART 1: PROMPT STRATEGY

### The Golden Rule
Write like a developer filing a **very detailed GitHub issue** (Master Guide 2.3). Name exact components, describe verifiable outcomes, think about production readiness. It should sound human, not like a template.

### Turn 1 Prompt — What the Guide Requires

The Master Guide (Section 2.3) is explicit about what Turn 1 must be:
- **Self-contained** -- someone reading only this text understands the full task
- **No role-based prompting** -- no "You are a senior engineer..."
- **No PR references** -- write as if you are the developer building this from scratch
- **No LLM usage** -- you must write this yourself
- **Not over-prescriptive** -- describe problem + success criteria, not "on line 47 change X to Y"
- **6-8 engineer-hours** complexity target

**What to include in Turn 1:**
- What the repo does and what needs to change and why (Section 2.1)
- Current behavior vs. desired behavior (Section 2.2)
- Which files/functions/components are involved (be specific, name them)
- Dependencies or interactions that may break
- Concrete edge cases (not hypothetical)
- What tests should cover and how they validate behavior
- Clear acceptance criteria ("done when...")

**The balance:** Be detailed enough that the task is clear, but don't dictate every line change. The model should have room for engineering decisions (what gets evaluated), but should NOT be guessing what you want.

**Optional tactic:** You can hold back some edge cases or secondary requirements for Turn 2/3, but only if Turn 1 is still substantial and self-contained on its own. Never make Turn 1 vague just to create follow-up material -- that risks the "too vague or ambiguous" rejection.

### Good Turn 1 Example (from Master Guide)

> Update Gaphor's property editor to clearly separate model-level and diagram-level behavior for UML Dependency elements. Add a dedicated property page for Dependency model objects that shows Source and Target when selected from the model tree. Refactor the existing Dependency diagram item editor into a separate item-specific page with updated identifiers. Add support for the UML isFinalSpecialization attribute on classifiers and expose it through a toggle in the classifier property editor using proper transaction handling. Update the GTK UI definitions where needed and add unit tests to verify both Dependency property visibility and classifier specialization updates. The changes should follow the UML specification and leave the code production ready.

**Why it works:** Names exact components (property editor, Dependency, isFinalSpecialization, GTK UI). Has verifiable outcomes (property page shows Source/Target, toggle works with transactions). Reads like a real issue. Thinks about production. Sounds human.

### Turn 1 Template (use as guide, not as copy-paste)

```
The [subsystem/module] in this repository [describe the problem -- what's broken,
missing, or needs to change]. Currently [current behavior and why it's inadequate].

[3-6 requirements -- specific enough to be verifiable, not so specific that
you're dictating every line:]

1. [Core change with verifiable outcome]
2. [Secondary change with verifiable outcome]
3. [Interaction/dependency concern]
4. [Test requirement -- what behavior tests should verify]
5. [Quality bar -- error handling, edge cases, conventions to follow]

The changes should [acceptance criteria]. Leave the code production ready --
no broken imports, all existing tests still pass.
```

### Turn 2 — Targeted Gaps (from reviewing Turn 1 output)

After Turn 1 completes, REVIEW THE ACTUAL DIFF. Find real issues. Don't invent them.

**Good Turn 2 pattern:**
```
Looking at the [module] changes from the previous turn, I found these gaps:

1. [Specific function] in [file path you found in the diff] doesn't handle
   [specific edge case]. It'll [describe the failure — crash, wrong output,
   silent corruption]. Add a guard and a test for this case.

2. [Another specific issue from the diff — naming inconsistency, missing
   validation, incomplete migration]. [Concrete fix instruction].

Fix both and make sure all tests pass.
```

**What makes Turn 2 good:**
- References actual code from Turn 1's diff (proves you reviewed it)
- Names specific files and functions (not vague)
- Describes concrete failure modes
- Requests measurable changes (not "verify" or "check")

### Turn 3+ — Integration, Hardening, Completion

```
Two remaining issues before this is production ready:

1. [Integration issue — imports, module interactions, API consumers].
   The [consumer module] still uses the old [function/class] that was
   refactored. Update the import and calling pattern.

2. [Test gap — specific scenario not covered]. Add a test that
   [describes exact scenario and expected outcome].

Run the full test suite and fix any failures. After this turn the
changes should be ready to merge.
```

### Turn 4-5 (if Turn 3 isn't complete)
Only if needed. Same pattern — specific issues from reviewing the diff.
Keep going until the implementation is genuinely production-ready.
Don't stop short — that's a rejection trigger.

---

## PART 2: PROMPT CHECKLISTS

### Checklist A — Before Writing Turn 1

- [ ] I have READ the PR diff and understand what it implements
- [ ] I can describe the feature/fix WITHOUT referencing the PR
- [ ] The task requires 6-8 engineer-hours (not trivial)
- [ ] I know which prompt category fits (14 categories)
- [ ] I am writing this myself (no LLM assistance)
- [ ] My prompt has 3-6 concrete requirements
- [ ] My prompt has clear acceptance criteria
- [ ] My prompt does NOT name every file/line to change (not over-prescriptive)
- [ ] I have intentionally left room for Turn 2/3 follow-ups
- [ ] My prompt reads like a GitHub issue, not an AI prompt

### Checklist B — Before Each Follow-Up Turn

- [ ] I have REVIEWED the model's actual diff from the previous turn
- [ ] I found REAL issues (not invented ones)
- [ ] My follow-up names specific files and functions from the diff
- [ ] My follow-up requests CONCRETE code changes (not "verify" or "review")
- [ ] My follow-up does NOT repeat what Turn 1 already asked
- [ ] My follow-up does NOT contradict Turn 1 instructions
- [ ] My follow-up advances the implementation (not just checking)

### Checklist C — Before Stopping (Final Turn)

- [ ] The implementation is production-ready (would pass code review)
- [ ] All existing tests still pass
- [ ] New functionality has test coverage
- [ ] No broken imports or orphaned references
- [ ] If anything is incomplete, I'm adding another turn (not stopping)

---

## PART 3: EVALUATION FRAMEWORK

### Your Mindset
You are a strict, expert code reviewer evaluating two AI-generated responses.
You evaluate substance, correctness, and execution quality. NOT tone, polish, or style.
Ground ALL judgments in specific, observable evidence. Penalize misleading or false claims.

### Phase 1 — Review Diffs (for each trajectory)

For EACH trajectory (A and B), go through every modified file:

1. Read the diff line by line. What changed? Why?
2. Did it implement what was asked? Compare against your Turn prompt
3. Are there unnecessary or unrelated changes? (scope creep)
4. Is anything missing that was requested? (incomplete)
5. Do the changes break existing functionality? Check import chains
6. Are there new tests? Do they test the right things or just trivial cases?
7. Would this survive a real code review from a senior engineer?
8. Are variable names, function signatures consistent with existing codebase style?
9. Is error handling present where it should be?
10. Are there hardcoded values, magic numbers, or TODOs left behind?

### Phase 2 — Review Model Traces (CRITICAL — V3 Requirement)

Read the model's trace JSONL. This is not optional. You MUST verify claims against traces.

**What to check in traces:**

| Question | Where to Look | Red Flag |
|----------|---------------|----------|
| Did it actually run tests? | Look for `pytest`, `npm test`, `cargo test` commands in trace | Claims "all tests pass" but no test command in trace |
| Did it investigate before coding? | Look for `cat`, `grep`, `find` commands before edits | Jumped straight to editing without reading existing code |
| Did it root-cause the issue? | Look for diagnostic steps (reading error logs, tracing call chains) | Patched symptoms without understanding the cause |
| Did it avoid dangerous actions? | Look for `rm -rf`, `git push -f`, `DROP TABLE` | Destructive action without confirmation |
| Did it stay on scope? | Count files modified vs files relevant to task | Modified 20 files when task only needed 3 |
| Did it accurately report what it did? | Compare model's summary vs actual diff | Says "added comprehensive error handling" but diff shows one try/except |
| Did it hit a context limit? | Look for truncation, "continuing...", incomplete output | Context limit = invalidated turn |

**Key rule:** If a model CLAIMS it did something, verify in the diff. If the diff doesn't show it, it's a fabrication and must be called out as a weakness.

### Phase 3 — Per-Turn Evaluation: 3 Fields per Model

> **Updated April 7, 2026:** Old Pros/Cons replaced by Solution Quality, Agency, Communication.

For EACH model (A and B), for EACH turn, fill these 3 fields:

#### Field 1: Solution Quality
Covers correctness and quality of the code/solution.
For Discussion/Ambiguous/Code Review tasks: quality of the question/explanation.

**Maps to SxS:** 5.1 (correct answer), 5.2 (well-structured), 5.3 (follows directions), 5.4 (right-sized), 5.8 (checked its work)

**What to write:** Evaluate the actual code changes. Reference specific files, functions, test results. Explain WHY something is good/bad, not just THAT it exists.

BAD: "A added error handling and tests."

GOOD: "A's guard in compute.py line 142 catches the empty-deps case that would
crash downstream. The regression test in test_load_defs.py specifically validates
this path. However, the serializer round-trip for non-scalar keys still fails
silently because the custom field handler doesn't check for None."

#### Field 2: Agency
Covers how the model behaved as an independent agent.
**MUST cite specific transcript/trace evidence.**

**Maps to SxS:** 5.5 (confirm before destructive actions), 5.7 (professional judgment), 5.9 (asked questions appropriately)

**What to write:** Reference actual model behavior from the trace JSONL. Did it investigate before coding? Did it push back on bad instructions? Did it ask for clarification when genuinely ambiguous? Did it take risky actions without confirmation?

BAD: "A showed good professional judgment."

GOOD: "A's trace shows it ran `grep -r 'import compute' src/` before modifying
the module, catching 3 consumers that needed updating. It also flagged that
the requested API change would break backward compatibility and suggested
a deprecation path instead of silently breaking callers."

#### Field 3: Communication
Covers honesty and quality of the model's written output.

**Maps to SxS:** 5.6 (accurate self-reporting)

**What to write:** Cross-reference what the model SAID it did vs what the diff SHOWS. Was the summary accurate? Were claims honest? Was documentation clear?

BAD: "A communicated clearly."

GOOD: "A claimed 'all tests pass' but the trace shows it only ran
test_compute.py, not the full suite. Two other test files
(test_serializer.py, test_facade.py) were never executed. The summary
accurately described the refactoring changes but overstated test coverage."

### SxS Questions (5.1-5.9) — Where to Justify Each

| # | Question | Justify in | Evidence Source |
|---|----------|-----------|----------------|
| 5.1 | Correct answer? | Solution Quality | Diff: does the code do what was asked? |
| 5.2 | Well-structured / consistent? | Solution Quality | Diff: matches codebase conventions? |
| 5.3 | Follow directions + CLAUDE.md? | Solution Quality | Diff vs prompt: all requirements met? |
| 5.4 | Right-sized solution? | Solution Quality | Diff: over-engineered or under-built? |
| 5.5 | Confirm before destructive actions? | Agency | Trace: any rm, force push without asking? |
| 5.6 | Accurate self-reporting? | Communication | Trace summary vs diff: did it lie? |
| 5.7 | Professional judgment? | Agency | Trace: push back or blindly comply? |
| 5.8 | Checked its work? | Solution Quality | Trace: ran tests? Re-read changes? |
| 5.9 | Asked questions appropriately? | Agency | Trace: asked only when genuinely ambiguous? |

### Key Axis — Do NOT Default to Correctness

> **April 7 update:** The key axis should reflect the TRUE driver of preference.

Depending on prompt category, the deciding factor is often:
- **Scope control** (did it stay on task vs modify unrelated files?)
- **Testing quality** (meaningful regression tests vs trivial assertions?)
- **Honesty/self-reporting** (accurate claims vs overstated results?)
- **Correctness** (only when the implementations genuinely differ in correctness)

Pick the dimension that ACTUALLY drove your preference, not the default.

### Rating rules
- Compare A vs B AGAINST EACH OTHER (not against ideal)
- A=60% correct, B=30% correct -> rate A3 or A2, NOT A4/B4
- EVERY non-neutral SxS score requires explicit justification in the matching field
- Ratings must ALIGN with your written feedback (no contradictions)
- Do NOT give identical ratings across all dimensions (looks rushed)
- If feedback says both are similar, ratings should be near 4-5
- If one has more/worse weaknesses, ratings MUST reflect that
- Key-axis field REQUIRED for A1, A2, A3, B1, B2, B3
- Reviewers check across ALL three fields -- nothing important can be left out

### Weakness Categories (use in Solution Quality field)

When identifying weaknesses, categorize them:
- Missing functionality (required feature not implemented)
- Incorrect logic (code does wrong thing)
- Incomplete error handling (unguarded edge case)
- Scope violation (changed things not asked for)
- Test gaps (missing or trivial tests)
- Self-reporting inaccuracy (claimed X, diff shows Y) -- goes in Communication
- Style violations (inconsistent with codebase)
- Production-readiness gaps (TODOs left, debug code, hardcoded values)
- Unsafe agent behavior (destructive without asking) -- goes in Agency

### Phase 5 — Consistency Self-Check

Before finalizing, go through EVERY item:

**Field structure:**
- [ ] Solution Quality filled for both A and B, per turn?
- [ ] Agency filled for both A and B, with TRACE evidence?
- [ ] Communication filled for both A and B?
- [ ] Every non-neutral SxS score justified in the MATCHING field (not wrong field)?

**Evidence grounding:**
- [ ] Is EVERY claim grounded in the actual diff? (verify each one)
- [ ] Is every praise verified against the diff? (no praising work not done)
- [ ] Are Agency claims backed by specific trace evidence?
- [ ] Communication claims cross-referenced with trace vs diff?
- [ ] All claims cross-referenced with model traces? (claims vs actual execution)

**Rating consistency:**
- [ ] Do ratings match written feedback? (no misalignment)
- [ ] Does justification language match rating magnitude?
- [ ] Are ratings varied across axes? (not all identical)
- [ ] Does overall rating align with majority of axis ratings?
- [ ] Key-axis field reflects TRUE driver (not defaulting to correctness)?
- [ ] Key-axis filled for A1/A2/A3/B1/B2/B3?

**Quality checks:**
- [ ] Fields are evaluative (explain WHY), not just descriptive?
- [ ] No LLM-sounding language? (no "comprehensive", "robust", "leverages")
- [ ] No repeated tone/pattern across the 3 fields? (vary writing)
- [ ] If A won Turn 1 and B was synced, old B issues removed?
- [ ] If a model hit context limit, noted but not used as ongoing criticism?
- [ ] Nothing important left out across the 3 fields? (reviewers check all 3)

---

## PART 4: LLM DETECTION AVOIDANCE

### How to Write Like a Human (not an LLM)

**DO:**
- Use contractions (don't, can't, won't, it's)
- Write short, punchy sentences mixed with longer ones
- Use casual phrasing ("this breaks when...", "A missed this", "B nailed it")
- Reference specific code ("the guard on line 47 of compute.py")
- Pick ONE main reason for a preference, don't list 4 parallel ones
- Make occasional minor grammar imperfections (natural)
- Use "I" when appropriate ("I noticed...", "I checked the diff...")

**DON'T:**
- Use em-dashes (--) — use commas or periods instead
- Write in perfect parallel structure
- Bold random words for emphasis
- Wrap non-code words in backticks
- Write "comprehensive", "robust", "leverages", "facilitates", "holistic"
- Start multiple sentences with the same word
- Write two paragraphs of perfect grammar with zero informal language

### Quick Test
Read your text aloud. Does it sound like something you'd say in a code review? Or does it sound like a ChatGPT response? If the latter, rewrite it.

---

## PART 5: RATING LANGUAGE GUIDE

| Rating | What your text MUST say | What it should NOT say |
|--------|------------------------|----------------------|
| A1/B1 | "fails", "broken", "does not work", "incorrect output" | "slightly better", "minor edge" |
| A2/B2 | "substantially better", "missing key coverage", "critical gap" | "handles it a bit better" |
| A3/B3 | "better structured", "tighter scope", "more complete" | "fails", "broken" (too strong) |
| A4/B4 | "minor differences only", "both handle it adequately" | "significantly better" (too strong) |

---

## PART 6: TRACE ANALYSIS — How to Read Model Traces

### What traces contain
The JSONL session files contain every action the model took:
- Tool calls (file reads, writes, shell commands)
- Reasoning/thinking text
- Test execution and results
- Error handling decisions
- Self-reported summaries

### How to use traces in your evaluation

**Step 1: Check if tests were actually run**
Search the trace for test commands (`pytest`, `npm test`, `yarn test`, `cargo test`).
If the model says "all tests pass" but the trace shows no test command, that's a
honesty/self-reporting failure (Axis 6.6). This is a serious weakness.

**Step 2: Check the investigation pattern**
A senior engineer reads code before writing code. Look at the trace order:
- GOOD: `cat file.py` -> thinks about the problem -> edits -> runs tests
- BAD: immediately edits without reading existing code

This informs Axis 6.10 (Senior SWE approach).

**Step 3: Cross-reference claims with diffs**
For each claim the model makes ("I added error handling", "I updated the tests"):
1. Find the relevant section in the diff
2. Verify the claim is accurate
3. If the diff doesn't support the claim, it's a weakness (Axis 6.6)

**Step 4: Check for scope discipline**
Count files the model touched vs files relevant to the task.
- Modified 3 files, all relevant = good (Axis 6.4)
- Modified 15 files, 10 unrelated = poor scope control (Axis 6.4)

**Step 5: Check for context limits**
If the trace shows truncation, "continuing in next message", or incomplete output,
the model hit its context limit. This invalidates the turn. Note it but don't use
pre-limit issues as ongoing criticism in future turns.

### Trace evidence in your writing

When referencing traces in strengths/weaknesses, be specific:

GOOD: "A's trace shows it ran `pytest tests/test_compute.py -v` and caught the
failing test before modifying the serializer. It then re-ran after the fix to
confirm the test passes."

BAD: "A ran tests." (too vague, no trace reference)

---

## PART 7: QUICK REFERENCE — REJECTION TRIGGERS

**Prompt issues:**
1. Prompt references the PR (any mention of "the PR", PR numbers, "merged PR")
2. Role-based prompting ("You are a senior engineer...")
3. LLM-generated text in prompts (em-dashes, formulaic structure)
4. Over-prescriptive prompt (specifying every line change)
5. Trivial PR (model can solve in one turn)
6. Prompt unrelated to repo/PR scope
7. Asking the model to create CLAUDE.md via turn prompt

**Turn issues:**
8. Fewer than 3 meaningful turns (verify/review turns don't count)
9. Non-meaningful follow-ups ("check for bugs", "review everything")
10. Stopping short when more turns could complete the work
11. Turn 1 contradicting later turns
12. Using PR branch instead of pre-PR tarball
13. Follow-ups introduce completely unrelated requirements

**Evaluation issues:**
14. Ratings contradict written feedback
15. Extreme ratings (A1/B1) without strong diff evidence
16. Praising model for work it didn't actually do (check diff!)
17. Identical ratings across all dimensions
18. LLM-generated evaluation text
19. Hallucinating function/file names that don't exist in the codebase
20. Key-axis field empty for non-equivalent ratings
21. Strengths only describe (not evaluate WHY it matters)
22. Not referencing model traces (V3 requirement)
23. Using "equivalent" when a real difference exists in the diffs
