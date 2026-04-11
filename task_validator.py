#!/usr/bin/env python3
"""
Marlin V3 — Pre-Submission Task Validator
=========================================
A strict automated reviewer that catches rejection-worthy issues
BEFORE you submit to Snorkel. Based on real rejection feedback patterns.

Usage:
    python3 task_validator.py                    # Interactive mode
    python3 task_validator.py --json input.json  # Batch mode from JSON file

Exit codes:
    0 = PASS (safe to submit)
    1 = FAIL (issues found — do NOT submit)
"""

import re
import sys
import json
import argparse
from collections import Counter
from typing import Optional

# ─── Severity ───
CRITICAL = "CRITICAL"
HIGH = "HIGH"
MEDIUM = "MEDIUM"
LOW = "LOW"

RED = "\033[91m"
YELLOW = "\033[93m"
GREEN = "\033[92m"
CYAN = "\033[96m"
BOLD = "\033[1m"
DIM = "\033[2m"
NC = "\033[0m"


class Issue:
    def __init__(self, severity: str, category: str, message: str, field: str = "", suggestion: str = ""):
        self.severity = severity
        self.category = category
        self.message = message
        self.field = field
        self.suggestion = suggestion

    def __str__(self):
        sev_color = RED if self.severity == CRITICAL else YELLOW if self.severity == HIGH else CYAN
        loc = f" [{self.field}]" if self.field else ""
        s = f"  {sev_color}[{self.severity}]{NC}{loc} {self.message}"
        if self.suggestion:
            s += f"\n    {DIM}→ {self.suggestion}{NC}"
        return s


