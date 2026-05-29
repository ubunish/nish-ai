#!/usr/bin/env bash
# Hard-dispatch the session router on the first user prompt of each session.
# recognition-session-start.sh arms a per-session flag; this consumes it once,
# injecting a forceful categorize+dispatch directive at the moment the first
# prompt lands — freshest position, so it is not buried by other injected
# context. Subsequent prompts are silent (router fires once per session).
#
# "re-categorize" in a prompt re-arms the flag on demand.
set -euo pipefail

FLAG_DIR="$HOME/.claude"
command -v jq >/dev/null || exit 0

INPUT="$(cat)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null || echo default)"
PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || echo "")"
FLAG="$FLAG_DIR/.nish-recognition-pending-$SID"

# Explicit re-categorization on demand.
shopt -s nocasematch
if [[ "$PROMPT" =~ re-?categori[sz]e ]]; then
  : > "$FLAG"
fi

[[ -f "$FLAG" ]] || exit 0   # not the first prompt (or already dispatched) -> silent
rm -f "$FLAG"                # consume: fire exactly once

CTX="SESSION ROUTER — DISPATCH NOW (nish-ai-prompt-recognition). This is the first substantive prompt of the session. Before any other output, explanation, or tool call: categorize it as one of A (Project Planning, no commit) / B (User Question, no commit) / C (Goal-Oriented Coding: feat|fix|refactor) / D (Documentation: docs) / E (Quick Task: chore). Pick the narrowest fit. Announce one line — 'Session category: <name> → invoking <skill>' — then invoke that skill, which owns the rest of the session. If two categories tie, ask before dispatching."

jq -n --arg ctx "$CTX" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
