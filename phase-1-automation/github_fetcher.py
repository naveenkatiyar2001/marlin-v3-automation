#!/usr/bin/env python3
"""
MARLIN V3 — Rich GitHub Data Fetcher

Fetches detailed data for repos and PRs from GitHub API:
  - Repo: description, README (first 3000 chars), language, topics, structure
  - PR: title, full body, files changed with paths, additions/deletions per file,
        review comments, commit messages, labels

Outputs structured data that the Cursor analysis prompt will consume.
"""

import json
import ssl
import sys
import base64
import urllib.request
import urllib.error
from pathlib import Path

import os

try:
    import certifi
    _SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    _SSL_CONTEXT = ssl._create_unverified_context()

_GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")

DATA_DIR = Path(__file__).parent / "data"


def github_api(endpoint: str, accept: str = "application/vnd.github.v3+json") -> dict | list | None:
    url = f"https://api.github.com{endpoint}"
    headers = {
        "Accept": accept,
        "User-Agent": "MarlinV3-Fetcher",
    }
    if _GITHUB_TOKEN:
        headers["Authorization"] = f"token {_GITHUB_TOKEN}"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15, context=_SSL_CONTEXT) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.URLError, urllib.error.HTTPError, Exception) as e:
        return None


def fetch_repo_detail(owner: str, repo: str) -> dict:
    """Fetch comprehensive repo data."""
    result = {
        "owner": owner,
        "repo": repo,
        "full_name": f"{owner}/{repo}",
        "fetch_ok": False,
    }

    repo_data = github_api(f"/repos/{owner}/{repo}")
    if not repo_data:
        return result

    result["fetch_ok"] = True
    result["description"] = repo_data.get("description", "")
    result["language"] = (repo_data.get("language") or "unknown").lower()
    result["stars"] = repo_data.get("stargazers_count", 0)
    result["forks"] = repo_data.get("forks_count", 0)
    result["open_issues"] = repo_data.get("open_issues_count", 0)
    result["size_kb"] = repo_data.get("size", 0)
    result["topics"] = repo_data.get("topics", [])
    result["default_branch"] = repo_data.get("default_branch", "main")
    result["created_at"] = repo_data.get("created_at", "")
    result["updated_at"] = repo_data.get("updated_at", "")
    result["homepage"] = repo_data.get("homepage", "")
    result["license"] = (repo_data.get("license") or {}).get("spdx_id", "None")
    result["archived"] = repo_data.get("archived", False)

    readme_data = github_api(f"/repos/{owner}/{repo}/readme")
    if readme_data and readme_data.get("content"):
        try:
            raw = base64.b64decode(readme_data["content"]).decode("utf-8", errors="replace")
            result["readme_preview"] = raw[:3000]
        except Exception:
            result["readme_preview"] = "(could not decode)"
    else:
        result["readme_preview"] = "(no README found)"

    tree_data = github_api(f"/repos/{owner}/{repo}/git/trees/{result['default_branch']}?recursive=1")
    if tree_data and tree_data.get("tree"):
        all_paths = [item["path"] for item in tree_data["tree"] if item["type"] == "blob"]
        top_dirs = sorted(set(p.split("/")[0] for p in all_paths if "/" in p))
        result["top_level_dirs"] = top_dirs[:30]
        result["total_files"] = len(all_paths)

        test_files = [p for p in all_paths if "test" in p.lower()]
        result["test_file_count"] = len(test_files)
        result["has_tests"] = len(test_files) > 0

        config_files = [p for p in all_paths if p.split("/")[-1] in {
            "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt",
            "package.json", "tsconfig.json", "go.mod", "Cargo.toml",
            "pom.xml", "build.gradle", "CMakeLists.txt", "Makefile",
            ".github", "tox.ini", "pytest.ini", "jest.config.js",
        }]
        result["config_files"] = config_files[:20]
    else:
        result["top_level_dirs"] = []
        result["total_files"] = 0
        result["test_file_count"] = 0
        result["has_tests"] = False
        result["config_files"] = []

    return result