class TaskValidator:
    def __init__(self):
        self.issues: list[Issue] = []

    # ═══════════════════════════════════════════════════════════════════
    # 1. PR REFERENCE DETECTION
    # ═══════════════════════════════════════════════════════════════════
    PR_PATTERNS = [
        (r'\bthe\s+(merged|original|source|target|base)\s+PR\b', "References '{match}' — write as if building from scratch"),
        (r'\bmerged\s+PR\b', "References 'merged PR'"),
        (r'\bPR\s*#?\d+\b', "References a PR number"),
        (r'\bpull\s*[/\\]?\s*\d+\b', "References a pull request by number"),
        (r'\bpull\s+request\b', "Mentions 'pull request'"),
        (r'\bPR\s+branch\b', "References 'PR branch'"),
        (r'\bPR\s+changes?\b', "References 'PR changes'"),
        (r'\balign\s+with\s+the\s+(merged|original)\s+PR\b', "Says 'align with the PR'"),
        (r'\bthe\s+PR\b', "References 'the PR'"),
        (r'\bthis\s+PR\b', "References 'this PR'"),
    ]

    def check_pr_references(self, text: str, field: str):
        for pattern, desc in self.PR_PATTERNS:
            matches = re.finditer(pattern, text, re.IGNORECASE)
            for m in matches:
                self.issues.append(Issue(
                    CRITICAL, "PR Reference",
                    f"{desc}: \"{m.group()}\"",
                    field,
                    "Remove all PR references. Write as if you're the developer building this from scratch."
                ))

    # ═══════════════════════════════════════════════════════════════════
    # 2. ROLE-BASED PROMPTING DETECTION
    # ═══════════════════════════════════════════════════════════════════
    ROLE_PATTERNS = [
        r'\b(act|behave|respond)\s+as\s+(a|an)\s+',
        r'\byou\s+are\s+(a|an)\s+(senior|expert|experienced|skilled)\b',
        r'\bimagine\s+you\s+are\b',
        r'\bpretend\s+(to\s+be|you\'re)\b',
        r'\bas\s+a\s+senior\s+(engineer|developer|swe)\b',
    ]

    def check_role_prompting(self, text: str, field: str):
        for pattern in self.ROLE_PATTERNS:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                self.issues.append(Issue(
                    CRITICAL, "Role Prompting",
                    f"Role-based prompting detected: \"{match.group()}\"",
                    field,
                    "Remove all role-based prompting. Describe the problem, not the persona."
                ))

    # ═══════════════════════════════════════════════════════════════════
    # 3. LLM-GENERATED TEXT DETECTION
    # ═══════════════════════════════════════════════════════════════════
    LLM_PHRASES = [
        r'\bdemonstrates?\s+a\s+(comprehensive|thorough|deep|solid)\s+understanding\b',
        r'\bexhibits?\s+(strong|excellent|robust)\b',
        r'\bshowcases?\s+(a\s+)?(solid|strong|deep|thorough)\b',
        r'\badheres?\s+to\b.*\b(conventions?|standards?|practices?)\b',
        r'\brobust\s+(error\s+handling|implementation|solution)\b',
        r'\bcomprehensive\s+(approach|understanding|solution|coverage|implementation)\b',
        r'\bmaintains?\s+consistent\s+adherence\b',
        r'\bsystematic\s+approach\b',
        r'\bholistic\s+(approach|understanding|view)\b',
        r'\bseamless(ly)?\s+(integrat|transition|handl)\b',
        r'\bmeticulously?\b',
        r'\bleverag(e[sd]?|ing)\s+(the|existing|modern)\b',
        r'\bfacilitat(e[sd]?|ing)\b',
        r'\bensur(e[sd]?|ing)\s+optimal\b',
        r'\bin\s+conclusion\b',
        r'\boverall,\s+(the|both|model)\b',
        r'\bit\s+is\s+worth\s+noting\b',
    ]

    def check_llm_indicators(self, text: str, field: str):
        llm_hits = 0
        matched_phrases = []

        for pattern in self.LLM_PHRASES:
            matches = re.findall(pattern, text, re.IGNORECASE)
            if matches:
                llm_hits += len(matches)
                matched_phrases.append(re.search(pattern, text, re.IGNORECASE).group())

        # Em dash frequency (strong LLM signal)
        em_dash_count = text.count("—") + text.count("–")
        word_count = len(text.split())
        em_dash_ratio = em_dash_count / max(word_count, 1) * 100

        if em_dash_ratio > 1.5 and em_dash_count >= 3:
            self.issues.append(Issue(
                HIGH, "LLM Indicator",
                f"High em-dash frequency: {em_dash_count} em-dashes in {word_count} words ({em_dash_ratio:.1f}%)",
                field,
                "Replace em-dashes with commas, periods, or parentheses. Real developers rarely use em-dashes."
            ))

        if llm_hits >= 3:
            self.issues.append(Issue(
                CRITICAL, "LLM Indicator",
                f"Strong LLM-generated text signals ({llm_hits} matches): {', '.join(matched_phrases[:4])}",
                field,
                "Rewrite in your own words. Use casual, engineer-style language. Avoid polished/academic phrasing."
            ))
        elif llm_hits >= 1:
            self.issues.append(Issue(
                MEDIUM, "LLM Indicator",
                f"Possible LLM phrasing detected ({llm_hits} matches): {', '.join(matched_phrases[:3])}",
                field,
                "Consider rephrasing to sound more natural/casual."
            ))

        # Uniformity check: do sentences start with the same patterns?
        sentences = re.split(r'[.!?]\s+', text)
        if len(sentences) >= 4:
            first_words = [s.split()[0].lower() for s in sentences if s.strip() and s.split()]
            word_counts = Counter(first_words)
            most_common_word, most_common_count = word_counts.most_common(1)[0]
            if most_common_count >= 4 and most_common_count / len(first_words) > 0.4:
                self.issues.append(Issue(
                    HIGH, "LLM Indicator",
                    f"Repetitive sentence structure: {most_common_count}/{len(first_words)} sentences start with \"{most_common_word}\"",
                    field,
                    "Vary your sentence openings. Formulaic structure is a strong LLM signal."
                ))

    # ═══════════════════════════════════════════════════════════════════
    # 4. REDUNDANT TURN DETECTION
    # ═══════════════════════════════════════════════════════════════════
    REDUNDANCY_VERBS = [
        r'\b(verify|validate|confirm|check|ensure|review|inspect)\s+(that\s+)?(the\s+)?(changes?|implementation|modifications?|code|updates?)\b',
        r'\b(make\s+sure|double[- ]check)\b',
        r'\breview\s+everything\b',
        r'\bcheck\s+(for\s+)?(bugs?|errors?|issues?|correctness)\b',
        r'\bensure\s+(all\s+)?tests?\s+pass\b',
        r'\bconfirm\s+(the\s+)?(changes?|fix(es)?|implementation)\b',
        r'\bverify\s+(the\s+)?(correct|proper)\b',
    ]

    def check_turn_redundancy(self, turns: list[str]):
        if len(turns) < 2:
            return

        for i, turn in enumerate(turns[1:], start=2):
            redundancy_hits = 0
            for pattern in self.REDUNDANCY_VERBS:
                if re.search(pattern, turn, re.IGNORECASE):
                    redundancy_hits += 1

            # Check if turn is mostly about validating, not building
            words = turn.lower().split()
            action_words = sum(1 for w in words if w in [
                'add', 'create', 'implement', 'build', 'write', 'refactor',
                'introduce', 'extract', 'move', 'split', 'merge', 'fix'
            ])
            check_words = sum(1 for w in words if w in [
                'verify', 'validate', 'confirm', 'check', 'ensure', 'review',
                'inspect', 'test', 'pass', 'correct', 'properly'
            ])

            if redundancy_hits >= 2 and check_words > action_words:
                self.issues.append(Issue(
                    CRITICAL, "Redundant Turn",
                    f"Turn {i} appears to only validate/check previous work without adding new functionality",
                    f"Turn {i}",
                    "Each turn must ADD new work: new edge cases, new files, new features, bug fixes. Never just 'verify'."
                ))
            elif redundancy_hits >= 1 and action_words == 0:
                self.issues.append(Issue(
                    HIGH, "Redundant Turn",
                    f"Turn {i} may be redundant — found validation language but no action verbs (add, create, implement, fix)",
                    f"Turn {i}",
                    "Include concrete new work in every follow-up turn."
                ))

        # Cross-turn duplication check
        for i in range(1, len(turns)):
            for j in range(i):
                overlap = self._text_overlap(turns[j], turns[i])
                if overlap > 0.4:
                    self.issues.append(Issue(
                        HIGH, "Redundant Turn",
                        f"Turn {i+1} has ~{overlap*100:.0f}% content overlap with Turn {j+1}",
                        f"Turn {i+1}",
                        "Follow-up turns should address NEW issues, not repeat previous requests."
                    ))

    def _text_overlap(self, text_a: str, text_b: str) -> float:
        words_a = set(text_a.lower().split())
        words_b = set(text_b.lower().split())
        if not words_a or not words_b:
            return 0.0
        intersection = words_a & words_b
        # Remove common stop words
        stop = {'the', 'a', 'an', 'is', 'are', 'was', 'were', 'to', 'in', 'of', 'and', 'or', 'for', 'with', 'that', 'this', 'it', 'on', 'at', 'by', 'from', 'as', 'be', 'not', 'but', 'if'}
        meaningful_intersection = intersection - stop
        meaningful_b = words_b - stop
        if not meaningful_b:
            return 0.0
        return len(meaningful_intersection) / len(meaningful_b)

    # ═══════════════════════════════════════════════════════════════════
    # 5. TURN COUNT AND QUALITY
    # ═══════════════════════════════════════════════════════════════════
    def check_turn_count(self, turns: list[str]):
        if len(turns) < 3:
            self.issues.append(Issue(
                CRITICAL, "Turn Count",
                f"Only {len(turns)} turn(s) provided. Minimum 3 required.",
                "Turns",
                "Add more meaningful follow-up turns. Each must advance the implementation."
            ))

    def check_turn_specificity(self, turns: list[str]):
        for i, turn in enumerate(turns, start=1):
            # Check for file/function references (sign of specificity)
            has_file_ref = bool(re.search(r'\b\w+\.(py|js|ts|tsx|jsx|go|rs|java|cpp|c|h|rb|php)\b', turn))
            has_func_ref = bool(re.search(r'\b(function|method|class|def|func|fn)\s+\w+\b|`\w+\(`|\b\w+\(\)\b', turn, re.IGNORECASE))
            has_specific_ref = has_file_ref or has_func_ref

            word_count = len(turn.split())

            if i > 1 and not has_specific_ref and word_count < 100:
                self.issues.append(Issue(
                    MEDIUM, "Turn Specificity",
                    f"Turn {i} doesn't reference specific files or functions",
                    f"Turn {i}",
                    "Name the exact file, function, or behavior you want changed."
                ))

            if word_count < 15:
                self.issues.append(Issue(
                    HIGH, "Turn Quality",
                    f"Turn {i} is very short ({word_count} words) — likely not specific enough",
                    f"Turn {i}",
                    "Follow-up turns should describe the specific issue, what to change, and where."
                ))

    # ═══════════════════════════════════════════════════════════════════
    # 6. EVALUATION / RATING CONSISTENCY
    # ═══════════════════════════════════════════════════════════════════
    RATING_STRONG_LANGUAGE = {
        'A1': ['fails', 'incorrect', 'broken', 'fundamentally', 'completely wrong', 'does not work'],
        'B1': ['fails', 'incorrect', 'broken', 'fundamentally', 'completely wrong', 'does not work'],
        'A2': ['substantially', 'significantly', 'missing key', 'major gap', 'critical'],
        'B2': ['substantially', 'significantly', 'missing key', 'major gap', 'critical'],
    }

    def check_rating_consistency(self, rating: str, justification: str, strengths_a: str, weaknesses_a: str, strengths_b: str, weaknesses_b: str):
        if not rating or not justification:
            return

        rating = rating.upper().strip()

        # Check extreme ratings have strong language
        if rating in self.RATING_STRONG_LANGUAGE:
            required_words = self.RATING_STRONG_LANGUAGE[rating]
            has_strong = any(w in justification.lower() for w in required_words)
            if not has_strong:
                winner = "A" if rating.startswith("A") else "B"
                self.issues.append(Issue(
                    HIGH, "Rating Consistency",
                    f"Rating {rating} (extreme) but justification lacks strong language like: {', '.join(required_words[:3])}",
                    "Justification",
                    f"For {rating}, use language that matches the severity: 'fails', 'broken', 'fundamentally wrong', etc."
                ))

        # Check A-favoring rating has more A strengths than B
        if rating.startswith("A") and rating not in ["A4"]:
            if len(strengths_b) > len(strengths_a) * 1.5 and len(strengths_b) > 100:
                self.issues.append(Issue(
                    HIGH, "Rating Consistency",
                    f"Rating favors A ({rating}) but B's strengths section is longer/more detailed than A's",
                    "Strengths",
                    "Make sure your strengths and weaknesses align with your rating."
                ))

        if rating.startswith("B") and rating not in ["B4"]:
            if len(strengths_a) > len(strengths_b) * 1.5 and len(strengths_a) > 100:
                self.issues.append(Issue(
                    HIGH, "Rating Consistency",
                    f"Rating favors B ({rating}) but A's strengths section is longer/more detailed than B's",
                    "Strengths",
                    "Make sure your strengths and weaknesses align with your rating."
                ))

    def check_strengths_evaluative(self, text: str, field: str):
        """Strengths must explain WHY something matters, not just describe what was done."""
        if not text.strip():
            self.issues.append(Issue(HIGH, "Empty Field", f"{field} is empty", field))
            return

        descriptive_patterns = [
            r'^(added|implemented|created|wrote|updated|modified|changed|fixed)\s+',
            r'^(uses?|utilizes?)\s+',
        ]
        lines = [l.strip() for l in text.strip().split('\n') if l.strip()]
        descriptive_count = 0
        for line in lines:
            clean = re.sub(r'^[-*•]\s*', '', line)
            for p in descriptive_patterns:
                if re.match(p, clean, re.IGNORECASE):
                    descriptive_count += 1
                    break

        if len(lines) >= 3 and descriptive_count / len(lines) > 0.6:
            self.issues.append(Issue(
                MEDIUM, "Evaluative Strengths",
                f"{field}: Most lines just describe what was done, not WHY it matters",
                field,
                "Explain impact: 'A caught the import cycle before it broke anything' vs 'A added error handling'"
            ))

    # ═══════════════════════════════════════════════════════════════════
    # 7. PROMPT COMPLEXITY CHECK
    # ═══════════════════════════════════════════════════════════════════
    def check_prompt_complexity(self, turn1: str):
        word_count = len(turn1.split())
        if word_count < 50:
            self.issues.append(Issue(
                HIGH, "Trivial Prompt",
                f"Turn 1 is only {word_count} words — may be too simple for V3 requirements",
                "Turn 1",
                "V3 requires ~6-8 engineer-hours complexity. The prompt should describe a multi-step, non-trivial task."
            ))

        # Count distinct action items / requirements
        numbered_items = len(re.findall(r'^\s*\d+[.)]\s', turn1, re.MULTILINE))
        bullet_items = len(re.findall(r'^\s*[-*•]\s', turn1, re.MULTILINE))
        total_items = numbered_items + bullet_items

        if total_items < 2 and word_count < 100:
            self.issues.append(Issue(
                MEDIUM, "Trivial Prompt",
                "Turn 1 has few distinct requirements — might be too trivial",
                "Turn 1",
                "A good prompt lists 3-6 concrete requirements with acceptance criteria."
            ))

    # ═══════════════════════════════════════════════════════════════════
    # 8. OVER-PRESCRIPTIVE CHECK
    # ═══════════════════════════════════════════════════════════════════
    def check_over_prescriptive(self, turn1: str):
        line_ref_count = len(re.findall(r'\bline\s+\d+\b', turn1, re.IGNORECASE))
        exact_change_count = len(re.findall(r'\bchange\s+\w+\s+to\s+\w+\b', turn1, re.IGNORECASE))
        replace_count = len(re.findall(r'\breplace\s+`[^`]+`\s+with\s+`[^`]+`\b', turn1, re.IGNORECASE))

        total = line_ref_count + exact_change_count + replace_count
        if total >= 3:
            self.issues.append(Issue(
                HIGH, "Over-Prescriptive",
                f"Turn 1 has {total} specific line/change references — may be over-prescriptive",
                "Turn 1",
                "Describe the problem and success criteria, not exact line-by-line changes."
            ))

    # ═══════════════════════════════════════════════════════════════════
    # 13. EVALUATION CONSISTENCY CHECK
    # ═══════════════════════════════════════════════════════════════════
    def check_eval_consistency(self, strengths_a: str, weaknesses_a: str,
                                strengths_b: str, weaknesses_b: str,
                                justification: str, rating: str):
        """Check that strengths don't contradict weaknesses, and all claims are grounded."""
        if not rating:
            return

        rating = rating.upper().strip()
        winner = "A" if rating.startswith("A") and rating not in ["A4"] else \
                 "B" if rating.startswith("B") and rating not in ["B4"] else "tie"

        # Winner should have more strengths than loser
        if winner == "A" and strengths_b and strengths_a:
            if len(strengths_b.split()) > len(strengths_a.split()) * 1.8:
                self.issues.append(Issue(
                    HIGH, "Eval Consistency",
                    f"Rating favors A ({rating}) but B has more detailed strengths ({len(strengths_b.split())} vs {len(strengths_a.split())} words)",
                    "Strengths",
                    "The winner's strengths should be more detailed than the loser's."
                ))

        if winner == "B" and strengths_a and strengths_b:
            if len(strengths_a.split()) > len(strengths_b.split()) * 1.8:
                self.issues.append(Issue(
                    HIGH, "Eval Consistency",
                    f"Rating favors B ({rating}) but A has more detailed strengths ({len(strengths_a.split())} vs {len(strengths_b.split())} words)",
                    "Strengths",
                    "The winner's strengths should be more detailed than the loser's."
                ))

        # Check minimum length for strengths and justification
        for field_name, field_text, min_words in [
            ("Strengths A", strengths_a, 30),
            ("Strengths B", strengths_b, 30),
            ("Justification", justification, 40),
        ]:
            if field_text and len(field_text.split()) < min_words:
                self.issues.append(Issue(
                    MEDIUM, "Eval Depth",
                    f"{field_name} is only {len(field_text.split())} words — likely too brief",
                    field_name,
                    f"Aim for {min_words}+ words with specific file/function references."
                ))

    # ═══════════════════════════════════════════════════════════════════
    # 14. PRODUCTION-READY CHECK
    # ═══════════════════════════════════════════════════════════════════
    def check_production_ready_language(self, turns: list[str]):
        """Last turn should indicate production-readiness."""
        if len(turns) < 3:
            return
        last_turn = turns[-1].lower()
        has_completion_signal = any(phrase in last_turn for phrase in [
            'production ready', 'ready to merge', 'complete', 'finalize',
            'all tests', 'remaining', 'integration', 'cleanup'
        ])
        if not has_completion_signal:
            self.issues.append(Issue(
                MEDIUM, "Completion Signal",
                f"Last turn (Turn {len(turns)}) doesn't mention production readiness or completion",
                f"Turn {len(turns)}",
                "Final turn should push toward production-ready state. If more work is needed, add another turn."
            ))

    # ═══════════════════════════════════════════════════════════════════
    # 9. CLAUDE.md DELEGATION CHECK (from Training Hub)
    # ═══════════════════════════════════════════════════════════════════
    def check_claudemd_delegation(self, turns: list[str]):
        """CLAUDE.md must be created by YOU, not via a turn prompt."""
        for i, turn in enumerate(turns, 1):
            if re.search(r'\bcreate\s+(a\s+)?CLAUDE\.md\b', turn, re.IGNORECASE) or \
               re.search(r'\bgenerate\s+(a\s+)?CLAUDE\.md\b', turn, re.IGNORECASE) or \
               re.search(r'\bwrite\s+(a\s+)?CLAUDE\.md\b', turn, re.IGNORECASE):
                self.issues.append(Issue(
                    CRITICAL, "CLAUDE.md Delegation",
                    f"Turn {i} asks the model to create CLAUDE.md — this must be done by YOU before launching CLI",
                    f"Turn {i}",
                    "Create CLAUDE.md manually or via a separate instance. Never delegate via a turn prompt."
                ))

    # ═══════════════════════════════════════════════════════════════════
    # 10. TURN CONTRADICTION CHECK (from Training Hub)
    # ═══════════════════════════════════════════════════════════════════
    def check_turn_contradictions(self, turns: list[str]):
        """Turn 1 instructions contradicted by later turn criticism."""
        if len(turns) < 2:
            return
        turn1_lower = turns[0].lower()

        negations_t1 = []
        for pattern in [r'do\s+not\s+(\w+(?:\s+\w+){0,3})', r'don\'t\s+(\w+(?:\s+\w+){0,3})', r'avoid\s+(\w+(?:\s+\w+){0,3})', r'without\s+(\w+(?:\s+\w+){0,3})']:
            for m in re.finditer(pattern, turn1_lower):
                negations_t1.append(m.group(1).strip())

        for i, turn in enumerate(turns[1:], start=2):
            turn_lower = turn.lower()
            for neg in negations_t1:
                key_word = neg.split()[0] if neg.split() else ""
                if key_word and len(key_word) > 3:
                    if re.search(rf"\b(didn't|did not|doesn't|does not|failed to|missing)\b.*\b{re.escape(key_word)}\b", turn_lower):
                        self.issues.append(Issue(
                            HIGH, "Turn Contradiction",
                            f"Turn 1 says 'do not {neg}' but Turn {i} may criticize the model for not doing it",
                            f"Turn {i}",
                            "Don't contradict your own Turn 1 instructions in follow-ups."
                        ))

    # ═══════════════════════════════════════════════════════════════════
    # 11. KEY-AXIS FIELD CHECK (from Training Hub Quiz Q11)
    # ═══════════════════════════════════════════════════════════════════
    def check_key_axis(self, rating: str, key_axis: str):
        """Key-axis required for A1, A2, B1, B2 (per quiz). Also needed for A3, B3 per master guide."""
        if not rating:
            return
        rating = rating.upper().strip()
        needs_key_axis = rating in ["A1", "A2", "A3", "B1", "B2", "B3"]
        if needs_key_axis and (not key_axis or len(key_axis.strip()) < 10):
            self.issues.append(Issue(
                CRITICAL, "Key-Axis Missing",
                f"Rating is {rating} but key-axis field is empty or too short",
                "Key-Axis",
                "Name the dimension that drove the preference: correctness, test coverage, scope control, root cause handling, or self-reporting accuracy."
            ))

    # ═══════════════════════════════════════════════════════════════════
    # 12. RANDOM MARKDOWN/BOLDING CHECK (from Training Hub LLM signals)
    # ═══════════════════════════════════════════════════════════════════
    def check_random_formatting(self, text: str, field: str):
        """Random bolding, italics, code-wrapping for no reason = LLM signal."""
        bold_count = len(re.findall(r'\*\*\w+\*\*', text))
        code_count = len(re.findall(r'`\w+`', text))
        word_count = len(text.split())

        if word_count > 30:
            if bold_count >= 4:
                self.issues.append(Issue(
                    MEDIUM, "LLM Indicator",
                    f"{field}: {bold_count} bolded words — random bolding is an LLM signal",
                    field,
                    "Remove unnecessary markdown formatting. Real developers don't bold random words."
                ))
            if code_count >= 5 and not re.search(r'\.(py|js|ts|go|rs)\b', text):
                self.issues.append(Issue(
                    MEDIUM, "LLM Indicator",
                    f"{field}: {code_count} code-wrapped words — excessive backtick wrapping is an LLM signal",
                    field,
                    "Only use backticks for actual code references (file names, function names, commands)."
                ))

    # ═══════════════════════════════════════════════════════════════════
    # MAIN VALIDATION
    # ═══════════════════════════════════════════════════════════════════
    def validate(self, data: dict) -> list[Issue]:
        self.issues = []

        turns = data.get("turns", [])

        # New April 7 fields (per model, per turn)
        solution_quality_a = data.get("solution_quality_a", data.get("strengths_a", ""))
        solution_quality_b = data.get("solution_quality_b", data.get("strengths_b", ""))
        agency_a = data.get("agency_a", "")
        agency_b = data.get("agency_b", "")
        communication_a = data.get("communication_a", "")
        communication_b = data.get("communication_b", "")

        # Legacy fields (still accepted for backward compat)
        strengths_a = data.get("strengths_a", solution_quality_a)
        weaknesses_a = data.get("weaknesses_a", "")
        strengths_b = data.get("strengths_b", solution_quality_b)
        weaknesses_b = data.get("weaknesses_b", "")

        justification = data.get("justification", "")
        rating = data.get("rating", "")
        expected_response = data.get("senior_expectations", data.get("expected_response", ""))

        # All text fields for scanning
        all_eval_fields = [
            ("Solution Quality A", solution_quality_a),
            ("Solution Quality B", solution_quality_b),
            ("Agency A", agency_a),
            ("Agency B", agency_b),
            ("Communication A", communication_a),
            ("Communication B", communication_b),
            ("Justification", justification),
            ("Expected Response", expected_response),
        ]

        # 1. Check all text fields for PR references, LLM indicators
        for i, turn in enumerate(turns, 1):
            self.check_pr_references(turn, f"Turn {i}")
            self.check_role_prompting(turn, f"Turn {i}")
            self.check_llm_indicators(turn, f"Turn {i}")

        for field_name, field_text in all_eval_fields:
            if field_text:
                self.check_pr_references(field_text, field_name)
                self.check_llm_indicators(field_text, field_name)

        # 2. Turn quality
        self.check_turn_count(turns)
        self.check_turn_redundancy(turns)
        self.check_turn_specificity(turns)
        self.check_claudemd_delegation(turns)
        self.check_turn_contradictions(turns)

        # 3. Turn 1 prompt quality
        if turns:
            self.check_prompt_complexity(turns[0])
            self.check_over_prescriptive(turns[0])

        # 4. Evaluation quality (Solution Quality fields replace old Strengths)
        if solution_quality_a:
            self.check_strengths_evaluative(solution_quality_a, "Solution Quality A")
        if solution_quality_b:
            self.check_strengths_evaluative(solution_quality_b, "Solution Quality B")

        # 4b. Agency must cite trace evidence
        for label, text in [("Agency A", agency_a), ("Agency B", agency_b)]:
            if text:
                trace_words = ['trace', 'transcript', 'ran ', 'executed', 'command', 'grep', 'cat ',
                               'test', 'pytest', 'npm test', 'shows it', 'log shows']
                has_trace_ref = any(w in text.lower() for w in trace_words)
                if not has_trace_ref:
                    self.issues.append(Issue(
                        HIGH, "Agency Evidence",
                        f"{label} does not reference model trace/transcript evidence",
                        label,
                        "Agency field MUST cite specific transcript evidence (trace commands, model behavior)."
                    ))

        if rating and justification:
            self.check_rating_consistency(rating, justification,
                                          solution_quality_a, weaknesses_a,
                                          solution_quality_b, weaknesses_b)

        # 5. Key-axis check (must NOT default to correctness)
        key_axis = data.get("key_axis", "")
        if rating:
            self.check_key_axis(rating, key_axis)
            if key_axis and key_axis.strip().lower() in ['correctness', 'correct answer', 'correct']:
                self.issues.append(Issue(
                    MEDIUM, "Key-Axis Default",
                    "Key-axis is set to 'correctness' — consider if scope control, testing quality, or honesty was the true driver",
                    "Key-Axis",
                    "April 7 update: do NOT default to correctness. Reflect the true driver of preference."
                ))

        # 6. Random formatting (LLM signals)
        for field_name, field_text in all_eval_fields:
            if field_text:
                self.check_random_formatting(field_text, field_name)

        # 7. Evaluation consistency
        if rating:
            self.check_eval_consistency(solution_quality_a, weaknesses_a,
                                        solution_quality_b, weaknesses_b,
                                        justification, rating)

        # 8. Production-ready check on final turn
        self.check_production_ready_language(turns)

        # 9. Empty required fields (new structure)
        required_fields = [
            ("Solution Quality A", solution_quality_a),
            ("Solution Quality B", solution_quality_b),
            ("Justification", justification),
        ]
        for field_name, field_text in required_fields:
            if not field_text or len(field_text.strip()) < 20:
                self.issues.append(Issue(
                    CRITICAL, "Empty Field",
                    f"{field_name} is empty or too short ({len(field_text.strip()) if field_text else 0} chars)",
                    field_name,
                    "Each field needs substantive, evidence-based content."
                ))

        # Agency and Communication recommended but not always required
        for field_name, field_text in [("Agency A", agency_a), ("Agency B", agency_b),
                                        ("Communication A", communication_a), ("Communication B", communication_b)]:
            if not field_text or len(field_text.strip()) < 10:
                self.issues.append(Issue(
                    MEDIUM, "Missing Field",
                    f"{field_name} is empty or very short — reviewers check all 3 fields",
                    field_name,
                    "Fill all 3 per-model fields: Solution Quality, Agency, Communication."
                ))

        return self.issues

    def print_report(self, issues: list[Issue]):
        critical = [i for i in issues if i.severity == CRITICAL]
        high = [i for i in issues if i.severity == HIGH]
        medium = [i for i in issues if i.severity == MEDIUM]
        low = [i for i in issues if i.severity == LOW]

        print(f"\n{BOLD}{'='*60}{NC}")
        print(f"{BOLD}  MARLIN V3 — PRE-SUBMISSION VALIDATION REPORT{NC}")
        print(f"{BOLD}{'='*60}{NC}\n")

        if not issues:
            print(f"  {GREEN}{BOLD}✓ ALL CHECKS PASSED — Safe to submit{NC}\n")
            return True

        for severity_label, group, color in [
            ("CRITICAL", critical, RED),
            ("HIGH", high, YELLOW),
            ("MEDIUM", medium, CYAN),
            ("LOW", low, DIM),
        ]:
            if group:
                print(f"  {color}{BOLD}{severity_label} ({len(group)}){NC}")
                for issue in group:
                    print(issue)
                print()

        print(f"{BOLD}{'─'*60}{NC}")
        print(f"  Total: {RED}{len(critical)} critical{NC}, {YELLOW}{len(high)} high{NC}, {CYAN}{len(medium)} medium{NC}, {DIM}{len(low)} low{NC}")
        print()

        if critical:
            print(f"  {RED}{BOLD}✗ DO NOT SUBMIT — {len(critical)} critical issue(s) will cause rejection{NC}")
            return False
        elif high:
            print(f"  {YELLOW}{BOLD}⚠ RISKY — {len(high)} high-severity issue(s) may cause rejection{NC}")
            return False
        else:
            print(f"  {GREEN}{BOLD}✓ LIKELY SAFE — only minor issues found{NC}")
            return True


