#!/usr/bin/env python3
"""
MARLIN V3 -- Prompt Quality Validator (v3 -- Deep AI-Detection Hardened)

Goes beyond surface-level word checks. Detects the statistical and structural
patterns that real AI detectors (Undetectable AI, GPTZero, Originality.ai) use:
  - Relative clause density & "that" chaining
  - Imperative verb parallelism / syntactic template repetition
  - Prepositional phrase stacking depth
  - Formality uniformity (missing all informal markers)
  - AI softener / qualifier words ("clearly", "dedicated", "proper")
  - Burstiness and perplexity proxies

Usage:
    python3 prompt_validator.py "Your prompt text here"
    python3 prompt_validator.py --file path/to/prompt.txt
"""

import re
import sys
import math
from collections import Counter


# ---------------------------------------------------------------------------
# CHECK 1: Em-dashes and unusual dashes
# ---------------------------------------------------------------------------
def check_em_dashes(text: str) -> list[str]:
    issues = []
    if "\u2014" in text:
        issues.append(f"Em-dash (U+2014) found {text.count(chr(0x2014))}x -- use a comma, period, or rewrite")
    if "\u2013" in text:
        issues.append(f"En-dash (U+2013) found {text.count(chr(0x2013))}x -- use a hyphen or rewrite")
    double_dash_count = len(re.findall(r'(?<!\-)\-\-(?!\-)', text))
    if double_dash_count:
        issues.append(
            f'Double-dash "--" found {double_dash_count}x. '
            f'This is an AI workaround for em-dashes. Use a comma, period, '
            f'colon, or just split the sentence instead.'
        )
    return issues


# ---------------------------------------------------------------------------
# CHECK 2: PR references
# ---------------------------------------------------------------------------
def check_pr_references(text: str) -> list[str]:
    issues = []
    t = text.lower()
    if re.search(r'#\d{3,6}', text):
        issues.append("PR number reference (#digits) found")
    if re.search(r'pull/\d+', t):
        issues.append("Pull URL reference found")
    if re.search(r'\bpr[\s-]?\d+', t):
        issues.append("PR label reference found")
    for phrase in ["this pr", "the pr", "this pull request", "the pull request",
                   "in the pr", "from the pr", "pr changes", "pr description"]:
        pat = r'\b' + re.escape(phrase) + r'\b'
        m = re.search(pat, t)
        if m:
            ctx = t[max(0, m.start()-15):m.end()+15]
            skip = any(w in ctx for w in ["project", "process", "program", "problem",
                                          "protocol", "property", "practice", "procedure",
                                          "provide", "produce", "product", "protect"])
            if not skip:
                issues.append(f'PR phrase: "{phrase}"')
    return issues


# ---------------------------------------------------------------------------
# CHECK 3: Role-based prompting
# ---------------------------------------------------------------------------
def check_role_prompting(text: str) -> list[str]:
    issues = []
    patterns = [
        r'(?i)\byou are a[n]?\s+\w+',
        r'(?i)\bact as a[n]?\s+\w+',
        r'(?i)\bimagine you',
        r'(?i)\bpretend you',
        r'(?i)\byour role is',
        r'(?i)\bas a senior\b',
        r'(?i)\bas an expert\b',
    ]
    for p in patterns:
        if re.search(p, text):
            issues.append(f"Role-based prompting: {p}")
    return issues


# ---------------------------------------------------------------------------
# CHECK 4: Over-prescriptive
# ---------------------------------------------------------------------------
def check_over_prescriptive(text: str) -> list[str]:
    issues = []
    patterns = [
        (r'(?i)\bon line \d+', "Line number reference"),
        (r'(?i)\bat line \d+', "Line number reference"),
        (r'(?i)\bline \d+ of\b', "Line number reference"),
        (r'(?i)change .{3,40} to .{3,40} in .+\.\w{1,4}', "Specific file change instruction"),
        (r'(?i)step \d+\s*:', "Numbered step instructions"),
    ]
    for p, label in patterns:
        if re.search(p, text):
            issues.append(label)
    return issues


# ---------------------------------------------------------------------------
# CHECK 5: LLM signature words (massively expanded)
# ---------------------------------------------------------------------------
_SIGNATURE_WORDS = {
    # Tier 1: dead giveaways (almost never used by humans in tech writing)
    "leverage": ("use", "CRITICAL"),
    "utilize": ("use", "CRITICAL"),
    "delve": ("look into", "CRITICAL"),
    "tapestry": ("remove entirely", "CRITICAL"),
    "multifaceted": ("complex", "CRITICAL"),
    "holistic": ("full / complete", "CRITICAL"),
    "synergy": ("combination", "CRITICAL"),
    "paradigm": ("approach", "CRITICAL"),
    "cutting-edge": ("modern", "CRITICAL"),
    "state-of-the-art": ("current / modern", "CRITICAL"),
    "in conclusion": ("drop it", "CRITICAL"),
    "it's worth noting": ("just state it directly", "CRITICAL"),
    "it is important to note": ("just state it directly", "CRITICAL"),
    "it should be noted": ("just state it directly", "CRITICAL"),
    "it bears mentioning": ("drop it", "CRITICAL"),
    "plays a crucial role": ("matters / is needed", "CRITICAL"),
    "a testament to": ("shows / proves", "CRITICAL"),
    "at its core": ("basically / fundamentally", "CRITICAL"),
    "in today's landscape": ("drop it", "CRITICAL"),
    "the landscape of": ("drop it", "CRITICAL"),

    # Tier 2: suspicious if clustered (humans use rarely, AI uses often)
    "comprehensive": ("complete / full / thorough", "WARNING"),
    "robust": ("strong / solid / reliable", "WARNING"),
    "seamless": ("smooth", "WARNING"),
    "facilitate": ("help / enable / allow", "WARNING"),
    "enhance": ("improve", "WARNING"),
    "streamline": ("simplify", "WARNING"),
    "optimize": ("improve / speed up", "WARNING"),
    "pivotal": ("key / important", "WARNING"),
    "foster": ("encourage / build", "WARNING"),
    "elevate": ("improve / raise", "WARNING"),
    "empower": ("enable / let", "WARNING"),
    "harness": ("use / apply", "WARNING"),
    "bolster": ("strengthen", "WARNING"),
    "underscore": ("highlight / show", "WARNING"),
    "navigate": ("handle / work through", "WARNING"),
    "spearhead": ("lead", "WARNING"),
    "realm": ("area / domain / field", "WARNING"),
    "cornerstone": ("foundation / base", "WARNING"),
    "encompasses": ("includes / covers", "WARNING"),
    "intricate": ("complex / detailed", "WARNING"),
    "notably": ("especially", "WARNING"),
    "crucially": ("importantly", "WARNING"),
    "inherently": ("naturally / by nature", "WARNING"),
    "nuanced": ("subtle / detailed", "WARNING"),
    "overarching": ("main / broad", "WARNING"),
    "aforementioned": ("above / earlier", "WARNING"),
    "subsequently": ("then / next / after", "WARNING"),
    "respectively": ("(often unnecessary)", "WARNING"),
    "meticulously": ("carefully", "WARNING"),
    "judiciously": ("carefully / wisely", "WARNING"),

    # Tier 3: AI softener/qualifier words (sound professional but scream AI)
    # NOTE: "dedicated", "structured", "properly", "clearly" are ALLOWED
    # because Marlin V3's official good prompt example uses them.
    "appropriate": ("right / correct", "WARNING"),
    "relevant": ("related / matching", "WARNING"),
    "respective": ("matching / corresponding", "WARNING"),
    "various": ("several / different / a few", "WARNING"),
    "functionality": ("feature / behavior / logic", "WARNING"),
    "straightforward": ("simple / easy", "WARNING"),
    "demonstrates": ("shows", "WARNING"),
    "corresponding": ("matching", "WARNING"),
}

