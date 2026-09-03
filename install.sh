#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"
AGENTS_DIR="$HOME/.claude/agents"
SETTINGS_FILE="$HOME/.claude/settings.json"

# Session router: hard-dispatch via injected ruleset, not a soft pointer.
# SessionStart loads the full router body + arms a once-per-session flag;
# UserPromptSubmit consumes the flag on the first prompt to force dispatch.
RECOG_SS_CMD='bash "$HOME/.claude/skills/nish-ai-prompt-recognition/hooks/recognition-session-start.sh"'
RECOG_UP_CMD='bash "$HOME/.claude/skills/nish-ai-prompt-recognition/hooks/recognition-prompt-submit.sh"'
RECOG_SS_MARKER='recognition-session-start\.sh'
RECOG_UP_MARKER='recognition-prompt-submit\.sh'
# Category tracker: PostToolUse on Skill, records the dispatched category to a
# per-session flag the statusline reads. Matcher restricts it to Skill calls.
RECOG_CAT_CMD='bash "$HOME/.claude/skills/nish-ai-prompt-recognition/hooks/recognition-category-tracker.sh"'
RECOG_CAT_MARKER='recognition-category-tracker\.sh'
RECOG_CAT_MATCHER='Skill'

# Writing-style enforcement hooks (caveman-style: full ruleset at session start,
# one-line reminder every turn). $HOME expands at hook runtime, not now.
STYLE_SS_CMD='bash "$HOME/.claude/skills/nish-ai-writing-style/hooks/style-session-start.sh"'
STYLE_UP_CMD='bash "$HOME/.claude/skills/nish-ai-writing-style/hooks/style-prompt-submit.sh"'
STYLE_SS_MARKER='style-session-start\.sh'
STYLE_UP_MARKER='style-prompt-submit\.sh'
# Mid-turn re-anchor: PostToolUse re-injects the TERMINAL reminder after the
# tools whose results bury writing style by recency — Skill dispatch plus the
# exploration/edit tail (Bash, Read, Edit, Write, Grep, Glob) — so the model
# does not drift back to full prose between tool calls.
STYLE_PT_CMD='bash "$HOME/.claude/skills/nish-ai-writing-style/hooks/style-post-skill.sh"'
STYLE_PT_MARKER='style-post-skill\.sh'
STYLE_PT_MATCHER='Bash|Edit|Write|Read|Grep|Glob|Skill'

# Commit-format validator: PreToolUse on Bash, auto-fixes or blocks malformed git commits.
GH_VALIDATE_CMD='bash "$HOME/.claude/skills/nish-ai-github/hooks/validate-commit.sh"'
GH_VALIDATE_MARKER='validate-commit\.sh'

# github SessionStart anchor: primes the subject-only commit convention at
# session start. The base harness prompt pushes a Co-Authored-By trailer and a
# body; without this anchor Claude follows that pull and the PreToolUse
# validator strips it after the fact. This makes subject-only the default reach.
GH_SS_CMD='bash "$HOME/.claude/skills/nish-ai-github/hooks/github-session-start.sh"'
GH_SS_MARKER='github-session-start\.sh'

# uv enforcement hook: PreToolUse on Bash, blocks bare python/pip/poetry/pipenv/
# virtualenv calls and returns the uv rewrite. The skill itself is symlinked by
# install_skills (it lives at the repo root); only the hook needs registering.
UV_HOOK_CMD='bash "$HOME/.claude/skills/nish-ai-uv/hooks/uv-pretooluse.sh"'
UV_HOOK_MARKER='uv-pretooluse\.sh'

# uv SessionStart anchor: primes the python→uv mapping at session start, before
# Claude drafts a bare command. Without it the convention loads only reactively
# (on the PreToolUse block), so Claude reaches for python first and gets
# corrected. This makes uv the default reach from message one; the PreToolUse
# hook above stays as the backstop.
UV_SS_CMD='bash "$HOME/.claude/skills/nish-ai-uv/hooks/uv-session-start.sh"'
UV_SS_MARKER='uv-session-start\.sh'

