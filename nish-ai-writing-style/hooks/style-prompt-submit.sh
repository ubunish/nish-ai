#!/usr/bin/env bash
# Re-inject a one-line writing-style reminder on every user prompt.
# Copies caveman's UserPromptSubmit tracker: short per-turn reminder = no drift,
# plus phrase-based toggle. "off" flag at ~/.claude/.nish-style-off (default on).
#
# No jq: UserPromptSubmit stdout IS added to context, so plain stdout works.
# Removes the old silent-no-op path that fired when jq was missing.
#
# Reminder text lives in terminal-reminder.txt — the single source shared with
# style-post-skill.sh, so the rules never drift between the two injection points.
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFF_FLAG="$HOME/.claude/.nish-style-off"

# Read the hook payload (JSON). Toggle phrases are literal text, so they are
# matched against the raw payload directly — no jq needed to extract .prompt.
INPUT="$(cat)"

# Refuse a symlink at the flag path: the toggles below truncate and delete it,
# either of which would reach whatever a planted link points at.
[[ -L "$OFF_FLAG" ]] && exit 0

shopt -s nocasematch
if [[ "$INPUT" =~ (drop[[:space:]]+style|verbose[[:space:]]+mode) ]]; then
  : > "$OFF_FLAG"            # disable: create off flag, no reminder this turn
  exit 0
elif [[ "$INPUT" =~ (resume[[:space:]]+style|style[[:space:]]+on|enable[[:space:]]+style) ]]; then
  rm -f "$OFF_FLAG"         # re-enable
fi

[[ -f "$OFF_FLAG" ]] && exit 0

cat "$HOOK_DIR/terminal-reminder.txt"
