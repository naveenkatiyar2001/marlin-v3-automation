#!/usr/bin/env python3
"""
Marlin V3 — Evidence Collector & Deep Analyzer
===============================================
Captures all model evidence (diffs, traces, tmux, new files) after each turn
and generates analysis.json with structured facts for evaluation answer generation.

Usage:
    python3 marlin_evidence_collector.py --turn 2 --task dagster-airlift-refactor
    python3 marlin_evidence_collector.py --turn 1 --task my-task --prompt "The prompt text"
    python3 marlin_evidence_collector.py --turn 3 --task my-task --prompt-file prompt.txt
"""

import argparse
import json
import os
import re
import subprocess
import sys
import glob
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple


WORKSPACE_ROOT = Path(__file__).parent.parent
EVIDENCE_BASE = WORKSPACE_ROOT / "marlin-evidence-task1"
HFI_CACHE = Path.home() / ".cache" / "claude-hfi"
HFI_TEMP_BASE = Path("/var/folders")


def run(cmd: str, cwd: str = None) -> str:
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd, timeout=30)
        return r.stdout.strip()
    except Exception:
        return ""


def find_hfi_session() -> Optional[str]:
    tmux_out = run("tmux list-sessions -F '#{session_name}'")
    for line in tmux_out.splitlines():
        line = line.strip()
        if re.match(r'^[0-9a-f]{8}-', line) and line.endswith('-A'):
            return line.replace('-A', '')
    return None


def find_worktrees(session_id: str) -> Tuple[Optional[str], Optional[str]]:
    pattern = str(HFI_CACHE / "*")
    for d in sorted(glob.glob(pattern)):
        a_path = os.path.join(d, "A")
        b_path = os.path.join(d, "B")
        if os.path.isdir(a_path) and os.path.isdir(b_path):
            return a_path, b_path
    return None, None


def find_repo_dir() -> Optional[str]:
    workspace_dir = WORKSPACE_ROOT / "phase-3-automation" / "marlin-workspace"
    if not workspace_dir.exists():
        return None
    for task_dir in sorted(workspace_dir.iterdir()):
        if task_dir.is_dir() and task_dir.name.startswith("task-"):
            for repo_dir in sorted(task_dir.iterdir()):
                if repo_dir.is_dir() and (repo_dir / ".git").exists():
                    return str(repo_dir)
    return None


# =========================================================================
# EVIDENCE CAPTURE
# =========================================================================

def capture_diff(worktree: str) -> str:
    return run("git diff HEAD", cwd=worktree)


def capture_tmux(session_id: str, trajectory: str) -> str:
    sess = f"{session_id}-{trajectory}"
    return run(f'tmux capture-pane -t "{sess}" -p -S -1000')


def capture_diff_stat(worktree: str) -> str:
    return run("git diff HEAD --stat", cwd=worktree)


def capture_new_files(worktree: str) -> List[str]:
    out = run("git ls-files --others --exclude-standard", cwd=worktree)
    return [f for f in out.splitlines() if f.strip()] if out else []


def copy_new_package_files(worktree: str, dest: str, label: str):
    serialization_dir = None
    for root, dirs, files in os.walk(worktree):
        if root.endswith("core/serialization") and "__init__.py" in files:
            serialization_dir = root
            break
    if not serialization_dir:
        return
    dest_dir = os.path.join(dest, f"{label}_serialization")
    os.makedirs(dest_dir, exist_ok=True)
    for f in os.listdir(serialization_dir):
        if f.endswith(".py"):
            src = os.path.join(serialization_dir, f)
            subprocess.run(["cp", src, dest_dir], capture_output=True)


# =========================================================================
# DEEP ANALYSIS
# =========================================================================

