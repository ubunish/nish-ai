#!/usr/bin/env bash
# Re-anchor the writing style right after a nish-ai-* skill is dispatched.
#
# Why this exists: the UserPromptSubmit reminder fires once per user prompt. A
# single prompt can spawn a skill dispatch plus a long tail of model steps
# (narrate, explore, call tools) with no further style injection. By the tail,
# the freshest injected text is the dispatched SKILL.md body, whose register
# (task voice) displaces TERMINAL style — the model drifts back to full prose.
#
# Firing on PostToolUse for the Skill tool puts the reminder back at the front
# of attention at the exact moment dispatch happens, closing that gap.
#
# Reminder text is shared with style-prompt-submit.sh via terminal-reminder.txt
# — single source, so the two injection points never diverge.
#
# PostToolUse stdout is NOT added to context (unlike UserPromptSubmit), so the
# reminder must be returned as hookSpecificOutput.additionalContext via jq.
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFF_FLAG="$HOME/.claude/.nish-style-off"
REMINDER_FILE="$HOOK_DIR/terminal-reminder.txt"

# Honour the global off switch and missing-dependency cases silently.
[[ -f "$OFF_FLAG" ]] && exit 0
[[ -f "$REMINDER_FILE" ]] || exit 0
command -v jq >/dev/null || exit 0

INPUT="$(cat)"

# Only re-anchor after a nish-ai-* skill — those are the dispatch targets that
# shift register. Other skills (cloudflare, deep-research, …) do not claim to
# own user-facing prose, so leave them alone.
SKILL="$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)"
case "$SKILL" in
  nish-ai-*) ;;
  *) exit 0 ;;
esac

LEAD="STYLE RE-ANCHOR (post-dispatch). Continue this turn in TERMINAL mode — the dispatched skill sets task behavior, NOT writing style. Writing style still governs every user-facing line, including tool-preamble narration."
BODY="$(cat "$REMINDER_FILE")"

jq -n --arg ctx "$LEAD"$'\n'"$BODY" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
