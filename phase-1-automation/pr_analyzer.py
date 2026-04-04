#!/usr/bin/env python3
"""
MARLIN V3 — Phase 1 PR Analyzer

After the repo is selected, this watches live_prs.json for PRs
copied from Snorkel. When 'complete', it fetches GitHub data for
each PR and scores them for Marlin difficulty.

Scoring criteria (will the PR make Opus 4.6 / Claude Sonnet fail?):
  - Number of files changed (more = harder to get all right)
  - Total additions + deletions (larger scope)
  - Number of commits (complex iteration history)
  - Whether tests are involved
  - Cross-module changes vs. single-file changes
  - Type of change (refactor > docs, feature > chore)
  - PR description quality (well-described = clearer task)

Output: analyzed_prs.json with ranked recommendations + suggested category
"""

import json
import re
import ssl
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime
from pathlib import Path

try:
    _SSL_CONTEXT = ssl.create_default_context()
except Exception:
    _SSL_CONTEXT = ssl._create_unverified_context()

try:
    import certifi
    _SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    _SSL_CONTEXT = ssl._create_unverified_context()

DATA_DIR = Path(__file__).parent / "data"
LIVE_FILE = DATA_DIR / "live_prs.json"
OUTPUT_FILE = DATA_DIR / "analyzed_prs.json"
REPO_FILE = DATA_DIR / "analyzed_repos.json"
POLL_INTERVAL = 2

CATEGORY_KEYWORDS = {
    "refactor": ["refactor", "restructure", "cleanup", "consolidat", "reorganiz", "simplif", "rename"],
    "bug_fix": ["fix", "bug", "error", "crash", "issue", "broken", "regression", "patch"],
    "new_feature": ["add", "new", "implement", "introduce", "support", "feature", "enable"],
    "chore": ["chore", "bump", "upgrade", "dependency", "config", "ci", "build", "lint"],
    "documentation": ["doc", "readme", "comment", "tutorial", "guide", "example"],
    "testing": ["test", "coverage", "spec", "fixture", "mock", "assert"],
    "performance": ["perf", "optimi", "speed", "fast", "slow", "latency", "memory", "cache"],
    "git": ["merge", "rebase", "branch", "cherry-pick", "bisect"],
}

MARLIN_CATEGORY_MAP = {
    "refactor": 6,
    "bug_fix": 8,
    "new_feature": 11,
    "chore": 9,
    "documentation": 10,
    "testing": 13,
    "performance": 12,
    "git": 1,
}

MARLIN_CATEGORY_NAMES = {
    1: "Git", 2: "Ambiguous", 3: "Discussion", 4: "Explaining",
    5: "Code Review", 6: "Refactor", 7: "Greenfield", 8: "Bug Fix",
    9: "Chore", 10: "Documentation", 11: "New Feature", 12: "Performance",
    13: "Testing and QA", 14: "Other",
}


def github_api(endpoint: str) -> dict | list | None:
    url = f"https://api.github.com{endpoint}"
    req = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "MarlinV3-Analyzer",
    })
    try:
        with urllib.request.urlopen(req, timeout=15, context=_SSL_CONTEXT) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.URLError, urllib.error.HTTPError, Exception) as e:
        print(f"  [API ERROR] {endpoint}: {e}")
        return None


def detect_category(title: str, body: str) -> tuple[str, int]:
    """Detect the best Marlin prompt category from PR title + body."""
    text = (title + " " + body).lower()
    scores = {}
    for cat, keywords in CATEGORY_KEYWORDS.items():
        score = sum(1 for kw in keywords if kw in text)
        if score > 0:
            scores[cat] = score

    if not scores:
        return "other", 14

    best = max(scores, key=scores.get)
    return best, MARLIN_CATEGORY_MAP.get(best, 14)


def get_selected_repo() -> tuple[str, str] | None:
    """Read the best repo from analyzed_repos.json."""
    if REPO_FILE.exists():
        try:
            data = json.loads(REPO_FILE.read_text())
            best = data.get("best_pick", {})
            if best.get("owner") and best.get("repo"):
                return best["owner"], best["repo"]
        except (json.JSONDecodeError, IOError):
            pass
    return None


