#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
SETTINGS_FILE="$HOME/.claude/settings.json"

HOOK_CMD='echo '\''{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Session router active. Invoke the nish-ai-prompt-recognition skill on the first substantive user prompt of this session to categorize and dispatch."}}'\'''
HOOK_MARKER='nish-ai-prompt-recognition'

# Writing-style enforcement hooks (caveman-style: full ruleset at session start,
# one-line reminder every turn). $HOME expands at hook runtime, not now.
STYLE_SS_CMD='bash "$HOME/.claude/skills/nish-ai-writing-style/hooks/style-session-start.sh"'
STYLE_UP_CMD='bash "$HOME/.claude/skills/nish-ai-writing-style/hooks/style-prompt-submit.sh"'
STYLE_SS_MARKER='style-session-start\.sh'
STYLE_UP_MARKER='style-prompt-submit\.sh'

# Commit-format validator: PreToolUse on Bash, blocks malformed git commits.
GH_VALIDATE_CMD='bash "$HOME/.claude/skills/nish-ai-github/hooks/validate-commit.sh"'
GH_VALIDATE_MARKER='validate-commit\.sh'

require_jq() {
  command -v jq >/dev/null || { echo "jq required (brew install jq)" >&2; exit 1; }
}

find_skills() {
  find "$REPO_DIR" -name SKILL.md \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -print0 | xargs -0 -n1 dirname
}

hook_installed() {
  [[ -f "$SETTINGS_FILE" ]] || return 1
  jq -e --arg m "$HOOK_MARKER" \
    '(.hooks.SessionStart // []) | map(.hooks[]? | select(.command? | test($m))) | length > 0' \
    "$SETTINGS_FILE" >/dev/null
}

# Generic hook helpers, keyed by event + a command-substring marker (regex).
hook_installed_for() { # $1=event $2=marker
  [[ -f "$SETTINGS_FILE" ]] || return 1
  jq -e --arg e "$1" --arg m "$2" \
    '(.hooks[$e] // []) | map(.hooks[]? | select(.command? | test($m))) | length > 0' \
    "$SETTINGS_FILE" >/dev/null
}

add_hook() { # $1=event $2=cmd $3=marker $4=label $5=matcher(optional)
  require_jq
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  [[ -f "$SETTINGS_FILE" ]] || echo '{}' > "$SETTINGS_FILE"
  if hook_installed_for "$1" "$3"; then
    echo "  skip   $4 (already installed)"
    return
  fi
  local tmp; tmp="$(mktemp)"
  jq --arg e "$1" --arg cmd "$2" --arg mt "${5:-}" '
    .hooks //= {}
    | .hooks[$e] //= []
    | .hooks[$e] += [
        {"hooks": [{"type": "command", "command": $cmd}]}
        + (if $mt == "" then {} else {"matcher": $mt} end)
      ]
  ' "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  echo "  add    $4 -> $SETTINGS_FILE"
}

remove_hook() { # $1=event $2=marker $3=label
  [[ -f "$SETTINGS_FILE" ]] || { echo "  skip   $3 (no settings file)"; return; }
  require_jq
  if ! hook_installed_for "$1" "$2"; then
    echo "  skip   $3 (not installed)"
    return
  fi
  local tmp; tmp="$(mktemp)"
  jq --arg e "$1" --arg m "$2" '
    .hooks[$e] |= (
      map(.hooks |= map(select(.command? | test($m) | not)))
      | map(select((.hooks // []) | length > 0))
    )
    | if (.hooks[$e] // []) | length == 0 then del(.hooks[$e]) else . end
    | if (.hooks // {}) == {} then del(.hooks) else . end
  ' "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  echo "  remove $3"
}

install_style_hooks() {
  add_hook SessionStart    "$STYLE_SS_CMD" "$STYLE_SS_MARKER" "writing-style SessionStart hook"
  add_hook UserPromptSubmit "$STYLE_UP_CMD" "$STYLE_UP_MARKER" "writing-style UserPromptSubmit hook"
}

uninstall_style_hooks() {
  remove_hook SessionStart     "$STYLE_SS_MARKER" "writing-style SessionStart hook"
  remove_hook UserPromptSubmit "$STYLE_UP_MARKER" "writing-style UserPromptSubmit hook"
}

status_style_hooks() {
  if [[ ! -f "$SETTINGS_FILE" ]] || ! command -v jq >/dev/null; then
    printf "  %-10s writing-style hooks (cannot verify)\n" "unknown"
    return
  fi
  local ev mk
  for pair in "SessionStart:$STYLE_SS_MARKER" "UserPromptSubmit:$STYLE_UP_MARKER"; do
    ev="${pair%%:*}"; mk="${pair##*:}"
    if hook_installed_for "$ev" "$mk"; then
      printf "  %-10s writing-style hook (%s)\n" "installed" "$ev"
    else
      printf "  %-10s writing-style hook (%s)\n" "missing" "$ev"
    fi
  done
}

install_github_hook() {
  add_hook PreToolUse "$GH_VALIDATE_CMD" "$GH_VALIDATE_MARKER" "commit-format validator" "Bash"
}

uninstall_github_hook() {
  remove_hook PreToolUse "$GH_VALIDATE_MARKER" "commit-format validator"
}

status_github_hook() {
  if [[ ! -f "$SETTINGS_FILE" ]] || ! command -v jq >/dev/null; then
    printf "  %-10s commit-format validator (cannot verify)\n" "unknown"
    return
  fi
  if hook_installed_for PreToolUse "$GH_VALIDATE_MARKER"; then
    printf "  %-10s commit-format validator (PreToolUse)\n" "installed"
  else
    printf "  %-10s commit-format validator (PreToolUse)\n" "missing"
  fi
}

install_skills() {
  mkdir -p "$SKILLS_DIR"
  local count=0
  while IFS= read -r src; do
    local name target backup
    name="$(basename "$src")"
    target="$SKILLS_DIR/$name"

    if [[ -L "$target" && "$(readlink "$target")" == "$src" ]]; then
      echo "  skip   $name (already linked)"
    else
      if [[ -e "$target" || -L "$target" ]]; then
        backup="$target.bak-$(date +%Y%m%d-%H%M%S)"
        mv "$target" "$backup"
        echo "  backup $name -> $(basename "$backup")"
      fi
      ln -s "$src" "$target"
      echo "  link   $name"
    fi
    count=$((count + 1))
  done < <(find_skills)
  echo "skills: $count linked"
}

install_hook() {
  require_jq
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  [[ -f "$SETTINGS_FILE" ]] || echo '{}' > "$SETTINGS_FILE"

  if hook_installed; then
    echo "  skip   SessionStart hook (already installed)"
    return
  fi

  local tmp; tmp="$(mktemp)"
  jq --arg cmd "$HOOK_CMD" '
    .hooks //= {}
    | .hooks.SessionStart //= []
    | .hooks.SessionStart += [{"hooks": [{"type": "command", "command": $cmd}]}]
  ' "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  echo "  add    SessionStart hook -> $SETTINGS_FILE"
}

auto_memory_disabled() {
  [[ -f "$SETTINGS_FILE" ]] || return 1
  jq -e '.autoMemoryEnabled == false' "$SETTINGS_FILE" >/dev/null
}

install_auto_memory() {
  require_jq
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  [[ -f "$SETTINGS_FILE" ]] || echo '{}' > "$SETTINGS_FILE"

  if auto_memory_disabled; then
    echo "  skip   autoMemoryEnabled (already false)"
    return
  fi

  local tmp; tmp="$(mktemp)"
  jq '.autoMemoryEnabled = false' "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  echo "  set    autoMemoryEnabled=false -> $SETTINGS_FILE"
}

uninstall_auto_memory() {
  [[ -f "$SETTINGS_FILE" ]] || { echo "  skip   autoMemoryEnabled (no settings file)"; return; }
  require_jq

  if ! jq -e 'has("autoMemoryEnabled")' "$SETTINGS_FILE" >/dev/null; then
    echo "  skip   autoMemoryEnabled (not set)"
    return
  fi

  local tmp; tmp="$(mktemp)"
  jq 'del(.autoMemoryEnabled)' "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  echo "  remove autoMemoryEnabled"
}

uninstall_skills() {
  local count=0
  while IFS= read -r src; do
    local name target
    name="$(basename "$src")"
    target="$SKILLS_DIR/$name"
    if [[ -L "$target" && "$(readlink "$target")" == "$src" ]]; then
      rm "$target"
      echo "  unlink $name"
      count=$((count + 1))
    fi
  done < <(find_skills)
  echo "skills: $count unlinked"
}

uninstall_hook() {
  [[ -f "$SETTINGS_FILE" ]] || { echo "  skip   hook (no settings file)"; return; }
  require_jq

  if ! hook_installed; then
    echo "  skip   SessionStart hook (not installed)"
    return
  fi

  local tmp; tmp="$(mktemp)"
  jq --arg m "$HOOK_MARKER" '
    .hooks.SessionStart |= (
      map(.hooks |= map(select(.command? | test($m) | not)))
      | map(select((.hooks // []) | length > 0))
    )
    | if (.hooks.SessionStart // []) | length == 0 then del(.hooks.SessionStart) else . end
    | if (.hooks // {}) == {} then del(.hooks) else . end
  ' "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  echo "  remove SessionStart hook"
}

status_skills() {
  while IFS= read -r src; do
    local name target state
    name="$(basename "$src")"
    target="$SKILLS_DIR/$name"
    if [[ -L "$target" && "$(readlink "$target")" == "$src" ]]; then
      state="linked"
    elif [[ -e "$target" || -L "$target" ]]; then
      state="conflict"
    else
      state="missing"
    fi
    printf "  %-10s %s\n" "$state" "$name"
  done < <(find_skills)
}

status_hook() {
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    printf "  %-10s SessionStart hook (no settings file)\n" "missing"
    return
  fi
  if ! command -v jq >/dev/null; then
    printf "  %-10s SessionStart hook (jq not installed; cannot verify)\n" "unknown"
    return
  fi
  if hook_installed; then
    printf "  %-10s SessionStart hook\n" "installed"
  else
    printf "  %-10s SessionStart hook\n" "missing"
  fi
}

status_auto_memory() {
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    printf "  %-10s autoMemoryEnabled (no settings file)\n" "missing"
    return
  fi
  if ! command -v jq >/dev/null; then
    printf "  %-10s autoMemoryEnabled (jq not installed; cannot verify)\n" "unknown"
    return
  fi
  if auto_memory_disabled; then
    printf "  %-10s autoMemoryEnabled=false\n" "set"
  else
    printf "  %-10s autoMemoryEnabled\n" "missing"
  fi
}

cmd_install() {
  install_skills
  install_hook
  install_style_hooks
  install_github_hook
  install_auto_memory
}

cmd_uninstall() {
  uninstall_skills
  uninstall_hook
  uninstall_style_hooks
  uninstall_github_hook
  uninstall_auto_memory
}

cmd_status() {
  status_skills
  status_hook
  status_style_hooks
  status_github_hook
  status_auto_memory
}

case "${1:-install}" in
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  -h|--help|help) echo "usage: $0 {install|uninstall|status}" ;;
  *) echo "unknown: $1" >&2; echo "usage: $0 {install|uninstall|status}" >&2; exit 1 ;;
esac