def check_llm_signature_words(text: str) -> list[str]:
    issues = []
    t = text.lower()
    crit_count = 0
    warn_count = 0
    for word, (replacement, severity) in _SIGNATURE_WORDS.items():
        if word in t:
            n = t.count(word)
            issues.append(f'[{severity}] "{word}" ({n}x) -> use "{replacement}"')
            if severity == "CRITICAL":
                crit_count += n
            else:
                warn_count += n
    return issues


# ---------------------------------------------------------------------------
# CHECK 6: AI transition and filler phrases
# ---------------------------------------------------------------------------
_AI_TRANSITIONS = [
    "additionally", "furthermore", "moreover", "consequently",
    "in addition", "as a result", "in light of", "with that said",
    "that being said", "on the other hand", "in this regard",
    "to that end", "with this in mind", "by the same token",
    "in essence", "in summary", "to summarize", "overall",
    "moving forward", "going forward", "as we move forward",
    "it is essential", "it is crucial", "it is vital",
    "it is imperative", "it is worth mentioning", "it is noteworthy",
    "this ensures", "this enables", "this allows for",
    "this approach ensures", "this helps ensure",
    "not only", "but also",
]

def check_ai_transitions(text: str) -> list[str]:
    issues = []
    t = text.lower()
    found = []
    for phrase in _AI_TRANSITIONS:
        count = len(re.findall(r'\b' + re.escape(phrase) + r'\b', t))
        if count:
            found.append(f'"{phrase}" ({count}x)')
    if found:
        issues.append(f"AI transition phrases: {', '.join(found)}")
        if len(found) >= 3:
            issues.append(f"HIGH AI SIGNAL: {len(found)} different AI transition phrases detected")
    return issues


# ---------------------------------------------------------------------------
# CHECK 7: Adverb overuse (AI signature)
# ---------------------------------------------------------------------------
_AI_ADVERBS = [
    "effectively", "efficiently", "seamlessly", "significantly",
    "fundamentally", "essentially", "particularly", "specifically",
    "ultimately", "inherently", "critically", "notably",
    "increasingly", "accordingly", "precisely", "proactively",
    "systematically", "comprehensively", "strategically",
    "demonstrably", "ostensibly", "unequivocally",
]

def check_adverb_overuse(text: str) -> list[str]:
    issues = []
    t = text.lower()
    found = []
    for adv in _AI_ADVERBS:
        if adv in t:
            found.append(adv)
    if len(found) >= 2:
        issues.append(f'Adverb cluster: {", ".join(found)} -- drop most of them, humans use fewer adverbs')
    elif len(found) == 1:
        issues.append(f'AI-associated adverb: "{found[0]}" -- consider removing')
    return issues


# ---------------------------------------------------------------------------
# CHECK 8: Sentence starter repetition
# ---------------------------------------------------------------------------
def check_sentence_starters(text: str) -> list[str]:
    issues = []
    sents = [s for s in _split_sentences(text) if len(s.split()) > 3]
    if len(sents) < 4:
        return issues

    starters = [s.split()[0].lower() for s in sents]
    starter_counts = Counter(starters)

    for word, count in starter_counts.most_common(5):
        ratio = count / len(sents)
        if count >= 3 and ratio >= 0.3:
            issues.append(
                f'{count}/{len(sents)} sentences start with "{word}" ({ratio:.0%}) '
                f'-- vary your openings'
            )
        elif word == "the" and count >= 3:
            issues.append(
                f'{count} sentences start with "The" -- AI signature, reword some'
            )

    first_two = [s.split()[:2] for s in sents]
    first_two_str = [" ".join(w).lower() for w in first_two]
    two_counts = Counter(first_two_str)
    for phrase, count in two_counts.most_common(3):
        if count >= 2:
            issues.append(f'{count} sentences start with "{phrase}" -- vary the structure')

    return issues


# ---------------------------------------------------------------------------
# CHECK 9: Passive voice density
# ---------------------------------------------------------------------------
_PASSIVE_PATTERNS = [
    r'\b(?:is|are|was|were|be|been|being)\s+\w+ed\b',
    r'\b(?:is|are|was|were|be|been|being)\s+\w+en\b',
    r'\b(?:should|must|can|could|will|would|may|might)\s+be\s+\w+ed\b',
]

def _split_sentences(text: str) -> list[str]:
    """Split text into sentences, handling file extensions and abbreviations."""
    cleaned = re.sub(r'(\w+)\.(\w{1,4})(?=[\s,;:\)]|$)', r'\1_DOT_\2', text)
    cleaned = re.sub(r'\b(e\.g|i\.e|etc|vs|Dr|Mr|Mrs|Ms)\.\s', r'\1_DOT_ ', cleaned)
    parts = re.split(r'[.!?]+', cleaned)
    return [s.strip().replace('_DOT_', '.') for s in parts if s.strip() and len(s.split()) > 2]

