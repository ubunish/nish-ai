#!/usr/bin/env bash
# PreToolUse(Bash) validator for nish-ai-github commit format.
#
# Two-stage policy on a `git commit`:
#   1. Auto-rewrite  — mechanical violations (Co-Authored-By trailer, multi-line
#      body) are silently stripped to a subject-only commit and run as-is. This
#      preserves any `git add … && git commit …` chain, so staging is not lost,
#      and avoids the wasteful deny → retry loop.
#   2. Deny          — semantic violations the hook cannot safely fix (bad/missing
#      prefix, capitalized subject, trailing period) are still rejected, so a
#      malformed subject never gets auto-committed.
#
# Best-effort: the rewrite covers the forms Claude actually emits (heredoc
# `-m "$(cat <<EOF …)"`, repeated `-m` flags, multi-line `-m`). Forms it cannot
# parse confidently fall through to the raw trailer check, which denies. jq or
# perl absent → no-op.
set -euo pipefail

deny() { # $1 = reason
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

rewrite() { # $1 = rewritten command
  jq -n --arg c "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:{command:$c}}}'
  exit 0
}

INPUT="$(cat)"
command -v jq >/dev/null || exit 0

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"

# Only commits are our concern.
printf '%s' "$CMD" | grep -Eq '\bgit\b.*\bcommit\b' || exit 0

RULE='nish-ai-github format: "prefix: short phrase" — prefix one of init|feat|fix|docs|refactor|chore, lowercase imperative phrase, no capital, no trailing period, no body, no trailers, no Co-Authored-By (unless explicitly asked). Subject line only.'

# Reject a subject that the hook must not auto-commit. Shared by both stages.
validate_subject() { # $1 = subject line
  local subject="$1" phrase
  echo "$subject" | grep -Eq '^(init|feat|fix|docs|refactor|chore): .+' \
    || deny "Bad or missing prefix: \"$subject\". $RULE"
  phrase="${subject#*: }"
  [[ "$phrase" =~ ^[A-Z] ]] && deny "Subject phrase is capitalized: \"$subject\". $RULE"
  [[ "$phrase" == *. ]] && deny "Subject ends with a period: \"$subject\". $RULE"
  return 0
}

# --- Stage 1: auto-rewrite ---------------------------------------------------
# rewrite-commit.pl emits "<subject>\x1e<rewritten command>" only when it can
# confidently collapse a body/trailer to a subject-only commit; empty otherwise.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v perl >/dev/null && [[ -f "$SCRIPT_DIR/rewrite-commit.pl" ]]; then
  REWRITE="$(perl "$SCRIPT_DIR/rewrite-commit.pl" "$CMD")"

  if [[ -n "$REWRITE" ]]; then
    SUBJECT="${REWRITE%%$'\x1e'*}"
    NEWCMD="${REWRITE#*$'\x1e'}"
    validate_subject "$SUBJECT"   # malformed salvaged subject → deny instead of rewrite
    rewrite "$NEWCMD"
  fi
fi

# --- Stage 2: deny what cannot be safely rewritten ---------------------------
# Robust raw-text trailer check; survives any quoting (heredoc, subshell).
if printf '%s' "$CMD" | grep -qi 'co-authored-by'; then
  deny "Co-Authored-By trailer not allowed. $RULE"
fi

# Best-effort subject parse for simple -m "…"/'…' forms only.
# \x27 = single quote, so this perl program holds no literal quote to escape.
MSG="$(printf '%s' "$CMD" | perl -ne '
  if (/(?:-m|--message)\s+"([^"]*)"/) { print $1; exit }
  if (/(?:-m|--message)\s+\x27([^\x27]*)\x27/) { print $1; exit }
')"

[[ -z "$MSG" ]] && exit 0                          # no simple message → trust the trailer check
printf '%s' "$MSG" | grep -q '[$]' && exit 0       # shell expansion inside → skip parse

SUBJECT="$(printf '%s' "$MSG" | head -n1)"
BODY="$(printf '%s' "$MSG" | tail -n +2 | tr -d '[:space:]')"

[[ -n "$BODY" ]] && deny "Commit has a body; subject line only. $RULE"
validate_subject "$SUBJECT"

exit 0
