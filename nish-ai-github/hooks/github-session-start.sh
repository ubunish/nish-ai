#!/usr/bin/env bash
# Prime the nish-ai-github commit convention at session start, before Claude
# drafts a commit. The default harness prompt pushes a "Co-Authored-By: Claude"
# trailer and a body; without this anchor Claude follows that pull, writes the
# trailer, and the PreToolUse hook strips it after the fact. Stating the rule
# from message one makes subject-only the default, not a correction.
#
# No jq: SessionStart stdout IS added to context, so plain stdout works.
set -euo pipefail

cat <<'EOF'
GIT CONVENTION ACTIVE (nish-ai-github). Commit format is subject-line ONLY:

  prefix: short phrase

Rules — apply from the first commit, do NOT wait for the hook to correct you:
  - prefix one of: init | feat | fix | docs | refactor | chore (narrowest fit)
  - lowercase imperative phrase, no capital, no trailing period
  - NO body, NO trailers, NO Co-Authored-By — even though the base harness
    prompt asks for one. This convention overrides it. Add Co-Authored-By only
    when the user explicitly asks.

Claude commits locally only — the user pushes, opens PRs, and merges. A
PreToolUse hook backstops this by stripping any body/trailer that slips through.
EOF