def check_passive_voice(text: str) -> list[str]:
    issues = []
    sents = _split_sentences(text)
    if not sents:
        return issues

    passive_count = 0
    for sent in sents:
        for pat in _PASSIVE_PATTERNS:
            if re.search(pat, sent, re.IGNORECASE):
                passive_count += 1
                break

    ratio = passive_count / len(sents) if sents else 0
    if ratio > 0.4:
        issues.append(
            f"High passive voice: {passive_count}/{len(sents)} sentences ({ratio:.0%}) "
            f"-- rewrite some in active voice"
        )
    elif ratio > 0.25:
        issues.append(
            f"Moderate passive voice: {passive_count}/{len(sents)} ({ratio:.0%}) "
            f"-- consider rewriting 1-2 in active voice"
        )
    return issues


# ---------------------------------------------------------------------------
# CHECK 10: Lack of contractions (AI avoids contractions)
# ---------------------------------------------------------------------------
_EXPANDABLE = {
    "do not": "don't", "does not": "doesn't", "did not": "didn't",
    "is not": "isn't", "are not": "aren't", "was not": "wasn't",
    "were not": "weren't", "will not": "won't", "would not": "wouldn't",
    "could not": "couldn't", "should not": "shouldn't",
    "can not": "can't", "cannot": "can't",
    "it is": "it's", "that is": "that's",
    "there is": "there's",
}

def check_contractions(text: str) -> list[str]:
    issues = []
    t = text.lower()
    expanded_count = 0
    found_pairs = []
    for expanded, contracted in _EXPANDABLE.items():
        n = len(re.findall(r'\b' + re.escape(expanded) + r'\b', t))
        if n:
            expanded_count += n
            found_pairs.append(f'"{expanded}" -> "{contracted}"')

    has_any_contraction = bool(re.search(r"\w+'(?:t|s|re|ve|ll|d|m)\b", t))

    if expanded_count >= 3 and not has_any_contraction:
        issues.append(
            f"No contractions used but {expanded_count} expandable phrases found -- "
            f"AI avoids contractions, humans use them naturally. Contract some: "
            + "; ".join(found_pairs[:4])
        )
    elif expanded_count >= 2 and not has_any_contraction:
        issues.append(
            f"Consider using contractions for natural tone: " + "; ".join(found_pairs[:3])
        )
    return issues


# ---------------------------------------------------------------------------
# CHECK 11: Sentence length variety (expanded)
# ---------------------------------------------------------------------------
def check_sentence_variety(text: str) -> list[str]:
    issues = []
    sents = [s for s in _split_sentences(text) if len(s.split()) > 2]
    if len(sents) < 4:
        return issues

    lengths = [len(s.split()) for s in sents]
    avg = sum(lengths) / len(lengths)
    variance = sum((l - avg) ** 2 for l in lengths) / len(lengths)
    std_dev = math.sqrt(variance)

    if std_dev < 3:
        issues.append(
            f"Robotic rhythm: sentence lengths are too uniform "
            f"(avg={avg:.0f} words, std_dev={std_dev:.1f}). "
            f"Mix 5-8 word sentences with 20+ word ones."
        )

    long_count = sum(1 for l in lengths if l > 25)
    if long_count >= 3:
        issues.append(
            f"{long_count} sentences over 25 words -- break some up, "
            f"humans write shorter sentences in instructions"
        )

    all_medium = all(12 <= l <= 22 for l in lengths)
    if all_medium and len(lengths) >= 4:
        issues.append(
            "All sentences are 12-22 words (AI sweet spot) -- "
            "add some short punchy sentences (5-8 words)"
        )

    return issues


# ---------------------------------------------------------------------------
# CHECK 12: Word count
# ---------------------------------------------------------------------------
def check_word_count(text: str) -> list[str]:
    issues = []
    count = len(text.split())
    if count < 100:
        issues.append(f"Word count: {count} -- too short (minimum ~150 for a substantive prompt)")
    elif count < 150:
        issues.append(f"Word count: {count} -- slightly short (target: 150-300 words)")
    elif count > 350:
        issues.append(f"Word count: {count} -- too long (target: 150-300 words, consider trimming)")
    elif count > 300:
        issues.append(f"Word count: {count} -- slightly long (target: 150-300 words)")
    return issues


# ---------------------------------------------------------------------------
# CHECK 13: Comma density (AI uses more commas than humans)
# ---------------------------------------------------------------------------
def check_comma_density(text: str) -> list[str]:
    issues = []
    words = text.split()
    commas = text.count(",")
    if not words:
        return issues
    ratio = commas / len(words)
    if ratio > 0.12:
        issues.append(
            f"High comma density: {commas} commas in {len(words)} words ({ratio:.0%}) -- "
            f"AI overuses commas. Break into shorter sentences or remove unnecessary commas."
        )
    return issues


# ---------------------------------------------------------------------------
# CHECK 14: List pattern detection (AI loves structured lists in prose)
# ---------------------------------------------------------------------------
def check_list_patterns(text: str) -> list[str]:
    issues = []
    colon_count = text.count(":")
    sents = _split_sentences(text)
    if sents and colon_count / max(len(sents), 1) > 0.3:
        issues.append(
            f"High colon usage ({colon_count} colons in {len(sents)} sentences) -- "
            f"AI patterns. Use fewer colons, integrate terms into flowing sentences."
        )

    three_pattern = re.findall(r'\b\w+,\s+\w+,\s+and\s+\w+\b', text.lower())
    if len(three_pattern) >= 2:
        issues.append(
            f"Multiple 'X, Y, and Z' triads ({len(three_pattern)}x) -- "
            f"AI loves three-item lists. Vary the count."
        )
    return issues


# ---------------------------------------------------------------------------
# CHECK 15: Gerund opener overuse
# ---------------------------------------------------------------------------
def check_gerund_openers(text: str) -> list[str]:
    issues = []
    sents = [s for s in _split_sentences(text) if len(s.split()) > 3]
    if len(sents) < 4:
        return issues
    gerund_starts = sum(1 for s in sents if re.match(r'^[A-Z]\w+ing\b', s))
    if gerund_starts >= 2:
        issues.append(
            f"{gerund_starts} sentences start with a gerund (-ing word) -- "
            f"AI pattern, rewrite some with a noun or verb start"
        )
    return issues


