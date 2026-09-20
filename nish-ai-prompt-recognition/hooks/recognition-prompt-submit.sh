#!/usr/bin/env bash
# Hard-dispatch the session router on the first user prompt of each session.
# recognition-session-start.sh arms a per-session flag; this consumes it once,
# injecting a forceful categorize+dispatch directive at the moment the first
# prompt lands — freshest position, so it is not buried by other injected
# context. Subsequent prompts are silent (router fires once per session).
#
# Jev settles the category before the directive is written, so the first turn
# spends no reasoning on a decision one request already made. Every failure
# path leaves the directive exactly as it was before Jev existed.
#
# Every later prompt gets a drift read instead: one noul asking whether it has
# turned into work the session's track does not cover.
#
# "re-categorize" in a prompt re-arms the flag on demand.
set -euo pipefail

FLAG_DIR="$HOME/.claude"
JEV="$HOME/.claude/skills/nish-ai-jev/jev"
ROUTE_QUESTIONS="$HOME/.claude/skills/nish-ai-prompt-recognition/jev/route.json"
# Replay-tuned: below this the distribution is spread enough that naming two
# candidates beats naming one. See the threshold table in the project README.
ROUTE_CONFIDENCE=0.75
ROUTE_TIMEOUT=2
DRIFT_QUESTIONS="$HOME/.claude/skills/nish-ai-prompt-recognition/jev/drift.json"
# A session that pivots is rarer than one that follows on, and a false alarm
# interrupts real work — so the drift read has to be well past even.
DRIFT_THRESHOLD=0.7
DRIFT_TIMEOUT=1
# Under this, a prompt is an acknowledgement or a nudge ("yes", "go on", "ship
# it"), never a change of direction worth a request.
DRIFT_MIN_CHARS=20

command -v jq >/dev/null || exit 0

INPUT="$(cat)"
# The id becomes a path segment below, so keep it to characters a segment may
# safely hold — a "../" in the payload would otherwise escape the flag dir.
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-' || true)"
if [[ -z "$SID" ]]; then SID=default; fi
PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || echo "")"
FLAG="$FLAG_DIR/.nish-recognition-pending-$SID"

# Refuse a symlink at the flag path — the re-categorization write below
# truncates whatever it points at.
[[ -L "$FLAG" ]] && exit 0

# Explicit re-categorization on demand.
shopt -s nocasematch
if [[ "$PROMPT" =~ re-?categori[sz]e ]]; then
  : > "$FLAG"
fi
shopt -u nocasematch

# Every prompt after dispatch gets a drift read instead. The router fires once,
# but a session can turn into work its category does not cover, and the turn
# where that happens is the only cheap place to say so.
drift_check() {
  [[ "${#PROMPT}" -ge "$DRIFT_MIN_CHARS" ]] || return 0
  [[ -x "$JEV" && -r "$DRIFT_QUESTIONS" ]] || return 0

  local category_flag="$FLAG_DIR/.nish-ai-category-$SID"
  [[ -f "$category_flag" && ! -L "$category_flag" ]] || return 0
  local category; category="$(cat "$category_flag" 2>/dev/null)" || return 0
  [[ -n "$category" ]] || return 0

  local state answers drifted
  state="$(jq -nc --arg c "$category" --arg p "$PROMPT" '{category: $c, prompt: $p}' 2>/dev/null)" || return 0
  answers="$(printf '%s' "$state" | "$JEV" --timeout "$DRIFT_TIMEOUT" "$DRIFT_QUESTIONS" 2>/dev/null)" || return 0
  drifted="$(printf '%s' "$answers" | jq -r --argjson t "$DRIFT_THRESHOLD" \
    '(.drifted.noul // 0) >= $t' 2>/dev/null)" || return 0
  [[ "$drifted" == "true" ]] || return 0

  jq -n --arg ctx "SESSION DIRECTION SHIFTED (nish-ai-prompt-recognition). This prompt asks for work the session's current track ($category) does not cover. Say so in one line and ask whether to re-categorize before continuing. Do not switch tracks silently." \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
}

