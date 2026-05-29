#!/usr/bin/env bash
# Re-anchor writing style mid-turn, after tool calls that would otherwise bury
# it by recency. A single user prompt can spawn a skill dispatch plus a long
# tail of model steps (narrate, explore, edit) with no fresh style injection;
# by the tail the freshest context is the last tool result, whose register
# displaces TERMINAL style and the model drifts back to full prose.
#
# Two gaps this closes (kept the file name from the original Skill-only version
# to avoid churning the installed hook path):
#
#   1. Dispatch — after a nish-ai-* Skill loads, the skill body sets task voice.
#      Each category SKILL.md now ends with a style anchor too; this hook adds a
#      second nudge right after dispatch.
#   2. Tail — after each Bash/Read/Edit/… result, the model's next narration
#      line is what drifts. Re-inject a short reminder so style stays freshest.
#
# PostToolUse stdout is NOT added to context, so the reminder must be returned
# as hookSpecificOutput.additionalContext via jq.
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFF_FLAG="$HOME/.claude/.nish-style-off"
REMINDER_FILE="$HOOK_DIR/terminal-reminder.txt"

# Honour the global off switch and missing-dependency cases silently.
[[ -f "$OFF_FLAG" ]] && exit 0
command -v jq >/dev/null || exit 0

INPUT="$(cat)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"

case "$TOOL" in
  Skill)
    # Re-anchor only after a nish-ai-* skill — those dispatch targets shift
    # register. Other skills (cloudflare, deep-research, …) do not own prose.
    SKILL="$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)"
    case "$SKILL" in
      nish-ai-*) ;;
      *) exit 0 ;;
    esac
    [[ -f "$REMINDER_FILE" ]] || exit 0
    LEAD="STYLE RE-ANCHOR (post-dispatch). Continue this turn in TERMINAL mode — the dispatched skill sets task behavior, NOT writing style. Writing style still governs every user-facing line, including tool-preamble narration."
    CTX="$LEAD"$'\n'"$(cat "$REMINDER_FILE")"
    ;;
  *)
    # Tail tools (Bash, Read, Edit, Write, Grep, Glob — set by the install
    # matcher). Short one-line reminder keeps per-step token cost low.
    CTX="STYLE RE-ANCHOR (mid-turn). Your next user-facing line — including one-line tool preambles like \"reading X…\" — is TERMINAL mode: no a/an/the, fragments not sentences, drop and/but/so, self-check before sending."
    ;;
esac

jq -n --arg ctx "$CTX" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
