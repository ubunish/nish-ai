#!/usr/bin/env bash
# Statusline badge: show whether nish-ai-writing-style is active this session.
# Mirrors caveman's statusline — a visible signal that the per-turn hook is live.
#
# Output (single line): "<dir>  |  ✎ style:on"  or  "... ✎ style:off"
# jq is optional here: if absent, fall back to $PWD for the directory.
set -euo pipefail

OFF_FLAG="$HOME/.claude/.nish-style-off"
INPUT="$(cat)"

DIR="$PWD"
if command -v jq >/dev/null; then
  PARSED="$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null || true)"
  [[ -n "$PARSED" ]] && DIR="$PARSED"
fi

BADGE="✎ style:on"
[[ -f "$OFF_FLAG" ]] && BADGE="✎ style:off"

printf '%s  |  %s' "$(basename "$DIR")" "$BADGE"
