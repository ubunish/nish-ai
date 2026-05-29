#!/usr/bin/env bash
# Re-inject a one-line writing-style reminder on every user prompt.
# Copies caveman's UserPromptSubmit tracker: short per-turn reminder = no drift,
# plus phrase-based toggle. "off" flag at ~/.claude/.nish-style-off (default on).
set -euo pipefail

OFF_FLAG="$HOME/.claude/.nish-style-off"

INPUT="$(cat)"
if command -v jq >/dev/null; then
  PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || printf '%s' "$INPUT")"
else
  PROMPT="$INPUT"
fi

shopt -s nocasematch
if [[ "$PROMPT" =~ (drop[[:space:]]+style|verbose[[:space:]]+mode) ]]; then
  : > "$OFF_FLAG"            # disable: create off flag, no reminder this turn
  exit 0
elif [[ "$PROMPT" =~ (resume[[:space:]]+style|style[[:space:]]+on|enable[[:space:]]+style) ]]; then
  rm -f "$OFF_FLAG"         # re-enable
fi

[[ -f "$OFF_FLAG" ]] && exit 0
command -v jq >/dev/null || exit 0

CTX="WRITING STYLE ACTIVE (nish-ai-writing-style): state idea once; drop articles/filler/hedging; fragments OK; simple word > complex; diagram > text; Title Case headings, sentence case body. Exempt: security/destructive warnings, code blocks, or when user asks for detail."

jq -n --arg ctx "$CTX" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
