#!/usr/bin/env bash
# Portable test suite for the jev CLI. No bats dependency — plain bash
# assertions, matching tests/run.sh.
#
# Covers nish-ai-jev/jev: the origin allowlist, the fail-open exits (no key, no
# origin, timeout, HTTP error, malformed question file), and the request shape
# for string and structured state. Also covers nish-ai-jev/replay, against a
# synthetic transcript in a throwaway HOME. Every request goes to a local stub,
# so the suite never touches the network and never spends an API call.
#
# Run: ./tests/jev.sh   (exits non-zero if any assertion fails)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JEV="$REPO_DIR/nish-ai-jev/jev"
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

# --- stub -------------------------------------------------------------------
uv run "$STUB" "$STUB_LOG" > "$STUB_OUT" 2>/dev/null &
STUB_PID=$!
PORT=""
for _ in $(seq 1 100); do
  PORT="$(head -n1 "$STUB_OUT" 2>/dev/null)"
  [[ -n "$PORT" ]] && break
  sleep 0.1
done
[[ -n "$PORT" ]] || { echo "stub server did not start" >&2; exit 1; }
STUB_URL="http://127.0.0.1:$PORT/v1/systemone"

# --- fixtures ---------------------------------------------------------------
QUESTIONS="$SANDBOX/questions.json"
cat > "$QUESTIONS" <<'JSON'
{ "ok": { "type": "noul", "instructions": "Is this a test?" } }
JSON
printf 'not json' > "$SANDBOX/broken.json"

# A throwaway repo per origin: the allowlist is matched against the origin of
# the directory jev runs in, so the origin is the only thing that varies.
new_repo() { # $1 = origin url -> repo path
  local dir; dir="$(mktemp -d "$SANDBOX/repo.XXXXXX")"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$1"
  printf '%s' "$dir"
}
ALLOWED_REPO="$(new_repo 'https://github.com/ubunish/nish-ai.git')"
SCP_REPO="$(new_repo 'git@github.com:Ubunish/Other.git')"
REFUSED_REPO="$(new_repo 'https://github.com/first-motive/fm-ai.git')"
BARE_REPO="$(mktemp -d "$SANDBOX/repo.XXXXXX")"; git -C "$BARE_REPO" init -q

requests() { wc -l < "$STUB_LOG" | tr -d ' '; }

# Run jev in a repo with the stub as its endpoint. Extra args land before the
# question file.
run_jev() { # $1 = repo  $2 = state  $3.. = extra args
  local repo="$1" state="$2"; shift 2
  ( cd "$repo" && printf '%s' "$state" \
      | JEV_ENDPOINT="$STUB_URL" TYPESAFE_API_KEY=test-key-123 \
        bash "$JEV" "$@" "$QUESTIONS" 2>/dev/null )
}

assert_ok() { # $1 = label  $2 = repo  $3 = state
  local out; out="$(run_jev "$2" "$3")"
  local status=$?
  if [[ $status -ne 0 ]]; then bad "$1" "expected exit 0, got $status"; return; fi
  printf '%s' "$out" | jq -e '.ok.noul == 0.9' >/dev/null 2>&1 \
    && ok "$1" || bad "$1" "answers missing from stdout: [$out]"
}
assert_fails() { # $1 = label  $2.. = command
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then bad "$label" "expected non-zero exit"; else ok "$label"; fi
}

echo "allowlist"
before="$(requests)"
assert_fails "first-motive origin refused" \
  env JEV_ENDPOINT="$STUB_URL" TYPESAFE_API_KEY=test-key-123 \
  bash -c "cd '$REFUSED_REPO' && printf x | bash '$JEV' '$QUESTIONS'"
assert_fails "no origin refused" \
  env JEV_ENDPOINT="$STUB_URL" TYPESAFE_API_KEY=test-key-123 \
  bash -c "cd '$BARE_REPO' && printf x | bash '$JEV' '$QUESTIONS'"
[[ "$(requests)" == "$before" ]] && ok "refused repos sent no request" \
  || bad "refused repos sent no request" "stub logged $(( $(requests) - before )) request(s)"

assert_ok "allowlisted origin answers" "$ALLOWED_REPO" "a prompt"
assert_ok "scp-form origin normalizes" "$SCP_REPO" "a prompt"

