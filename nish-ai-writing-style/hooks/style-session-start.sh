#!/usr/bin/env bash
# Inject the full nish-ai-writing-style ruleset at session start.
# Copies caveman's SessionStart inject: load whole rule body once, from message one.
# Skips when the "off" flag is present (set by "drop style" / "verbose mode").
#
# No jq: SessionStart stdout IS added to context, so plain stdout works.
# Removes the old silent-no-op path that fired when jq was missing.
set -euo pipefail

OFF_FLAG="$HOME/.claude/.nish-style-off"
SKILL="$HOME/.claude/skills/nish-ai-writing-style/SKILL.md"

[[ -f "$OFF_FLAG" ]] && exit 0
[[ -f "$SKILL" ]] || exit 0

# Strip YAML frontmatter (first --- ... --- block), keep the rule body.
BODY="$(awk '/^---[[:space:]]*$/{fm++; next} fm>=2{print}' "$SKILL")"

printf 'WRITING STYLE ACTIVE (nish-ai-writing-style). Apply to all user-facing prose every response:\n%s\n' "$BODY"
