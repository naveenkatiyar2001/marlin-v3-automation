#!/usr/bin/env python3
"""
MARLIN V3 — PRE-SUBMISSION CONSISTENCY CHECKER

Usage:
    python3 marlin_check.py                      # Interactive mode
    python3 marlin_check.py --prompt "your prompt text"  # Quick check

Checks performed:
    1. Prompt does not reference PR numbers/URLs
    2. No role-based prompting phrases
    3. Prompt is not over-prescriptive (line-number references)
    4. Minimum length / substance check
    5. Rating ↔ justification language consistency
    6. Key-axis field presence for non-equivalent ratings
    7. Strengths fields are evaluative (not just descriptive)
    8. Follow-up prompts are not generic/meaningless
"""

import re
import sys
import json
from dataclasses import dataclass, field
from typing import Optional
from pathlib import Path


@dataclass
class CheckResult:
    name: str
    passed: bool
    message: str
    severity: str = "error"


@dataclass
class TurnData:
    turn_number: int
    prompt: str = ""
    model_a_strengths: str = ""
    model_a_weaknesses: str = ""
    model_b_strengths: str = ""
    model_b_weaknesses: str = ""
    rating: str = ""
    key_axis: str = ""
    justification: str = ""


PR_PATTERNS = [
    r'#\d{3,6}',
    r'pull/\d+',
    r'PR[\s\-_]?\d+',
    r'pr[\s\-_]?\d+',
    r'pull request\s*#?\d+',
    r'github\.com/.+/pull/\d+',
]

ROLE_PHRASES = [
    r'you are a[n]?\s+(senior|expert|experienced|skilled)',
    r'act as a[n]?\s+',
    r'imagine you are a[n]?\s+',
    r'pretend you are',
    r'as a senior (software |)engineer',
    r'you\'re a[n]?\s+(senior|expert)',
    r'take on the role of',
]

OVERPRESCRIPTIVE_PATTERNS = [
    r'on line \d+',
    r'at line \d+',
    r'line \d+.*change',
    r':\d+:\s',
]

GENERIC_FOLLOWUP_PHRASES = [
    "please double check",
    "review everything",
    "make sure it works",
    "ensure everything is production ready",
    "check for any remaining bugs",
    "fix anything that might be wrong",
    "verify all changes",
    "review the implementation and fix",
    "make changes only if needed",
    "check for any remaining improvements",
]

DESCRIPTIVE_ONLY_PATTERNS = [
    r'^model [ab] added \w+$',
    r'^model [ab] created \w+$',
    r'^model [ab] implemented \w+$',
    r'^model [ab] fixed \w+$',
    r'^model [ab] wrote \w+$',
    r'^added tests?\.?$',
    r'^implemented the feature\.?$',
    r'^fixed the bug\.?$',
]

RATING_LANGUAGE_MAP = {
    "A1": ["fails", "incorrect", "broken", "critical", "fundamentally", "completely wrong", "does not work"],
    "B1": ["fails", "incorrect", "broken", "critical", "fundamentally", "completely wrong", "does not work"],
    "A2": ["substantially", "significantly", "missing key", "major gap", "much better", "far superior"],
    "B2": ["substantially", "significantly", "missing key", "major gap", "much better", "far superior"],
    "A3": ["better structured", "tighter scope", "cleaner", "more readable", "better organized", "more complete"],
    "B3": ["better structured", "tighter scope", "cleaner", "more readable", "better organized", "more complete"],
    "A4": ["minor", "equivalent", "negligible", "similar", "comparable", "functionally equivalent"],
    "B4": ["minor", "equivalent", "negligible", "similar", "comparable", "functionally equivalent"],
}


def check_pr_references(prompt: str) -> CheckResult:
    for pattern in PR_PATTERNS:
        match = re.search(pattern, prompt, re.IGNORECASE)
        if match:
            return CheckResult(
                name="PR Reference Check",
                passed=False,
                message=f"Prompt contains a PR reference: '{match.group()}'. Remove all PR references.",
                severity="error",
            )
    return CheckResult(
        name="PR Reference Check",
        passed=True,
        message="No PR references found.",
    )


def check_role_prompting(prompt: str) -> CheckResult:
    for pattern in ROLE_PHRASES:
        match = re.search(pattern, prompt, re.IGNORECASE)
        if match:
            return CheckResult(
                name="Role-Based Prompting Check",
                passed=False,
                message=f"Contains role-based prompting: '{match.group()}'. Remove persona instructions.",
                severity="error",
            )
    return CheckResult(
        name="Role-Based Prompting Check",
        passed=True,
        message="No role-based prompting detected.",
    )


