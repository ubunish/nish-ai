#!/usr/bin/env bash
# Portable test suite for the hooks that write flag files under a path built
# from the payload. No bats dependency — plain bash assertions.
#
# Two guarantees per hook: a session_id carrying "../" must not escape the
# directory the hook owns while still producing the marker the hook depends on,
# and a symlink planted at a flag path must be left alone rather than followed.
#
# Run: ./tests/session-id.sh   (exits non-zero if any assertion fails)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODING_HOOK="$REPO_DIR/nish-ai-categories/nish-ai-coding/hooks/coding-pretooluse.sh"
START_HOOK="$REPO_DIR/nish-ai-prompt-recognition/hooks/recognition-session-start.sh"
SUBMIT_HOOK="$REPO_DIR/nish-ai-prompt-recognition/hooks/recognition-prompt-submit.sh"
TRACKER_HOOK="$REPO_DIR/nish-ai-prompt-recognition/hooks/recognition-category-tracker.sh"
STYLE_HOOK="$REPO_DIR/nish-ai-writing-style/hooks/style-prompt-submit.sh"

command -v jq >/dev/null || { echo "jq required for tests" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }

assert_file()    { [[ -e "$2" ]] && ok "$1" || bad "$1" "missing $2"; }
assert_no_file() { [[ ! -e "$2" ]] && ok "$1" || bad "$1" "unexpected $2"; }

# A throwaway HOME and TMPDIR keep real markers and flags out of the run. The
# escape target sits one level above each hook's own directory.
new_sandbox() {
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX/home"
  export TMPDIR="$SANDBOX/tmp/"
  mkdir -p "$HOME/.claude/skills/nish-ai-prompt-recognition" "$SANDBOX/tmp"
  # The SessionStart hook bails unless the skill body it injects exists.
  printf -- '---\nname: x\n---\nbody\n' \
    > "$HOME/.claude/skills/nish-ai-prompt-recognition/SKILL.md"
}
drop_sandbox() { rm -rf "$SANDBOX"; }

# "../evil" survives sanitization as "evil" — the traversal is stripped, the
# hook still writes a marker, and nothing lands in the parent directory.
TRAVERSAL='../evil'

echo "coding-pretooluse.sh"
new_sandbox
jq -nc --arg s "$TRAVERSAL" '{session_id:$s,tool_input:{file_path:"/tmp/x.py"}}' \
  | bash "$CODING_HOOK" >/dev/null 2>&1
assert_file    "marker written inside TMPDIR" "$SANDBOX/tmp/nish-ai-coding-anchor-evil"
assert_no_file "no marker above TMPDIR"       "$SANDBOX/nish-ai-coding-anchor-evil"
drop_sandbox

echo "recognition-session-start.sh"
new_sandbox
jq -nc --arg s "$TRAVERSAL" '{session_id:$s,source:"startup"}' \
  | bash "$START_HOOK" >/dev/null 2>&1
assert_file    "flag armed inside .claude" "$HOME/.claude/.nish-recognition-pending-evil"
assert_no_file "no flag above .claude"     "$HOME/.nish-recognition-pending-evil"
drop_sandbox

echo "recognition-prompt-submit.sh"
new_sandbox
# The submit hook consumes the flag the start hook armed; both must agree on the
# sanitized name or the router would fire on every prompt.
: > "$HOME/.claude/.nish-recognition-pending-evil"
OUT="$(jq -nc --arg s "$TRAVERSAL" '{session_id:$s,prompt:"build a thing"}' \
  | bash "$SUBMIT_HOOK" 2>/dev/null)"
[[ "$OUT" == *"SESSION ROUTER"* ]] && ok "sanitized id finds the armed flag" \
  || bad "sanitized id finds the armed flag" "got [$OUT]"
assert_no_file "flag consumed" "$HOME/.claude/.nish-recognition-pending-evil"
drop_sandbox

echo "recognition-category-tracker.sh"
new_sandbox
jq -nc --arg s "$TRAVERSAL" \
  '{session_id:$s,tool_input:{skill:"nish-ai-goal-oriented-coding"}}' \
  | bash "$TRACKER_HOOK" >/dev/null 2>&1
assert_file    "category flag inside .claude" "$HOME/.claude/.nish-ai-category-evil"
assert_no_file "no category flag above .claude" "$HOME/.nish-ai-category-evil"
drop_sandbox