def analyze_pr(entry: dict, default_owner: str, default_repo: str) -> dict:
    """Fetch GitHub data and compute a difficulty score for a PR."""
    owner = entry.get("owner", default_owner)
    repo = entry.get("repo", default_repo)
    pr_number = entry.get("pr_number", "")

    result = {
        "raw_text": entry.get("raw_text", ""),
        "owner": owner,
        "repo": repo,
        "pr_number": pr_number,
        "score": 0,
        "score_breakdown": {},
        "recommendation": "",
        "suggested_category": "",
        "suggested_category_id": 14,
        "title": "",
        "details": {},
    }

    if not pr_number:
        raw = entry.get("raw_text", "")
        nums = re.findall(r'\d+', raw)
        if nums:
            pr_number = nums[-1]
            result["pr_number"] = pr_number

    if not pr_number:
        result["recommendation"] = "SKIP — could not determine PR number"
        return result

    print(f"  Analyzing {owner}/{repo}#{pr_number}...", end=" ", flush=True)

    pr_data = github_api(f"/repos/{owner}/{repo}/pulls/{pr_number}")
    if not pr_data:
        result["recommendation"] = "SKIP — could not fetch PR data"
        print("FAILED")
        return result

    title = pr_data.get("title", "")
    body = pr_data.get("body", "") or ""
    result["title"] = title

    result["details"] = {
        "title": title,
        "state": pr_data.get("state", ""),
        "merged": pr_data.get("merged", False),
        "additions": pr_data.get("additions", 0),
        "deletions": pr_data.get("deletions", 0),
        "changed_files": pr_data.get("changed_files", 0),
        "commits": pr_data.get("commits", 0),
        "comments": pr_data.get("comments", 0),
        "review_comments": pr_data.get("review_comments", 0),
        "created_at": pr_data.get("created_at", ""),
        "body_preview": body[:300],
    }

    cat_key, cat_id = detect_category(title, body)
    result["suggested_category"] = MARLIN_CATEGORY_NAMES.get(cat_id, "Other")
    result["suggested_category_id"] = cat_id

    # --- Scoring ---
    score = 0
    breakdown = {}

    # 1. Changed files: more files = more places to get wrong
    changed = pr_data.get("changed_files", 0)
    if changed >= 20:
        breakdown["file_spread"] = 25
    elif changed >= 10:
        breakdown["file_spread"] = 20
    elif changed >= 5:
        breakdown["file_spread"] = 15
    elif changed >= 3:
        breakdown["file_spread"] = 10
    else:
        breakdown["file_spread"] = 5

    # 2. Total code churn: larger changes = more to get right
    additions = pr_data.get("additions", 0)
    deletions = pr_data.get("deletions", 0)
    churn = additions + deletions
    if churn >= 1000:
        breakdown["code_churn"] = 20
    elif churn >= 500:
        breakdown["code_churn"] = 15
    elif churn >= 200:
        breakdown["code_churn"] = 12
    elif churn >= 50:
        breakdown["code_churn"] = 8
    else:
        breakdown["code_churn"] = 3

    # 3. Both additions AND deletions = refactor (harder than pure add)
    if additions > 50 and deletions > 50:
        ratio = min(additions, deletions) / max(additions, deletions) if max(additions, deletions) > 0 else 0
        if ratio > 0.3:
            breakdown["refactor_signal"] = 15
        else:
            breakdown["refactor_signal"] = 5
    else:
        breakdown["refactor_signal"] = 0

    # 4. Commits: more commits = more iteration = probably trickier
    commits = pr_data.get("commits", 0)
    if commits >= 10:
        breakdown["iteration_depth"] = 10
    elif commits >= 5:
        breakdown["iteration_depth"] = 7
    elif commits >= 3:
        breakdown["iteration_depth"] = 5
    else:
        breakdown["iteration_depth"] = 2

    # 5. Review comments: more review = more nuance / edge cases
    review_comments = pr_data.get("review_comments", 0)
    if review_comments >= 10:
        breakdown["review_depth"] = 15
    elif review_comments >= 5:
        breakdown["review_depth"] = 10
    elif review_comments >= 2:
        breakdown["review_depth"] = 5
    else:
        breakdown["review_depth"] = 0

    # 6. Category difficulty multiplier
    hard_categories = {"refactor": 10, "bug_fix": 8, "performance": 10, "new_feature": 7}
    easy_categories = {"documentation": -5, "chore": -3}
    breakdown["category_difficulty"] = hard_categories.get(cat_key, easy_categories.get(cat_key, 0))

    # 7. Body length = well-described PR = clearer task
    if len(body) > 500:
        breakdown["description_quality"] = 10
    elif len(body) > 200:
        breakdown["description_quality"] = 7
    elif len(body) > 50:
        breakdown["description_quality"] = 4
    else:
        breakdown["description_quality"] = 0

    # 8. Test mentions in title/body = test-aware PR
    test_text = (title + " " + body).lower()
    if "test" in test_text:
        breakdown["test_awareness"] = 5
    else:
        breakdown["test_awareness"] = 0

    score = sum(breakdown.values())
    result["score"] = score
    result["score_breakdown"] = breakdown

    if score >= 70:
        result["recommendation"] = "EXCELLENT — very likely to make models struggle"
    elif score >= 50:
        result["recommendation"] = "GOOD — solid difficulty for Marlin tasking"
    elif score >= 35:
        result["recommendation"] = "MODERATE — usable but consider harder alternatives"
    else:
        result["recommendation"] = "WEAK — likely too simple for meaningful model differentiation"

    verdict = result["recommendation"].split("—")[0].strip()
    print(f"Score: {score} — {verdict} | Category: {result['suggested_category']}")
    return result


