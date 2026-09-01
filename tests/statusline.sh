#!/usr/bin/env bash
# Portable test suite for the statusline badge. No bats dependency — plain bash
# assertions, so it runs anywhere the hook itself runs.
#
# Covers style-statusline.sh: the usage badge (bar fill, colour bands, reset
# countdown), and the guarantee that a payload without rate_limits, or a PATH
# without jq, leaves the line exactly as it was.
#
# Run: ./tests/statusline.sh   (exits non-zero if any assertion fails)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUSLINE="$REPO_DIR/nish-ai-writing-style/hooks/style-statusline.sh"

command -v jq >/dev/null || { echo "jq required for tests" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }

# A throwaway HOME keeps the real off-flag and category flags out of the run.
TMPHOME="$(mktemp -d)"
mkdir -p "$TMPHOME/.claude"
trap 'rm -rf "$TMPHOME"' EXIT

# Run the hook on a payload, return its stdout with ANSI stripped.
render() { # $1 = stdin JSON  [$2... = extra env assignments]
  local payload="$1"; shift
  printf '%s' "$payload" \
    | env HOME="$TMPHOME" "$@" bash "$STATUSLINE" 2>/dev/null \
    | sed $'s/\e\\[[0-9;]*m//g'
}
render_stderr() { # $1 = stdin JSON  [$2... = extra env] -> stderr only
  local payload="$1"; shift
  printf '%s' "$payload" | env HOME="$TMPHOME" "$@" bash "$STATUSLINE" 2>&1 >/dev/null
}

# Payload with a five_hour block; $2 = resets_at (omitted when empty).
payload() { # $1 = used_percentage  $2 = resets_at
  if [[ -z "${2:-}" ]]; then
    jq -nc --argjson p "$1" \
      '{workspace:{current_dir:"/tmp/proj"},rate_limits:{five_hour:{used_percentage:$p}}}'
  else
    jq -nc --argjson p "$1" --arg r "$2" \
      '{workspace:{current_dir:"/tmp/proj"},rate_limits:{five_hour:{used_percentage:$p,resets_at:$r}}}'
  fi
}
bare_payload() { jq -nc '{workspace:{current_dir:"/tmp/proj"}}'; }

assert_contains() { # $1 = label  $2 = needle  $3 = haystack
  [[ "$3" == *"$2"* ]] && ok "$1" || bad "$1" "expected [$2] in [$3]"
}
assert_missing() { # $1 = label  $2 = needle  $3 = haystack
  [[ "$3" != *"$2"* ]] && ok "$1" || bad "$1" "did not expect [$2] in [$3]"
}
assert_matches() { # $1 = label  $2 = regex  $3 = haystack
  [[ "$3" =~ $2 ]] && ok "$1" || bad "$1" "expected /$2/ in [$3]"
}

echo "usage badge"
assert_contains "percent renders"    "42%"      "$(render "$(payload 42 '')")"
assert_contains "bar renders"        "▰▰▱▱▱ 42%" "$(render "$(payload 42 '')")"
assert_contains "left group kept"    "▪ proj"   "$(render "$(payload 42 '')")"

echo "bar fill by percent"
assert_contains "0 empty"    "▱▱▱▱▱ 0%"   "$(render "$(payload 0 '')")"
assert_contains "49 two"     "▰▰▱▱▱ 49%"  "$(render "$(payload 49 '')")"
assert_contains "50 two"     "▰▰▱▱▱ 50%"  "$(render "$(payload 50 '')")"
assert_contains "79 three"   "▰▰▰▱▱ 79%"  "$(render "$(payload 79 '')")"
assert_contains "80 four"    "▰▰▰▰▱ 80%"  "$(render "$(payload 80 '')")"
assert_contains "100 full"   "▰▰▰▰▰ 100%" "$(render "$(payload 100 '')")"
assert_contains "float floors to int" "37%" "$(render "$(payload 37.8 '')")"

