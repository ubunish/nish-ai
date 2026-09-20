#!/usr/bin/env bash
# Portable test suite for the Jev path through the session router. No bats
# dependency — plain bash assertions, matching tests/run.sh.
#
# Covers recognition-prompt-submit.sh: a confident judgment settles the
# category, a spread one names two, a prompt that is only pasted material is
# left to the model, and every failure path emits the directive the hook
# emitted before Jev existed. Requests go to the local stub, so the suite never
# touches the network.
#
# Run: ./tests/router.sh   (exits non-zero if any assertion fails)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/nish-ai-prompt-recognition/hooks/recognition-prompt-submit.sh"
STUB="$REPO_DIR/tests/fixtures/jev-stub.py"

command -v jq  >/dev/null || { echo "jq required for tests"  >&2; exit 1; }
command -v uv  >/dev/null || { echo "uv required for tests"  >&2; exit 1; }
command -v git >/dev/null || { echo "git required for tests" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }

SANDBOX="$(mktemp -d)"
STUB_LOG="$SANDBOX/requests.log"
STUB_OUT="$SANDBOX/stub.out"
: > "$STUB_LOG"

cleanup() {
  [[ -n "${STUB_PID:-}" ]] && kill "$STUB_PID" 2>/dev/null
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

uv run "$STUB" "$STUB_LOG" > "$STUB_OUT" 2>/dev/null &
STUB_PID=$!
PORT=""
for _ in $(seq 1 100); do
  PORT="$(head -n1 "$STUB_OUT" 2>/dev/null)"
  [[ -n "$PORT" ]] && break
  sleep 0.1
done
[[ -n "$PORT" ]] || { echo "stub server did not start" >&2; exit 1; }

# A throwaway HOME carrying the symlinks install.sh creates, so the hook
# resolves jev and the route question file the way it does live.
FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME/.claude/skills"
ln -s "$REPO_DIR/nish-ai-jev" "$FAKE_HOME/.claude/skills/nish-ai-jev"
ln -s "$REPO_DIR/nish-ai-prompt-recognition" "$FAKE_HOME/.claude/skills/nish-ai-prompt-recognition"

SESSION=0
# Each call arms a fresh per-session flag, since the hook fires once per session.
route() { # $1 = prompt  $2 = endpoint path suffix  $3.. = env options (before assignments)
  SESSION=$((SESSION + 1))
  : > "$FAKE_HOME/.claude/.nish-recognition-pending-s$SESSION"
  local prompt="$1" suffix="$2"; shift 2
  jq -nc --arg s "s$SESSION" --arg p "$prompt" '{session_id:$s, prompt:$p}' \
    | env "$@" HOME="$FAKE_HOME" JEV_ENDPOINT="http://127.0.0.1:$PORT$suffix" \
      bash "$HOOK" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""'
}
assert_contains() { # $1 = label  $2 = needle  $3 = haystack
  case "$3" in
    *"$2"*) ok "$1" ;;
    *)      bad "$1" "expected to find [$2] in [$3]" ;;
  esac
}

echo "settled"
OUT="$(route "fix the failing login test" /v1/systemone TYPESAFE_API_KEY=test-key-123)"
assert_contains "names the judged category"  "already categorized this first prompt as C" "$OUT"
assert_contains "names the skill to invoke"  "invoking nish-ai-goal-oriented-coding"      "$OUT"

echo "narrowed"
OUT="$(route "tidy up the auth module" /spread TYPESAFE_API_KEY=test-key-123)"
assert_contains "names two tracks"   "narrowed this first prompt to two tracks" "$OUT"
assert_contains "names the runner-up" "B: User Question"                        "$OUT"

echo "pasted content"
OUT="$(route "Traceback (most recent call last): File x line 3" /pasted TYPESAFE_API_KEY=test-key-123)"
assert_contains "falls back to the five-way directive" "categorize it as one of A" "$OUT"

echo "fail-open"
OUT="$(route "fix the failing login test" /v1/systemone -u TYPESAFE_API_KEY)"
assert_contains "no key falls back" "categorize it as one of A" "$OUT"

OUT="$(route "fix the failing login test" /fail TYPESAFE_API_KEY=test-key-123)"
assert_contains "api error falls back" "categorize it as one of A" "$OUT"

BARE_HOME="$SANDBOX/bare-home"
mkdir -p "$BARE_HOME/.claude"
: > "$BARE_HOME/.claude/.nish-recognition-pending-bare"
OUT="$(jq -nc '{session_id:"bare", prompt:"fix the failing login test"}' \
  | env HOME="$BARE_HOME" TYPESAFE_API_KEY=test-key-123 bash "$HOOK" 2>/dev/null \
  | jq -r '.hookSpecificOutput.additionalContext // ""')"
assert_contains "uninstalled jev falls back" "categorize it as one of A" "$OUT"

echo "fires once"
: > "$FAKE_HOME/.claude/.nish-recognition-pending-once"
jq -nc '{session_id:"once", prompt:"fix the failing login test"}' \
  | env HOME="$FAKE_HOME" JEV_ENDPOINT="http://127.0.0.1:$PORT/v1/systemone" \
        TYPESAFE_API_KEY=test-key-123 bash "$HOOK" >/dev/null 2>&1
SECOND="$(jq -nc '{session_id:"once", prompt:"and now document it"}' \
  | env HOME="$FAKE_HOME" JEV_ENDPOINT="http://127.0.0.1:$PORT/v1/systemone" \
        TYPESAFE_API_KEY=test-key-123 bash "$HOOK" 2>/dev/null)"
[[ -z "$SECOND" ]] && ok "second prompt is silent" || bad "second prompt is silent" "got [$SECOND]"

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
