#!/usr/bin/env bash
# Move a second session on one checkout into its own worktree. When a live
# peer that started earlier already sits in this checkout, inject an
# instruction to EnterWorktree before the first edit; two sessions writing one
# working tree would otherwise trample each other's uncommitted changes.
#
# Only the newer session moves, so two sessions starting together do not both
# leave. A solo session gets nothing — no output, no tokens.
set -euo pipefail

CLI="$HOME/.claude/skills/nish-ai-sessions/bin/nish-session"
REGISTRY="$HOME/.claude/sessions"

command -v jq >/dev/null || exit 0
[[ -x "$CLI" ]] || exit 0

INPUT="$(cat)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
[[ -n "$SID" && -n "$CWD" ]] || exit 0

TOPLEVEL="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || exit 0

# A session missing from the registry has only just started, so it is the
# newest one present. A resumed session can leave an older file behind, so the
# latest start wins; files are read one at a time so a malformed one is skipped.
STARTED="$(for file in "$REGISTRY"/*.json; do
  jq -r --arg s "$SID" 'select(.sessionId == $s) | .startedAt' "$file" 2>/dev/null || true
done | sort -n | tail -n1)"
[[ "$STARTED" =~ ^[0-9]+$ ]] || STARTED="$(( $(date +%s) * 1000 ))"

HOLDERS="$("$CLI" peers --cwd "$CWD" --self "$SID" 2>/dev/null | jq -rs \
  --arg t "$TOPLEVEL" --argjson started "$STARTED" \
  'map(select(.toplevel == $t and (.started_at // 0) < $started)) | length' 2>/dev/null)" || exit 0
[[ "$HOLDERS" =~ ^[0-9]+$ && "$HOLDERS" -gt 0 ]] || exit 0

# The text is fixed: peer names and paths can come from directory names or a
# first prompt, and nothing peer-derived is placed in this instruction.
CTX="SESSION COLLISION (nish-ai-sessions). $HOLDERS other live Claude session(s) already work in this checkout. The user's standing instruction for this case: before the first file edit, call EnterWorktree with a short lowercase-hyphenated name drawn from this session's goal, and do all work there. Reading files and answering questions need no worktree."

jq -n --arg ctx "$CTX" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
