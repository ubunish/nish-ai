# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "textual>=0.74",
#   "nish-tui @ git+https://github.com/ubunish/nish-tui@6ec87b45f37cc645cecfd4e0852bf58a455bc011",
# ]
# ///
"""Read-only dashboard of parallel Claude sessions, their claims and events.

    uv run ~/.claude/skills/nish-ai-sessions/dash/dash.py

Three panels, refreshed every two seconds from the state nish-ai-sessions
keeps: live sessions (repo, branch or worktree, busy/idle, pending events),
live claims, and the most recent events. It never writes anything.
"""

from __future__ import annotations

import sys
from pathlib import Path

from rich.text import Text
from textual import work
from textual.app import App, ComposeResult
from textual.widgets import DataTable

import nish_tui
from nish_tui import BorderedPanel, Header, LogView

# A uv script has no package path, so the collector beside it is imported by
# putting this directory on sys.path.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import state  # noqa: E402

REFRESH_SECONDS = 2


def cell(value: object) -> Text:
    # Plain str cells are parsed as markup; a topic holding "[/x]" would raise.
    return Text(str(value))


@nish_tui.apply
class SessionsDashboard(App):
    TITLE = "nish-ai sessions"
    CSS = "BorderedPanel { height: 1fr; }"

    def compose(self) -> ComposeResult:
        yield Header("nish-ai sessions")
        with BorderedPanel(title="sessions"):
            yield DataTable(id="sessions", cursor_type="none", zebra_stripes=True)
        with BorderedPanel(title="claims"):
            yield DataTable(id="claims", cursor_type="none", zebra_stripes=True)
        with BorderedPanel(title="recent events"):
            yield LogView(id="events")

    def on_mount(self) -> None:
        self.query_one("#sessions", DataTable).add_columns(
            "session", "repo", "checkout", "status", "pending"
        )
        self.query_one("#claims", DataTable).add_columns("session", "kind", "topic")
        self.refresh_state()
        self.set_interval(REFRESH_SECONDS, self.refresh_state)

    # Collecting runs git per checkout, so it stays off the UI thread; a slow
    # mount delays the next snapshot instead of freezing the screen.
    @work(thread=True, exclusive=True)
    def refresh_state(self) -> None:
        snapshot = state.collect()
        self.call_from_thread(self.show, snapshot)

    def show(self, snapshot: dict) -> None:
        sessions = self.query_one("#sessions", DataTable)
        sessions.clear()
        for session in snapshot["sessions"]:
            sessions.add_row(
                cell(session["name"]),
                cell(session["repo"] or "-"),
                cell(state.checkout_label(session)),
                cell(session["status"]),
                cell(session["pending"]),
            )

        claims = self.query_one("#claims", DataTable)
        claims.clear()
        for claim in snapshot["claims"]:
            claims.add_row(cell(claim.get("name", "")), cell(claim.get("kind", "")), cell(claim.get("topic", "")))

        events = self.query_one("#events", LogView)
        events.clear()
        for event in snapshot["events"]:
            events.log_line(
                "info" if event.get("type") == "main_moved" else "debug",
                f"{event.get('ts', '')}  {event.get('type', '?')} → {event.get('to', '?')}",
            )


if __name__ == "__main__":
    SessionsDashboard().run()
