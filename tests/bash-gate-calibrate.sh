#!/usr/bin/env bash
# Opt-in calibration for the bash gate's `risky` question. Unlike the other
# suites this one calls the live Jev API — one request per case — so it is not
# part of the normal test run and spends real requests.
#
# Each line of tests/fixtures/bash-gate-cases.tsv is `label<TAB>command`, where
# label is `safe` (the gate should stay quiet) or `risky` (it should ask), and
# `\n` in the command stands for a newline. The command is judged from this
# repo, so the origin allowlist applies as it does live.
#
# Prints every case with its probability, then the highest `safe` score and the
# lowest `risky` score. The threshold in hooks/bash-gate.sh belongs in the gap
# between the two; choosing it is a human decision.
#
# Run: ./tests/bash-gate-calibrate.sh   (needs TYPESAFE_API_KEY)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JEV="$REPO_DIR/nish-ai-jev/jev"
QUESTIONS="$REPO_DIR/nish-ai-jev/hooks/bash-gate.json"
CASES="$REPO_DIR/tests/fixtures/bash-gate-cases.tsv"
# Longer than the hook's 1.5 s: a slow answer here is still a score, not a fallback.
TIMEOUT=5

command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }
[[ -n "${TYPESAFE_API_KEY:-}" ]] || { echo "TYPESAFE_API_KEY not set" >&2; exit 1; }

BRANCH="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)"
max_safe=0
min_risky=1

while IFS=$'\t' read -r label command; do
  [[ -n "$label" ]] || continue
  command="$(printf '%b' "$command")"
  risk="$(jq -nc --arg c "$command" --arg d "$REPO_DIR" --arg b "$BRANCH" \
      '{command: $c, cwd: $d, branch: $b}' \
    | (cd "$REPO_DIR" && "$JEV" --timeout "$TIMEOUT" "$QUESTIONS") 2>/dev/null \
    | jq -r '.risky.noul // empty' 2>/dev/null)"
  if [[ -z "$risk" ]]; then
    printf '%-5s  error  %s\n' "$label" "$(head -n1 <<<"$command" | cut -c1-70)"
    continue
  fi
  printf '%-5s  %-5s  %s\n' "$label" "$risk" "$(head -n1 <<<"$command" | cut -c1-70)"
  if [[ "$label" == safe ]]; then
    max_safe="$(jq -n --argjson a "$max_safe" --argjson b "$risk" '[$a, $b] | max')"
  else
    min_risky="$(jq -n --argjson a "$min_risky" --argjson b "$risk" '[$a, $b] | min')"
  fi
done < "$CASES"

echo
echo "highest safe: $max_safe  lowest risky: $min_risky"