def analyze_scope(diff_text: str, label: str) -> Dict[str, Any]:
    files_changed = []
    current_file = None
    additions = 0
    deletions = 0

    for line in diff_text.splitlines():
        if line.startswith("diff --git"):
            if current_file:
                files_changed.append({"name": current_file, "additions": additions, "deletions": deletions})
            match = re.search(r'b/(.+)$', line)
            current_file = match.group(1) if match else "unknown"
            additions = 0
            deletions = 0
        elif line.startswith("+") and not line.startswith("+++"):
            additions += 1
        elif line.startswith("-") and not line.startswith("---"):
            deletions += 1
    if current_file:
        files_changed.append({"name": current_file, "additions": additions, "deletions": deletions})

    types_renamed = []
    types_kept = []
    signatures_changed = []
    new_types = []
    import_changes = []
    null_guard_changes = []

    for line in diff_text.splitlines():
        if re.search(r'^\+.*class\s+Serialized\w+', line):
            cls = re.search(r'class\s+(\w+)', line)
            if cls:
                new_types.append(cls.group(1))

        if re.search(r'^\-.*class\s+(\w+)', line):
            old_cls = re.search(r'class\s+(\w+)', line)
            if old_cls:
                old_name = old_cls.group(1)
                for new_line in diff_text.splitlines():
                    if re.search(rf'^\+.*class\s+\w*{old_name}\w*', new_line):
                        new_cls = re.search(r'class\s+(\w+)', new_line)
                        if new_cls and new_cls.group(1) != old_name:
                            types_renamed.append({"from": old_name, "to": new_cls.group(1)})

        if re.search(r'^\-\s*def\s+\w+\(', line):
            func = re.search(r'def\s+(\w+)\((.+?)(?:\)|$)', line)
            if func:
                func_name = func.group(1)
                old_params = func.group(2)
                for new_line in diff_text.splitlines():
                    if re.search(rf'^\+\s*def\s+{func_name}\(', new_line):
                        new_func = re.search(r'def\s+\w+\((.+?)(?:\)|$)', new_line)
                        if new_func and new_func.group(1).strip() != old_params.strip():
                            signatures_changed.append({
                                "func": func_name,
                                "old_params": old_params.strip(),
                                "new_params": new_func.group(1).strip()
                            })

        if re.search(r'^\+.*from\s+\w+', line) and not line.startswith("+++"):
            import_changes.append({"added": line.lstrip("+").strip()})
        elif re.search(r'^\-.*from\s+\w+', line) and not line.startswith("---"):
            import_changes.append({"removed": line.lstrip("-").strip()})

        if re.search(r'^\+.*\.get\(', line) and re.search(r'^\-.*\[', diff_text):
            null_guard_changes.append(line.lstrip("+").strip())

    total_additions = sum(f["additions"] for f in files_changed)
    total_deletions = sum(f["deletions"] for f in files_changed)

    return {
        "files_changed": files_changed,
        "file_count": len(files_changed),
        "total_additions": total_additions,
        "total_deletions": total_deletions,
        "net_change": total_additions - total_deletions,
        "types_renamed": types_renamed,
        "types_kept": types_kept,
        "signatures_changed": signatures_changed,
        "new_types_introduced": new_types,
        "import_changes_count": len(import_changes),
        "null_guard_changes": null_guard_changes,
    }


def analyze_verification(trace_text: str, label: str) -> Dict[str, Any]:
    investigation_cmds = []
    tests_run = []
    round_trip_tested = False
    linter_run = None
    pre_existing_verified = False
    deps_installed = []

    lines = trace_text.splitlines()
    for i, line in enumerate(lines):
        if re.search(r'Searched for \d+ pattern', line):
            match = re.search(r'Searched for (\d+) pattern.*, read (\d+) file', line)
            if match:
                investigation_cmds.append({
                    "type": "search_and_read",
                    "patterns": int(match.group(1)),
                    "files": int(match.group(2))
                })

        if re.search(r'Read \d+ file', line):
            match = re.search(r'Read (\d+) file', line)
            if match:
                investigation_cmds.append({"type": "read_files", "count": int(match.group(1))})

        if re.search(r'pytest|python -m pytest', line):
            result = "unknown"
            for j in range(i+1, min(i+10, len(lines))):
                if re.search(r'(\d+) passed', lines[j]):
                    passed = re.search(r'(\d+) passed', lines[j])
                    result = f"{passed.group(1)} passed"
                    break
                if "Error" in lines[j] or "FAILED" in lines[j]:
                    result = "failed"
                    break
            tests_run.append({"command": line.strip()[:100], "result": result})

        if re.search(r'serialize_value|deserialize_value|round.?trip', line, re.IGNORECASE):
            round_trip_tested = True

        if re.search(r'ruff|flake8|pylint', line):
            result = "unknown"
            for j in range(i+1, min(i+5, len(lines))):
                if "All checks passed" in lines[j]:
                    result = "clean"
                    break
                if "Error" in lines[j] or "failed" in lines[j].lower():
                    result = "issues_found"
                    break
            linter_run = {"tool": "ruff" if "ruff" in line else "other", "result": result}

        if re.search(r'git stash|git checkout.*HEAD|git show HEAD', line):
            pre_existing_verified = True

        if re.search(r'pip install', line):
            pkg = re.search(r'pip install\s+["\']?([^\s"\']+)', line)
            if pkg:
                deps_installed.append(pkg.group(1))

    files_read_before_first_edit = 0
    first_edit_found = False
    for line in lines:
        if not first_edit_found:
            if re.search(r'Read \d+ file|Searched for', line):
                match = re.search(r'Read (\d+) file', line)
                if match:
                    files_read_before_first_edit += int(match.group(1))
                match2 = re.search(r'read (\d+) file', line)
                if match2:
                    files_read_before_first_edit += int(match2.group(1))
            if re.search(r'Update\(|Write\(|Bash\(mkdir|cat >', line):
                first_edit_found = True

    return {
        "investigation_commands": investigation_cmds,
        "files_read_before_first_edit": files_read_before_first_edit,
        "tests_run": tests_run,
        "tests_run_count": len(tests_run),
        "round_trip_tested": round_trip_tested,
        "linter_run": linter_run,
        "pre_existing_failures_verified": pre_existing_verified,
        "dependencies_installed": deps_installed,
    }