# Coding-principles anchor: PreToolUse on Edit|Write, injects the build ladder
# and seven principles as additionalContext on the first source-file edit of a
# session — before the write, where the ladder can still shape it. Once per
# session; non-source files pass through silently.
CODING_HOOK_CMD='bash "$HOME/.claude/skills/nish-ai-coding/hooks/coding-pretooluse.sh"'
CODING_HOOK_MARKER='coding-pretooluse\.sh'
CODING_HOOK_MATCHER='Edit|Write'

# Statusline badge: renders the writing-style on/off state and session category.
# Unlike the hooks above, .statusLine is a single object (not a list), so it is
# set only when absent or when it still points at our script — never clobbering a
# user's own status line.
STATUSLINE_CMD='bash "$HOME/.claude/skills/nish-ai-writing-style/hooks/style-statusline.sh"'
STATUSLINE_MARKER='style-statusline\.sh'

# Code-intelligence plugin: the clangd C/C++ LSP, installed via the Claude Code
# plugin CLI. The CLI owns the marketplace clone, install record, and enable
# toggle, so we drive it rather than hand-writing plugin JSON.
PLUGIN_NAME='clangd-lsp@claude-plugins-official'
PLUGIN_MARKETPLACE='anthropics/claude-plugins-official'

# Codebase-memory MCP: a per-project knowledge-graph server, registered with
# Claude Code at user scope so every repo gets the graph tools. We install the
# static binary with --skip-config (binary only, no per-agent wiring), register
# it ourselves, and flip on auto_index. With auto_index=true a new project indexes
# on first connect and an already-indexed one refreshes through the background
# git watcher — no per-repo ceremony. Cached graphs live in ~/.cache, so nothing
# lands in the repo. Moved here from nish-setup, which now owns no memory step.
CBM_BIN="$HOME/.local/bin/codebase-memory-mcp"
CBM_MCP_NAME='codebase-memory'
CBM_INSTALL_URL='https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh'

# d2 diagram renderer: the documentation skill draws diagrams with terrastruct's
# d2, rendered to an SVG sidecar. Provisioned system-wide via the upstream
# curl-pipe installer with --tala, which drops both the d2 binary and the TALA
# layout plugin (d2plugin-tala) on PATH; the same script removes them with
# --uninstall. TALA is the architecture-tuned layout engine — closed-source and
# license-gated, it runs in evaluation mode (watermarked) until a TSTRUCT_TOKEN
# is set, which is enough for local rendering. Detection is command -v on both
# binaries — no install record to track.
D2_INSTALL_URL='https://d2lang.com/install.sh'

# Permission rules: auto-allow the tools that are safe to never prompt for.
# Merged into .permissions by set membership, so a user's own rules are preserved
# and only missing entries are added; uninstall removes exactly these.
#   Tier 1 (allow): read-only + research   Read/Grep/Glob/WebSearch/WebFetch
#   Tier 2 (allow): writes + local git     Edit/Write/git add|commit|branch|checkout|merge|rebase
#   Tier 3 (allow): read-only shell        ls/cat/pwd/which/find/head/tail/wc/file/tree
#   Tier 4 (allow): test/lint/build        npm test|run, pytest, ruff, eslint, tsc, uv run
#   Tier 5 (allow): ship                   git push, gh pr create|view|checks|merge
# Tiers 3-4 never touch the network and read project code only. Network installs
# and arbitrary remote execution (npm install, npx, uvx, pip install, ...) are
# left OFF the allow list on purpose — they pull and run remote code, so they
# keep prompting as a supply-chain guard.
#
# Tier 5 is a deliberate loosening. It started as `gh pr merge` alone, after a
# session that merged fifteen pull requests across eight repositories and was
# interrupted at every one; push and PR creation joined it once months of
# sessions showed the prompt was never the thing catching mistakes — the user
# approved every push and merge anyway. The trade is real and worth stating
# plainly: pushing and merging are outward-facing and effectively irreversible,
# and `gh pr merge --admin` bypasses a required-review branch protection. What
# makes it acceptable is that the commit gate (tests + reviewer agents) runs
# before any of these, CI gates the merge itself, and nish-ai-github forbids
# force-push and merging on red. Move an entry back off this list if the prompt
# is ever the thing catching mistakes.
#
# `git rebase` joins tier 2 on the same reasoning as the rest of local git: it
# rewrites only local history, and the reflog makes it recoverable.
#
# Nothing is denied by default — anything outside the allow list (reset --hard,
# rm -rf, ...) falls through to a normal prompt rather than a hard block. Add
# specific entries to PERM_DENY_JSON if a hard block is ever wanted.
PERM_ALLOW_JSON='["Read","Grep","Glob","WebSearch","WebFetch","Edit","Write","Bash(cd:*)","Bash(git status:*)","Bash(git diff:*)","Bash(git log:*)","Bash(git show:*)","Bash(git branch:*)","Bash(git add:*)","Bash(git commit:*)","Bash(git checkout:*)","Bash(git merge:*)","Bash(git rebase:*)","Bash(git push:*)","Bash(gh pr create:*)","Bash(gh pr view:*)","Bash(gh pr checks:*)","Bash(gh pr merge:*)","Bash(ls:*)","Bash(cat:*)","Bash(pwd)","Bash(which:*)","Bash(find:*)","Bash(head:*)","Bash(tail:*)","Bash(wc:*)","Bash(file:*)","Bash(tree:*)","Bash(npm test:*)","Bash(npm run:*)","Bash(pytest:*)","Bash(ruff:*)","Bash(eslint:*)","Bash(tsc:*)","Bash(uv run:*)"]'
PERM_DENY_JSON='[]'

