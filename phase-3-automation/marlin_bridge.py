#!/usr/bin/env python3
"""
Marlin Bridge — Live JSON communication between terminal and Cursor.

No API keys needed. Uses Cursor's subscription model directly.
Terminal writes to live_bridge.json, Cursor reads and responds.

Usage:
    # Write a heal request (called by marlin_setup.sh):
    python3 marlin_bridge.py write-heal --desc "..." --cmd "..." --error "..." --cwd "..."

    # Read heal response (called by marlin_setup.sh):
    python3 marlin_bridge.py read-response

    # Update step status:
    python3 marlin_bridge.py update-step --step "3.5" --status "running"

    # Gather repo context for CLAUDE.md:
    python3 marlin_bridge.py repo-context --path /path/to/repo
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime

BRIDGE_DIR = Path(__file__).parent / ".marlin-bridge"
LIVE_JSON = BRIDGE_DIR / "live_bridge.json"


def init():
    BRIDGE_DIR.mkdir(exist_ok=True)


def read_bridge() -> dict:
    if LIVE_JSON.exists():
        try:
            return json.loads(LIVE_JSON.read_text())
        except json.JSONDecodeError:
            pass
    return {}


def write_bridge(data: dict):
    import tempfile, os
    tmp_fd, tmp_path = tempfile.mkstemp(dir=str(LIVE_JSON.parent), suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            json.dump(data, f, indent=2)
        os.rename(tmp_path, str(LIVE_JSON))
    except Exception:
        try: os.unlink(tmp_path)
        except OSError: pass
        LIVE_JSON.write_text(json.dumps(data, indent=2))


def add_log(bridge: dict, msg: str):
    if "log" not in bridge:
        bridge["log"] = []
    bridge["log"].append({
        "time": datetime.now().strftime("%H:%M:%S"),
        "msg": msg,
    })
    # Keep last 50 entries
    bridge["log"] = bridge["log"][-50:]


def write_heal_request(description: str, command: str, error_output: str,
                       working_dir: str, context_hint: str = "",
                       attempt: int = 1, max_retries: int = 3):
    """Write a heal request to the live bridge JSON."""
    init()
    bridge = read_bridge()

    req_id = f"heal-{int(datetime.now().timestamp())}-{os.getpid()}"

    py_ver = "unknown"
    try:
        import subprocess
        py_ver = subprocess.check_output(
            ["python3", "--version"], text=True, stderr=subprocess.STDOUT
        ).strip()
    except Exception:
        pass

    bridge["heal_request"] = {
        "id": req_id,
        "status": "needs_fix",
        "description": description,
        "failed_command": command,
        "error_output": error_output[-3000:],
        "working_directory": working_dir,
        "context_hint": context_hint,
        "python_version": py_ver,
        "os": f"{os.uname().sysname} {os.uname().machine}",
        "attempt": attempt,
        "max_retries": max_retries,
        "timestamp": datetime.now().isoformat(),
    }
    bridge["heal_response"] = None
    bridge["status"] = "waiting_for_cursor"

    add_log(bridge, f"HEAL REQUEST: {description}")
    write_bridge(bridge)

    return req_id


def read_heal_response():
    """Read heal response from the live bridge JSON."""
    bridge = read_bridge()
    resp = bridge.get("heal_response")
    if resp and isinstance(resp, dict) and resp.get("status") == "fixed":
        return resp
    return None


def clear_heal():
    """Clear heal request/response after processing."""
    bridge = read_bridge()
    bridge["heal_request"] = None
    bridge["heal_response"] = None
    bridge["status"] = "running"
    add_log(bridge, "Heal cycle complete")
    write_bridge(bridge)


def update_step(step: str, status: str):
    """Update current step in the live bridge."""
    init()
    bridge = read_bridge()
    bridge["current_step"] = step
    bridge["step_status"] = status
    add_log(bridge, f"Step {step}: {status}")
    write_bridge(bridge)


def init_session(task_name: str):
    """Initialize a new bridge session."""
    init()
    bridge = {
        "session_id": f"session-{int(datetime.now().timestamp())}",
        "task_name": task_name,
        "status": "running",
        "current_step": "init",
        "step_status": "starting",
        "heal_request": None,
        "heal_response": None,
        "repo_path": "",
        "log": [{"time": datetime.now().strftime("%H:%M:%S"),
                 "msg": f"Session started: {task_name}"}],
    }
    write_bridge(bridge)
    return bridge["session_id"]


def set_repo_path(repo_path: str):
    """Set the repo path in the bridge."""
    bridge = read_bridge()
    bridge["repo_path"] = repo_path
    write_bridge(bridge)


def gather_repo_context(repo_path: str) -> dict:
    """Scan repo and build context for CLAUDE.md generation."""
    repo = Path(repo_path)
    skip = {".git", ".venv", "node_modules", "__pycache__",
            ".mypy_cache", ".pytest_cache", ".tox", "dist", "build"}

    ctx = {
        "repo_name": repo.name,
        "repo_path": str(repo),
        "structure": [],
        "readme": "",
        "language": "unknown",
        "configs": {},
        "test_dirs": [],
        "source_samples": {},
    }

    # Top-level structure
    for item in sorted(repo.iterdir()):
        if item.name in skip or item.name.startswith("."):
            continue
        ctx["structure"].append({
            "name": item.name,
            "type": "dir" if item.is_dir() else "file",
        })

    # README
    for name in ["README.md", "README.rst", "README"]:
        readme = repo / name
        if readme.exists():
            ctx["readme"] = readme.read_text(errors="replace")[:3000]
            break

    # Language
    if (repo / "setup.py").exists() or (repo / "pyproject.toml").exists():
        ctx["language"] = "python"
    elif (repo / "package.json").exists():
        ctx["language"] = "node"
    elif (repo / "Cargo.toml").exists():
        ctx["language"] = "rust"
    elif (repo / "go.mod").exists():
        ctx["language"] = "go"

    # Config files
    for cname in ["setup.py", "pyproject.toml", "setup.cfg", "package.json",
                   "Cargo.toml", "go.mod", "tox.ini", "Makefile",
                   "CONTRIBUTING.md"]:
        cpath = repo / cname
        if cpath.exists():
            lines = cpath.read_text(errors="replace").split("\n")[:80]
            ctx["configs"][cname] = "\n".join(lines)

    # Test dirs
    for dirpath, dirnames, _ in os.walk(repo):
        dirnames[:] = [d for d in dirnames if d not in skip]
        if "test" in os.path.basename(dirpath).lower():
            ctx["test_dirs"].append(os.path.relpath(dirpath, repo))
        if len(ctx["test_dirs"]) >= 10:
            break

    # Source samples (entry points)
    for pattern in ["*/__init__.py", "*/main.py", "*/app.py"]:
        for f in list(repo.glob(pattern))[:2]:
            rel = str(f.relative_to(repo))
            if not any(s in rel for s in skip):
                lines = f.read_text(errors="replace").split("\n")[:40]
                ctx["source_samples"][rel] = "\n".join(lines)

    return ctx


def main():
    if len(sys.argv) < 2:
        print("Usage: marlin_bridge.py <command> [args]")
        print("Commands: init-session, write-heal, read-response,")
        print("          clear-heal, update-step, set-repo, repo-context")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "init-session":
        import argparse
        p = argparse.ArgumentParser()
        p.add_argument("cmd_name")
        p.add_argument("--task", required=True)
        a = p.parse_args()
        sid = init_session(a.task)
        print(sid)

    elif cmd == "write-heal":
        import argparse
        p = argparse.ArgumentParser()
        p.add_argument("cmd_name")
        p.add_argument("--desc", required=True)
        p.add_argument("--cmd", required=True)
        p.add_argument("--error-file", required=True)
        p.add_argument("--cwd", required=True)
        p.add_argument("--hint", default="")
        p.add_argument("--attempt", type=int, default=1)
        p.add_argument("--max-retries", type=int, default=3)
        a = p.parse_args()
        error_text = Path(a.error_file).read_text() if Path(a.error_file).exists() else ""
        req_id = write_heal_request(a.desc, a.cmd, error_text,
                                     a.cwd, a.hint, a.attempt, a.max_retries)
        print(req_id)

    elif cmd == "read-response":
        resp = read_heal_response()
        if resp:
            print(json.dumps(resp))
        else:
            sys.exit(1)

    elif cmd == "clear-heal":
        clear_heal()

    elif cmd == "update-step":
        import argparse
        p = argparse.ArgumentParser()
        p.add_argument("cmd_name")
        p.add_argument("--step", required=True)
        p.add_argument("--status", required=True)
        a = p.parse_args()
        update_step(a.step, a.status)

    elif cmd == "set-repo":
        import argparse
        p = argparse.ArgumentParser()
        p.add_argument("cmd_name")
        p.add_argument("--path", required=True)
        a = p.parse_args()
        set_repo_path(a.path)

    elif cmd == "repo-context":
        import argparse
        p = argparse.ArgumentParser()
        p.add_argument("cmd_name")
        p.add_argument("--path", required=True)
        a = p.parse_args()
        ctx = gather_repo_context(a.path)
        print(json.dumps(ctx, indent=2))

    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
