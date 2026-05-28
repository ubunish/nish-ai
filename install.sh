#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
SETTINGS_FILE="$HOME/.claude/settings.json"

HOOK_CMD='echo '\''{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Session router active. Invoke the nish-ai-prompt-recognition skill on the first substantive user prompt of this session to categorize and dispatch."}}'\'''
HOOK_MARKER='nish-ai-prompt-recognition'

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

cmd_install() {
  install_skills
  install_hook
}

cmd_uninstall() {
  uninstall_skills
  uninstall_hook
}

cmd_status() {
  status_skills
  status_hook
}

case "${1:-install}" in
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  -h|--help|help) echo "usage: $0 {install|uninstall|status}" ;;
  *) echo "unknown: $1" >&2; echo "usage: $0 {install|uninstall|status}" >&2; exit 1 ;;
esac