# ---------------------------------------------------------------------------
# CHECK 16: Relative "that/which" clause density
# AI chains relative clauses; humans break them into separate sentences.
# ---------------------------------------------------------------------------
def check_relative_clauses(text: str) -> list[str]:
    issues = []
    sents = _split_sentences(text)
    if len(sents) < 3:
        return issues

    that_clause_pat = re.compile(
        r'\b(?:that|which)\s+(?:is|are|was|were|has|have|had|can|could|will|would|'
        r'should|must|may|might|does|do|did|'
        r'[a-z]+s|[a-z]+ed|[a-z]+es)\b',
        re.IGNORECASE
    )

    that_count = 0
    for s in sents:
        if that_clause_pat.search(s):
            that_count += 1

    ratio = that_count / len(sents)
    if ratio > 0.35:
        issues.append(
            f'High "that/which" clause density: {that_count}/{len(sents)} sentences '
            f'({ratio:.0%}) use relative clauses -- AI chains these, humans break them '
            f'into separate short sentences'
        )
    elif that_count >= 3 and ratio > 0.25:
        issues.append(
            f'{that_count} sentences rely on "that/which" subordination -- '
            f'rephrase some as standalone statements'
        )
    return issues


# ---------------------------------------------------------------------------
# CHECK 17: Imperative verb parallelism / syntactic template repetition
# AI writes lists of commands in identical templates.
# ---------------------------------------------------------------------------
_COMMON_IMPERATIVES = {
    "add", "create", "define", "extract", "implement", "include", "make",
    "move", "remove", "replace", "set", "update", "use", "write", "build",
    "ensure", "fix", "refactor", "convert", "introduce", "apply", "modify",
    "extend", "leave", "keep", "put", "split", "merge", "rename", "delete",
    "handle", "check", "verify", "validate", "configure", "expose", "wrap",
    "register", "wire", "connect", "separate", "integrate", "emit", "return",
    "pass", "attach", "export", "import", "call",
}

def check_imperative_parallelism(text: str) -> list[str]:
    issues = []
    sents = _split_sentences(text)
    if len(sents) < 4:
        return issues

    imperative_sents = []
    for s in sents:
        first_word = s.split()[0].lower().rstrip(",;:")
        if first_word in _COMMON_IMPERATIVES:
            imperative_sents.append(s)

    # NOTE: Marlin V3's official good prompt example is ~80% imperative style.
    # Only flag when it's extremely robotic (>85%) with many sentences.
    ratio = len(imperative_sents) / len(sents)
    if ratio > 0.85 and len(imperative_sents) >= 6:
        issues.append(
            f'{len(imperative_sents)}/{len(sents)} sentences start with an imperative '
            f'verb ({ratio:.0%}) -- every single sentence is a command. '
            f'Mix in 1-2 context sentences like "The changes should..." or '
            f'"The current code does X, which causes Y."'
        )
    elif ratio > 0.7 and len(imperative_sents) >= 5:
        issues.append(
            f'{len(imperative_sents)} imperative-style sentences -- '
            f'add a context sentence or a closing like "Leave the code production ready."'
        )
    return issues


# ---------------------------------------------------------------------------
# CHECK 18: Prepositional phrase stacking depth
# AI chains "into X under Y within Z for W" -- humans rarely go past 2 deep.
# ---------------------------------------------------------------------------
_PREPS = (
    r'\b(?:into|under|within|through|using|from|across|for|via|by|of|with|'
    r'over|upon|between|among|behind|throughout|toward|towards|alongside|'
    r'inside|outside|against|beyond|during|without|beneath|above|below|'
    r'atop|onto|past|until|after|before|since|near|beside)\b'
)

def check_prep_stacking(text: str) -> list[str]:
    issues = []
    sents = _split_sentences(text)
    deep_chains = 0
    for s in sents:
        preps = re.findall(_PREPS, s, re.IGNORECASE)
        if len(preps) >= 4:
            deep_chains += 1

    if deep_chains >= 2:
        issues.append(
            f'{deep_chains} sentences stack 4+ prepositions in a chain -- '
            f'AI pattern. Break into shorter sentences. '
            f'e.g. "Move X out of A into B within C" -> '
            f'"Pull X out of A. Put it in B, inside C."'
        )
    elif deep_chains == 1:
        issues.append(
            f'1 sentence has a deep prepositional chain (4+ preps) -- '
            f'consider splitting it'
        )
    return issues


# ---------------------------------------------------------------------------
# CHECK 19: Formality uniformity (zero informality markers)
# Humans break register -- use contractions, abbreviations, casual asides.
# A text with ZERO informal signals is statistically AI.
# ---------------------------------------------------------------------------
def check_formality_uniformity(text: str) -> list[str]:
    """Check for signs of human texture in formal writing.

    Marlin V3 says 'avoid conversational language', so we don't require
    slang or heavy informality. But genuine human technical writing still
    has texture: domain-specific terms, varied connectors, occasional
    contractions, conditional phrasing, etc. We check for those.
    """
    issues = []
    t = text.lower()
    words = t.split()
    if len(words) < 80:
        return issues

    human_texture = 0
    # Contractions (humans use even in formal writing)
    if re.search(r"\w+'(?:t|s|re|ve|ll|d|m)\b", t):
        human_texture += 1
    # Domain-specific or unusual vocabulary (not generic CS terms)
    if re.search(r'\b(?:gotcha|tricky|snag|caveat|quirk|nuance|subtle)\b', t):
        human_texture += 1
    # Conditional/hedging language
    if re.search(r'\b(?:if needed|where needed|when available|as needed|when possible)\b', t):
        human_texture += 1
    # Natural connectors
    if re.search(r'\b(?:should follow|should leave|should still|the changes should)\b', t):
        human_texture += 1
    # "Leave the code production ready" style closings
    if re.search(r'\b(?:production ready|production-ready|leave the code)\b', t):
        human_texture += 1
    # Mixed sentence types (not all commands)
    has_declarative = bool(re.search(r'\b(?:the current|right now|currently|at this point)\b', t))
    if has_declarative:
        human_texture += 1
    # Parenthetical asides
    if '(' in text and ')' in text:
        human_texture += 1

    if human_texture == 0 and len(words) > 120:
        issues.append(
            'No human texture in 120+ word text: no contractions, no conditional '
            'phrasing ("where needed"), no domain-specific terms, no closings '
            'like "Leave the code production ready." Add a few natural touches.'
        )
    return issues


