#!/usr/bin/env bash
# PreToolUse(Edit|Write) anchor for nish-ai-coding.
#
# Injects the build ladder + seven principles as additionalContext on the FIRST
# source-file edit of a session, before the write happens — the ladder governs
# what gets written, so a PostToolUse reminder would arrive too late. Later
# edits in the same session stay silent (a per-session marker gates the
# injection) so the reminder costs one block per session, not one per edit.
#
# Skips (stays silent) when:
#   - jq is absent — cannot parse the tool input.
#   - the bypass marker ~/.claude/.coding-off exists — set by "drop coding style".
#   - the target file is not source code (docs, config, data are exempt).
#   - the session already received the reminder.
set -euo pipefail

INPUT="$(cat)"
command -v jq >/dev/null || exit 0

# Bypass marker wins over everything: "drop coding style" turns the hook off.
[[ -f "$HOME/.claude/.coding-off" ]] && exit 0

FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')"
# The id becomes a path segment below, so keep it to characters a segment may
# safely hold — a "../" in the payload would otherwise escape the marker dir.
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null \
  | tr -cd 'A-Za-z0-9_-' || true)"
[[ -z "$FILE_PATH" || -z "$SESSION_ID" ]] && exit 0

# Source files only. Extension allowlist — prose, config, and data files do not
# need coding principles injected.
case "$FILE_PATH" in
  *.py|*.pyi|*.js|*.mjs|*.cjs|*.ts|*.tsx|*.jsx|*.go|*.rs|*.c|*.cc|*.cpp|*.h|*.hpp|\
  *.swift|*.rb|*.java|*.kt|*.cs|*.m|*.mm|*.sh|*.bash|*.zsh|*.sql|*.proto|*.msg|*.srv|*.action) ;;
  *) exit 0 ;;
esac

# Once per session. Marker name embeds the session id; stale markers from dead
# sessions are harmless and cleaned by the OS tmp reaper.
MARKER="${TMPDIR:-/tmp}/nish-ai-coding-anchor-${SESSION_ID}"
# Refuse a symlink: on a shared or attacker-controlled TMPDIR the write below
# would create or truncate whatever it points at.
[[ -L "$MARKER" ]] && exit 0
[[ -f "$MARKER" ]] && exit 0
: > "$MARKER"

CONTEXT='CODING PRINCIPLES ACTIVE (nish-ai-coding). This is the first source edit of the session — apply from here on. Build ladder, stop at first rung that solves it: 1 reuse existing code, 2 stdlib, 3 native platform, 4 installed dep, 5 smallest new dep, 6 minimum new code. Seven principles at every edit: modular (one responsibility), scalable (works at 10x), consistent (match project conventions), documented (module README + diagram), tested (code ships with tests), no premature abstraction (Rule of Three), self-explaining (names carry meaning, comments for WHY only; mark cheap choices with a typed tradeoff: comment). ROS2 code -> also load nish-ai-ros2. Full ruleset: invoke the nish-ai-coding skill. Off only on "drop coding style".'

jq -cn --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $ctx
  }
}'