def interactive_mode():
    print(f"\n{BOLD}{CYAN}  MARLIN V3 — Pre-Submission Task Validator{NC}")
    print(f"  {DIM}Paste your content. Press Enter twice (empty line) to finish each field.{NC}\n")

    def read_multiline(prompt):
        print(f"  {BOLD}{prompt}{NC}")
        print(f"  {DIM}(Enter text, then press Enter twice when done){NC}")
        lines = []
        while True:
            try:
                line = input()
            except EOFError:
                break
            if line == "" and lines and lines[-1] == "":
                lines.pop()
                break
            lines.append(line)
        return "\n".join(lines)

    turns = []
    print(f"\n{BOLD}── PROMPTS / TURNS ──{NC}\n")
    for i in range(1, 6):
        turn = read_multiline(f"Turn {i} prompt (leave empty to stop):")
        if not turn.strip():
            break
        turns.append(turn)
        print(f"  {GREEN}✓ Turn {i} captured ({len(turn.split())} words){NC}\n")

    print(f"\n{BOLD}── EVALUATION (April 7 format: Solution Quality / Agency / Communication) ──{NC}\n")
    solution_quality_a = read_multiline("Model A — Solution Quality (correctness, code quality, tests):")
    agency_a = read_multiline("Model A — Agency (trace evidence: investigation, judgment, safety):")
    communication_a = read_multiline("Model A — Communication (honesty, self-reporting accuracy):")
    print()
    solution_quality_b = read_multiline("Model B — Solution Quality (correctness, code quality, tests):")
    agency_b = read_multiline("Model B — Agency (trace evidence: investigation, judgment, safety):")
    communication_b = read_multiline("Model B — Communication (honesty, self-reporting accuracy):")
    print()
    justification = read_multiline("Overall Preference Justification:")
    expected_response = read_multiline("Expected Model Response (senior engineer baseline):")
    key_axis = read_multiline("Key Axis (what drove the preference — NOT just 'correctness'):")

    print(f"\n{BOLD}── RATING ──{NC}")
    rating = input(f"  Overall rating (A1/A2/A3/A4/B4/B3/B2/B1): ").strip()

    data = {
        "turns": turns,
        "solution_quality_a": solution_quality_a,
        "agency_a": agency_a,
        "communication_a": communication_a,
        "solution_quality_b": solution_quality_b,
        "agency_b": agency_b,
        "communication_b": communication_b,
        "justification": justification,
        "expected_response": expected_response,
        "key_axis": key_axis,
        "rating": rating,
    }

    validator = TaskValidator()
    issues = validator.validate(data)
    passed = validator.print_report(issues)
    sys.exit(0 if passed else 1)


def json_mode(filepath: str):
    with open(filepath) as f:
        data = json.load(f)

    validator = TaskValidator()
    issues = validator.validate(data)
    passed = validator.print_report(issues)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Marlin V3 Pre-Submission Task Validator")
    parser.add_argument("--json", "-j", help="Path to JSON file with task data")
    args = parser.parse_args()

    if args.json:
        json_mode(args.json)
    else:
        interactive_mode()