require_jq() {
  command -v jq >/dev/null || { echo "jq required (brew install jq)" >&2; exit 1; }
}

find_skills() {
  find "$REPO_DIR" -name SKILL.md \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -print0 | while IFS= read -r -d '' f; do
      local dir p
      dir="$(dirname "$f")"
      # Skip skills inside a nested git repo (vendored/reference clones, e.g. a
      # caveman/ checkout dropped in for comparison). Walk ancestors up to
      # REPO_DIR; if any holds its own .git, the skill is not ours to install.
      p="$dir"
      while [[ "$p" != "$REPO_DIR" && "$p" != "/" ]]; do
        [[ -e "$p/.git" ]] && continue 2
        p="$(dirname "$p")"
      done
      printf '%s\n' "$dir"
    done
}

find_commands() {
  [[ -d "$REPO_DIR/commands" ]] || return 0
  find "$REPO_DIR/commands" -maxdepth 1 -name '*.md' -type f
}

find_agents() {
  [[ -d "$REPO_DIR/agents" ]] || return 0
  find "$REPO_DIR/agents" -maxdepth 1 -name '*.md' -type f
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
  add_hook PostToolUse     "$STYLE_PT_CMD" "$STYLE_PT_MARKER" "writing-style PostToolUse re-anchor" "$STYLE_PT_MATCHER"
}

uninstall_style_hooks() {
  remove_hook SessionStart     "$STYLE_SS_MARKER" "writing-style SessionStart hook"
  remove_hook UserPromptSubmit "$STYLE_UP_MARKER" "writing-style UserPromptSubmit hook"
  remove_hook PostToolUse      "$STYLE_PT_MARKER" "writing-style PostToolUse re-anchor"
}

status_style_hooks() {
  if [[ ! -f "$SETTINGS_FILE" ]] || ! command -v jq >/dev/null; then
    printf "  %-10s writing-style hooks (cannot verify)\n" "unknown"
    return
  fi
  local ev mk
  for pair in "SessionStart:$STYLE_SS_MARKER" "UserPromptSubmit:$STYLE_UP_MARKER" "PostToolUse:$STYLE_PT_MARKER"; do
    ev="${pair%%:*}"; mk="${pair##*:}"
    if hook_installed_for "$ev" "$mk"; then
      printf "  %-10s writing-style hook (%s)\n" "installed" "$ev"
    else
      printf "  %-10s writing-style hook (%s)\n" "missing" "$ev"
    fi
  done
}

install_github_hook() {
  add_hook PreToolUse   "$GH_VALIDATE_CMD" "$GH_VALIDATE_MARKER" "commit-format validator" "Bash"
  add_hook SessionStart "$GH_SS_CMD"       "$GH_SS_MARKER"       "github SessionStart anchor"
}

