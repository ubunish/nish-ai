#!/usr/bin/env bash
# PreToolUse(Bash) enforcement for nish-ai-uv.
#
# Blocks bare python/pip/poetry/pipenv/virtualenv calls and returns the uv
# rewrite in the deny message, so Claude reissues the uv form. Matches only the
# command's leading program — a clean rewrite of an arbitrary mid-chain call is
# not safe, so compound commands with python buried in the middle pass through.
#
# Skips (allows the call unchanged) when:
#   - jq is absent — cannot parse the tool input.
#   - the bypass marker ~/.claude/.uv-off exists — set by "drop uv".
#   - $VIRTUAL_ENV is set — the venv's own python is legitimate.
#   - the command already starts with `uv`.
#   - the command is a conda invocation.
set -euo pipefail

INPUT="$(cat)"
command -v jq >/dev/null || exit 0

# Bypass marker wins over everything: "drop uv" turns the hook off for the session.
[[ -f "$HOME/.claude/.uv-off" ]] && exit 0

# Inside an active venv, a bare `python` is the venv's interpreter — leave it be.
[[ -n "${VIRTUAL_ENV:-}" ]] && exit 0

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"
[[ -z "$CMD" ]] && exit 0

# Leading program + the rest of the command, with surrounding whitespace trimmed.
TRIMMED="${CMD#"${CMD%%[![:space:]]*}"}"   # strip leading whitespace
PROG="${TRIMMED%%[[:space:]]*}"            # first token
REST="${TRIMMED#"$PROG"}"
REST="${REST#"${REST%%[![:space:]]*}"}"    # rest, leading whitespace stripped

# Already uv, or conda — nothing to do.
[[ "$PROG" == "uv" ]] && exit 0
[[ "$PROG" == "conda" ]] && exit 0

deny() { # $1 = suggested uv command
  local reason
  reason="nish-ai-uv: prefer uv over $PROG. Run instead:

  $1"
  jq -n --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

case "$PROG" in
  python|python3|python[0-9]|python[0-9].[0-9]*)
    if [[ -z "$REST" ]]; then
      deny "uv run python"                       # bare REPL
    elif [[ "$REST" == "-m venv "* || "$REST" == "-m venv" ]]; then
      args="${REST#-m venv}"                     # python -m venv .venv → uv venv .venv
      args="${args#"${args%%[![:space:]]*}"}"    # strip the leading space left behind
      deny "uv venv $args"
    elif [[ "$REST" == "-m "* ]]; then
      deny "uv run -m ${REST#-m }"               # python -m mod → uv run -m mod
    else
      deny "uv run $REST"                         # python script.py → uv run script.py
    fi
    ;;
  pip|pip3)
    deny "uv pip $REST"                           # pip install X → uv pip install X
    ;;
  poetry)
    case "$REST" in
      add\ *)   deny "uv add ${REST#add }" ;;     # poetry add X → uv add X
      install*) deny "uv sync" ;;                 # poetry install → uv sync
      *)        deny "the uv equivalent (uv add / uv sync / uv remove)" ;;
    esac
    ;;
  pipenv)
    case "$REST" in
      install\ *) deny "uv add ${REST#install }" ;;  # pipenv install X → uv add X
      install)    deny "uv sync" ;;                  # pipenv install → uv sync
      *)          deny "the uv equivalent (uv add / uv sync / uv remove)" ;;
    esac
    ;;
  virtualenv)
    deny "uv venv $REST"                          # virtualenv .venv → uv venv .venv
    ;;
esac

exit 0   # not a targeted program — allow.
