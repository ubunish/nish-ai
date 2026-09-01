#!/usr/bin/env bash
# Inject the full nish-ai-prompt-recognition ruleset at session start, and arm
# the once-per-session dispatch flag consumed by recognition-prompt-submit.sh.
# Mirrors nish-ai-writing-style's caveman SessionStart inject: load the whole
# rule body once, from message one, so dispatch never depends on the model
# choosing to read a soft pointer.
#
# The flag is armed only for a genuinely new session (source startup|clear).
# On resume/compact the ruleset is re-injected to restore lost context, but the
# flag is NOT re-armed — the router fires once per session, not once per window.
set -euo pipefail

SKILL="$HOME/.claude/skills/nish-ai-prompt-recognition/SKILL.md"
FLAG_DIR="$HOME/.claude"

[[ -f "$SKILL" ]] || exit 0
command -v jq >/dev/null || exit 0

INPUT="$(cat)"
# The id becomes a path segment below, so keep it to characters a segment may
# safely hold — a "../" in the payload would otherwise escape the flag dir.
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-' || true)"
if [[ -z "$SID" ]]; then SID=default; fi
SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // "startup"' 2>/dev/null || echo startup)"

# Reap stale per-session flags before arming a new one. These accumulate in
# ~/.claude/ as sessions come and go with no other cleanup. Match only the two
# known prefixes, never unrelated files; best-effort, silent on failure.
find "$FLAG_DIR" -maxdepth 1 -type f \
  \( -name '.nish-recognition-pending-*' -o -name '.nish-ai-category-*' \) \
  -mtime +7 -delete 2>/dev/null || true

# Arm the pending flag only for a new logical session. Refuse a symlink at the
# flag path: a local attacker could point it at a sensitive file and have this
# truncating write clobber it.
PENDING="$FLAG_DIR/.nish-recognition-pending-$SID"
case "$SOURCE" in
  startup|clear) [[ -L "$PENDING" ]] || : > "$PENDING" ;;
esac

# Strip YAML frontmatter (first --- ... --- block), keep the rule body.
BODY="$(awk '/^---[[:space:]]*$/{fm++; next} fm>=2{print}' "$SKILL")"

CTX="SESSION ROUTER ACTIVE (nish-ai-prompt-recognition). On the first substantive user prompt, your FIRST action — before any other output, explanation, or tool call — MUST be to categorize the prompt and dispatch per the rules below: announce the category, then invoke the matching skill. Fires once per session.
$BODY"

jq -n --arg ctx "$CTX" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