def check_overprescriptive(prompt: str) -> CheckResult:
    for pattern in OVERPRESCRIPTIVE_PATTERNS:
        match = re.search(pattern, prompt, re.IGNORECASE)
        if match:
            return CheckResult(
                name="Over-Prescriptive Check",
                passed=False,
                message=f"May be over-prescriptive (line-number reference): '{match.group()}'. Describe the problem, not exact lines.",
                severity="warning",
            )
    return CheckResult(
        name="Over-Prescriptive Check",
        passed=True,
        message="Not over-prescriptive.",
    )


def check_prompt_length(prompt: str) -> CheckResult:
    words = len(prompt.split())
    if words < 30:
        return CheckResult(
            name="Prompt Substance Check",
            passed=False,
            message=f"Prompt is only {words} words. A good Marlin prompt typically needs 50-200 words to be specific enough.",
            severity="warning",
        )
    if words > 500:
        return CheckResult(
            name="Prompt Substance Check",
            passed=False,
            message=f"Prompt is {words} words — may be over-prescriptive. Target 50-200 words describing problem + success criteria.",
            severity="warning",
        )
    return CheckResult(
        name="Prompt Substance Check",
        passed=True,
        message=f"Prompt length ({words} words) is reasonable.",
    )


def check_generic_followup(prompt: str, turn_number: int) -> CheckResult:
    if turn_number <= 1:
        return CheckResult(
            name="Follow-Up Quality Check",
            passed=True,
            message="Turn 1 — not a follow-up.",
        )
    prompt_lower = prompt.lower()
    for phrase in GENERIC_FOLLOWUP_PHRASES:
        if phrase in prompt_lower:
            return CheckResult(
                name="Follow-Up Quality Check",
                passed=False,
                message=f"Follow-up contains generic phrase: '{phrase}'. Name specific files/functions/behaviors instead.",
                severity="error",
            )
    return CheckResult(
        name="Follow-Up Quality Check",
        passed=True,
        message="Follow-up prompt is specific.",
    )


def check_rating_justification(turn: TurnData) -> CheckResult:
    if not turn.rating or not turn.justification:
        return CheckResult(
            name="Rating ↔ Justification Check",
            passed=True,
            message="No rating or justification provided yet.",
        )
    rating = turn.rating.upper()
    expected_words = RATING_LANGUAGE_MAP.get(rating, [])
    if not expected_words:
        return CheckResult(
            name="Rating ↔ Justification Check",
            passed=True,
            message=f"Rating '{rating}' not in map — skipping language check.",
        )
    justification_lower = turn.justification.lower()
    found = any(word in justification_lower for word in expected_words)
    if not found:
        return CheckResult(
            name="Rating ↔ Justification Check",
            passed=False,
            message=f"Rating is '{rating}' but justification language doesn't match expected tone. For {rating}, use words like: {', '.join(expected_words[:4])}.",
            severity="warning",
        )
    return CheckResult(
        name="Rating ↔ Justification Check",
        passed=True,
        message=f"Justification language aligns with '{rating}' rating.",
    )


def check_key_axis(turn: TurnData) -> CheckResult:
    if not turn.rating:
        return CheckResult(
            name="Key-Axis Field Check",
            passed=True,
            message="No rating provided yet.",
        )
    rating = turn.rating.upper()
    needs_key_axis = rating in ("A1", "A2", "A3", "B1", "B2", "B3")
    if needs_key_axis and not turn.key_axis.strip():
        return CheckResult(
            name="Key-Axis Field Check",
            passed=False,
            message=f"Rating is '{rating}' — key-axis field is REQUIRED. Name the dimension that drove the preference (e.g., correctness, test coverage, scope control).",
            severity="error",
        )
    return CheckResult(
        name="Key-Axis Field Check",
        passed=True,
        message="Key-axis field is properly filled (or not required).",
    )