def run_analyzer():
    selected = get_selected_repo()
    default_owner = selected[0] if selected else ""
    default_repo = selected[1] if selected else ""

    print(f"\n{'='*60}")
    print(f"  MARLIN V3 — PR ANALYZER")
    print(f"{'='*60}")
    if selected:
        print(f"  Selected repo : {default_owner}/{default_repo}")
    print(f"  Watching      : {LIVE_FILE}")
    print(f"  Polling       : every {POLL_INTERVAL}s")
    print(f"{'='*60}\n")

    while True:
        if not LIVE_FILE.exists():
            print(f"  Waiting for {LIVE_FILE.name}...", end="\r")
            time.sleep(POLL_INTERVAL)
            continue

        try:
            data = json.loads(LIVE_FILE.read_text())
        except (json.JSONDecodeError, IOError):
            time.sleep(POLL_INTERVAL)
            continue

        status = data.get("status", "")
        entries = data.get("entries", [])

        if status == "watching":
            count = len(entries)
            print(f"  Clipboard watcher active — {count} PR(s) captured so far...", end="\r")
            time.sleep(POLL_INTERVAL)
            continue

        if status == "complete":
            print(f"\n  Clipboard watcher finished. {len(entries)} PRs to analyze.\n")
            break

        time.sleep(POLL_INTERVAL)

    if not entries:
        print("  No PRs captured. Exiting.")
        return

    print(f"  Fetching GitHub data for {len(entries)} PRs...\n")
    analyzed = []
    for entry in entries:
        result = analyze_pr(entry, default_owner, default_repo)
        analyzed.append(result)
        time.sleep(0.5)

    analyzed_sorted = sorted(analyzed, key=lambda x: x["score"], reverse=True)
    for i, r in enumerate(analyzed_sorted):
        r["rank"] = i + 1

    output = {
        "analyzed_at": datetime.now().isoformat(),
        "repo": f"{default_owner}/{default_repo}" if selected else "unknown",
        "total_prs": len(analyzed_sorted),
        "prs": analyzed_sorted,
        "best_pick": analyzed_sorted[0] if analyzed_sorted else None,
    }
    OUTPUT_FILE.write_text(json.dumps(output, indent=2, default=str))

    print(f"\n{'='*60}")
    print(f"  ANALYSIS COMPLETE — RANKED PRs")
    print(f"{'='*60}\n")

    for r in analyzed_sorted:
        title_short = (r.get("title") or "untitled")[:50]
        print(f"  #{r['rank']:2d}  Score: {r['score']:3d}  PR #{r['pr_number']}  \"{title_short}\"")
        print(f"       {r['recommendation']}")
        print(f"       Category: {r['suggested_category']} | Files: {r['details'].get('changed_files',0)} | Churn: +{r['details'].get('additions',0)}/−{r['details'].get('deletions',0)}")
        print()

    best = analyzed_sorted[0]
    print(f"{'='*60}")
    print(f"  RECOMMENDED PR: #{best['pr_number']} — \"{best.get('title', '')}\"")
    print(f"  Score: {best['score']} — {best['recommendation']}")
    print(f"  Suggested Category: {best['suggested_category']} (#{best['suggested_category_id']})")
    print(f"{'='*60}")
    print(f"\n  Full analysis saved to: {OUTPUT_FILE}\n")


if __name__ == "__main__":
    run_analyzer()