echo "fail-open"
assert_fails "missing key exits non-zero" \
  env JEV_ENDPOINT="$STUB_URL" -u TYPESAFE_API_KEY \
  bash -c "cd '$ALLOWED_REPO' && printf x | bash '$JEV' '$QUESTIONS'"
assert_fails "key with a quote refused" \
  env JEV_ENDPOINT="$STUB_URL" TYPESAFE_API_KEY='bad"key' \
  bash -c "cd '$ALLOWED_REPO' && printf x | bash '$JEV' '$QUESTIONS'"
# 10.255.255.1 is unroutable, so the connection hangs until --timeout fires.
assert_fails "timeout exits non-zero" \
  env JEV_ENDPOINT="http://10.255.255.1/v1/systemone" TYPESAFE_API_KEY=test-key-123 \
  bash -c "cd '$ALLOWED_REPO' && printf x | bash '$JEV' --timeout 1 '$QUESTIONS'"
assert_fails "http error exits non-zero" \
  env JEV_ENDPOINT="http://127.0.0.1:$PORT/fail" TYPESAFE_API_KEY=test-key-123 \
  bash -c "cd '$ALLOWED_REPO' && printf x | bash '$JEV' '$QUESTIONS'"
assert_fails "missing question file exits non-zero" \
  env JEV_ENDPOINT="$STUB_URL" TYPESAFE_API_KEY=test-key-123 \
  bash -c "cd '$ALLOWED_REPO' && printf x | bash '$JEV' '$SANDBOX/absent.json'"
assert_fails "malformed question file exits non-zero" \
  env JEV_ENDPOINT="$STUB_URL" TYPESAFE_API_KEY=test-key-123 \
  bash -c "cd '$ALLOWED_REPO' && printf x | bash '$JEV' '$SANDBOX/broken.json'"

echo "request shape"
: > "$STUB_LOG"
run_jev "$ALLOWED_REPO" 'plain text' >/dev/null
last_body() { tail -n1 "$STUB_LOG"; }
last_body | jq -e '.state == "plain text" and .model == "jev-latest" and (.questions.ok.type == "noul")' \
  >/dev/null 2>&1 && ok "string state sent as a string" \
  || bad "string state sent as a string" "body was [$(last_body)]"

: > "$STUB_LOG"
run_jev "$ALLOWED_REPO" '{"command":"rm -rf x","branch":"main"}' >/dev/null
last_body | jq -e '.state.command == "rm -rf x"' >/dev/null 2>&1 \
  && ok "structured state sent as an object" \
  || bad "structured state sent as an object" "body was [$(last_body)]"

echo "replay"
# A synthetic transcript in a throwaway ~/.claude/projects: one session whose
# first prompt is free text and whose first category Skill call is the label.
# The session's cwd is the allowlisted repo, so jev answers from the stub.
REPLAY_HOME="$SANDBOX/replay-home"
mkdir -p "$REPLAY_HOME/.claude/projects/sample"
{
  jq -nc --arg cwd "$ALLOWED_REPO" '{type:"user", cwd:$cwd, message:{content:"build the widget"}}'
  jq -nc --arg cwd "$ALLOWED_REPO" \
    '{type:"assistant", cwd:$cwd, message:{content:[{type:"tool_use", name:"Skill", input:{skill:"nish-ai-goal-oriented-coding"}}]}}'
} > "$REPLAY_HOME/.claude/projects/sample/session.jsonl"

REPLAY_OUT="$(HOME="$REPLAY_HOME" JEV_ENDPOINT="$STUB_URL" TYPESAFE_API_KEY=test-key-123 \
  bash "$REPO_DIR/nish-ai-jev/replay" "$QUESTIONS" 2>&1)"
printf '%s' "$REPLAY_OUT" | grep -q 'answered: 1' \
  && ok "replay scores a session from a transcript" \
  || bad "replay scores a session from a transcript" "output was [$REPLAY_OUT]"
printf '%s' "$REPLAY_OUT" | grep -q 'latency  p50=' \
  && ok "replay reports latency percentiles" \
  || bad "replay reports latency percentiles" "output was [$REPLAY_OUT]"

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