uninstall_github_hook() {
  remove_hook PreToolUse   "$GH_VALIDATE_MARKER" "commit-format validator"
  remove_hook SessionStart "$GH_SS_MARKER"       "github SessionStart anchor"
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
  if hook_installed_for SessionStart "$GH_SS_MARKER"; then
    printf "  %-10s github SessionStart anchor (SessionStart)\n" "installed"
  else
    printf "  %-10s github SessionStart anchor (SessionStart)\n" "missing"
  fi
}

install_uv_hook() {
  add_hook PreToolUse  "$UV_HOOK_CMD" "$UV_HOOK_MARKER" "uv enforcement hook" "Bash"
  add_hook SessionStart "$UV_SS_CMD"  "$UV_SS_MARKER"   "uv SessionStart anchor"
}

uninstall_uv_hook() {
  remove_hook PreToolUse   "$UV_HOOK_MARKER" "uv enforcement hook"
  remove_hook SessionStart "$UV_SS_MARKER"   "uv SessionStart anchor"
}

status_uv_hook() {
  if [[ ! -f "$SETTINGS_FILE" ]] || ! command -v jq >/dev/null; then
    printf "  %-10s uv enforcement hook (cannot verify)\n" "unknown"
    return
  fi
  if hook_installed_for PreToolUse "$UV_HOOK_MARKER"; then
    printf "  %-10s uv enforcement hook (PreToolUse)\n" "installed"
  else
    printf "  %-10s uv enforcement hook (PreToolUse)\n" "missing"
  fi
  if hook_installed_for SessionStart "$UV_SS_MARKER"; then
    printf "  %-10s uv SessionStart anchor (SessionStart)\n" "installed"
  else
    printf "  %-10s uv SessionStart anchor (SessionStart)\n" "missing"
  fi
}

statusline_installed() {
  [[ -f "$SETTINGS_FILE" ]] || return 1
  jq -e --arg m "$STATUSLINE_MARKER" \
    '(.statusLine.command? // "") | test($m)' "$SETTINGS_FILE" >/dev/null
}

install_statusline() {
  require_jq
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  [[ -f "$SETTINGS_FILE" ]] || echo '{}' > "$SETTINGS_FILE"
  if statusline_installed; then
    echo "  skip   statusline badge (already installed)"
    return
  fi
  # .statusLine is a single object: only set it when absent. A status line that
  # points elsewhere is the user's own — never clobber it.
  if jq -e 'has("statusLine")' "$SETTINGS_FILE" >/dev/null; then
    echo "  skip   statusline badge (custom .statusLine present, not ours)"
    return
  fi
  local tmp; tmp="$(mktemp)"
  jq --arg cmd "$STATUSLINE_CMD" \
    '.statusLine = {"type": "command", "command": $cmd}' \
    "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  echo "  add    statusline badge -> $SETTINGS_FILE"
}

uninstall_statusline() {
  [[ -f "$SETTINGS_FILE" ]] || { echo "  skip   statusline badge (no settings file)"; return; }
  require_jq
  if ! statusline_installed; then
    echo "  skip   statusline badge (not ours)"
    return
  fi
  local tmp; tmp="$(mktemp)"
  jq 'del(.statusLine)' "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  echo "  remove statusline badge"
}

status_statusline() {
  if [[ ! -f "$SETTINGS_FILE" ]] || ! command -v jq >/dev/null; then
    printf "  %-10s statusline badge (cannot verify)\n" "unknown"
    return
  fi
  if statusline_installed; then
    printf "  %-10s statusline badge (statusLine)\n" "installed"
  elif jq -e 'has("statusLine")' "$SETTINGS_FILE" >/dev/null; then
    printf "  %-10s statusline badge (custom .statusLine, not ours)\n" "conflict"
  else
    printf "  %-10s statusline badge (statusLine)\n" "missing"
  fi
}

plugin_installed() {
  command -v claude >/dev/null || return 1
  claude plugin list 2>/dev/null | grep -q "$PLUGIN_NAME"
}