echo "empty id falls back"
# An id of only stripped characters must not leave a bare trailing-dash name:
# the recognition hooks fall back to "default", the coding anchor writes nothing.
EMPTY='../'

new_sandbox
jq -nc --arg s "$EMPTY" '{session_id:$s,source:"startup"}' | bash "$START_HOOK" >/dev/null 2>&1
assert_file    "session-start uses default" "$HOME/.claude/.nish-recognition-pending-default"
assert_no_file "session-start writes no bare name" "$HOME/.claude/.nish-recognition-pending-"
drop_sandbox

new_sandbox
: > "$HOME/.claude/.nish-recognition-pending-default"
jq -nc --arg s "$EMPTY" '{session_id:$s,prompt:"build a thing"}' \
  | bash "$SUBMIT_HOOK" >/dev/null 2>&1
assert_no_file "prompt-submit consumes the default flag" \
  "$HOME/.claude/.nish-recognition-pending-default"
drop_sandbox

new_sandbox
jq -nc --arg s "$EMPTY" '{session_id:$s,tool_input:{skill:"nish-ai-quick-task"}}' \
  | bash "$TRACKER_HOOK" >/dev/null 2>&1
assert_file    "tracker uses default" "$HOME/.claude/.nish-ai-category-default"
assert_no_file "tracker writes no bare name" "$HOME/.claude/.nish-ai-category-"
drop_sandbox

new_sandbox
jq -nc --arg s "$EMPTY" '{session_id:$s,tool_input:{file_path:"/tmp/x.py"}}' \
  | bash "$CODING_HOOK" >/dev/null 2>&1
assert_no_file "coding anchor writes no bare marker" "$SANDBOX/tmp/nish-ai-coding-anchor-"
drop_sandbox

echo "symlinked flags"
# A symlink planted at a flag path must be left alone — every write here
# truncates, so following one would clobber whatever it points at.
new_sandbox
printf 'secret\n' > "$SANDBOX/target"
ln -s "$SANDBOX/target" "$HOME/.claude/.nish-recognition-pending-evil"
jq -nc '{session_id:"evil",source:"startup"}' | bash "$START_HOOK" >/dev/null 2>&1
[[ "$(cat "$SANDBOX/target")" == "secret" ]] \
  && ok "session-start leaves symlink target intact" \
  || bad "session-start leaves symlink target intact" "target was truncated"
drop_sandbox

new_sandbox
printf 'secret\n' > "$SANDBOX/target"
ln -s "$SANDBOX/target" "$HOME/.claude/.nish-recognition-pending-evil"
jq -nc '{session_id:"evil",prompt:"please re-categorize"}' \
  | bash "$SUBMIT_HOOK" >/dev/null 2>&1
[[ "$(cat "$SANDBOX/target")" == "secret" ]] \
  && ok "prompt-submit leaves symlink target intact" \
  || bad "prompt-submit leaves symlink target intact" "target was truncated"
drop_sandbox

new_sandbox
printf 'secret\n' > "$SANDBOX/target"
ln -s "$SANDBOX/target" "$SANDBOX/tmp/nish-ai-coding-anchor-evil"
jq -nc '{session_id:"evil",tool_input:{file_path:"/tmp/x.py"}}' \
  | bash "$CODING_HOOK" >/dev/null 2>&1
[[ "$(cat "$SANDBOX/target")" == "secret" ]] \
  && ok "coding anchor leaves symlink target intact" \
  || bad "coding anchor leaves symlink target intact" "target was truncated"
drop_sandbox

new_sandbox
# The style off-flag is not session-scoped, but both toggles reach through a
# symlink the same way: "drop style" truncates it, "resume style" deletes it.
printf 'secret\n' > "$SANDBOX/target"
ln -s "$SANDBOX/target" "$HOME/.claude/.nish-style-off"
printf 'drop style' | bash "$STYLE_HOOK" >/dev/null 2>&1
[[ "$(cat "$SANDBOX/target")" == "secret" ]] \
  && ok "style toggle leaves symlink target intact" \
  || bad "style toggle leaves symlink target intact" "target was truncated"
printf 'resume style' | bash "$STYLE_HOOK" >/dev/null 2>&1
assert_file "style toggle leaves symlink in place" "$HOME/.claude/.nish-style-off"
drop_sandbox

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