# ---------------------------------------------------------------------------
# CHECK 20: Sentence template uniformity (syntactic burstiness proxy)
# Beyond just length: checks if sentences follow identical structures.
# ---------------------------------------------------------------------------
def _get_sentence_template(sent: str) -> str:
    """Reduce a sentence to a rough syntactic template."""
    words = sent.split()
    if not words:
        return ""
    template_parts = []
    first = words[0].lower()
    if first in _COMMON_IMPERATIVES:
        template_parts.append("IMP")
    elif first in {"the", "a", "an", "this", "that", "these", "those", "its", "their", "our"}:
        template_parts.append("DET")
    elif first in {"each", "every", "all", "some", "any", "no"}:
        template_parts.append("QUANT")
    else:
        template_parts.append("OTHER")

    has_that = bool(re.search(r'\bthat\b', sent, re.IGNORECASE))
    has_which = bool(re.search(r'\bwhich\b', sent, re.IGNORECASE))
    if has_that or has_which:
        template_parts.append("+REL")

    prep_count = len(re.findall(_PREPS, sent, re.IGNORECASE))
    if prep_count >= 3:
        template_parts.append("+PP3")
    elif prep_count >= 2:
        template_parts.append("+PP2")

    wlen = len(words)
    if wlen <= 8:
        template_parts.append("/S")
    elif wlen <= 16:
        template_parts.append("/M")
    else:
        template_parts.append("/L")

    return "|".join(template_parts)


def check_template_uniformity(text: str) -> list[str]:
    issues = []
    sents = _split_sentences(text)
    if len(sents) < 5:
        return issues

    templates = [_get_sentence_template(s) for s in sents]
    template_counts = Counter(templates)
    most_common_template, most_common_count = template_counts.most_common(1)[0]
    ratio = most_common_count / len(sents)

    if ratio >= 0.5 and most_common_count >= 3:
        issues.append(
            f'{most_common_count}/{len(sents)} sentences follow the identical syntactic '
            f'template ({most_common_template}) -- monotonous AI structure. '
            f'Mix imperative commands with context sentences, short observations, '
            f'and compound sentences joined by "and" or "but".'
        )

    unique_templates = len(template_counts)
    template_diversity = unique_templates / len(sents)
    if template_diversity < 0.4 and len(sents) >= 5:
        issues.append(
            f'Low syntactic diversity: only {unique_templates} distinct sentence patterns '
            f'across {len(sents)} sentences ({template_diversity:.0%}). '
            f'Humans write with more structural variety.'
        )

    return issues


# ---------------------------------------------------------------------------
# CHECK 21: "Clearly/properly/ensure/dedicated" -- AI qualifier overuse
# These aren't in the main signature list because they're common words,
# but AI uses them 5-10x more than humans in technical writing.
# ---------------------------------------------------------------------------
# NOTE: "clearly", "properly", "dedicated" are ALLOWED per Marlin V3 good example.
# Only flag words NOT in the official example.
_AI_QUALIFIERS = [
    "ensure", "ensures", "ensuring",
    "accordingly", "respective",
    "well-defined", "well-structured", "well-organized",
]

def check_ai_qualifiers(text: str) -> list[str]:
    issues = []
    t = text.lower()
    found = []
    for q in _AI_QUALIFIERS:
        n = len(re.findall(r'\b' + re.escape(q) + r'\b', t))
        if n:
            found.append(f'"{q}" ({n}x)')

    if len(found) >= 3:
        issues.append(
            f'AI qualifier cluster: {", ".join(found)} -- '
            f'these are filler words AI uses to sound precise. '
            f'Drop most of them; the sentence works without them.'
        )
    elif len(found) == 2:
        issues.append(
            f'AI qualifiers detected: {", ".join(found)} -- consider dropping one'
        )
    return issues


# ---------------------------------------------------------------------------
# CHECK 22: Production-ready closing (Marlin V3 explicit requirement)
# The guide's good example ends with "leave the code production ready."
# Template B.1 expands: "no broken imports, no orphaned references,
# all existing tests still pass."
# ---------------------------------------------------------------------------
def check_production_closing(text: str) -> list[str]:
    issues = []
    t = text.lower()
    has_closing = bool(re.search(
        r'\b(?:production.?ready|production ready|leave the code|'
        r'all existing tests still pass|all tests (?:should |must )?(?:still )?pass|'
        r'existing tests pass|must be production)',
        t
    ))
    if not has_closing:
        issues.append(
            'Missing production-ready closing. Marlin V3 requires the prompt to '
            'end with production readiness. Use one of:\n'
            '    "Leave the code production ready."\n'
            '    "The code must be production-ready: no broken imports, no orphaned '
            'references, all existing tests still pass."'
        )
    return issues