def fetch_pr_detail(owner: str, repo: str, pr_number: str) -> dict:
    """Fetch comprehensive PR data."""
    result = {
        "owner": owner,
        "repo": repo,
        "pr_number": pr_number,
        "full_ref": f"{owner}/{repo}#{pr_number}",
        "fetch_ok": False,
    }

    pr_data = github_api(f"/repos/{owner}/{repo}/pulls/{pr_number}")
    if not pr_data:
        return result

    result["fetch_ok"] = True
    result["title"] = pr_data.get("title", "")
    result["body"] = (pr_data.get("body") or "")[:2000]
    result["state"] = pr_data.get("state", "")
    result["merged"] = pr_data.get("merged", False)
    result["additions"] = pr_data.get("additions", 0)
    result["deletions"] = pr_data.get("deletions", 0)
    result["changed_files_count"] = pr_data.get("changed_files", 0)
    result["commits_count"] = pr_data.get("commits", 0)
    result["comments_count"] = pr_data.get("comments", 0)
    result["review_comments_count"] = pr_data.get("review_comments", 0)
    result["created_at"] = pr_data.get("created_at", "")
    result["merged_at"] = pr_data.get("merged_at", "")
    result["author"] = (pr_data.get("user") or {}).get("login", "")
    result["labels"] = [l.get("name", "") for l in (pr_data.get("labels") or [])]
    result["base_branch"] = (pr_data.get("base") or {}).get("ref", "")
    result["head_branch"] = (pr_data.get("head") or {}).get("ref", "")

    files_data = github_api(f"/repos/{owner}/{repo}/pulls/{pr_number}/files?per_page=100")
    if files_data:
        result["changed_files"] = []
        for f in files_data:
            result["changed_files"].append({
                "path": f.get("filename", ""),
                "status": f.get("status", ""),
                "additions": f.get("additions", 0),
                "deletions": f.get("deletions", 0),
            })

        dirs_touched = sorted(set(
            "/".join(f["path"].split("/")[:-1]) or "(root)"
            for f in result["changed_files"]
        ))
        result["directories_touched"] = dirs_touched
        result["cross_module"] = len(dirs_touched) > 2
    else:
        result["changed_files"] = []
        result["directories_touched"] = []
        result["cross_module"] = False

    commits_data = github_api(f"/repos/{owner}/{repo}/pulls/{pr_number}/commits?per_page=20")
    if commits_data:
        result["commit_messages"] = [
            (c.get("commit") or {}).get("message", "")[:200]
            for c in commits_data[:10]
        ]
    else:
        result["commit_messages"] = []

    reviews_data = github_api(f"/repos/{owner}/{repo}/pulls/{pr_number}/comments?per_page=20")
    if reviews_data:
        result["review_comment_previews"] = [
            {
                "author": (r.get("user") or {}).get("login", ""),
                "body": (r.get("body") or "")[:300],
                "path": r.get("path", ""),
            }
            for r in reviews_data[:10]
        ]
    else:
        result["review_comment_previews"] = []

    return result


def fetch_all_repos(entries: list) -> list:
    """Fetch detailed data for all repo entries."""
    results = []
    for entry in entries:
        owner = entry.get("owner", "")
        repo = entry.get("repo", "")
        if not owner or not repo:
            continue
        print(f"  Fetching {owner}/{repo}...", end=" ", flush=True)
        data = fetch_repo_detail(owner, repo)
        if data["fetch_ok"]:
            print(f"OK ({data['total_files']} files, {data['language']})")
        else:
            print("FAILED")
        results.append(data)
    return results


def fetch_all_prs(entries: list, default_owner: str = "", default_repo: str = "") -> list:
    """Fetch detailed data for all PR entries."""
    import re
    results = []
    for entry in entries:
        owner = entry.get("owner", default_owner)
        repo = entry.get("repo", default_repo)
        pr_number = entry.get("pr_number", "")
        if not pr_number:
            nums = re.findall(r'\d+', entry.get("raw_text", ""))
            pr_number = nums[-1] if nums else ""
        if not pr_number or not owner or not repo:
            continue
        print(f"  Fetching {owner}/{repo}#{pr_number}...", end=" ", flush=True)
        data = fetch_pr_detail(owner, repo, pr_number)
        if data["fetch_ok"]:
            print(f"OK (\"{data['title'][:50]}\")")
        else:
            print("FAILED")
        results.append(data)
    return results


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 2:
        owner, repo = sys.argv[1], sys.argv[2]
        pr = sys.argv[3] if len(sys.argv) > 3 else None
        if pr:
            data = fetch_pr_detail(owner, repo, pr)
        else:
            data = fetch_repo_detail(owner, repo)
        print(json.dumps(data, indent=2))