# True when the user has explicitly disabled the plugin in settings
# (enabledPlugins["<name>"] == false). An explicit disable is a user decision
# the installer must not override — install skips instead of re-enabling.
plugin_disabled_by_user() {
  [[ -f "$SETTINGS_FILE" ]] || return 1
  command -v jq >/dev/null || return 1
  jq -e --arg p "$PLUGIN_NAME" '.enabledPlugins[$p] == false' "$SETTINGS_FILE" >/dev/null 2>&1
}

install_plugin() {
  if ! command -v claude >/dev/null; then
    echo "  skip   $PLUGIN_NAME (claude CLI not found)"
    return
  fi
  if plugin_disabled_by_user; then
    echo "  skip   $PLUGIN_NAME (disabled in settings; remove the enabledPlugins false entry to reinstall)"
    return
  fi
  if plugin_installed; then
    echo "  skip   $PLUGIN_NAME (already installed)"
    return
  fi
  claude plugin marketplace add "$PLUGIN_MARKETPLACE" >/dev/null 2>&1 || true  # idempotent
  if claude plugin install "$PLUGIN_NAME" >/dev/null 2>&1; then
    echo "  add    $PLUGIN_NAME"
  else
    echo "  fail   $PLUGIN_NAME (claude plugin install failed)"
  fi
}

uninstall_plugin() {
  if ! command -v claude >/dev/null; then
    echo "  skip   $PLUGIN_NAME (claude CLI not found)"
    return
  fi
  if ! plugin_installed; then
    echo "  skip   $PLUGIN_NAME (not installed)"
    return
  fi
  if claude plugin uninstall "$PLUGIN_NAME" >/dev/null 2>&1; then
    echo "  remove $PLUGIN_NAME"
  else
    echo "  fail   $PLUGIN_NAME (claude plugin uninstall failed)"
  fi
}

status_plugin() {
  if ! command -v claude >/dev/null; then
    printf "  %-10s %s (claude CLI not found)\n" "unknown" "$PLUGIN_NAME"
    return
  fi
  if plugin_disabled_by_user; then
    printf "  %-10s %s (user-disabled in settings)\n" "disabled" "$PLUGIN_NAME"
  elif plugin_installed; then
    printf "  %-10s %s\n" "installed" "$PLUGIN_NAME"
  else
    printf "  %-10s %s\n" "missing" "$PLUGIN_NAME"
  fi
}

# Installed only when both the d2 binary and the TALA plugin are present, so a
# box with d2 but no TALA still upgrades on the next install run.
d2_installed() {
  command -v d2 >/dev/null && command -v d2plugin-tala >/dev/null
}

install_d2() {
  if d2_installed; then
    echo "  skip   d2 binary (already installed)"
    return
  fi
  if ! command -v curl >/dev/null; then
    echo "  skip   d2 binary (curl not found)"
    return
  fi
  if curl -fsSL "$D2_INSTALL_URL" | sh -s -- --tala >/dev/null 2>&1; then
    echo "  add    d2 binary (with TALA)"
  else
    echo "  fail   d2 binary (install script failed)"
  fi
}

uninstall_d2() {
  if ! d2_installed; then
    echo "  skip   d2 binary (not installed)"
    return
  fi
  if ! command -v curl >/dev/null; then
    echo "  skip   d2 binary (curl not found)"
    return
  fi
  if curl -fsSL "$D2_INSTALL_URL" | sh -s -- --tala --uninstall >/dev/null 2>&1; then
    echo "  remove d2 binary (with TALA)"
  else
    echo "  fail   d2 binary (uninstall script failed)"
  fi
}

status_d2() {
  if command -v d2 >/dev/null; then
    tala="without TALA"
    command -v d2plugin-tala >/dev/null && tala="with TALA"
    printf "  %-10s d2 binary (%s, %s)\n" "installed" "$(d2 --version 2>/dev/null | head -1)" "$tala"
  else
    printf "  %-10s d2 binary\n" "missing"
  fi
}

cbm_registered() {
  command -v claude >/dev/null || return 1
  claude mcp list 2>/dev/null | grep -q "^${CBM_MCP_NAME}:"
}

