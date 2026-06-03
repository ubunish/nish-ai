#!/usr/bin/env bash
# Prime the nish-ai-uv convention at session start, before Claude drafts any
# python/pip command. Mirrors style-session-start.sh: load the rule upfront,
# from message one, so uv is the default reach — not a correction the
# PreToolUse hook makes after the fact.
#
# Skips when the bypass marker is present (set by "drop uv").
#
# No jq: SessionStart stdout IS added to context, so plain stdout works.
set -euo pipefail

OFF_FLAG="$HOME/.claude/.uv-off"

[[ -f "$OFF_FLAG" ]] && exit 0

cat <<'EOF'
UV CONVENTION ACTIVE (nish-ai-uv). Reach for uv from the start — do NOT draft a
bare python/pip/poetry/pipenv/virtualenv command and wait for the hook to
correct it. Apply this mapping to every command you run AND every command you
suggest in chat:

  python script.py      → uv run script.py
  python -m mod         → uv run -m mod
  python   (REPL)       → uv run python
  python3 ...           → uv run ...
  pip install X         → uv pip install X
  pip ...               → uv pip ...
  python -m venv .venv  → uv venv .venv
  poetry add X          → uv add X
  poetry install        → uv sync
  pipenv install X      → uv add X
  virtualenv .venv      → uv venv .venv
  conda ...             → untouched

Exclusions: command already starts with uv; $VIRTUAL_ENV is set; conda. Off
only on "drop uv".
EOF
