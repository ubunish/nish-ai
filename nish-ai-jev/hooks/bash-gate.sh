#!/usr/bin/env bash
# PreToolUse(Bash): ask before a command that is hard to reverse or reaches
# outside this machine.
#
# The permission allowlist in install.sh is a fixed set of prefixes, so it can
# only ever say yes to commands someone thought of in advance. This hook covers
# the rest: a regex prefilter passes the obviously read-only commands for free,
# and everything else gets one Jev judgment. A probability at or above the
# threshold returns "ask", which surfaces the normal permission prompt.
#
# Silence is a pass. Every failure path — no jev, no key, an off-allowlist repo,
# a timeout — prints nothing, and the command is handled exactly as it was
# before this hook existed.
#
# What this hook assumes, and does not defend: the prefilter reads the verb a
# command is written with, not the binary the shell will resolve it to. An
# alias, a shell function, or a PATH with a writable directory ahead of /bin
# can make a read-only verb run something else entirely. That is not a hole
# this gate can close — the permission allowlist matches the same verb prefixes
# and has the same limit, and anyone who can set an alias can already run the
# command directly. The gate adds a prompt where there was none; it never
# removes one, so a verb it waves through is left exactly as the existing
# permission rules had it.
set -euo pipefail

JEV="$HOME/.claude/skills/nish-ai-jev/jev"
QUESTIONS="$HOME/.claude/skills/nish-ai-jev/hooks/bash-gate.json"
# A prompt costs a keystroke; a lost working tree costs an afternoon. Half is
# the point where asking is worth more than not asking.
RISK_THRESHOLD=0.5
TIMEOUT=1.5

command -v jq >/dev/null || exit 0
[[ -x "$JEV" && -r "$QUESTIONS" ]] || exit 0

INPUT="$(cat)"
COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$COMMAND" ]] || exit 0
# The payload names the directory; anything that is not one is ignored rather
# than handed to git, so the branch in the judgment state is always real.
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
[[ -d "$CWD" ]] || CWD="$PWD"

# Commands that only ever read, whatever flags they are given. A segment
# starting with one of these, with no redirection anywhere, needs no judgment —
# which keeps the common case free.
#
# find, sed and awk are deliberately absent. Each has a flag that turns a
# reading command into a writing one — `find -exec` and `-delete`, `sed -i` and
# its `e` modifier, awk's `system()` — and a verb-only prefilter cannot see the
# difference. They go to Jev, which reads the whole command.
READ_ONLY='^(ls|cat|pwd|cd|which|type|head|tail|wc|file|tree|stat|du|df|date|uname|whoami|echo|printf|grep|rg|jq|sort|uniq|cut|diff|basename|dirname|env|man|column)$'
GIT_READ_ONLY='^(status|diff|log|show|branch|remote|rev-parse|describe|blame|shortlog)$'

# Every character a command may contain and still be judged by its verbs alone.
# Naming what is allowed, rather than what is not, is the point: each round of
# review found another metacharacter that hid a second command behind a
# read-only verb — `>` then `<(` then a bare `&`. Anything outside this set —
# redirection, substitution, chaining, expansion, grouping, escapes — goes to
# Jev, which reads the whole line. The pipe is the one exception, split below.
UNSAFE_CHAR='[^A-Za-z0-9 _.,:=@+/*?~%|"'"'"'-]'

is_read_only() { # $1 = the whole command line
  # `&&` chains two commands the same way a pipe does, and both are split and
  # judged below — so it is normalized to a pipe before the character check,
  # which leaves a bare `&` (backgrounding, and a second command after it)
  # outside the allowed set where it belongs.
  local line="${1//&&/|}"
  if printf '%s' "$line" | LC_ALL=C grep -q "$UNSAFE_CHAR"; then
    return 1
  fi

  local segment verb
  # Only pipes survive the character check, so splitting on them covers every
  # chain that can reach here. `||` yields an empty piece, skipped below.
  while IFS= read -r segment; do
    segment="${segment#"${segment%%[![:space:]]*}"}"   # strip leading blanks
    [[ -n "$segment" ]] || continue
    read -r verb _ <<<"$segment"
    if [[ "$verb" == "git" ]]; then
      local subcommand
      read -r _ subcommand _ <<<"$segment"
      if [[ ! "$subcommand" =~ $GIT_READ_ONLY ]]; then return 1; fi
    elif [[ ! "$verb" =~ $READ_ONLY ]]; then
      return 1
    fi
  done < <(printf '%s\n' "$line" | tr '|' '\n')
  return 0
}

if is_read_only "$COMMAND"; then exit 0; fi

BRANCH="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
STATE="$(jq -nc --arg c "$COMMAND" --arg d "$CWD" --arg b "$BRANCH" \
  '{command: $c, cwd: $d, branch: $b}' 2>/dev/null)" || exit 0

ANSWERS="$(printf '%s' "$STATE" | "$JEV" --timeout "$TIMEOUT" "$QUESTIONS" 2>/dev/null)" || exit 0
RISK="$(printf '%s' "$ANSWERS" | jq -r '.risky.noul // 0' 2>/dev/null || echo 0)"
OVER="$(printf '%s' "$ANSWERS" | jq -r --argjson t "$RISK_THRESHOLD" '(.risky.noul // 0) >= $t' 2>/dev/null || echo false)"
[[ "$OVER" == "true" ]] || exit 0

jq -n --arg reason "Jev read this command as hard to reverse or outward-facing (p=$RISK). Confirm before it runs." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$reason}}'