# ---------------------------------------------------------------------------
# AI SCORE ESTIMATOR
# ---------------------------------------------------------------------------
def estimate_ai_score(text: str, all_issues: dict) -> tuple[int, list[str]]:
    """Estimate likely AI detection score (0-100). Lower is better."""
    score = 0
    reasons = []

    t = text.lower()

    # Signature words (big signal)
    sig_issues = all_issues.get("llm_signatures", [])
    crit_sigs = sum(1 for i in sig_issues if "[CRITICAL]" in i)
    warn_sigs = sum(1 for i in sig_issues if "[WARNING]" in i)
    if crit_sigs:
        score += min(crit_sigs * 12, 35)
        reasons.append(f"Signature words (+{min(crit_sigs * 12, 35)})")
    if warn_sigs >= 2:
        score += min(warn_sigs * 5, 15)
        reasons.append(f"Suspicious word cluster (+{min(warn_sigs * 5, 15)})")

    # Transitions
    trans = all_issues.get("ai_transitions", [])
    if any("HIGH AI SIGNAL" in i for i in trans):
        score += 20
        reasons.append("AI transition phrase cluster (+20)")
    elif trans:
        score += 8
        reasons.append("AI transition phrases (+8)")

    # Adverbs
    adv = all_issues.get("adverb_overuse", [])
    if any("cluster" in i.lower() for i in adv):
        score += 10
        reasons.append("Adverb cluster (+10)")

    # Sentence starters
    starters = all_issues.get("sentence_starters", [])
    score += min(len(starters) * 5, 15)
    if starters:
        reasons.append(f"Repetitive starters (+{min(len(starters) * 5, 15)})")

    # Passive voice
    passive = all_issues.get("passive_voice", [])
    if any("high" in i.lower() for i in passive):
        score += 10
        reasons.append("High passive voice (+10)")
    elif passive:
        score += 5

    # No contractions
    contr = all_issues.get("contractions", [])
    if contr:
        score += 8
        reasons.append("No contractions (+8)")

    # Sentence uniformity
    variety = all_issues.get("sentence_variety", [])
    if any("robotic" in i.lower() for i in variety):
        score += 12
        reasons.append("Uniform sentence length (+12)")
    elif any("all sentences" in i.lower() for i in variety):
        score += 8
        reasons.append("Sentences all in AI sweet spot (+8)")

    # Comma density
    comma = all_issues.get("comma_density", [])
    if comma:
        score += 6
        reasons.append("High comma density (+6)")

    # List patterns
    lists = all_issues.get("list_patterns", [])
    if lists:
        score += min(len(lists) * 5, 10)
        reasons.append(f"AI list patterns (+{min(len(lists) * 5, 10)})")

    # Gerund openers
    gerund = all_issues.get("gerund_openers", [])
    if gerund:
        score += 5
        reasons.append("Gerund opener pattern (+5)")

    # ----- DEEP STRUCTURAL CHECKS (v3) -----

    # Relative clause density
    rel = all_issues.get("relative_clauses", [])
    if any("high" in i.lower() for i in rel):
        score += 15
        reasons.append("Heavy that/which clause chaining (+15)")
    elif rel:
        score += 8
        reasons.append("Relative clause density (+8)")

    # Imperative parallelism (softened: Marlin good example IS imperative-heavy)
    imp = all_issues.get("imperative_parallelism", [])
    if any("every single" in i.lower() for i in imp):
        score += 12
        reasons.append("All sentences are imperative commands (+12)")
    elif imp:
        score += 6
        reasons.append("Heavy imperative parallelism (+6)")

    # Prepositional stacking
    prep = all_issues.get("prep_stacking", [])
    if any("2" in i.split()[0] or "3" in i.split()[0] for i in prep):
        score += 12
        reasons.append("Deep prepositional chains (+12)")
    elif prep:
        score += 6
        reasons.append("Prepositional chain detected (+6)")

    # Formality uniformity (softened: Marlin says "avoid conversational language")
    formality = all_issues.get("formality_uniformity", [])
    if formality:
        score += 8
        reasons.append("No human texture in long text (+8)")

    # Template uniformity
    tmpl = all_issues.get("template_uniformity", [])
    if any("monotonous" in i.lower() for i in tmpl):
        score += 15
        reasons.append("Monotonous sentence templates (+15)")
    if any("low syntactic diversity" in i.lower() for i in tmpl):
        score += 10
        reasons.append("Low syntactic diversity (+10)")

    # AI qualifiers
    qual = all_issues.get("ai_qualifiers", [])
    if any("cluster" in i.lower() for i in qual):
        score += 10
        reasons.append("AI qualifier word cluster (+10)")
    elif qual:
        score += 5
        reasons.append("AI qualifier words (+5)")

    score = min(score, 100)
    return score, reasons


# ---------------------------------------------------------------------------
# MAIN ORCHESTRATOR
# ---------------------------------------------------------------------------
def validate_prompt(text: str) -> dict:
    results = {
        "em_dashes": check_em_dashes(text),
        "pr_references": check_pr_references(text),
        "role_prompting": check_role_prompting(text),
        "over_prescriptive": check_over_prescriptive(text),
        "llm_signatures": check_llm_signature_words(text),
        "ai_transitions": check_ai_transitions(text),
        "adverb_overuse": check_adverb_overuse(text),
        "sentence_starters": check_sentence_starters(text),
        "passive_voice": check_passive_voice(text),
        "contractions": check_contractions(text),
        "sentence_variety": check_sentence_variety(text),
        "word_count": check_word_count(text),
        "comma_density": check_comma_density(text),
        "list_patterns": check_list_patterns(text),
        "gerund_openers": check_gerund_openers(text),
        # Marlin V3 explicit requirements
        "production_closing": check_production_closing(text),
        # v3 deep structural checks
        "relative_clauses": check_relative_clauses(text),
        "imperative_parallelism": check_imperative_parallelism(text),
        "prep_stacking": check_prep_stacking(text),
        "formality_uniformity": check_formality_uniformity(text),
        "template_uniformity": check_template_uniformity(text),
        "ai_qualifiers": check_ai_qualifiers(text),
    }

    total_issues = sum(len(v) for v in results.values())
    results["total_issues"] = total_issues

    ai_score, ai_reasons = estimate_ai_score(text, results)
    results["ai_score"] = ai_score
    results["ai_reasons"] = ai_reasons

    # Pass = AI score under 10 AND no critical Marlin rule violations.
    # Word count (INFO) and soft AI warnings don't block a PASS.
    critical_marlin_fails = (
        len(results["em_dashes"])
        + len(results["pr_references"])
        + len(results["role_prompting"])
    )
    results["pass"] = critical_marlin_fails == 0 and ai_score < 10

    return results


