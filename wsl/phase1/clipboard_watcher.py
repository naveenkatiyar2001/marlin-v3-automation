#!/usr/bin/env python3
"""
MARLIN V3 — Phase 1 Clipboard Watcher (WSL-Optimized)

Cross-platform clipboard access:
  - WSL:   powershell.exe Get-Clipboard / clip.exe
  - macOS: pbpaste / pbcopy
  - Linux: xclip

Modes:
    --mode repos    Watch for repository names/URLs
    --mode prs      Watch for PR names/URLs
"""

import json
import subprocess
import sys
import time
import os
import threading
import hashlib
from datetime import datetime
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
POLL_INTERVAL = 0.5


def detect_platform() -> str:
    """Detect whether we're on WSL, macOS, or plain Linux."""
    try:
        with open("/proc/version", "r") as f:
            version_info = f.read().lower()
        if "microsoft" in version_info or "wsl" in version_info:
            return "wsl"
    except FileNotFoundError:
        pass

    if sys.platform == "darwin":
        return "macos"

    return "linux"


PLATFORM = detect_platform()


def get_clipboard() -> str:
    """Get current clipboard content, platform-aware."""
    try:
        if PLATFORM == "wsl":
            result = subprocess.run(
                ["powershell.exe", "-NoProfile", "-Command", "Get-Clipboard"],
                capture_output=True, text=True, timeout=5,
            )
            return result.stdout.strip().replace("\r\n", "\n").strip()

        elif PLATFORM == "macos":
            result = subprocess.run(
                ["pbpaste"], capture_output=True, text=True, timeout=2,
            )
            return result.stdout.strip()

        else:
            result = subprocess.run(
                ["xclip", "-selection", "clipboard", "-o"],
                capture_output=True, text=True, timeout=2,
            )
            return result.stdout.strip()
    except FileNotFoundError:
        if PLATFORM == "wsl":
            try:
                result = subprocess.run(
                    ["xclip", "-selection", "clipboard", "-o"],
                    capture_output=True, text=True, timeout=2,
                )
                return result.stdout.strip()
            except FileNotFoundError:
                pass
        return ""
    except Exception:
        return ""


def set_clipboard(text: str):
    """Set clipboard content, platform-aware."""
    try:
        if PLATFORM == "wsl":
            subprocess.run(
                ["clip.exe"],
                input=text, text=True, timeout=5,
            )
        elif PLATFORM == "macos":
            subprocess.run(
                ["pbcopy"],
                input=text, text=True, timeout=2,
            )
        else:
            subprocess.run(
                ["xclip", "-selection", "clipboard"],
                input=text, text=True, timeout=2,
            )
    except Exception:
        pass


def content_hash(text: str) -> str:
    return hashlib.md5(text.encode()).hexdigest()


def parse_clipboard_entry(text: str, mode: str) -> dict | None:
    """Parse clipboard text into a structured entry."""
    text = text.strip()
    if not text or len(text) < 3:
        return None

    entry = {
        "raw_text": text,
        "captured_at": datetime.now().isoformat(),
        "type": mode,
    }

    if "github.com" in text:
        parts = text.rstrip("/").split("/")
        if mode == "repos" and len(parts) >= 5:
            entry["owner"] = parts[-2]
            entry["repo"] = parts[-1]
            entry["url"] = text
        elif mode == "prs" and "pull" in text and len(parts) >= 7:
            entry["owner"] = parts[-4]
            entry["repo"] = parts[-3]
            entry["pr_number"] = parts[-1]
            entry["url"] = text
    else:
        if mode == "repos":
            if "/" in text:
                parts = text.split("/")
                entry["owner"] = parts[0].strip()
                entry["repo"] = parts[1].strip()
            else:
                entry["repo"] = text
        elif mode == "prs":
            entry["pr_identifier"] = text

    return entry


def load_json(filepath: Path) -> dict:
    if filepath.exists():
        try:
            return json.loads(filepath.read_text())
        except (json.JSONDecodeError, IOError):
            pass
    return {"entries": [], "status": "watching", "updated_at": None}


def save_json(filepath: Path, data: dict):
    data["updated_at"] = datetime.now().isoformat()
    filepath.write_text(json.dumps(data, indent=2, default=str))


def watch_clipboard(mode: str):
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    if mode == "repos":
        json_file = DATA_DIR / "live_repos.json"
    else:
        json_file = DATA_DIR / "live_prs.json"

    data = {"entries": [], "status": "watching", "updated_at": None}
    save_json(json_file, data)

    seen_hashes = set()
    last_clipboard = ""
    entry_count = 0

    print(f"\n{'='*60}")
    print(f"  MARLIN V3 — CLIPBOARD WATCHER ({mode.upper()})")
    print(f"  Platform: {PLATFORM.upper()}")
    print(f"{'='*60}")
    print(f"  Output file : {json_file}")
    print(f"  Polling     : every {POLL_INTERVAL}s")
    print(f"{'='*60}")
    print(f"\n  Copy {mode} from Snorkel one by one.")
    print(f"  Each new clipboard entry will be captured automatically.")
    print(f"  Type 'END' here and press Enter when done.\n")

    stop_event = threading.Event()

    def clipboard_loop():
        nonlocal last_clipboard, entry_count
        while not stop_event.is_set():
            current = get_clipboard()
            h = content_hash(current)

            if current and current != last_clipboard and h not in seen_hashes:
                entry = parse_clipboard_entry(current, mode)
                if entry:
                    seen_hashes.add(h)
                    last_clipboard = current
                    entry_count += 1
                    entry["index"] = entry_count

                    data = load_json(json_file)
                    data["entries"].append(entry)
                    data["status"] = "watching"
                    save_json(json_file, data)

                    display = entry.get("repo") or entry.get("pr_identifier") or current[:60]
                    print(f"  [{entry_count}] Captured: {display}")

            time.sleep(POLL_INTERVAL)

    watcher_thread = threading.Thread(target=clipboard_loop, daemon=True)
    watcher_thread.start()

    while True:
        try:
            user_input = input()
            if user_input.strip().upper() == "END":
                break
        except (EOFError, KeyboardInterrupt):
            break

    stop_event.set()
    watcher_thread.join(timeout=2)

    data = load_json(json_file)
    data["status"] = "complete"
    save_json(json_file, data)

    print(f"\n  Done. Captured {entry_count} {mode}.")
    print(f"  Saved to: {json_file}")
    print(f"  Status set to 'complete' — ready for Cursor analysis.\n")


if __name__ == "__main__":
    mode = "repos"
    for i, arg in enumerate(sys.argv):
        if arg == "--mode" and i + 1 < len(sys.argv):
            mode = sys.argv[i + 1]

    if mode not in ("repos", "prs"):
        print("Usage: python3 clipboard_watcher.py --mode [repos|prs]")
        sys.exit(1)

    watch_clipboard(mode)
