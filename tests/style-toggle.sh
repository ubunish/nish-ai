#!/usr/bin/env bash
# Portable test suite for the writing-style toggle. No bats dependency — plain
# bash assertions, so it runs anywhere the hook itself runs.
#
# Covers style-prompt-submit.sh: "drop style" / "verbose mode" turn the style
# off, "resume style" turns it back on, and a phrase carried by any other field
# of the payload — cwd, transcript_path, a quoted filename — does not toggle.
#
# Run: ./tests/style-toggle.sh   (exits non-zero if any assertion fails)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/nish-ai-writing-style/hooks/style-prompt-submit.sh"

command -v jq >/dev/null || { echo "jq required for tests" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }

# A throwaway HOME keeps the real off-flag out of the run.
TMPHOME="$(mktemp -d)"
mkdir -p "$TMPHOME/.claude"
trap 'rm -rf "$TMPHOME"' EXIT
OFF_FLAG="$TMPHOME/.claude/.nish-style-off"

submit() { # $1 = payload JSON  [$2... = extra env]
  local payload="$1"; shift
  printf '%s' "$payload" | env HOME="$TMPHOME" "$@" bash "$HOOK" 2>/dev/null
}
prompt_payload() { jq -nc --arg p "$1" '{session_id:"s",cwd:"/tmp/proj",prompt:$p}'; }

assert_off() { # $1 = label
  [[ -f "$OFF_FLAG" ]] && ok "$1" || bad "$1" "off flag missing"
}
assert_on() { # $1 = label
  [[ ! -f "$OFF_FLAG" ]] && ok "$1" || bad "$1" "off flag present"
}

echo "toggle by prompt"
rm -f "$OFF_FLAG"
submit "$(prompt_payload 'drop style')" >/dev/null
assert_off "drop style turns it off"
submit "$(prompt_payload 'resume style')" >/dev/null
assert_on "resume style turns it back on"
submit "$(prompt_payload 'verbose mode please')" >/dev/null
assert_off "verbose mode turns it off"
submit "$(prompt_payload 'style on')" >/dev/null
assert_on "style on turns it back on"
submit "$(prompt_payload 'drop style')" >/dev/null
submit "$(prompt_payload 'enable style')" >/dev/null
assert_on "enable style turns it back on"

echo "reminder emitted"
rm -f "$OFF_FLAG"
OUT="$(submit "$(prompt_payload 'build a thing')")"
[[ "$OUT" == *"WRITING STYLE ACTIVE"* ]] && ok "reminder on a plain prompt" \
  || bad "reminder on a plain prompt" "got [${OUT:0:60}]"
submit "$(prompt_payload 'drop style')" >/dev/null
[[ -z "$(submit "$(prompt_payload 'build a thing')")" ]] && ok "silent while off" \
  || bad "silent while off" "reminder emitted with the flag set"

echo "phrase outside the prompt"
# The regression: these fields ride along on every payload. A phrase in one of
# them must not flip the style.
rm -f "$OFF_FLAG"
submit "$(jq -nc '{session_id:"s",cwd:"/tmp/drop style",prompt:"run install.sh"}')" >/dev/null
assert_on "cwd does not toggle"
submit "$(jq -nc '{session_id:"s",transcript_path:"/tmp/verbose mode.jsonl",prompt:"ls"}')" >/dev/null
assert_on "transcript_path does not toggle"
# A prompt that only quotes the phrase as documentation still toggles — the
# match is on the prompt text, and that text is what the user typed.
submit "$(prompt_payload 'the readme says "drop style" turns it off')" >/dev/null
assert_off "quoted phrase in the prompt still toggles"

echo "resume path does not delete either"
rm -f "$OFF_FLAG"
: > "$OFF_FLAG"
submit "$(jq -nc '{session_id:"s",cwd:"/tmp/resume style",prompt:"ls"}')" >/dev/null
assert_off "cwd does not re-enable"

echo "no jq"
# Without jq the hook falls back to the raw payload, so the toggle survives. The
# stub PATH keeps the binaries the hook itself needs and drops only jq.
NOJQ_BIN="$TMPHOME/bin"
mkdir -p "$NOJQ_BIN"
ln -sf "$(command -v cat)" "$NOJQ_BIN/cat"
rm -f "$OFF_FLAG"
printf '%s' "$(prompt_payload 'drop style')" \
  | env HOME="$TMPHOME" PATH="$NOJQ_BIN" "$(command -v bash)" "$HOOK" >/dev/null 2>&1
assert_off "toggle still works without jq"

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