echo "colour bands"
# Colours survive the ANSI strip only if we look at the raw output.
raw() { printf '%s' "$1" | env HOME="$TMPHOME" bash "$STATUSLINE" 2>/dev/null; }
assert_contains "under 50 mint"  $'\e[38;2;46;230;168m'  "$(raw "$(payload 49 '')")"
assert_contains "50-79 amber"    $'\e[38;2;255;179;57m'  "$(raw "$(payload 50 '')")"
assert_contains "79 still amber" $'\e[38;2;255;179;57m'  "$(raw "$(payload 79 '')")"
assert_contains "80+ red"        $'\e[38;2;255;77;109m'  "$(raw "$(payload 80 '')")"

echo "reset countdown"
FUTURE_H="$(date -u -v+1H -v+12M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
  || date -u -d '+1 hour 12 minutes' '+%Y-%m-%dT%H:%M:%SZ')"
FUTURE_M="$(date -u -v+47M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
  || date -u -d '+47 minutes' '+%Y-%m-%dT%H:%M:%SZ')"
PAST="$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
  || date -u -d '-1 hour' '+%Y-%m-%dT%H:%M:%SZ')"
# A second can elapse between fixture and render, so the last minute is loose.
assert_matches "hours and minutes" '1h1[12]m'  "$(render "$(payload 42 "$FUTURE_H")")"
assert_matches "minutes only"      '· 4[67]m'  "$(render "$(payload 42 "$FUTURE_M")")"
assert_contains "past percent kept" "42%"    "$(render "$(payload 42 "$PAST")")"
assert_missing  "past countdown omitted" "·  " "$(render "$(payload 42 "$PAST")" | sed 's/^.*42%//')"
assert_missing  "unparseable countdown omitted" "m" \
  "$(render "$(payload 42 'not-a-timestamp')" | sed 's/^.*42%//')"

echo "graceful degradation"
BASE="$(render "$(bare_payload)")"
assert_missing  "no rate_limits, no bar"    "▱" "$BASE"
assert_contains "no rate_limits, line kept" "▪ proj" "$BASE"
# jq absent: an empty PATH strips it, and the line falls back to $PWD.
NOJQ="$(printf '%s' "$(payload 42 '')" | env HOME="$TMPHOME" PATH=/nonexistent \
  bash "$STATUSLINE" 2>/dev/null | sed $'s/\e\\[[0-9;]*m//g')"
assert_missing "no jq, no badge" "42%" "$NOJQ"
[[ -z "$(render_stderr "$(payload 42 '')")" ]] \
  && ok "no stderr" || bad "no stderr" "got [$(render_stderr "$(payload 42 '')")]"
printf '%s' "$(payload 42 '')" | env HOME="$TMPHOME" bash "$STATUSLINE" >/dev/null 2>&1
[[ "$?" -eq 0 ]] && ok "exit 0" || bad "exit 0" "non-zero exit"

echo "untrusted payload"
# An escape byte in current_dir must not survive into the rendered line.
ESC_DIR="$(printf '%s' '{"workspace":{"current_dir":"/tmp/ev\u001b[31mil"}}' \
  | env HOME="$TMPHOME" bash "$STATUSLINE" 2>/dev/null)"
assert_missing "escape byte stripped from dir" $'\e[31m' "$ESC_DIR"
# A session_id carrying path separators must not reach outside .claude/.
printf 'planning' > "$TMPHOME/probe"
TRAVERSAL="$(printf '%s' '{"workspace":{"current_dir":"/tmp/proj"},"session_id":"../probe"}' \
  | env HOME="$TMPHOME" bash "$STATUSLINE" 2>/dev/null | sed $'s/\e\\[[0-9;]*m//g')"
assert_missing "session id traversal blocked" "▸ planning" "$TRAVERSAL"

echo "narrow terminal"
# No controlling terminal in a test run, so COLS comes from tput; a 20-column
# terminal cannot fit the composed line and must fall back to appending.
NARROW="$(printf '%s' "$(payload 42 '')" | env HOME="$TMPHOME" COLUMNS=20 TERM=dumb \
  bash "$STATUSLINE" 2>/dev/null | sed $'s/\e\\[[0-9;]*m//g')"
assert_contains "narrow keeps badge" "42%" "$NARROW"
assert_missing  "narrow does not wrap" $'\n' "$NARROW"

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
