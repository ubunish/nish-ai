#!/usr/bin/env bash
# Portable test suite for the session coordination layer. No bats dependency —
# plain bash assertions, matching tests/run.sh.
#
# Runs against a throwaway HOME holding a fake Claude Code session registry and
# throwaway git repos, so the real registry and inboxes are never touched.
# Live sessions are backed by sleep processes; a dead one by a reaped pid.
#
# Run: ./tests/sessions.sh   (exits non-zero if any assertion fails)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_DIR/nish-ai-sessions/bin/nish-session"

command -v jq  >/dev/null || { echo "jq required for tests"  >&2; exit 1; }
command -v git >/dev/null || { echo "git required for tests" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }
assert_eq() { # $1 = label  $2 = expected  $3 = actual
  [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "expected [$2], got [$3]"
}

SANDBOX="$(mktemp -d)"
SANDBOX="$(cd "$SANDBOX" && pwd -P)"   # git reports resolved paths; match them
LIVE_PIDS=()
cleanup() {
  [[ ${#LIVE_PIDS[@]} -gt 0 ]] && { kill "${LIVE_PIDS[@]}"; wait "${LIVE_PIDS[@]}"; } 2>/dev/null
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

export HOME="$SANDBOX/home"
unset CLAUDE_CODE_SESSION_ID
REGISTRY="$HOME/.claude/sessions"
STATE="$HOME/.claude/nish-ai-sessions"
mkdir -p "$REGISTRY"

git_quiet() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@" >/dev/null 2>&1; }
new_repo() { # $1 = path
  mkdir -p "$1"
  git_quiet -C "$1" init
  git_quiet -C "$1" commit --allow-empty -m init
}

# Sets LIVE to a fresh live pid. Run in this shell, never in $(...): the sleep
# would hold the substitution's stdout open and LIVE_PIDS would be lost.
start_live() { sleep 300 >/dev/null 2>&1 & LIVE="$!"; LIVE_PIDS+=("$LIVE"); }
dead_pid() { sh -c 'exit 0' & local p=$!; wait "$p"; echo "$p"; }

register() { # $1 = pid  $2 = session id  $3 = cwd  $4 = name  $5 = startedAt (optional)
  jq -n --argjson pid "$1" --arg s "$2" --arg c "$3" --arg n "$4" --argjson t "${5:-1000}" \
    '{pid: $pid, sessionId: $s, cwd: $c, name: $n, status: "busy", startedAt: $t}' \
    > "$REGISTRY/$1.json"
}

peer_names() { # $@ = peers args -> sorted, comma-joined names
  "$CLI" peers "$@" | jq -r '.name' | sort | paste -sd, -
}

new_repo "$SANDBOX/repo-a"
git_quiet -C "$SANDBOX/repo-a" worktree add -b wt "$SANDBOX/repo-a-wt"
new_repo "$SANDBOX/repo-b"

start_live; register "$LIVE" self   "$SANDBOX/repo-a"    me
start_live; register "$LIVE" twin   "$SANDBOX/repo-a"    twin
start_live; register "$LIVE" branch "$SANDBOX/repo-a-wt" branch
start_live; register "$LIVE" other  "$SANDBOX/repo-b"    other
register "$(dead_pid)" ghost "$SANDBOX/repo-a" ghost
# Malformed entries: no cwd would make git -C fall back to the caller's own dir.
start_live; register "$LIVE" nocwd "" nocwd
printf '{"pid":"abc","sessionId":"junk","cwd":"%s","name":"junk"}\n' "$SANDBOX/repo-a" > "$REGISTRY/junk.json"

echo "peers"
assert_eq "same repo, worktree included, self/dead/other repo/malformed excluded" \
  "branch,twin" "$(peer_names --cwd "$SANDBOX/repo-a" --self self)"
assert_eq "from inside a worktree the primary checkout is a peer" \
  "me,twin" "$(peer_names --cwd "$SANDBOX/repo-a-wt" --self branch)"
assert_eq "self defaults to CLAUDE_CODE_SESSION_ID" \
  "branch,twin" "$(CLAUDE_CODE_SESSION_ID=self peer_names --cwd "$SANDBOX/repo-a")"
assert_eq "toplevel names each peer's checkout" \
  "$SANDBOX/repo-a-wt" "$("$CLI" peers --cwd "$SANDBOX/repo-a" --self self | jq -r 'select(.name == "branch") | .toplevel')"
mkdir -p "$SANDBOX/plain"
assert_eq "outside a repo there are no peers" "" "$(peer_names --cwd "$SANDBOX/plain" --self self)"

echo "inbox"
echo '{"type":"main_moved","sha":"abc"}' | "$CLI" emit twin
echo '{"type":"main_moved","sha":"def"}' | "$CLI" emit twin
assert_eq "drain prints events in order" "abc,def" \
  "$("$CLI" drain twin | jq -r '.sha' | paste -sd, -)"
assert_eq "drain clears the inbox" "" "$("$CLI" drain twin)"
assert_eq "emit stamps a timestamp" "true" \
  "$(echo '{"type":"x"}' | "$CLI" emit twin; "$CLI" drain twin | jq -r 'has("ts")')"
assert_eq "emitter cannot forge the timestamp" "false" \
  "$(echo '{"type":"x","ts":"forged"}' | "$CLI" emit twin; "$CLI" drain twin | jq -r '.ts == "forged"')"
EMITS=()
for i in $(seq 1 20); do echo "{\"n\":$i}" | "$CLI" emit race & EMITS+=("$!"); done
drained="$("$CLI" drain race)"
wait "${EMITS[@]}"
drained="$drained"$'\n'"$("$CLI" drain race)"
assert_eq "no event lost when emits race a drain" "20" "$(printf '%s\n' "$drained" | grep -c '"n"')"

mkdir "$STATE/.lock"; dead_pid > "$STATE/.lock/pid"
echo '{"type":"x"}' | "$CLI" emit stale \
  && ok "lock left by a dead holder is taken over" || bad "lock left by a dead holder is taken over"
[[ ! -e "$STATE/.lock" ]] && ok "taken-over lock released" || bad "taken-over lock released"
"$CLI" drain stale >/dev/null

start_live; mkdir "$STATE/.lock"; printf '%s' "$LIVE" > "$STATE/.lock/pid"
echo '{"type":"x"}' | "$CLI" emit held 2>/dev/null \
  && bad "lock held by a live pid refuses the emit" || ok "lock held by a live pid refuses the emit"
assert_eq "live holder's lock left in place" "$LIVE" "$(cat "$STATE/.lock/pid" 2>/dev/null)"
rm -rf "$STATE/.lock"
echo '[1,2]' | "$CLI" emit twin 2>/dev/null && bad "non-object event refused" || ok "non-object event refused"

echo '{"type":"x"}' | "$CLI" emit '../evil'
[[ -f "$STATE/inbox/evil.jsonl" && ! -e "$STATE/evil.jsonl" ]] \
  && ok "session id stripped to a safe segment" || bad "session id stripped to a safe segment"

printf 'secret\n' > "$SANDBOX/target"
ln -s "$SANDBOX/target" "$STATE/inbox/trap.jsonl"
echo '{"type":"x"}' | "$CLI" emit trap 2>/dev/null
assert_eq "emit leaves a symlinked inbox untouched" "secret" "$(cat "$SANDBOX/target")"
assert_eq "drain does not read through a symlink" "" "$("$CLI" drain trap)"
[[ -L "$STATE/inbox/trap.jsonl" ]] && ok "drain leaves the symlink in place" || bad "drain leaves the symlink in place"

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