def check_evaluative_strengths(strengths: str, model_label: str) -> CheckResult:
    if not strengths.strip():
        return CheckResult(
            name=f"{model_label} Strengths Quality",
            passed=False,
            message=f"{model_label} strengths field is empty.",
            severity="error",
        )
    for pattern in DESCRIPTIVE_ONLY_PATTERNS:
        if re.match(pattern, strengths.strip(), re.IGNORECASE):
            return CheckResult(
                name=f"{model_label} Strengths Quality",
                passed=False,
                message=f"{model_label} strengths is purely descriptive: '{strengths.strip()}'. Explain WHY it matters.",
                severity="warning",
            )
    if len(strengths.split()) < 10:
        return CheckResult(
            name=f"{model_label} Strengths Quality",
            passed=False,
            message=f"{model_label} strengths is very short ({len(strengths.split())} words). Add specific file/function references and explain impact.",
            severity="warning",
        )
    return CheckResult(
        name=f"{model_label} Strengths Quality",
        passed=True,
        message=f"{model_label} strengths appears evaluative.",
    )


def run_prompt_checks(prompt: str, turn_number: int = 1) -> list[CheckResult]:
    results = []
    results.append(check_pr_references(prompt))
    results.append(check_role_prompting(prompt))
    results.append(check_overprescriptive(prompt))
    results.append(check_prompt_length(prompt))
    results.append(check_generic_followup(prompt, turn_number))
    return results


def run_turn_checks(turn: TurnData) -> list[CheckResult]:
    results = run_prompt_checks(turn.prompt, turn.turn_number)
    results.append(check_rating_justification(turn))
    results.append(check_key_axis(turn))
    results.append(check_evaluative_strengths(turn.model_a_strengths, "Model A"))
    results.append(check_evaluative_strengths(turn.model_b_strengths, "Model B"))
    return results


def print_results(results: list[CheckResult]) -> bool:
    all_passed = True
    print("\n" + "=" * 60)
    print("MARLIN V3 — PRE-SUBMISSION CHECK RESULTS")
    print("=" * 60)

    for r in results:
        if r.passed:
            icon = "\033[92m✓\033[0m"
        elif r.severity == "warning":
            icon = "\033[93m⚠\033[0m"
        else:
            icon = "\033[91m✗\033[0m"
            all_passed = False

        print(f"  {icon}  {r.name}")
        if not r.passed:
            print(f"      → {r.message}")

    print("\n" + "-" * 60)
    if all_passed:
        print("\033[92mAll checks passed. Ready to submit.\033[0m")
    else:
        errors = sum(1 for r in results if not r.passed and r.severity == "error")
        warnings = sum(1 for r in results if not r.passed and r.severity == "warning")
        print(f"\033[91m{errors} error(s)\033[0m, \033[93m{warnings} warning(s)\033[0m found. Fix before submitting.")
    print("=" * 60 + "\n")
    return all_passed


def interactive_mode():
    print("\n" + "=" * 60)
    print("MARLIN V3 — INTERACTIVE SUBMISSION CHECKER")
    print("=" * 60)

    num_turns = int(input("\nHow many turns? "))

    all_results = []
    for t in range(1, num_turns + 1):
        print(f"\n--- Turn {t} ---")
        prompt = input(f"Turn {t} prompt (paste, then press Enter): ").strip()

        if t == num_turns:
            rating = input("Overall rating (A1/A2/A3/A4/B4/B3/B2/B1): ").strip()
            key_axis = input("Key-axis (leave blank if A4/B4): ").strip()
            justification = input("Justification: ").strip()
            a_strengths = input("Model A strengths: ").strip()
            b_strengths = input("Model B strengths: ").strip()

            turn = TurnData(
                turn_number=t,
                prompt=prompt,
                rating=rating,
                key_axis=key_axis,
                justification=justification,
                model_a_strengths=a_strengths,
                model_b_strengths=b_strengths,
            )
            all_results.extend(run_turn_checks(turn))
        else:
            all_results.extend(run_prompt_checks(prompt, t))

    if num_turns < 3:
        all_results.append(CheckResult(
            name="Minimum Turns Check",
            passed=False,
            message=f"Only {num_turns} turns. Marlin V3 requires at least 3 meaningful turns.",
            severity="error",
        ))
    else:
        all_results.append(CheckResult(
            name="Minimum Turns Check",
            passed=True,
            message=f"{num_turns} turns — meets minimum requirement.",
        ))

    print_results(all_results)


def quick_check(prompt: str):
    results = run_prompt_checks(prompt, turn_number=1)
    print_results(results)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--prompt":
        prompt_text = " ".join(sys.argv[2:])
        quick_check(prompt_text)
    elif len(sys.argv) > 1 and sys.argv[1] == "--file":
        filepath = sys.argv[2]
        prompt_text = Path(filepath).read_text()
        quick_check(prompt_text)
    else:
        interactive_mode()
