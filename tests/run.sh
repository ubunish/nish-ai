#!/usr/bin/env bash
# Portable test runner for the nish-ai-github commit hooks. No bats dependency —
# plain bash assertions, so it runs anywhere the hooks themselves run.
#
# Covers two scripts:
#   validate-commit.sh — PreToolUse(Bash) gate: pass | rewrite | deny.
#   rewrite-commit.pl  — collapses a body/trailer commit to subject-only.
#
# Run: ./tests/run.sh   (exits non-zero if any assertion fails)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$REPO_DIR/nish-ai-github/hooks/validate-commit.sh"
REWRITER="$REPO_DIR/nish-ai-github/hooks/rewrite-commit.pl"

command -v jq   >/dev/null || { echo "jq required for tests"   >&2; exit 1; }
command -v perl >/dev/null || { echo "perl required for tests" >&2; exit 1; }

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }

# --- validate-commit.sh helpers ---------------------------------------------
# Feed a command as PreToolUse JSON, capture the hook's stdout.
validate() { # $1 = git command
  jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$VALIDATOR"
}
decision() { # $1 = hook output -> "deny" | "rewrite" | "pass"
  local out="$1"
  [[ -z "$out" ]] && { echo pass; return; }
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    && { echo deny; return; }
  printf '%s' "$out" | jq -e '.hookSpecificOutput.updatedInput.command' >/dev/null 2>&1 \
    && { echo rewrite; return; }
  echo unknown
}
assert_decision() { # $1 = label  $2 = expected  $3 = command
  local got; got="$(decision "$(validate "$3")")"
  [[ "$got" == "$2" ]] && ok "$1" || bad "$1" "expected $2, got $got"
}
assert_rewrite_cmd() { # $1 = label  $2 = expected command  $3 = input command
  local cmd; cmd="$(validate "$3" | jq -r '.hookSpecificOutput.updatedInput.command // ""')"
  [[ "$cmd" == "$2" ]] && ok "$1" || bad "$1" "expected [$2], got [$cmd]"
}

# --- rewrite-commit.pl helpers ----------------------------------------------
# Prints "<subject>\x1e<command>" on a confident rewrite, nothing otherwise.
rewrite_cmd() { # $1 = command -> rewritten command, or "" on bail
  local out; out="$(perl "$REWRITER" "$1")"
  [[ -z "$out" ]] && { printf ''; return; }
  printf '%s' "${out#*$'\x1e'}"
}
assert_collapse() { # $1 = label  $2 = expected command  $3 = input command
  local got; got="$(rewrite_cmd "$3")"
  [[ "$got" == "$2" ]] && ok "$1" || bad "$1" "expected [$2], got [$got]"
}
assert_bail() { # $1 = label  $2 = input command
  local got; got="$(rewrite_cmd "$2")"
  [[ -z "$got" ]] && ok "$1" || bad "$1" "expected no rewrite, got [$got]"
}

echo "validate-commit.sh"
assert_decision "good subject passes"        pass    'git commit -m "feat: add widget"'
assert_decision "bad prefix denied"          deny    'git commit -m "wip: poke at things"'
assert_decision "capitalized subject denied" deny    'git commit -m "feat: Add widget"'
assert_decision "trailing period denied"     deny    'git commit -m "fix: patch the bug."'
# Co-Authored-By the rewriter can parse is collapsed, not denied (see rewriter tests).
# A -F heredoc carries no -m flag, so the rewriter bails and the raw trailer check denies.
assert_decision "co-authored-by (no -m) denied" deny \
  $'git commit -F - <<\'EOF\'\nfeat: add widget\n\nCo-Authored-By: A <a@b.c>\nEOF'
# A body in a parseable -m form is rewritten to subject-only, not denied — the
# validator's primary defence against bodies is the rewrite, not a deny.
assert_rewrite_cmd "body via -m rewritten to subject-only" \
  'git commit -m "feat: add widget"' \
  'git commit -m "feat: add widget" -m "extra body line"'

echo "rewrite-commit.pl"
assert_collapse "heredoc body collapses to subject-only" \
  'git commit -m "feat: add widget"' \
  $'git commit -m "$(cat <<\'EOF\'\nfeat: add widget\n\nlong body paragraph\nEOF\n)"'
assert_collapse "repeated -m collapses" \
  'git commit -m "feat: add widget"' \
  'git commit -m "feat: add widget" -m "body paragraph"'
assert_collapse "git add prefix preserved" \
  'git add -A && git commit -m "feat: add widget"' \
  'git add -A && git commit -m "feat: add widget" -m "body"'
assert_collapse "chained && git log tail preserved" \
  'git commit -m "feat: add widget" && git log -1' \
  'git commit -m "feat: add widget" -m "body" && git log -1'
assert_bail "second git commit in tail bails" \
  'git commit -m "feat: add widget" -m "body" && git commit -m "feat: more"'
assert_bail "plain subject-only emits nothing" \
  'git commit -m "feat: add widget"'

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