install_memory() {
  # Binary first, idempotent. --skip-config installs the binary only; we wire
  # Claude Code ourselves below rather than let the upstream installer touch
  # every agent it auto-detects.
  if [[ -x "$CBM_BIN" ]]; then
    echo "  skip   codebase-memory binary (already installed)"
  elif ! command -v curl >/dev/null; then
    echo "  skip   codebase-memory binary (curl not found)"
    return
  elif curl -fsSL "$CBM_INSTALL_URL" | bash -s -- --skip-config >/dev/null 2>&1; then
    echo "  add    codebase-memory binary"
  else
    echo "  fail   codebase-memory binary (install script failed)"
    return
  fi

  # Register at user scope so all projects see the graph tools.
  if ! command -v claude >/dev/null; then
    echo "  skip   codebase-memory mcp (claude CLI not found)"
    return
  fi
  if cbm_registered; then
    echo "  skip   codebase-memory mcp (already registered)"
  elif claude mcp add --scope user "$CBM_MCP_NAME" "$CBM_BIN" >/dev/null 2>&1; then
    echo "  add    codebase-memory mcp (user scope)"
  else
    echo "  fail   codebase-memory mcp (claude mcp add failed)"
  fi

  # auto_index: new projects index on first connect, existing ones refresh via
  # the background git watcher. Idempotent.
  if "$CBM_BIN" config set auto_index true >/dev/null 2>&1; then
    echo "  set    auto_index=true"
  else
    echo "  fail   auto_index (config set failed)"
  fi
}

uninstall_memory() {
  if cbm_registered; then
    claude mcp remove --scope user "$CBM_MCP_NAME" >/dev/null 2>&1 || true
    echo "  remove codebase-memory mcp"
  else
    echo "  skip   codebase-memory mcp (not registered)"
  fi
  # Reset auto_index before removing the binary — reset needs the binary to run.
  if [[ -x "$CBM_BIN" ]]; then
    "$CBM_BIN" config reset auto_index >/dev/null 2>&1 || true
    rm -f "$CBM_BIN"
    echo "  remove codebase-memory binary"
  else
    echo "  skip   codebase-memory binary (not installed)"
  fi
  # Cached graphs in ~/.cache/codebase-memory-mcp/ are left in place.
}

