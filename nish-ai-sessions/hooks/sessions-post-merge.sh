#!/usr/bin/env bash
# Tell every live peer in a repo that main moved, right after this session
# moved it. PostToolUse on Bash: a finished `gh pr merge`, or a `git push`
# that updates main, appends {type: main_moved, sha, from} to each peer's
# inbox. The peers act on it at their next prompt (sessions-prompt-submit.sh),
# which fetches and verifies rather than trusting the event.
#
# Only merges made by Claude sessions are seen; nothing polls the remote.
set -euo pipefail

CLI="$HOME/.claude/skills/nish-ai-sessions/bin/nish-session"

command -v jq >/dev/null || exit 0
[[ -x "$CLI" ]] || exit 0

INPUT="$(cat)"
# Every Bash call lands here, so the cheap text check runs before any parse.
case "$INPUT" in *"git"*"push"*|*"gh"*"pr"*"merge"*) ;; *) exit 0 ;; esac

IFS=$'\t' read -r SID CWD INTERRUPTED < <(printf '%s' "$INPUT" | jq -r \
  '[.session_id // "", .cwd // "", (.tool_response.interrupted // false)] | @tsv' 2>/dev/null) || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
# Defensive: PostToolUse fires on success, but an interrupted call never moved main.
[[ -n "$SID" && -n "$CWD" && -n "$CMD" && "$INTERRUPTED" != "true" ]] || exit 0

# The command is read one segment at a time (split on && || ; |), so a ship
# chain like `cd <repo> && git push origin HEAD:main && git push origin
# --delete feat` is judged by its push, and `cd` hops are followed up to that
# segment: the repo that moved is where the push ran, not the session's cwd.

# A merge moves main unless it was only queued.
merge_moves_main() { # $@ = segment words
  [[ "${1:-} ${2:-} ${3:-}" == "gh pr merge" ]] || return 1
  local word; for word in "$@"; do [[ "$word" == "--auto" ]] && return 1; done
  return 0
}

# A push moves main when a refspec names it (`main`, `HEAD:main`, `wt:main`),
# or when it is bare / `origin HEAD` from a checkout on main. Deletes and dry
# runs move nothing.
push_moves_main() { # $1 = dir  $@ = segment words
  local dir="$1"; shift
  [[ "${1:-} ${2:-}" == "git push" ]] || return 1
  shift 2
  local word refspecs=() redirect_target=0
  for word in "$@"; do
    # Redirections (`2>&1`, `>/dev/null`, `> log`) are not refspecs.
    if [[ "$redirect_target" -eq 1 ]]; then redirect_target=0; continue; fi
    case "$word" in
      *[\<\>])                  redirect_target=1; continue ;;
      *[\<\>]*)                 continue ;;
    esac
    case "$word" in
      --delete|-d|--dry-run|-n) return 1 ;;
      -*)                       ;;
      *)                        refspecs+=("$word") ;;
    esac
  done
  # The first positional is the remote. Bash 3.2 under set -u rejects an empty
  # array expansion, so the refspec loop runs only when one exists.
  if [[ ${#refspecs[@]} -gt 1 ]]; then
    for word in "${refspecs[@]:1}"; do
      word="${word#refs/heads/}"; word="${word/:refs\/heads\//:}"
      case "$word" in
        :*)          return 1 ;;
        main|*:main) return 0 ;;
      esac
    done
    [[ "${refspecs[*]:1}" == "HEAD" ]] || return 1
  fi
  [[ "$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)" == "main" ]]
}

resolve_cd() { # $1 = dir  $2 = cd target -> new dir
  local hop="${2#[\"\']}"; hop="${hop%[\"\']}"
  case "$hop" in
    ""|"~")  hop="$HOME" ;;
    "~/"*)   hop="$HOME${hop#\~}" ;;
    /*)      ;;
    *)       hop="$1/$hop" ;;
  esac
  printf '%s' "$hop"
}

REPO_DIR=""
segments="${CMD//&&/$'\n'}"; segments="${segments//||/$'\n'}"
segments="${segments//;/$'\n'}"; segments="${segments//|/$'\n'}"
dir="$CWD"; previous="$CWD"
while IFS= read -r segment; do
  read -ra words <<<"$segment" || true
  [[ ${#words[@]} -gt 0 ]] || continue
  if [[ "${words[0]}" == "cd" ]]; then
    if [[ "${words[1]:-}" == "-" ]]; then next="$previous"; else next="$(resolve_cd "$dir" "${words[1]:-}")"; fi
    [[ -d "$next" ]] && { previous="$dir"; dir="$next"; }
  elif merge_moves_main "${words[@]}" || push_moves_main "$dir" "${words[@]}"; then
    REPO_DIR="$dir"; break
  fi
done <<<"$segments"
[[ -n "$REPO_DIR" ]] || exit 0

# Advisory only: a receiver fetches before it syncs, so a stale or empty sha is fine.
SHA="$(git -C "$REPO_DIR" rev-parse -q --verify refs/remotes/origin/main 2>/dev/null || true)"
EVENT="$(jq -nc --arg sha "$SHA" --arg from "$(printf '%s' "$SID" | tr -cd 'A-Za-z0-9_-')" \
  '{type: "main_moved", sha: $sha, from: $from}')"

"$CLI" peers --cwd "$REPO_DIR" --self "$SID" 2>/dev/null | jq -r '.session_id // empty' | while IFS= read -r peer; do
  printf '%s' "$EVENT" | "$CLI" emit "$peer" 2>/dev/null || true
done
