#!/usr/bin/env bash
# Portable test runner for the nish-ai-uv PreToolUse hook. No bats dependency —
# plain bash assertions, matching tests/run.sh.
#
# Covers uv-pretooluse.sh: deny + rewrite for python/pip/poetry/pipenv/
# virtualenv, and pass-through for uv/conda/venv-active/bypass-marker.
#
# Run: ./tests/uv.sh   (exits non-zero if any assertion fails)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/nish-ai-uv/hooks/uv-pretooluse.sh"

command -v jq >/dev/null || { echo "jq required for tests" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }

# Feed a command as PreToolUse JSON, capture the hook's stdout. VIRTUAL_ENV is
# cleared so the harness's own venv (if any) does not suppress the redirect.
run_hook() { # $1 = command
  jq -n --arg c "$1" '{tool_input:{command:$c}}' | env -u VIRTUAL_ENV bash "$HOOK"
}
# Decision: "deny" when the hook emits a deny block, else "pass".
decision() { # $1 = hook output
  [[ -z "$1" ]] && { echo pass; return; }
  printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    && { echo deny; return; }
  echo pass
}
# The suggested uv command carried in the deny reason's final line.
suggestion() { # $1 = hook output
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' \
    | grep -E '^\s+\S' | tail -n1 | sed 's/^[[:space:]]*//'
}

assert_deny() { # $1 = label  $2 = expected suggestion  $3 = command
  local out got sug
  out="$(run_hook "$3")"
  got="$(decision "$out")"
  if [[ "$got" != deny ]]; then bad "$1" "expected deny, got $got"; return; fi
  sug="$(suggestion "$out")"
  [[ "$sug" == "$2" ]] && ok "$1" || bad "$1" "expected [$2], got [$sug]"
}
assert_pass() { # $1 = label  $2 = command
  local got; got="$(decision "$(run_hook "$2")")"
  [[ "$got" == pass ]] && ok "$1" || bad "$1" "expected pass, got $got"
}

echo "uv-pretooluse.sh"
assert_deny "python script denied"   "uv run app.py"            'python app.py'
assert_deny "python REPL denied"     "uv run python"            'python'
assert_deny "python -m denied"       "uv run -m http.server"    'python -m http.server'
assert_deny "python -m venv denied"  "uv venv .venv"            'python -m venv .venv'
assert_deny "python3 denied"         "uv run app.py"            'python3 app.py'
assert_deny "pip install denied"     "uv pip install requests"  'pip install requests'
assert_deny "poetry add denied"      "uv add httpx"             'poetry add httpx'
assert_deny "poetry install denied"  "uv sync"                  'poetry install'
assert_deny "pipenv install denied"  "uv add flask"             'pipenv install flask'
assert_deny "virtualenv denied"      "uv venv .venv"            'virtualenv .venv'

assert_pass "already uv"             'uv run python app.py'
assert_pass "conda untouched"        'conda install numpy'
assert_pass "unrelated command"      'ls -la'

# $VIRTUAL_ENV set → venv python is legit, hook stands down.
got_venv="$(decision "$(jq -n --arg c 'python app.py' '{tool_input:{command:$c}}' \
  | VIRTUAL_ENV=/tmp/v bash "$HOOK")")"
[[ "$got_venv" == pass ]] && ok "VIRTUAL_ENV set passes" || bad "VIRTUAL_ENV set passes" "got $got_venv"

# Bypass marker present → hook stands down. Use a temp HOME so the real marker
# state is irrelevant.
TMPHOME="$(mktemp -d)"
mkdir -p "$TMPHOME/.claude"
touch "$TMPHOME/.claude/.uv-off"
got_marker="$(decision "$(jq -n --arg c 'python app.py' '{tool_input:{command:$c}}' \
  | env -u VIRTUAL_ENV HOME="$TMPHOME" bash "$HOOK")")"
[[ "$got_marker" == pass ]] && ok "bypass marker passes" || bad "bypass marker passes" "got $got_marker"
rm -rf "$TMPHOME"

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