def analyze_process(trace_text: str, label: str) -> Dict[str, Any]:
    planning_visible = False
    plan_text = ""
    error_diagnoses = []
    questions_asked = []
    destructive_actions = []

    lines = trace_text.splitlines()

    for i, line in enumerate(lines):
        if re.search(r'^\d+\.\s+\w|step \d|Step \d|plan:', line, re.IGNORECASE):
            planning_visible = True
            plan_text = line.strip()[:200]

        if re.search(r'rm\s+-rf|git\s+push\s+-f|git\s+reset\s+--hard|DROP\s+TABLE|force.push', line, re.IGNORECASE):
            destructive_actions.append(line.strip()[:150])

        if re.search(r'version mismatch|pre-existing|not related to our|not a regression', line, re.IGNORECASE):
            error_diagnoses.append({
                "diagnosis": line.strip()[:200],
                "quality": "correct_root_cause"
            })

        if re.search(r'\?\s*$|should I|do you want|clarif', line, re.IGNORECASE):
            if not re.search(r'Tip:|ctrl\+o', line):
                questions_asked.append(line.strip()[:150])

    time_markers = []
    for line in lines:
        match = re.search(r'(\d+)m\s+(\d+)s|(\d+)s\s', line)
        if match:
            time_markers.append(line.strip()[:100])

    return {
        "planning_visible": planning_visible,
        "plan_text": plan_text if planning_visible else None,
        "error_diagnoses": error_diagnoses,
        "error_diagnosis_count": len(error_diagnoses),
        "questions_asked": questions_asked,
        "questions_asked_count": len(questions_asked),
        "destructive_actions": destructive_actions,
        "destructive_action_count": len(destructive_actions),
        "time_markers": time_markers[:5],
    }


