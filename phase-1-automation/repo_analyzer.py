#!/usr/bin/env python3
"""
MARLIN V3 — Phase 1 Repo Analyzer

Watches live_repos.json every 2 seconds.
When status becomes 'complete', analyzes all repos via GitHub API
and scores them for Marlin difficulty.

Scoring criteria (designed to find repos that will break models like Opus 4.6):
  - Repo size / complexity
  - Primary language (supported?)
  - Number of open PRs (active development = more context needed)
  - Star count (well-known = more training data = model may memorize)
  - File count and structure depth
  - Test infrastructure presence

Output: analyzed_repos.json with ranked recommendations
"""

import json
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
LIVE_FILE = DATA_DIR / "live_repos.json"
OUTPUT_FILE = DATA_DIR / "analyzed_repos.json"
POLL_INTERVAL = 2

SUPPORTED_LANGUAGES = {"python", "javascript", "typescript", "go", "rust", "java", "c++", "c"}


def github_api(endpoint: str) -> dict | None:
    """Fetch from GitHub API (unauthenticated, 60 req/hr limit)."""
    url = f"https://api.github.com{endpoint}"
    req = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "MarlinV3-Analyzer",
    })
    try:
        with urllib.request.urlopen(req, timeout=10, context=_SSL_CONTEXT) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.URLError, urllib.error.HTTPError, Exception) as e:
        print(f"  [API ERROR] {endpoint}: {e}")
        return None


def analyze_repo(entry: dict) -> dict:
    """Fetch GitHub data and compute a difficulty score for a repo."""
    owner = entry.get("owner", "")
    repo = entry.get("repo", "")
    result = {
        "raw_text": entry.get("raw_text", ""),
        "owner": owner,
        "repo": repo,
        "score": 0,
        "score_breakdown": {},
        "recommendation": "",
        "language": "unknown",
        "supported_language": False,
        "details": {},
    }

    if not owner or not repo:
        result["recommendation"] = "SKIP — could not parse owner/repo"
        return result

    print(f"  Analyzing {owner}/{repo}...", end=" ", flush=True)

    repo_data = github_api(f"/repos/{owner}/{repo}")
    if not repo_data:
        result["recommendation"] = "SKIP — could not fetch repo data"
        print("FAILED")
        return result

    lang = (repo_data.get("language") or "unknown").lower()
    result["language"] = lang
    result["supported_language"] = lang in SUPPORTED_LANGUAGES
    result["details"] = {
        "stars": repo_data.get("stargazers_count", 0),
        "forks": repo_data.get("forks_count", 0),
        "open_issues": repo_data.get("open_issues_count", 0),
        "size_kb": repo_data.get("size", 0),
        "default_branch": repo_data.get("default_branch", "main"),
        "description": repo_data.get("description", ""),
        "topics": repo_data.get("topics", []),
        "created_at": repo_data.get("created_at", ""),
        "updated_at": repo_data.get("updated_at", ""),
    }

    score = 0
    breakdown = {}

    if not result["supported_language"]:
        breakdown["language"] = -100
        score -= 100
        result["recommendation"] = f"SKIP — language '{lang}' not supported in V3"
        result["score"] = score
        result["score_breakdown"] = breakdown
        print(f"UNSUPPORTED LANG ({lang})")
        return result

    # --- Scoring factors ---

    # 1. Repo size: larger = more context = harder for model
    size_kb = repo_data.get("size", 0)
    if size_kb > 500000:
        breakdown["size"] = 25
    elif size_kb > 100000:
        breakdown["size"] = 20
    elif size_kb > 50000:
        breakdown["size"] = 15
    elif size_kb > 10000:
        breakdown["size"] = 10
    else:
        breakdown["size"] = 5

    # 2. Stars: very popular repos = model may have memorized patterns
    #    Sweet spot: 500–5000 stars (real project, but not overly memorized)
    stars = repo_data.get("stargazers_count", 0)
    if 500 <= stars <= 5000:
        breakdown["stars_sweet_spot"] = 15
    elif 100 <= stars < 500:
        breakdown["stars_sweet_spot"] = 10
    elif stars > 5000:
        breakdown["stars_sweet_spot"] = 5  # model may know it too well
    else:
        breakdown["stars_sweet_spot"] = 8

    # 3. Active development: more recent = more complex current state
    updated = repo_data.get("pushed_at", "")
    if updated and "2026" in updated:
        breakdown["active_development"] = 10
    elif updated and "2025" in updated:
        breakdown["active_development"] = 7
    else:
        breakdown["active_development"] = 3

    # 4. Open issues count: more = more complexity/edge cases
    open_issues = repo_data.get("open_issues_count", 0)
    if open_issues > 500:
        breakdown["issue_complexity"] = 15
    elif open_issues > 100:
        breakdown["issue_complexity"] = 10
    elif open_issues > 20:
        breakdown["issue_complexity"] = 7
    else:
        breakdown["issue_complexity"] = 3

    # 5. Topics/domain: certain domains are harder for models
    topics = repo_data.get("topics", [])
    hard_topics = {"orchestration", "distributed", "compiler", "database", "kernel",
                   "serialization", "networking", "security", "cryptography", "parser",
                   "scheduler", "concurrency", "real-time"}
    topic_overlap = set(topics) & hard_topics
    if topic_overlap:
        breakdown["hard_domain"] = min(15, len(topic_overlap) * 5)
    else:
        breakdown["hard_domain"] = 0

    # 6. Language-specific bonus for languages models handle worse
    lang_difficulty = {"rust": 10, "c++": 10, "c": 8, "go": 5, "java": 3, "python": 0,
                       "javascript": 0, "typescript": 2}
    breakdown["language_difficulty"] = lang_difficulty.get(lang, 0)

    score = sum(breakdown.values())
    result["score"] = score
    result["score_breakdown"] = breakdown

    if score >= 60:
        result["recommendation"] = "EXCELLENT — high complexity, likely to challenge models"
    elif score >= 45:
        result["recommendation"] = "GOOD — solid difficulty, should differentiate model quality"
    elif score >= 30:
        result["recommendation"] = "MODERATE — may work but consider harder alternatives"
    else:
        result["recommendation"] = "WEAK — likely too easy or too memorized by models"

    print(f"Score: {score} — {result['recommendation'].split('—')[0].strip()}")
    return result