def print_results(results: dict, text: str):
    word_count = len(text.split())
    ai_score = results["ai_score"]

    if ai_score < 10:
        score_label = "HUMAN"
        score_color = "+"
    elif ai_score < 25:
        score_label = "MOSTLY HUMAN"
        score_color = "~"
    elif ai_score < 50:
        score_label = "MIXED"
        score_color = "!"
    else:
        score_label = "AI DETECTED"
        score_color = "X"

    print(f"\n{'=' * 66}")
    print(f"  MARLIN V3 -- PROMPT QUALITY VALIDATOR (v3 Deep Anti-AI)")
    print(f"{'=' * 66}")
    print(f"  Word count     : {word_count}")
    print(f"  Total issues   : {results['total_issues']}")
    print(f"  AI Score       : {ai_score}/100  [{score_color}] {score_label}")
    print(f"  Status         : {'PASS' if results['pass'] else 'NEEDS WORK'}")
    print(f"{'=' * 66}")

    # Marlin rules
    marlin_checks = [
        ("Em-dashes", "em_dashes", "CRITICAL"),
        ("PR References", "pr_references", "CRITICAL"),
        ("Role Prompting", "role_prompting", "CRITICAL"),
        ("Over-prescriptive", "over_prescriptive", "WARNING"),
        ("Production-Ready Closing", "production_closing", "WARNING"),
        ("Word Count", "word_count", "INFO"),
    ]

    print(f"\n  --- MARLIN V3 RULES ---")
    for label, key, severity in marlin_checks:
        issues = results[key]
        if issues:
            print(f"  [{severity}] {label}:")
            for i in issues:
                print(f"    - {i}")
        else:
            print(f"  [OK] {label}")

    # AI detection checks (surface)
    ai_checks = [
        ("LLM Signature Words", "llm_signatures", "CRITICAL"),
        ("AI Transitions", "ai_transitions", "WARNING"),
        ("Adverb Overuse", "adverb_overuse", "WARNING"),
        ("Sentence Starters", "sentence_starters", "WARNING"),
        ("Passive Voice", "passive_voice", "WARNING"),
        ("Contractions", "contractions", "WARNING"),
        ("Sentence Variety", "sentence_variety", "WARNING"),
        ("Comma Density", "comma_density", "INFO"),
        ("List Patterns", "list_patterns", "INFO"),
        ("Gerund Openers", "gerund_openers", "INFO"),
    ]

    print(f"\n  --- AI DETECTION SIGNALS (surface) ---")
    for label, key, severity in ai_checks:
        issues = results[key]
        if issues:
            print(f"  [{severity}] {label}:")
            for i in issues:
                print(f"    - {i}")
        else:
            print(f"  [OK] {label}")

    # Deep structural checks (v3)
    ai_checks = [
        ("That/Which Clause Density", "relative_clauses", "CRITICAL"),
        ("Imperative Parallelism", "imperative_parallelism", "CRITICAL"),
        ("Prepositional Stacking", "prep_stacking", "WARNING"),
        ("Formality Uniformity", "formality_uniformity", "CRITICAL"),
        ("Sentence Template Uniformity", "template_uniformity", "CRITICAL"),
        ("AI Qualifier Words", "ai_qualifiers", "WARNING"),
    ]

    print(f"\n  --- DEEP STRUCTURAL SIGNALS (v3) ---")
    for label, key, severity in ai_checks:
        issues = results[key]
        if issues:
            print(f"  [{severity}] {label}:")
            for i in issues:
                print(f"    - {i}")
        else:
            print(f"  [OK] {label}")

    # AI score breakdown
    if results["ai_reasons"]:
        print(f"\n  --- AI SCORE BREAKDOWN ({ai_score}/100) ---")
        for r in results["ai_reasons"]:
            print(f"    {r}")

    # Verdict
    print(f"\n{'=' * 66}")
    if ai_score < 10:
        print(f"  PASS: Content reads as human-written. Ready to submit.")
    elif ai_score < 25:
        print(f"  CLOSE: Fix the flagged items above to get below 10%.")
    elif ai_score < 50:
        print(f"  REWRITE NEEDED: Multiple AI patterns detected.")
        print(f"  Tips: use contractions, vary sentence length,")
        print(f"  drop filler phrases, use simpler words.")
    else:
        print(f"  HEAVY REWRITE: Content will be flagged as AI-generated.")
        print(f"  Rewrite from scratch in your own voice.")
    print(f"{'=' * 66}\n")


# ---------------------------------------------------------------------------
# AUTO-HUMANIZER: programmatically transforms AI text toward human patterns
# ---------------------------------------------------------------------------

_CONTRACTION_MAP = {
    r'\bdo not\b': "don't",
    r'\bdoes not\b': "doesn't",
    r'\bdid not\b': "didn't",
    r'\bis not\b': "isn't",
    r'\bare not\b': "aren't",
    r'\bwas not\b': "wasn't",
    r'\bwere not\b': "weren't",
    r'\bwill not\b': "won't",
    r'\bwould not\b': "wouldn't",
    r'\bcould not\b': "couldn't",
    r'\bshould not\b': "shouldn't",
    r'\bcannot\b': "can't",
    r'\bcan not\b': "can't",
    r'\bit is\b': "it's",
    r'\bthat is\b': "that's",
    r'\bthere is\b': "there's",
    r'\bthey are\b': "they're",
    r'\bwe are\b': "we're",
    r'\byou are\b': "you're",
    r'\byou will\b': "you'll",
    r'\byou have\b': "you've",
    r'\bwhat is\b': "what's",
    r'\blet us\b': "let's",
    r'\bI am\b': "I'm",
    r'\bI have\b': "I've",
    r'\bI will\b': "I'll",
    r'\bI would\b': "I'd",
}

_FORMAL_TO_CASUAL = {
    # Only replace words that are NOT in Marlin V3's official good example.
    # Marlin-approved: "clearly", "dedicated", "properly", "structured" -- keep these.
    "utilize": "use",
    "leverage": "use",
    "facilitate": "help",
    "comprehensive": "full",
    "robust": "solid",
    "seamless": "smooth",
    "enhance": "improve",
    "streamline": "simplify",
    "optimize": "speed up",
    "functionality": "feature",
    "demonstrates": "shows",
    "additional": "more",
    "subsequently": "then",
    "aforementioned": "earlier",
    "respective": "matching",
    "corresponding": "matching",
    "delve": "dig into",
    "intricate": "tricky",
    "nuanced": "subtle",
    "various": "a few",
    "straightforward": "simple",
}

_AI_TRANSITION_REPLACEMENTS = {
    "additionally": "",
    "furthermore": "",
    "moreover": "",
    "consequently": "so",
    "in addition": "also",
    "as a result": "so",
    "in light of": "given",
    "with that said": "",
    "that being said": "",
    "it is essential": "you need",
    "it is crucial": "you need",
    "it is important": "you need",
    "it is vital": "you need",
    "it is imperative": "you need",
    "this ensures": "this way",
    "this enables": "this lets",
    "this allows for": "this lets",
    "moving forward": "",
    "going forward": "",
}


