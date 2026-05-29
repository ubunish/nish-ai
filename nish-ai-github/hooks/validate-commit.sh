#!/usr/bin/env bash
# PreToolUse(Bash) validator: enforce nish-ai-github commit format.
# Denies a `git commit` whose message carries a Co-Authored-By trailer, a body,
# a bad/missing prefix, a capitalized subject, or a trailing period.
# Best-effort: complex message forms (heredoc / $(...) / -F) get the robust
# raw-text trailer check only, never a subject-parse block. jq absent → no-op.
set -euo pipefail

deny() { # $1 = reason
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

INPUT="$(cat)"
command -v jq >/dev/null || exit 0

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"

# Only commits are our concern.
printf '%s' "$CMD" | grep -Eq '\bgit\b.*\bcommit\b' || exit 0

RULE='nish-ai-github format: "prefix: short phrase" — prefix one of init|feat|fix|docs|refactor|chore, lowercase imperative phrase, no capital, no trailing period, no body, no trailers, no Co-Authored-By (unless explicitly asked). Subject line only.'

# Tier 1 — robust raw-text check, survives any quoting (heredoc, subshell).
if printf '%s' "$CMD" | grep -qi 'co-authored-by'; then
  deny "Co-Authored-By trailer not allowed. $RULE"
fi

# Tier 2 — best-effort subject parse for simple -m "..."/'...' forms only.
# \x27 = single quote, so this perl program holds no literal quote to escape.
MSG="$(printf '%s' "$CMD" | perl -ne '
  if (/(?:-m|--message)\s+"([^"]*)"/) { print $1; exit }
  if (/(?:-m|--message)\s+\x27([^\x27]*)\x27/) { print $1; exit }
')"

[[ -z "$MSG" ]] && exit 0                          # no simple message → trust Tier 1
printf '%s' "$MSG" | grep -q '[$]' && exit 0       # shell expansion inside → skip parse

SUBJECT="$(printf '%s' "$MSG" | head -n1)"
BODY="$(printf '%s' "$MSG" | tail -n +2 | tr -d '[:space:]')"

[[ -n "$BODY" ]] && deny "Commit has a body; subject line only. $RULE"

echo "$SUBJECT" | grep -Eq '^(init|feat|fix|docs|refactor|chore): .+' \
  || deny "Bad or missing prefix: \"$SUBJECT\". $RULE"

PHRASE="${SUBJECT#*: }"
[[ "$PHRASE" =~ ^[A-Z] ]] && deny "Subject phrase is capitalized: \"$SUBJECT\". $RULE"
[[ "$PHRASE" == *. ]] && deny "Subject ends with a period: \"$SUBJECT\". $RULE"

exit 0
