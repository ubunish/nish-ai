#!/usr/bin/env bash
# Inject the full nish-ai-writing-style ruleset at session start.
# Copies caveman's SessionStart inject: load whole rule body once, from message one.
# Skips when the "off" flag is present (set by "drop style" / "verbose mode").
set -euo pipefail

OFF_FLAG="$HOME/.claude/.nish-style-off"
SKILL="$HOME/.claude/skills/nish-ai-writing-style/SKILL.md"

[[ -f "$OFF_FLAG" ]] && exit 0
[[ -f "$SKILL" ]] || exit 0
command -v jq >/dev/null || exit 0

# Strip YAML frontmatter (first --- ... --- block), keep the rule body.
BODY="$(awk '/^---[[:space:]]*$/{fm++; next} fm>=2{print}' "$SKILL")"

CTX="WRITING STYLE ACTIVE (nish-ai-writing-style). Apply to all user-facing prose every response:
$BODY"

jq -n --arg ctx "$CTX" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
