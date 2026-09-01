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

# Read the hook payload (JSON) and match toggles against .prompt alone. The
# payload also carries cwd and transcript_path, so matching it raw let a phrase
# anywhere in the JSON flip the style off. Without jq the raw payload is still
# the only thing to match — over-broad, but better than losing the toggle.
INPUT="$(cat)"
PROMPT="$INPUT"
if command -v jq >/dev/null; then
  PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || printf '%s' "$INPUT")"
fi

# Refuse a symlink at the flag path: the toggles below truncate and delete it,
# either of which would reach whatever a planted link points at.
[[ -L "$OFF_FLAG" ]] && exit 0

shopt -s nocasematch
if [[ "$PROMPT" =~ (drop[[:space:]]+style|verbose[[:space:]]+mode) ]]; then
  : > "$OFF_FLAG"            # disable: create off flag, no reminder this turn
  exit 0
elif [[ "$PROMPT" =~ (resume[[:space:]]+style|style[[:space:]]+on|enable[[:space:]]+style) ]]; then
  rm -f "$OFF_FLAG"         # re-enable
fi

[[ -f "$OFF_FLAG" ]] && exit 0

cat "$HOOK_DIR/terminal-reminder.txt"
