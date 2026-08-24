#!/usr/bin/env bash
# Statusline badge: show writing-style state and the session's router category.
# Mirrors caveman's statusline — a visible signal that the per-turn hooks are live.
#
# Output (single line, coloured on the nish-tui palette):
#   "▪ <dir>  ✎ style:on  ▸ coding"   (category known)
#   "▪ <dir>  ✎ style:off"            (no category dispatched yet)
# jq is optional here: if absent, fall back to $PWD and skip the category badge
# (the session_id needed to find the category flag only arrives via the JSON).
set -euo pipefail

OFF_FLAG="$HOME/.claude/.nish-style-off"
INPUT="$(cat)"

# 24-bit foreground escapes. Tokens mirror nish_tui.PALETTE — keep in step.
ACCENT=$'\e[38;2;51;225;255m'   # #33e1ff
TEXT=$'\e[38;2;221;231;240m'    # #dde7f0
MUTED=$'\e[38;2;92;107;125m'    # #5c6b7d
INFO=$'\e[38;2;46;230;168m'     # #2ee6a8
ERROR=$'\e[38;2;255;77;109m'    # #ff4d6d
DIM=$'\e[2m'
RESET=$'\e[0m'
SEP="${MUTED}${DIM}  ·  ${RESET}"

DIR="$PWD"
SID=""
if command -v jq >/dev/null; then
  PARSED="$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null || true)"
  [[ -n "$PARSED" ]] && DIR="$PARSED"
  SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi

if [[ -f "$OFF_FLAG" ]]; then
  BADGE="${ERROR}✎ style:off${RESET}"
else
  BADGE="${INFO}✎ style:on${RESET}"
fi

printf '%s▪ %s%s%s%s%s' "$ACCENT" "$TEXT" "$(basename "$DIR")" "$RESET" "$SEP" "$BADGE"

# Category badge: written per-session by recognition-category-tracker.sh.
# Refuse symlinks and whitelist the contents — never echo arbitrary flag bytes
# (a local attacker could otherwise plant ANSI escapes in the flag file).
if [[ -n "$SID" ]]; then
  CAT_FLAG="$HOME/.claude/.nish-ai-category-$SID"
  if [[ -f "$CAT_FLAG" && ! -L "$CAT_FLAG" ]]; then
    CAT="$(head -c 16 "$CAT_FLAG" 2>/dev/null | tr -cd 'a-z')"
    case "$CAT" in
      planning|question|coding|docs|chore)
        printf '%s%s▸ %s%s' "$SEP" "$ACCENT" "$CAT" "$RESET" ;;
    esac
  fi
fi
