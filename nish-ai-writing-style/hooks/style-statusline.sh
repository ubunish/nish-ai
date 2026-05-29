#!/usr/bin/env bash
# Statusline badge: show writing-style state and the session's router category.
# Mirrors caveman's statusline — a visible signal that the per-turn hooks are live.
#
# Output (single line):
#   "<dir>  |  ✎ style:on  |  ▸ coding"   (category known)
#   "<dir>  |  ✎ style:off"               (no category dispatched yet)
# jq is optional here: if absent, fall back to $PWD and skip the category badge
# (the session_id needed to find the category flag only arrives via the JSON).
set -euo pipefail

OFF_FLAG="$HOME/.claude/.nish-style-off"
INPUT="$(cat)"

DIR="$PWD"
SID=""
if command -v jq >/dev/null; then
  PARSED="$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null || true)"
  [[ -n "$PARSED" ]] && DIR="$PARSED"
  SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi

BADGE="✎ style:on"
[[ -f "$OFF_FLAG" ]] && BADGE="✎ style:off"

printf '%s  |  %s' "$(basename "$DIR")" "$BADGE"

# Category badge: written per-session by recognition-category-tracker.sh.
# Refuse symlinks and whitelist the contents — never echo arbitrary flag bytes
# (a local attacker could otherwise plant ANSI escapes in the flag file).
if [[ -n "$SID" ]]; then
  CAT_FLAG="$HOME/.claude/.nish-ai-category-$SID"
  if [[ -f "$CAT_FLAG" && ! -L "$CAT_FLAG" ]]; then
    CAT="$(head -c 16 "$CAT_FLAG" 2>/dev/null | tr -cd 'a-z')"
    case "$CAT" in
      planning|question|coding|docs|chore) printf '  |  ▸ %s' "$CAT" ;;
    esac
  fi
fi