def run_analyzer():
    print(f"\n{'='*60}")
    print(f"  MARLIN V3 — REPO ANALYZER")
    print(f"{'='*60}")
    print(f"  Watching : {LIVE_FILE}")
    print(f"  Polling  : every {POLL_INTERVAL}s")
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
            print(f"  Clipboard watcher active — {count} repo(s) captured so far...", end="\r")
            time.sleep(POLL_INTERVAL)
            continue

        if status == "complete":
            print(f"\n  Clipboard watcher finished. {len(entries)} repos to analyze.\n")
            break

        time.sleep(POLL_INTERVAL)

    if not entries:
        print("  No repos captured. Exiting.")
        return

    print(f"  Fetching GitHub data for {len(entries)} repos...\n")
    analyzed = []
    for entry in entries:
        result = analyze_repo(entry)
        analyzed.append(result)
        time.sleep(0.3)

    analyzed_sorted = sorted(analyzed, key=lambda x: x["score"], reverse=True)
    for i, r in enumerate(analyzed_sorted):
        r["rank"] = i + 1

    output = {
        "analyzed_at": datetime.now().isoformat(),
        "total_repos": len(analyzed_sorted),
        "repos": analyzed_sorted,
        "best_pick": analyzed_sorted[0] if analyzed_sorted else None,
    }
    OUTPUT_FILE.write_text(json.dumps(output, indent=2, default=str))

    print(f"\n{'='*60}")
    print(f"  ANALYSIS COMPLETE — RANKED REPOS")
    print(f"{'='*60}\n")

    for r in analyzed_sorted:
        lang_tag = f"[{r['language']}]" if r['supported_language'] else f"[{r['language']} — UNSUPPORTED]"
        print(f"  #{r['rank']:2d}  Score: {r['score']:3d}  {r['owner']}/{r['repo']}  {lang_tag}")
        print(f"       {r['recommendation']}")
        if r.get("details"):
            d = r["details"]
            print(f"       Stars: {d.get('stars',0)} | Size: {d.get('size_kb',0)}KB | Issues: {d.get('open_issues',0)}")
        print()

    best = analyzed_sorted[0]
    print(f"{'='*60}")
    print(f"  RECOMMENDED REPO: {best['owner']}/{best['repo']}")
    print(f"  Score: {best['score']} — {best['recommendation']}")
    print(f"{'='*60}")
    print(f"\n  Full analysis saved to: {OUTPUT_FILE}\n")


if __name__ == "__main__":
    run_analyzer()