status_memory() {
  if [[ -x "$CBM_BIN" ]]; then
    printf "  %-10s codebase-memory binary (%s)\n" "installed" "$("$CBM_BIN" --version 2>/dev/null | head -1)"
  else
    printf "  %-10s codebase-memory binary\n" "missing"
  fi
  if ! command -v claude >/dev/null; then
    printf "  %-10s codebase-memory mcp (claude CLI not found)\n" "unknown"
  elif cbm_registered; then
    printf "  %-10s codebase-memory mcp (user scope)\n" "registered"
  else
    printf "  %-10s codebase-memory mcp\n" "missing"
  fi
  if [[ -x "$CBM_BIN" ]]; then
    local ai
    ai="$("$CBM_BIN" config list 2>/dev/null | awk '/auto_index /{print $3}')"
    if [[ "$ai" == "true" ]]; then
      printf "  %-10s auto_index=true\n" "set"
    else
      printf "  %-10s auto_index=%s\n" "missing" "${ai:-false}"
    fi
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

install_commands() {
  local cmds; cmds="$(find_commands)"
  [[ -n "$cmds" ]] || { echo "commands: 0 to link"; return; }
  mkdir -p "$COMMANDS_DIR"
  local count=0
  while IFS= read -r src; do
    [[ -n "$src" ]] || continue
    local name target backup
    name="$(basename "$src")"
    target="$COMMANDS_DIR/$name"

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
  done <<< "$cmds"
  echo "commands: $count linked"
}

uninstall_commands() {
  local count=0
  while IFS= read -r src; do
    [[ -n "$src" ]] || continue
    local name target
    name="$(basename "$src")"
    target="$COMMANDS_DIR/$name"
    if [[ -L "$target" && "$(readlink "$target")" == "$src" ]]; then
      rm "$target"
      echo "  unlink $name"
      count=$((count + 1))
    fi
  done <<< "$(find_commands)"
  echo "commands: $count unlinked"
}

status_commands() {
  while IFS= read -r src; do
    [[ -n "$src" ]] || continue
    local name target state
    name="$(basename "$src")"
    target="$COMMANDS_DIR/$name"
    if [[ -L "$target" && "$(readlink "$target")" == "$src" ]]; then
      state="linked"
    elif [[ -e "$target" || -L "$target" ]]; then
      state="conflict"
    else
      state="missing"
    fi
    printf "  %-10s %s\n" "$state" "$name"
  done <<< "$(find_commands)"
}

install_agents() {
  local agents; agents="$(find_agents)"
  [[ -n "$agents" ]] || { echo "agents: 0 to link"; return; }
  mkdir -p "$AGENTS_DIR"
  local count=0
  while IFS= read -r src; do
    [[ -n "$src" ]] || continue
    local name target backup
    name="$(basename "$src")"
    target="$AGENTS_DIR/$name"

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
  done <<< "$agents"
  echo "agents: $count linked"
}

uninstall_agents() {
  local count=0
  while IFS= read -r src; do
    [[ -n "$src" ]] || continue
    local name target
    name="$(basename "$src")"
    target="$AGENTS_DIR/$name"
    if [[ -L "$target" && "$(readlink "$target")" == "$src" ]]; then
      rm "$target"
      echo "  unlink $name"
      count=$((count + 1))
    fi
  done <<< "$(find_agents)"
  echo "agents: $count unlinked"
}

status_agents() {
  while IFS= read -r src; do
    [[ -n "$src" ]] || continue
    local name target state
    name="$(basename "$src")"
    target="$AGENTS_DIR/$name"
    if [[ -L "$target" && "$(readlink "$target")" == "$src" ]]; then
      state="linked"
    elif [[ -e "$target" || -L "$target" ]]; then
      state="conflict"
    else
      state="missing"
    fi
    printf "  %-10s %s\n" "$state" "$name"
  done <<< "$(find_agents)"
}

install_recognition_hooks() {
  add_hook SessionStart     "$RECOG_SS_CMD" "$RECOG_SS_MARKER" "router SessionStart hook"
  add_hook UserPromptSubmit "$RECOG_UP_CMD" "$RECOG_UP_MARKER" "router UserPromptSubmit hook"
  add_hook PostToolUse      "$RECOG_CAT_CMD" "$RECOG_CAT_MARKER" "category tracker hook" "$RECOG_CAT_MATCHER"
}

uninstall_recognition_hooks() {
  remove_hook SessionStart     "$RECOG_SS_MARKER" "router SessionStart hook"
  remove_hook UserPromptSubmit "$RECOG_UP_MARKER" "router UserPromptSubmit hook"
  remove_hook PostToolUse      "$RECOG_CAT_MARKER" "category tracker hook"
}

status_recognition_hooks() {
  if [[ ! -f "$SETTINGS_FILE" ]] || ! command -v jq >/dev/null; then
    printf "  %-10s router hooks (cannot verify)\n" "unknown"
    return
  fi
  local ev mk
  for pair in "SessionStart:$RECOG_SS_MARKER" "UserPromptSubmit:$RECOG_UP_MARKER" "PostToolUse:$RECOG_CAT_MARKER"; do
    ev="${pair%%:*}"; mk="${pair##*:}"
    if hook_installed_for "$ev" "$mk"; then
      printf "  %-10s router hook (%s)\n" "installed" "$ev"
    else
      printf "  %-10s router hook (%s)\n" "missing" "$ev"
    fi
  done
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

permissions_installed() {
  [[ -f "$SETTINGS_FILE" ]] || return 1
  jq -e --argjson a "$PERM_ALLOW_JSON" --argjson d "$PERM_DENY_JSON" '
    (($a - (.permissions.allow // [])) | length) == 0
    and (($d - (.permissions.deny // [])) | length) == 0
  ' "$SETTINGS_FILE" >/dev/null
}

install_permissions() {
  require_jq
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  [[ -f "$SETTINGS_FILE" ]] || echo '{}' > "$SETTINGS_FILE"
  if permissions_installed; then
    echo "  skip   permission rules (already present)"
    return
  fi
  # Append only the entries we don't already have, preserving existing order and
  # any rules the user added themselves.
  local tmp; tmp="$(mktemp)"
  jq --argjson a "$PERM_ALLOW_JSON" --argjson d "$PERM_DENY_JSON" '
    .permissions //= {}
    | .permissions.allow = ((.permissions.allow // []) + ($a - (.permissions.allow // [])))
    | .permissions.deny  = ((.permissions.deny  // []) + ($d - (.permissions.deny  // [])))
  ' "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  echo "  add    permission rules -> $SETTINGS_FILE"
}

uninstall_permissions() {
  [[ -f "$SETTINGS_FILE" ]] || { echo "  skip   permission rules (no settings file)"; return; }
  require_jq
  # Remove exactly our entries; leave user-added rules and drop now-empty keys.
  local tmp; tmp="$(mktemp)"
  jq --argjson a "$PERM_ALLOW_JSON" --argjson d "$PERM_DENY_JSON" '
    if .permissions then
      .permissions.allow = ((.permissions.allow // []) - $a)
      | .permissions.deny  = ((.permissions.deny  // []) - $d)
      | (if (.permissions.allow // []) == [] then del(.permissions.allow) else . end)
      | (if (.permissions.deny  // []) == [] then del(.permissions.deny)  else . end)
      | (if (.permissions // {}) == {} then del(.permissions) else . end)
    else . end
  ' "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  echo "  remove permission rules"
}

status_permissions() {
  if [[ ! -f "$SETTINGS_FILE" ]] || ! command -v jq >/dev/null; then
    printf "  %-10s permission rules (cannot verify)\n" "unknown"
    return
  fi
  local miss
  miss="$(jq -r --argjson a "$PERM_ALLOW_JSON" --argjson d "$PERM_DENY_JSON" \
    '(($a - (.permissions.allow // [])) + ($d - (.permissions.deny // []))) | length' \
    "$SETTINGS_FILE")"
  if [[ "$miss" == "0" ]]; then
    printf "  %-10s permission rules (allow+deny)\n" "installed"
  elif jq -e 'has("permissions")' "$SETTINGS_FILE" >/dev/null; then
    printf "  %-10s permission rules (%s entries absent)\n" "partial" "$miss"
  else
    printf "  %-10s permission rules (allow+deny)\n" "missing"
  fi
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

install_coding_hook() {
  add_hook PreToolUse "$CODING_HOOK_CMD" "$CODING_HOOK_MARKER" "coding-principles anchor" "$CODING_HOOK_MATCHER"
}

uninstall_coding_hook() {
  remove_hook PreToolUse "$CODING_HOOK_MARKER" "coding-principles anchor"
}

status_coding_hook() {
  if [[ ! -f "$SETTINGS_FILE" ]] || ! command -v jq >/dev/null; then
    printf "  %-10s coding-principles anchor (cannot verify)\n" "unknown"
    return
  fi
  if hook_installed_for PreToolUse "$CODING_HOOK_MARKER"; then
    printf "  %-10s coding-principles anchor (PreToolUse)\n" "installed"
  else
    printf "  %-10s coding-principles anchor (PreToolUse)\n" "missing"
  fi
}

cmd_install() {
  install_skills
  install_commands
  install_agents
  install_recognition_hooks
  install_style_hooks
  install_github_hook
  install_uv_hook
  install_coding_hook
  install_statusline
  install_plugin
  install_d2
  install_memory
  install_auto_memory
  install_permissions
}

cmd_uninstall() {
  uninstall_skills
  uninstall_commands
  uninstall_agents
  uninstall_recognition_hooks
  uninstall_style_hooks
  uninstall_github_hook
  uninstall_uv_hook
  uninstall_coding_hook
  uninstall_statusline
  uninstall_plugin
  uninstall_d2
  uninstall_memory
  uninstall_auto_memory
  uninstall_permissions
}

cmd_status() {
  status_skills
  status_commands
  status_agents
  status_recognition_hooks
  status_style_hooks
  status_github_hook
  status_uv_hook
  status_coding_hook
  status_statusline
  status_plugin
  status_d2
  status_memory
  status_auto_memory
  status_permissions
}

case "${1:-install}" in
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  -h|--help|help) echo "usage: $0 {install|uninstall|status}" ;;
  *) echo "unknown: $1" >&2; echo "usage: $0 {install|uninstall|status}" >&2; exit 1 ;;
esac