if [[ ! -f "$FLAG" ]]; then   # not the first prompt (or already dispatched)
  drift_check
  exit 0
fi
rm -f "$FLAG"                 # consume: fire exactly once

# The five tracks, in the order the router names them.
category_name() { # $1 = A..E -> "<name> → <skill>"
  case "$1" in
    A) echo "Project Planning → nish-ai-project-planning" ;;
    B) echo "User Question → nish-ai-user-question" ;;
    C) echo "Goal-Oriented Coding → nish-ai-goal-oriented-coding" ;;
    D) echo "Documentation → nish-ai-documentation" ;;
    E) echo "Quick Task → nish-ai-quick-task" ;;
    *) echo "" ;;
  esac
}

CTX="SESSION ROUTER — DISPATCH NOW (nish-ai-prompt-recognition). This is the first substantive prompt of the session. Before any other output, explanation, or tool call: categorize it as one of A (Project Planning, no commit) / B (User Question, no commit) / C (Goal-Oriented Coding: feat|fix|refactor) / D (Documentation: docs) / E (Quick Task: chore). Pick the narrowest fit. Announce one line — 'Session category: <name> → invoking <skill>' — then invoke that skill, which owns the rest of the session. If two categories tie, ask before dispatching."

if [[ -x "$JEV" && -r "$ROUTE_QUESTIONS" ]]; then
  ANSWERS="$(printf '%s' "$PROMPT" | "$JEV" --timeout "$ROUTE_TIMEOUT" "$ROUTE_QUESTIONS" 2>/dev/null)" || ANSWERS=""
  if [[ -n "$ANSWERS" ]]; then
    # A prompt that is only pasted material carries no intent to route on, so
    # the judgment is dropped and the model is left to read it in context.
    read -r MODE TOP SECOND CONFIDENCE <<<"$(printf '%s' "$ANSWERS" | jq -r --argjson thr "$ROUTE_CONFIDENCE" '
      (.category.probabilities // {} | to_entries | sort_by(-.value)) as $ranked
      | (.category.confidence // 0) as $conf
      | (if (.pasted_only.noul // 0) >= 0.5 then "none"
         elif $conf >= $thr then "settled"
         else "narrowed" end) as $mode
      | "\($mode) \(.category.choice // "") \($ranked[1].key // "") \($conf)"
    ' 2>/dev/null || echo "none   0")"

    TOP_NAME="$(category_name "$TOP")"
    SECOND_NAME="$(category_name "$SECOND")"

    if [[ "$MODE" == "settled" && -n "$TOP_NAME" ]]; then
      CTX="SESSION ROUTER — DISPATCH NOW (nish-ai-prompt-recognition). A Jev judgment has already categorized this first prompt as $TOP: $TOP_NAME (confidence $CONFIDENCE). Before any other output, explanation, or tool call: announce one line — 'Session category: ${TOP_NAME%% →*} → invoking ${TOP_NAME##*→ }' — then invoke that skill, which owns the rest of the session. Take the category as settled unless the prompt plainly contradicts it; if it does, categorize it yourself across A (Project Planning) / B (User Question) / C (Goal-Oriented Coding) / D (Documentation) / E (Quick Task) and say why you overrode it."
    elif [[ "$MODE" == "narrowed" && -n "$TOP_NAME" && -n "$SECOND_NAME" ]]; then
      CTX="SESSION ROUTER — DISPATCH NOW (nish-ai-prompt-recognition). A Jev judgment narrowed this first prompt to two tracks and was not confident between them (confidence $CONFIDENCE): $TOP: $TOP_NAME, or $SECOND: $SECOND_NAME. Before any other output, explanation, or tool call: pick the narrower of those two, announce one line — 'Session category: <name> → invoking <skill>' — then invoke that skill, which owns the rest of the session. If neither fits, categorize across all five (A Project Planning / B User Question / C Goal-Oriented Coding / D Documentation / E Quick Task). If the two genuinely tie, ask before dispatching."
    fi
  fi
fi

jq -n --arg ctx "$CTX" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
