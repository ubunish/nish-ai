#!/usr/bin/env bash
# Persist the session's category for the statusline badge.
# Fires PostToolUse on the Skill tool. When the dispatched skill is one of the
# five router categories, map it to a short label and write it to a per-session
# flag file. The statusline reads this flag to show the active category.
#
# Category is a model decision made at dispatch — no hook can know it before the
# Skill call lands. Reading the dispatched skill name here is the deterministic
# point where the category becomes observable, so the flag never depends on the
# model remembering to record it. A re-categorization dispatches a new category
# skill, which overwrites the flag — the badge always reflects the latest.
#
# Non-category skills (/merge, /code-review, utility skills) are ignored, so the
# badge is not clobbered by unrelated Skill calls.
set -euo pipefail

command -v jq >/dev/null || exit 0

INPUT="$(cat)"
# The id becomes a path segment below, so keep it to characters a segment may
# safely hold — a "../" in the payload would otherwise escape ~/.claude.
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-' || true)"
if [[ -z "$SID" ]]; then SID=default; fi
SKILL="$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)"

case "$SKILL" in
  nish-ai-project-planning)     LABEL=planning ;;
  nish-ai-user-question)        LABEL=question ;;
  nish-ai-goal-oriented-coding) LABEL=coding ;;
  nish-ai-documentation)        LABEL=docs ;;
  nish-ai-quick-task)           LABEL=chore ;;
  *) exit 0 ;;  # not a category skill — leave the flag untouched
esac

FLAG="$HOME/.claude/.nish-ai-category-$SID"

# Refuse symlinks: a local attacker could point the flag at a sensitive file and
# have a future write clobber it, or have the statusline render its bytes.
[[ -L "$FLAG" ]] && exit 0

# Atomic write via temp + rename, created 0600. Silent-fail on any fs error —
# a tracker failure must never surface to the user mid-session.
TMP="$(mktemp "$HOME/.claude/.nish-ai-category-$SID.XXXXXX")" 2>/dev/null || exit 0
printf '%s' "$LABEL" > "$TMP" 2>/dev/null || { rm -f "$TMP"; exit 0; }
chmod 0600 "$TMP" 2>/dev/null || true
mv -f "$TMP" "$FLAG" 2>/dev/null || rm -f "$TMP"
exit 0