def humanize_text(text: str) -> str:
    """Auto-transform AI text patterns toward human-sounding text.

    This is a best-effort programmatic pass. It handles:
    1. Force contractions
    2. Replace formal vocabulary with casual equivalents
    3. Remove AI transition phrases
    4. Remove double-dashes
    5. Remove em/en-dashes
    """
    result = text

    # 1. Remove em-dashes and en-dashes
    result = result.replace("\u2014", ", ")
    result = result.replace("\u2013", "-")

    # 2. Remove double-dashes (AI workaround for em-dashes)
    result = re.sub(r'\s*--\s*', ', ', result)

    # 3. Force contractions (case-aware)
    for pattern, replacement in _CONTRACTION_MAP.items():
        # Handle original case: if first letter is uppercase, capitalize replacement
        def _contract(m):
            matched = m.group(0)
            if matched[0].isupper():
                return replacement[0].upper() + replacement[1:]
            return replacement
        result = re.sub(pattern, _contract, result, flags=re.IGNORECASE)

    # 4. Replace formal vocabulary
    for formal, casual in _FORMAL_TO_CASUAL.items():
        pat = re.compile(r'\b' + re.escape(formal) + r'\b', re.IGNORECASE)
        def _replace_formal(m, c=casual):
            matched = m.group(0)
            if not c:
                return ""
            if matched[0].isupper():
                return c[0].upper() + c[1:]
            return c
        result = pat.sub(_replace_formal, result)

    # 4b. Fix grammar artifacts from replacements ("a its own" -> "its own")
    result = re.sub(r'\ba (its own)\b', r'\1', result, flags=re.IGNORECASE)
    result = re.sub(r'\ban (its own)\b', r'\1', result, flags=re.IGNORECASE)

    # 5. Remove AI transitions
    for phrase, replacement in _AI_TRANSITION_REPLACEMENTS.items():
        pat = re.compile(r'\b' + re.escape(phrase) + r'[,\s]*', re.IGNORECASE)
        if replacement:
            result = pat.sub(replacement + " ", result)
        else:
            result = pat.sub("", result)

    # 6. Clean up artifacts: double spaces, leading commas, orphaned punctuation
    result = re.sub(r'  +', ' ', result)
    result = re.sub(r'\s+,', ',', result)
    result = re.sub(r',\s*,', ',', result)
    result = re.sub(r'\.\s*,', '.', result)
    result = re.sub(r',\s*\.', '.', result)
    result = re.sub(r'^\s*,\s*', '', result, flags=re.MULTILINE)

    # 7. Clean up sentences that start with lowercase after replacement removed a word
    sentences = re.split(r'(?<=[.!?])\s+', result)
    cleaned = []
    for s in sentences:
        s = s.strip()
        if s and s[0].islower() and (not cleaned or cleaned[-1][-1] in '.!?'):
            s = s[0].upper() + s[1:]
        if s:
            cleaned.append(s)
    result = ' '.join(cleaned)

    result = result.strip()
    return result


def print_humanized(original: str, humanized: str):
    """Print the auto-humanized text with a before/after diff summary."""
    print(f"\n{'=' * 66}")
    print(f"  AUTO-HUMANIZER OUTPUT")
    print(f"{'=' * 66}")

    orig_words = original.split()
    hum_words = humanized.split()
    print(f"  Original : {len(orig_words)} words")
    print(f"  Humanized: {len(hum_words)} words")

    # Count changes made
    changes = []
    for pattern, replacement in _CONTRACTION_MAP.items():
        count = len(re.findall(pattern, original, re.IGNORECASE))
        if count:
            changes.append(f"contracted {count}x")
    for formal, casual in _FORMAL_TO_CASUAL.items():
        if casual and re.search(r'\b' + re.escape(formal) + r'\b', original, re.IGNORECASE):
            changes.append(f'"{formal}" -> "{casual}"')
    dd_count = len(re.findall(r'(?<!\-)\-\-(?!\-)', original))
    if dd_count:
        changes.append(f"removed {dd_count} double-dashes")
    if "\u2014" in original:
        changes.append("removed em-dashes")

    if changes:
        print(f"\n  Changes applied:")
        for c in changes:
            print(f"    + {c}")
    else:
        print(f"\n  No automated fixes needed.")

    print(f"\n  --- HUMANIZED TEXT ---")
    # Word wrap at ~75 chars
    words = humanized.split()
    line = "  "
    for w in words:
        if len(line) + len(w) + 1 > 75:
            print(line)
            line = "  " + w
        else:
            line += " " + w if line.strip() else "  " + w
    if line.strip():
        print(line)

    print(f"\n{'=' * 66}")
    print(f"  NOTE: Auto-humanizer handles vocabulary and contractions.")
    print(f"  For sentence structure (parallelism, burstiness), manual")
    print(f"  editing is needed. Run the validator on this output next.")
    print(f"{'=' * 66}\n")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print('  python3 prompt_validator.py "Your prompt text"')
        print("  python3 prompt_validator.py --file path/to/prompt.txt")
        print('  python3 prompt_validator.py --humanize "Your prompt text"')
        print("  python3 prompt_validator.py --humanize --file path/to/prompt.txt")
        sys.exit(1)

    mode = "validate"
    text = None

    args = sys.argv[1:]
    if "--humanize" in args:
        mode = "humanize"
        args.remove("--humanize")

    if not args:
        print("Error: no text provided")
        sys.exit(1)

    if args[0] == "--file":
        if len(args) < 2:
            print("Error: --file requires a path argument")
            sys.exit(1)
        from pathlib import Path
        text = Path(args[1]).read_text()
    else:
        text = " ".join(args)

    if mode == "humanize":
        humanized = humanize_text(text)
        print_humanized(text, humanized)
        # Also validate the result
        results = validate_prompt(humanized)
        print_results(results, humanized)
        sys.exit(0 if results["pass"] else 1)
    else:
        results = validate_prompt(text)
        print_results(results, text)
        sys.exit(0 if results["pass"] else 1)
