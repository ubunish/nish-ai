"""Boot the sessions dashboard headless and report what it rendered.

Used by tests/sessions.sh: prints the row count of each table after the first
refresh, so the suite checks the real render path, not only the collector.
"""

import asyncio
import importlib.util
import sys
from pathlib import Path

DASH = Path(sys.argv[1])
sys.path.insert(0, str(DASH.parent))
spec = importlib.util.spec_from_file_location("dash", DASH)
dash = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dash)


async def main() -> None:
    app = dash.SessionsDashboard()
    async with app.run_test() as pilot:
        await app.workers.wait_for_complete()
        await pilot.pause()
        sessions = app.query_one("#sessions").row_count
        claims = app.query_one("#claims").row_count
        print(f"sessions={sessions} claims={claims}")


asyncio.run(main())
