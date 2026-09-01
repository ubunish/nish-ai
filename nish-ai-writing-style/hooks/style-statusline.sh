#!/usr/bin/env bash
# Statusline badge: show writing-style state, the session's router category, and
# the current 5-hour rate-limit usage.
# Mirrors caveman's statusline — a visible signal that the per-turn hooks are live.
#
# Output (single line, coloured on the nish-tui palette):
#   "▪ <dir>  ✎ style:on  ▸ coding            ▰▰▱▱▱ 42% · 1h12m"
#   "▪ <dir>  ✎ style:off"                    (no category, no usage payload)
# jq is optional here: if absent, fall back to $PWD and skip the category and
# usage badges (both need the JSON Claude Code passes on stdin).
set -euo pipefail

OFF_FLAG="$HOME/.claude/.nish-style-off"
INPUT="$(cat)"

# 24-bit foreground escapes. Tokens mirror nish_tui.PALETTE — keep in step.
ACCENT=$'\e[38;2;51;225;255m'   # #33e1ff
TEXT=$'\e[38;2;221;231;240m'    # #dde7f0
MUTED=$'\e[38;2;92;107;125m'    # #5c6b7d
INFO=$'\e[38;2;46;230;168m'     # #2ee6a8
WARN=$'\e[38;2;255;179;57m'     # #ffb339
ERROR=$'\e[38;2;255;77;109m'    # #ff4d6d
DIM=$'\e[2m'
RESET=$'\e[0m'
SEP="${MUTED}${DIM}  ·  ${RESET}"

DIR="$PWD"
SID=""
USAGE_JSON=""
if command -v jq >/dev/null; then
  # Every value below reaches a terminal or a file path, so strip control bytes
  # (an escape sequence in the payload would otherwise render as live ANSI) and
  # keep the session id to the characters a path segment may safely hold.
  PARSED="$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null \
    | tr -d '\000-\037' || true)"
  [[ -n "$PARSED" ]] && DIR="$PARSED" || true
  SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null \
    | tr -cd 'A-Za-z0-9_-' || true)"
  USAGE_JSON="$(printf '%s' "$INPUT" | jq -c '.rate_limits.five_hour // empty' 2>/dev/null || true)"
fi

if [[ -f "$OFF_FLAG" ]]; then
  BADGE="${ERROR}✎ style:off${RESET}"
else
  BADGE="${INFO}✎ style:on${RESET}"
fi

LINE="${ACCENT}▪ ${TEXT}$(basename "$DIR")${RESET}${SEP}${BADGE}"

# Category badge: written per-session by recognition-category-tracker.sh.
# Refuse symlinks and whitelist the contents — never echo arbitrary flag bytes
# (a local attacker could otherwise plant ANSI escapes in the flag file).
if [[ -n "$SID" ]]; then
  CAT_FLAG="$HOME/.claude/.nish-ai-category-$SID"
  if [[ -f "$CAT_FLAG" && ! -L "$CAT_FLAG" ]]; then
    CAT="$(head -c 16 "$CAT_FLAG" 2>/dev/null | tr -cd 'a-z')"
    case "$CAT" in
      planning|question|coding|docs|chore)
        LINE="${LINE}${SEP}${ACCENT}▸ ${CAT}${RESET}" ;;
    esac
  fi
fi

# --- usage badge ------------------------------------------------------------

# Seconds until $1 (epoch seconds or ISO-8601), or nothing when past/unparseable.
seconds_until() {
  local raw="$1" epoch="" plain
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    epoch="$raw"
  else
    # GNU date first, BSD date second — the script runs on both.
    epoch="$(date -d "$raw" +%s 2>/dev/null || true)"
    if [[ -z "$epoch" ]]; then
      # BSD date needs a bare "YYYY-MM-DDTHH:MM:SS"; -u reads it as UTC, which
      # is what the payload's ISO-8601 timestamps are.
      plain="${raw%%.*}"; plain="${plain%Z}"
      epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "$plain" +%s 2>/dev/null || true)"
    fi
  fi
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 0
  local left=$((epoch - $(date +%s)))
  if ((left > 0)); then printf '%s' "$left"; fi
}

# "1h12m" / "47m" / "<1m"
format_countdown() {
  local left="$1"
  local hours=$((left / 3600))
  local minutes=$(((left % 3600) / 60))
  if ((hours > 0)); then
    printf '%dh%02dm' "$hours" "$minutes"
  elif ((minutes > 0)); then
    printf '%dm' "$minutes"
  else
    printf '<1m'
  fi
}

USAGE=""
if [[ -n "$USAGE_JSON" ]]; then
  PCT="$(printf '%s' "$USAGE_JSON" | jq -r '.used_percentage // empty' 2>/dev/null || true)"
  # Coerce to integer before anything reaches the terminal — payload bytes are
  # never echoed raw.
  PCT="${PCT%%.*}"
  if [[ "$PCT" =~ ^[0-9]+$ ]]; then
    if ((PCT > 100)); then PCT=100; fi
    FILLED=$((PCT * 5 / 100))
    BAR=""
    for ((cell = 0; cell < 5; cell++)); do
      if ((cell < FILLED)); then BAR="${BAR}▰"; else BAR="${BAR}▱"; fi
    done
    if ((PCT >= 80)); then COLOUR="$ERROR"
    elif ((PCT >= 50)); then COLOUR="$WARN"
    else COLOUR="$INFO"; fi

    USAGE="${COLOUR}${BAR} ${PCT}%${RESET}"
    RESETS_AT="$(printf '%s' "$USAGE_JSON" | jq -r '.resets_at // empty' 2>/dev/null || true)"
    if [[ -n "$RESETS_AT" ]]; then
      LEFT="$(seconds_until "$RESETS_AT")"
      if [[ -n "$LEFT" ]]; then
        USAGE="${USAGE}${MUTED}${DIM} · $(format_countdown "$LEFT")${RESET}"
      fi
    fi
  fi
fi

# Right-align the usage badge by padding between it and the left group. Width
# comes from the controlling terminal; without one, the badge is appended after
# a separator rather than dropped.
visible_width() { # strips ANSI, counts characters
  local stripped
  stripped="$(printf '%s' "$1" | sed $'s/\e\\[[0-9;]*m//g')"
  printf '%s' "${#stripped}"
}

if [[ -n "$USAGE" ]]; then
  # Redirecting from /dev/tty fails loudly when there is no controlling
  # terminal, so the whole pipeline's stderr is muted, not just stty's.
  COLS="$({ stty size </dev/tty | cut -d' ' -f2; } 2>/dev/null || true)"
  [[ "$COLS" =~ ^[0-9]+$ ]] || COLS="$(tput cols 2>/dev/null || true)"
  GAP=-1
  if [[ "$COLS" =~ ^[0-9]+$ ]]; then
    GAP=$((COLS - $(visible_width "$LINE") - $(visible_width "$USAGE")))
  fi
  if ((GAP >= 1)); then
    LINE="${LINE}$(printf '%*s' "$GAP" '')${USAGE}"
  else
    LINE="${LINE}${SEP}${USAGE}"
  fi
fi

printf '%s' "$LINE"