def analyze_communication(trace_text: str, diff_text: str, label: str) -> Dict[str, Any]:
    summary_text = ""
    claims = []

    summary_start = None
    lines = trace_text.splitlines()
    for i, line in enumerate(lines):
        if re.search(r'Done\.|Summary|Changes Made|Here.s what was done|All.*changes', line, re.IGNORECASE):
            summary_start = i
            break

    if summary_start:
        summary_lines = []
        for j in range(summary_start, min(summary_start + 50, len(lines))):
            l = lines[j].strip()
            if l and not re.search(r'Tip:|ctrl\+o|Baking|Embellish|Symbioting|Wandering', l):
                summary_lines.append(l)
            if re.search(r'^\(base\)|^❯|^\$', l):
                break
        summary_text = "\n".join(summary_lines)

    test_claims = re.findall(r'(\d+)/(\d+)\s+pass|all.*tests?\s+pass|tests?\s+pass', trace_text, re.IGNORECASE)
    for tc in test_claims:
        claim = f"Tests pass"
        if isinstance(tc, tuple) and tc[0]:
            claim = f"{tc[0]}/{tc[1]} tests pass"

        verified = bool(re.search(r'pytest|python -m pytest', trace_text))
        claims.append({"claim": claim, "verified": verified, "source": "trace"})

    round_trip_claim = bool(re.search(r'round.?trip works|round.?trip pass', trace_text, re.IGNORECASE))
    if round_trip_claim:
        verified = bool(re.search(r'serialize_value.*deserialize_value|deserialize_value.*serialize_value', trace_text))
        claims.append({"claim": "Round-trip works", "verified": verified, "source": "trace"})

    ruff_claim = bool(re.search(r'All checks passed|ruff.*clean', trace_text, re.IGNORECASE))
    if ruff_claim:
        claims.append({"claim": "Ruff clean", "verified": True, "source": "trace"})

    omissions = []
    if re.search(r'^\-\s*def\s+\w+\(.*spec.*AssetSpec', diff_text, re.MULTILINE):
        if not re.search(r'spec.*param|signature.*change|API.*change|contract.*change', summary_text, re.IGNORECASE):
            omissions.append("Signature change in task_asset.py not flagged as API change")

    if re.search(r'Serialized\w+Data|Serialized\w+Dep', diff_text):
        rename_count = len(re.findall(r'^\+.*class\s+Serialized', diff_text, re.MULTILINE))
        if rename_count >= 3 and not re.search(r'rename|renamed', summary_text, re.IGNORECASE):
            omissions.append(f"{rename_count} types renamed but not highlighted as scope addition")

    return {
        "summary_text": summary_text[:2000],
        "summary_length_words": len(summary_text.split()),
        "claims": claims,
        "claims_verified_count": sum(1 for c in claims if c["verified"]),
        "claims_unverified_count": sum(1 for c in claims if not c["verified"]),
        "omissions": omissions,
        "omission_count": len(omissions),
    }


def generate_comparison(a_analysis: Dict, b_analysis: Dict) -> Dict[str, Any]:
    comparison = {}

    a_scope = a_analysis["scope"]
    b_scope = b_analysis["scope"]
    if len(a_scope["types_renamed"]) > len(b_scope["types_renamed"]):
        comparison["scope_winner"] = "B"
        comparison["scope_reason"] = f"A renamed {len(a_scope['types_renamed'])} types, B renamed {len(b_scope['types_renamed'])}"
    elif len(b_scope["types_renamed"]) > len(a_scope["types_renamed"]):
        comparison["scope_winner"] = "A"
        comparison["scope_reason"] = f"B renamed {len(b_scope['types_renamed'])} types, A renamed {len(a_scope['types_renamed'])}"
    else:
        if a_scope["net_change"] > b_scope["net_change"] + 30:
            comparison["scope_winner"] = "B"
            comparison["scope_reason"] = f"A added {a_scope['net_change']} net lines vs B's {b_scope['net_change']}"
        elif b_scope["net_change"] > a_scope["net_change"] + 30:
            comparison["scope_winner"] = "A"
            comparison["scope_reason"] = f"B added {b_scope['net_change']} net lines vs A's {a_scope['net_change']}"
        else:
            comparison["scope_winner"] = "tie"
            comparison["scope_reason"] = "Similar scope"

    a_ver = a_analysis["verification"]
    b_ver = b_analysis["verification"]
    a_test_score = a_ver["tests_run_count"] + (1 if a_ver["round_trip_tested"] else 0) + (1 if a_ver["linter_run"] else 0)
    b_test_score = b_ver["tests_run_count"] + (1 if b_ver["round_trip_tested"] else 0) + (1 if b_ver["linter_run"] else 0)

    if a_test_score > b_test_score + 1:
        comparison["verification_winner"] = "A"
        comparison["verification_reason"] = f"A ran {a_ver['tests_run_count']} tests, round-trip={a_ver['round_trip_tested']}, linter={a_ver['linter_run'] is not None}. B ran {b_ver['tests_run_count']} tests"
    elif b_test_score > a_test_score + 1:
        comparison["verification_winner"] = "B"
        comparison["verification_reason"] = f"B ran more verification"
    else:
        comparison["verification_winner"] = "tie"
        comparison["verification_reason"] = "Similar verification levels"

    a_proc = a_analysis["process"]
    b_proc = b_analysis["process"]
    if a_proc["destructive_action_count"] > 0 and b_proc["destructive_action_count"] == 0:
        comparison["process_winner"] = "B"
        comparison["process_reason"] = "A had destructive actions, B did not"
    elif b_proc["destructive_action_count"] > 0 and a_proc["destructive_action_count"] == 0:
        comparison["process_winner"] = "A"
        comparison["process_reason"] = "B had destructive actions, A did not"
    else:
        comparison["process_winner"] = "tie"
        comparison["process_reason"] = "Similar engineering process"

    a_comm = a_analysis["communication"]
    b_comm = b_analysis["communication"]
    a_honesty = a_comm["claims_verified_count"] - a_comm["omission_count"]
    b_honesty = b_comm["claims_verified_count"] - b_comm["omission_count"]
    if a_honesty > b_honesty + 1:
        comparison["communication_winner"] = "A"
    elif b_honesty > a_honesty + 1:
        comparison["communication_winner"] = "B"
    else:
        comparison["communication_winner"] = "tie"

    winners = [comparison["scope_winner"], comparison["verification_winner"],
               comparison["process_winner"], comparison["communication_winner"]]
    a_wins = winners.count("A")
    b_wins = winners.count("B")

    if b_wins > a_wins:
        comparison["overall_recommendation"] = "B"
        comparison["overall_magnitude"] = "slight" if b_wins - a_wins == 1 else "moderate"
    elif a_wins > b_wins:
        comparison["overall_recommendation"] = "A"
        comparison["overall_magnitude"] = "slight" if a_wins - b_wins == 1 else "moderate"
    else:
        comparison["overall_recommendation"] = "tie"
        comparison["overall_magnitude"] = "equivalent"

    if comparison["scope_winner"] != "tie":
        comparison["key_axis"] = "scope_control"
    elif comparison["verification_winner"] != "tie":
        comparison["key_axis"] = "verification_discipline"
    elif comparison["process_winner"] != "tie":
        comparison["key_axis"] = "engineering_process"
    else:
        comparison["key_axis"] = "equivalent"

    return comparison


