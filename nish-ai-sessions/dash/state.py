"""Read the session coordination state for the dashboard.

Stdlib only, so the collector runs and is tested without the TUI's
dependencies. Every read is best-effort: a missing, malformed or vanished file,
or a field of the wrong type, is skipped rather than raised, because sessions
come and go while the dashboard is open.

Run on its own to print the state as JSON:

    uv run --no-project nish-ai-sessions/dash/state.py
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

RECENT_EVENTS = 20
MAX_PID = 2**31 - 1
NO_CHECKOUT = {"repo": "", "branch": "", "worktree": False}


def _claude_dir() -> Path:
    return Path(os.environ.get("HOME", "~")).expanduser() / ".claude"


def _alive(pid: object) -> bool:
    if not isinstance(pid, int) or isinstance(pid, bool) or not 0 < pid <= MAX_PID:
        return False
    try:
        os.kill(pid, 0)
    except PermissionError:
        return True
    except (OSError, OverflowError):
        return False
    return True


def _read_text(path: Path) -> str:
    try:
        return path.read_text()
    except (OSError, ValueError):  # ValueError covers undecodable bytes
        return ""


def _read_json(path: Path) -> dict | None:
    try:
        data = json.loads(_read_text(path))
    except ValueError:
        return None
    return data if isinstance(data, dict) else None


def _read_jsonl(path: Path) -> list[dict]:
    rows = []
    for line in _read_text(path).splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows


def _text(value: object) -> str:
    return value if isinstance(value, str) else ""


def checkout(cwd: str) -> dict:
    """Repo name, branch, and whether cwd is a linked worktree, from one git call."""
    # An empty or relative cwd would make git -C fall back to this process's dir.
    if not cwd.startswith("/"):
        return dict(NO_CHECKOUT)
    try:
        done = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--path-format=absolute",
             "--git-dir", "--git-common-dir", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=2,
        )
    except (OSError, subprocess.TimeoutExpired):
        return dict(NO_CHECKOUT)
    lines = done.stdout.splitlines()
    if done.returncode != 0 or len(lines) != 3:
        return dict(NO_CHECKOUT)
    git_dir, common_dir, branch = lines
    return {"repo": Path(common_dir).parent.name, "branch": branch, "worktree": git_dir != common_dir}


def checkout_label(session: dict) -> str:
    if not session["branch"]:
        return "-"
    return f"{session['branch']} (worktree)" if session["worktree"] else session["branch"]


def _pending(inbox: Path, session_id: str) -> int:
    safe_id = "".join(c for c in session_id if c.isalnum() or c in "_-")
    box = inbox / f"{safe_id}.jsonl"
    if not safe_id or box.is_symlink():
        return 0
    return len(_read_jsonl(box))


def sessions(claude: Path) -> list[dict]:
    """Live Claude sessions from the registry, newest first."""
    inbox = claude / "nish-ai-sessions" / "inbox"
    checkouts: dict[str, dict] = {}  # sessions sharing a cwd share one git call
    rows = []
    for path in sorted((claude / "sessions").glob("*.json")):
        entry = _read_json(path)
        if not entry or not _alive(entry.get("pid")):
            continue
        cwd = _text(entry.get("cwd"))
        session_id = _text(entry.get("sessionId"))
        started_at = entry.get("startedAt")
        if cwd not in checkouts:
            checkouts[cwd] = checkout(cwd)
        rows.append(
            {
                "name": _text(entry.get("name")) or session_id[:8],
                "session_id": session_id,
                "status": _text(entry.get("status")),
                "started_at": started_at if isinstance(started_at, (int, float)) else 0,
                "cwd": cwd,
                **checkouts[cwd],
                "pending": _pending(inbox, session_id),
            }
        )
    return sorted(rows, key=lambda row: row["started_at"], reverse=True)


def claims(claude: Path) -> list[dict]:
    """Live claims across every repo."""
    rows = []
    for path in sorted((claude / "nish-ai-sessions" / "claims").glob("*.jsonl")):
        rows.extend(row for row in _read_jsonl(path) if _alive(row.get("pid")))
    return rows


def recent_events(claude: Path) -> list[dict]:
    """The newest events from the shared log, oldest first."""
    return _read_jsonl(claude / "nish-ai-sessions" / "events.jsonl")[-RECENT_EVENTS:]


def collect() -> dict:
    claude = _claude_dir()
    return {
        "sessions": sessions(claude),
        "claims": claims(claude),
        "events": recent_events(claude),
    }


if __name__ == "__main__":
    print(json.dumps(collect(), indent=2))
