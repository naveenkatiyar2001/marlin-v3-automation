# Marlin V3 — Rejection Feedback Log

> Collected from real task rejections. Use this as a training reference to avoid repeat mistakes.

---

## REJECTION #1 — Redundant Turn 3
**Date:** 2026-04-06
**Feedback:**
> Your 3rd prompt is entirely redundant. The model spends this turn validating against what you ask, adding nothing new and only checking previous work.

**Root cause:** Turn 3 asked the model to "verify" or "check" previous work instead of requesting new concrete changes.
**Rule violated:** Each follow-up must identify a specific issue and request a concrete change.

---

## REJECTION #2 — Redundant Turns + LLM Detection
**Date:** 2026-04-06
**Feedback:**
> 1. Turn 2 requests fixes that were already implemented in Turn 1, including wrapping root.unmount in act, using TODO annotations, and applying the correct async error assertion pattern, making the prompt fully redundant.
>
> 2. Turn 3 requests verification of changes that were already completed in Turn 1, including replacing ReactDOM with ReactDOMClient, removing filterOutComments, and maintaining consistent variable naming, so no new work was required.
>
> 3. There are strong indicators of LLM use throughout the submission. The prompts, pros, cons, and justifications use very uniform structure and phrasing across all turns.

**Root causes:**
- Turns 2 and 3 asked for things Turn 1 already did (didn't review Turn 1 output before writing follow-ups)
- LLM-generated text detected in prompts AND evaluation writeup
**Rules violated:**
- Each follow-up must advance the implementation meaningfully
- No LLM usage — you must write this yourself

---

## REJECTION #3 — LLM Indicators + Context Limit + Invalid Cons
**Date:** 2026-04-06
**Feedback:**
> LLM indicators.
>
> "...and the earlier B-side pattern on GIT skips was the kind of thing that would get asked to redo in a real PR."
>
> "Earlier in the same task line, B's diff had weak spots we already flagged: GIT skips collapsed to a generic line, and Idefics moved toward skipping mixin inheritance instead of fixing the setup like A did."
>
> "B hit a context limit mid-run." This invalidates the turn.
>
> A won turn 1, so B turn 1 gets synced to A. You are using a past that does not exist in future turns as cons.

**Root causes:**
- LLM-generated evaluation text
- Model B hit context limit (invalidated turn — should have been noted/handled)
- After A wins Turn 1, B gets synced to A's state. Cons written about B's Turn 1 don't apply to future turns because B now has A's code
**Rules violated:**
- No LLM usage
- Evaluate trajectories based on their CURRENT state, not invalidated past states
- If a trajectory hits context limits, note it but don't use pre-sync issues as ongoing cons

---

## REJECTION #4 — PR References + LLM Detection
**Date:** 2026-04-07
**Feedback:**
> Rejected due to multiple issues:
>
> 1. Turn 2 prompt references "the merged PR" in "Align dev-only prop validation order... with the merged PR", which indicates PR reference.
>
> 2. Turn 3 prompt again references "the merged PR" when asking to compare validation order, showing the same issue of PR reference in the prompt which is not allowed.
>
> 3. The prompts contain multiple em dashes and follow formulaic, repetitive structures, which are strong indicators of LLM-generated text rather than independent human input.

**Root causes:**
- Prompt explicitly mentions "the merged PR" in Turns 2 and 3
- LLM writing style detected (em dashes, formulaic structure)
**Rules violated:**
- No PR references — write as if you are the developer building this from scratch
- No LLM usage — must write yourself

---

## REJECTION #5 — Trivial PR
**Date:** 2026-04-07
**Feedback:**
> This PR is trivial. Please refrain from creating a prompt based off of a trivial PR, or add more features to the initial prompt. If you do the latter, ensure they are relevant. It can be a bit tricky given the small scopes, so it may be worth not selecting these in the future. Per V3 requirements, we want an initial prompt "You'd expect a model to struggle to complete the request on its 1st or 2nd try".

**Root cause:** Selected a PR that was too simple — a model could solve it in one turn.
**Rule violated:** Complexity filter — would a model likely fail on the 1st or 2nd try?

---

## REJECTION #6 -- CLAUDE.md Missing (claimed present but wasn't)
**Date:** 2026-04-05
**Feedback:**
> It was stated that there was a CLAUDE.md file in the original repository which is why one was not added. However there is no trace of any CLAUDE.md file in the https://github.com/microsoft/vscode repository. V3 submissions require a CLAUDE.md to be present.

**Root cause:** Trainer assumed CLAUDE.md existed in the repo and didn't create one. Reviewer checked and it wasn't there.
**Rule violated:** CLAUDE.md must be created by YOU before launching CLI. Always verify it exists.

---

## REJECTION #7 -- Same Voice Across All Turns + CLAUDE.md False Claim
**Date:** 2026-04-06
**Feedback:**
> Two main issues:
> 1. You said you added CLAUDE.md in the diff but it is not there at turn 1.
> 2. There is issue is the writing in the evaluation fields, not the technical judgments. Every turn is written in the same voice with the same structure and no contractions at all. The overall-preference sections all start with the same opener and follow the same pattern through all three turns. For example, phrases like "B gets the edge" followed by evidence appear in the same structural position in T1, T2, and T3. One or two of these patterns in isolation wouldn't matter, but the combination across all three turns is what makes this not read like a person. If you wrote this yourself, consider writing more casually next time.

**Root causes:**
- CLAUDE.md claimed to be added but diff doesn't show it
- Every turn's evaluation has identical voice, structure, no contractions
- Same opener pattern ("B gets the edge") repeated in same position across T1, T2, T3
- Cumulative pattern across turns is what triggers detection (not any single instance)
**Rules violated:**
- Verify CLAUDE.md against actual diff
- Vary writing structure across turns
- Use contractions naturally
- Don't reuse the same phrase in the same structural position across turns

---

## PATTERN SUMMARY

| Pattern | Occurrences | Severity |
|---------|-------------|----------|
| **Redundant follow-up turns** (verify/check instead of new work) | 3/8 | Critical |
| **LLM-generated text detected** (prompts, pros/cons, justifications) | 5/8 | Critical |
| **PR references in prompts** ("the merged PR") | 1/8 | Critical |
| **Trivial PR selected** (too easy for a model) | 1/8 | Critical |
| **CLAUDE.md missing or falsely claimed** | 2/8 | Critical |
| **Same voice/structure across all turns** | 1/8 | Critical |
| **Using invalidated trajectory state as cons** | 1/8 | High |
| **Context limit hit but not handled** | 1/8 | Medium |

---

## WHAT REVIEWERS FLAG AS LLM INDICATORS

1. **Em dashes (—)** used frequently throughout text
2. **Uniform sentence structure** across all turns and fields
3. **Formulaic bullet points** that start with the same grammatical pattern
4. **Parallel structure in pros/cons** ("Model A demonstrates...", "Model B exhibits...")
5. **Overly polished language** — real developers write casually
6. **Consistent formatting** across all fields (same heading style, same bullet patterns)
7. **Academic/formal tone** instead of engineer-speak

## WHAT GOOD FOLLOW-UP TURNS LOOK LIKE

**BAD (will be rejected):**
> "Verify that the changes from Turn 1 are correct and all tests pass. Ensure the implementation handles edge cases properly."

**BAD (will be rejected):**
> "Review the implementation and confirm that ReactDOM was properly replaced with ReactDOMClient throughout the codebase."

**GOOD (will be accepted):**
> "The `compute_serialized_data` function in serialization/compute.py doesn't handle empty deps — it'll throw a KeyError when looking up downstream neighbors. Add a guard and a test in test_load_defs.py that passes an asset spec with no dependencies."

**GOOD (will be accepted):**
> "Two things: 1) The custom field serializer for non-scalar-key mappings breaks on empty mapping — add a test that round-trips an empty one. 2) The facade's topo_order_index method uses list.index() which is O(n), pre-compute a lookup dict during construction instead."

## WHAT GOOD EVALUATION WRITING LOOKS LIKE

**BAD (LLM-detected):**
> "Model A demonstrates a comprehensive understanding of the codebase architecture, implementing robust error handling mechanisms and maintaining consistent adherence to the project's coding conventions throughout its modifications."

**GOOD (human-written):**
> "A actually ran the tests and caught the import cycle in serialization/compute.py before it broke anything. B just claimed tests pass without running them — you can see in the trace it skipped pytest entirely."

---

## PR SELECTION CHECKLIST (avoid trivial PRs)

Before selecting a PR, verify:
- [ ] Would a human engineer need ~2+ hours to complete this?
- [ ] Does it touch 5+ files?
- [ ] Are there non-obvious edge cases?
- [ ] Would a model likely fail on the 1st or 2nd try?
- [ ] Is there complex logic (not just renaming/config changes)?
- [ ] Are there component interactions that could break?

If any answer is "no", pick a harder PR.

---

## ADDITIONAL RULES FROM OFFICIAL TRAINING HUB PDF

Added from `common mistakes- Project Marlin.pdf`:

1. **CLAUDE.md delegation** — never ask the model to create CLAUDE.md via a turn prompt. Do it yourself.
2. **Out-of-scope features** — stick to the PR's intent. Don't request unrelated features.
3. **Turn 1 contradicts later turns** — if Turn 1 says "don't add comments", Turn 2 can't criticize "model didn't add comments"
4. **Final output must be production-ready** — if more turns could fix it but you stopped short, that's rejection-worthy
5. **Praising model for work it didn't do** — verify ALL claims against actual diffs
6. **N/A overuse** — only use N/A when category genuinely doesn't apply. Excessive N/A = disengagement signal
7. **Hallucinations in evaluations** — referencing functions/files/constants that don't exist in the codebase is a critical LLM signal
8. **Key-axis required for A1, A2, B1, B2** — name the specific dimension (correctness, test coverage, scope control, root cause handling, self-reporting accuracy)

## QUIZ ANSWERS (Common Mistakes Quiz — 15 questions)

| Q# | Question | Correct | Key Takeaway |
|----|----------|---------|--------------|
| Q2 | Avoid which prompt opening? | "You are a senior software engineer..." | No role-based prompting |
| Q3 | What violates prompt prep rules? | Using an LLM to generate/refine prompt | All writing must be yours |
| Q4 | V3 prompt complexity target? | 6-8 engineer-hours | Don't over-prescribe |
| Q5 | Min meaningful turns? | 3 | Verify/review turns don't count |
| Q6 | Acceptable follow-up prompt? | "validate_user() in auth.py doesn't handle expired tokens — add that case + test" | Must be specific |
| Q7 | Starting point for submission? | Pre-PR tarball from approval email | Never use PR branch |
| Q8 | When is A1/B1 appropriate? | When one model completed and other didn't attempt | Decisive quality diff only |
| Q9 | Sufficient justification? | "Option A refactored duplicate logic in payments/retry.py into shared helper..." | Must reference specific code |
| Q10 | A=60%, B=30% — what rating? | A3 or A2 | Rate relative difference, not closeness to ideal |
| Q11 | When to complete key-axis? | For A1, A2, B1, B2 | Name the driving dimension |