# =========================================================================
# MAIN
# =========================================================================

def main():
    parser = argparse.ArgumentParser(description="Marlin V3 Evidence Collector & Analyzer")
    parser.add_argument("--turn", "-t", type=int, required=True, help="Turn number")
    parser.add_argument("--task", required=True, help="Task name (e.g. dagster-airlift-refactor)")
    parser.add_argument("--prompt", help="Turn prompt text")
    parser.add_argument("--prompt-file", help="File containing turn prompt")
    parser.add_argument("--evidence-dir", help="Override evidence directory")
    args = parser.parse_args()

    session_id = find_hfi_session()
    if not session_id:
        print("ERROR: No HFI tmux session found. Is HFI running?")
        sys.exit(1)
    print(f"  Found HFI session: {session_id}")

    wt_a, wt_b = find_worktrees(session_id)
    if not wt_a or not wt_b:
        print("ERROR: Could not find worktrees A/B")
        sys.exit(1)
    print(f"  Worktree A: {wt_a}")
    print(f"  Worktree B: {wt_b}")

    evidence_dir = args.evidence_dir or str(EVIDENCE_BASE / f"task-{args.task}" / f"turn-{args.turn}")
    os.makedirs(evidence_dir, exist_ok=True)

    prompt_text = args.prompt or ""
    if args.prompt_file and os.path.exists(args.prompt_file):
        prompt_text = Path(args.prompt_file).read_text()

    print(f"\n  Collecting Turn {args.turn} evidence into: {evidence_dir}")

    # 1. Capture diffs
    diffs_dir = os.path.join(evidence_dir, "diffs")
    os.makedirs(diffs_dir, exist_ok=True)
    diff_a = capture_diff(wt_a)
    diff_b = capture_diff(wt_b)
    Path(os.path.join(diffs_dir, "diff_A.txt")).write_text(diff_a)
    Path(os.path.join(diffs_dir, "diff_B.txt")).write_text(diff_b)
    print(f"  Diffs: A={len(diff_a.splitlines())} lines, B={len(diff_b.splitlines())} lines")

    # 2. Capture tmux traces
    traces_dir = os.path.join(evidence_dir, "traces")
    os.makedirs(traces_dir, exist_ok=True)
    trace_a = capture_tmux(session_id, "A")
    trace_b = capture_tmux(session_id, "B")
    Path(os.path.join(traces_dir, "trace_A.txt")).write_text(trace_a)
    Path(os.path.join(traces_dir, "trace_B.txt")).write_text(trace_b)
    print(f"  Traces: A={len(trace_a.splitlines())} lines, B={len(trace_b.splitlines())} lines")

    # 3. Capture tmux full sessions
    tmux_dir = os.path.join(evidence_dir, "tmux-captures")
    os.makedirs(tmux_dir, exist_ok=True)
    Path(os.path.join(tmux_dir, f"turn{args.turn}-trajectory-A.txt")).write_text(trace_a)
    Path(os.path.join(tmux_dir, f"turn{args.turn}-trajectory-B.txt")).write_text(trace_b)

    # 4. Copy new package files
    new_files_dir = os.path.join(evidence_dir, "new-files")
    os.makedirs(new_files_dir, exist_ok=True)
    copy_new_package_files(wt_a, new_files_dir, "A")
    copy_new_package_files(wt_b, new_files_dir, "B")
    print(f"  New files copied")

    # 5. Diff stats
    stat_a = capture_diff_stat(wt_a)
    stat_b = capture_diff_stat(wt_b)

    # 6. Save metadata
    metadata = {
        "turn": args.turn,
        "task": args.task,
        "session_id": session_id,
        "timestamp": datetime.now().isoformat(),
        "prompt": prompt_text,
        "worktree_a": wt_a,
        "worktree_b": wt_b,
        "diff_stat_a": stat_a,
        "diff_stat_b": stat_b,
    }
    Path(os.path.join(evidence_dir, "metadata.json")).write_text(
        json.dumps(metadata, indent=2)
    )

    # 7. DEEP ANALYSIS
    print(f"\n  Running deep analysis...")

    a_scope = analyze_scope(diff_a, "A")
    b_scope = analyze_scope(diff_b, "B")
    print(f"    Scope: A changed {a_scope['file_count']} files (+{a_scope['total_additions']}/-{a_scope['total_deletions']}), B changed {b_scope['file_count']} files (+{b_scope['total_additions']}/-{b_scope['total_deletions']})")

    a_verification = analyze_verification(trace_a, "A")
    b_verification = analyze_verification(trace_b, "B")
    print(f"    Verification: A ran {a_verification['tests_run_count']} tests, B ran {b_verification['tests_run_count']} tests")

    a_process = analyze_process(trace_a, "A")
    b_process = analyze_process(trace_b, "B")
    print(f"    Process: A destructive={a_process['destructive_action_count']}, B destructive={b_process['destructive_action_count']}")

    a_communication = analyze_communication(trace_a, diff_a, "A")
    b_communication = analyze_communication(trace_b, diff_b, "B")
    print(f"    Communication: A claims={len(a_communication['claims'])}, B claims={len(b_communication['claims'])}")

    a_analysis = {
        "scope": a_scope,
        "verification": a_verification,
        "process": a_process,
        "communication": a_communication,
    }
    b_analysis = {
        "scope": b_scope,
        "verification": b_verification,
        "process": b_process,
        "communication": b_communication,
    }

    comparison = generate_comparison(a_analysis, b_analysis)
    print(f"    Comparison: scope={comparison['scope_winner']}, verification={comparison['verification_winner']}, overall={comparison['overall_recommendation']}")

    analysis = {
        "turn": args.turn,
        "task": args.task,
        "timestamp": datetime.now().isoformat(),
        "model_a": a_analysis,
        "model_b": b_analysis,
        "comparison": comparison,
    }

    analysis_path = os.path.join(evidence_dir, "analysis.json")
    Path(analysis_path).write_text(json.dumps(analysis, indent=2))
    print(f"\n  analysis.json saved: {analysis_path}")

    print(f"\n  ====================================")
    print(f"  Turn {args.turn} evidence captured successfully")
    print(f"  Evidence: {evidence_dir}")
    print(f"  Analysis: {analysis_path}")
    print(f"  ====================================")
    print(f"\n  Next: In Cursor chat, say 'Evaluate turn {args.turn} for task {args.task}'")


if __name__ == "__main__":
    main()
