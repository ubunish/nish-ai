#!/usr/bin/env bash
# Portable test runner for the reviewer agent layer. No bats dependency —
# plain bash assertions, matching tests/run.sh and tests/uv.sh.
#
# Covers two things:
#   frontmatter — every agents/*.md declares name, description, model: haiku,
#                 and read-only tools (Read/Grep/Glob only).
#   install     — install.sh links agents/*.md into ~/.claude/agents/, status
#                 reports them linked, uninstall removes them. Driven against a
#                 throwaway HOME so the real environment is untouched.
#
# Run: ./tests/agents.sh   (exits non-zero if any assertion fails)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_SRC="$REPO_DIR/agents"
INSTALL="$REPO_DIR/install.sh"

command -v jq >/dev/null || { echo "jq required for tests" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }

# Extract the YAML frontmatter block (between the first two --- fences).
frontmatter() { # $1 = file
  awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$1"
}
# Read a scalar frontmatter key's value (single-line values only).
fm_value() { # $1 = file  $2 = key
  frontmatter "$1" | grep -E "^$2:" | head -n1 | sed -E "s/^$2:[[:space:]]*//"
}

echo "frontmatter"
shopt -s nullglob
agent_files=("$AGENTS_SRC"/*.md)
[[ ${#agent_files[@]} -gt 0 ]] || bad "agents present" "no agents/*.md found"

for f in "${agent_files[@]}"; do
  base="$(basename "$f" .md)"
  fm="$(frontmatter "$f")"

  # name matches the filename stem
  name="$(fm_value "$f" name)"
  [[ "$name" == "$base" ]] && ok "$base: name matches filename" \
    || bad "$base: name matches filename" "name=[$name]"

  # description present
  printf '%s' "$fm" | grep -qE '^description:' \
    && ok "$base: has description" || bad "$base: has description"

  # model is haiku
  [[ "$(fm_value "$f" model)" == "haiku" ]] \
    && ok "$base: model is haiku" || bad "$base: model is haiku"

  # tools are read-only: Read/Grep/Glob present, no write-capable tool
  tools="$(fm_value "$f" tools)"
  if printf '%s' "$tools" | grep -qE '\bRead\b' \
     && ! printf '%s' "$tools" | grep -qE '\b(Write|Edit|NotebookEdit|Bash)\b'; then
    ok "$base: tools read-only"
  else
    bad "$base: tools read-only" "tools=[$tools]"
  fi
done

echo "install / status / uninstall"
# Throwaway HOME so we never touch the real ~/.claude. A stub `claude` on PATH
# keeps the plugin step offline and instant (no marketplace, no network).
TMPHOME="$(mktemp -d)"
STUBBIN="$(mktemp -d)"
mkdir -p "$TMPHOME/.claude"
cat > "$STUBBIN/claude" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$STUBBIN/claude"

run_install() { # $1 = subcommand
  HOME="$TMPHOME" PATH="$STUBBIN:$PATH" bash "$INSTALL" "$1" 2>/dev/null
}

# install → each agent is a symlink back to the repo source
run_install install >/dev/null
for f in "${agent_files[@]}"; do
  name="$(basename "$f")"
  link="$TMPHOME/.claude/agents/$name"
  if [[ -L "$link" && "$(readlink "$link")" == "$f" ]]; then
    ok "install links $name"
  else
    bad "install links $name" "link target=[$(readlink "$link" 2>/dev/null)]"
  fi
done

# status → reports them linked
status_out="$(run_install status)"
for f in "${agent_files[@]}"; do
  name="$(basename "$f")"
  printf '%s' "$status_out" | grep -qE "linked .*$name" \
    && ok "status shows $name linked" || bad "status shows $name linked"
done

# uninstall → links removed
run_install uninstall >/dev/null
for f in "${agent_files[@]}"; do
  name="$(basename "$f")"
  link="$TMPHOME/.claude/agents/$name"
  [[ ! -e "$link" && ! -L "$link" ]] \
    && ok "uninstall removes $name" || bad "uninstall removes $name"
done

rm -rf "$TMPHOME" "$STUBBIN"

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
