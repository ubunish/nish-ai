#!/usr/bin/env bash
# Portable test suite for the Jev bash gate. No bats dependency — plain bash
# assertions, matching tests/run.sh.
#
# Covers nish-ai-jev/hooks/bash-gate.sh: the read-only prefilter (which must
# pass without spending a request, and must not be talked past by a
# metacharacter), the "ask" decision above the threshold, the pass below it,
# and silence on every failure path. Requests go to the local
# stub, so the suite never touches the network.
#
# Run: ./tests/bash-gate.sh   (exits non-zero if any assertion fails)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/nish-ai-jev/hooks/bash-gate.sh"
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

# A throwaway HOME whose skills directory holds the same symlink install.sh
# creates, so the hook resolves jev and its question file the way it does live.
FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME/.claude/skills"
ln -s "$REPO_DIR/nish-ai-jev" "$FAKE_HOME/.claude/skills/nish-ai-jev"

# The gate reads the repo's origin through jev's allowlist, so the working
# directory it is handed must be an allowlisted repo.
WORK_REPO="$SANDBOX/repo"
mkdir -p "$WORK_REPO"
git -C "$WORK_REPO" init -q
git -C "$WORK_REPO" remote add origin 'https://github.com/ubunish/nish-ai.git'

requests() { wc -l < "$STUB_LOG" | tr -d ' '; }

run_hook() { # $1 = command  $2 = endpoint path suffix (default /v1/systemone)
  jq -nc --arg c "$1" --arg d "$WORK_REPO" '{tool_input:{command:$c}, cwd:$d}' \
    | env HOME="$FAKE_HOME" \
          JEV_ENDPOINT="http://127.0.0.1:$PORT${2:-/v1/systemone}" \
          TYPESAFE_API_KEY=test-key-123 \
      bash "$HOOK" 2>/dev/null
}
decision() { # $1 = hook output -> "ask" | "pass"
  [[ -z "$1" ]] && { echo pass; return; }
  printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null 2>&1 \
    && { echo ask; return; }
  echo pass
}
assert_decision() { # $1 = label  $2 = expected  $3 = command
  local got; got="$(decision "$(run_hook "$3")")"
  [[ "$got" == "$2" ]] && ok "$1" || bad "$1" "expected $2, got $got"
}

echo "read-only prefilter"
before="$(requests)"
assert_decision "ls passes"                    pass 'ls -la'
assert_decision "git status passes"            pass 'git status --short'
assert_decision "piped read-only chain passes" pass 'git log --oneline | head -20'
assert_decision "cat into grep passes"         pass 'cat README.md | grep -c set'
assert_decision "read-only && chain passes"    pass 'git status --short && git log --oneline'
[[ "$(requests)" == "$before" ]] && ok "prefilter spends no request" \
  || bad "prefilter spends no request" "stub logged $(( $(requests) - before )) request(s)"

echo "judged commands"
assert_decision "rm -rf asks"                  ask  'rm -rf scratch/'
assert_decision "redirection asks"             ask  'cat notes.md > /etc/motd'
assert_decision "command substitution asks"    ask  'echo $(rm -rf /tmp/x)'
assert_decision "process substitution asks"    ask  'cat <(rm -rf scratch)'
assert_decision "git push asks"                ask  'git push --force origin main'
assert_decision "background chaining asks"     ask  'echo test & rm -rf scratch'
assert_decision "brace group asks"             ask  '{ rm -rf scratch; }'
assert_decision "escape asks"                  ask  'echo a\; rm -rf scratch'
# A verb-only prefilter would read these as reads; the flag is what writes.
assert_decision "find -exec asks"              ask  'find . -name "*.tmp" -exec rm -f {} ;'
assert_decision "sed in place asks"            ask  "sed -i '' 's/a/b/' notes.md"
assert_decision "awk system asks"              ask  'awk "BEGIN { system(\"rm -rf x\") }"'
GOT_LOW="$(decision "$(run_hook 'rm -rf scratch/' '/low')")"
[[ "$GOT_LOW" == pass ]] && ok "low probability passes" || bad "low probability passes" "got $GOT_LOW"

echo "fail-open"
NO_KEY="$(jq -nc --arg c 'rm -rf scratch/' --arg d "$WORK_REPO" '{tool_input:{command:$c}, cwd:$d}' \
  | env HOME="$FAKE_HOME" JEV_ENDPOINT="http://127.0.0.1:$PORT/v1/systemone" -u TYPESAFE_API_KEY \
    bash "$HOOK" 2>/dev/null)"
[[ -z "$NO_KEY" ]] && ok "no key is silent" || bad "no key is silent" "got [$NO_KEY]"

API_DOWN="$(decision "$(run_hook 'rm -rf scratch/' '/fail')")"
[[ "$API_DOWN" == pass ]] && ok "api error passes" || bad "api error passes" "got $API_DOWN"

NO_SKILL_HOME="$SANDBOX/bare-home"
mkdir -p "$NO_SKILL_HOME/.claude"
UNINSTALLED="$(jq -nc --arg c 'rm -rf scratch/' --arg d "$WORK_REPO" '{tool_input:{command:$c}, cwd:$d}' \
  | env HOME="$NO_SKILL_HOME" TYPESAFE_API_KEY=test-key-123 bash "$HOOK" 2>/dev/null)"
[[ -z "$UNINSTALLED" ]] && ok "uninstalled jev is silent" || bad "uninstalled jev is silent" "got [$UNINSTALLED]"

EMPTY="$(printf '{}' | env HOME="$FAKE_HOME" TYPESAFE_API_KEY=test-key-123 bash "$HOOK" 2>/dev/null)"
[[ -z "$EMPTY" ]] && ok "payload without a command is silent" || bad "payload without a command is silent" "got [$EMPTY]"

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
