---
name: nish-ai-quick-task
description: >
  Nish's quick-task / chore skill. Invoked by nish-ai-prompt-recognition
  when the session's first prompt is light-touch housekeeping (Category E,
  `chore` commit prefix): dep bumps, file moves, gitignore/config edits,
  one-line bash operations. Vanilla Claude mode — no plan, no commit gate.
  nish-ai-writing-style still applies; if the chore touches source code,
  invoke nish-ai-coding first. User commits at their own discretion.
---

## Thinking

None. Chores are mechanical. Do not inject thinking keywords. If a chore turns out to need reasoning, that signals a re-categorization, not a thinking bump.

## Scope

Light-touch housekeeping. Common cases:

- Dep bumps (`npm update`, `pip install -U`, etc.)
- File moves and renames
- `.gitignore`, `.editorconfig`, formatter / linter config edits
- One-line bash operations the user wants run

## Mode

Vanilla Claude. Do the task, report the result. No plan, no commit workflow, no pre-commit gate.

What still applies:
- `nish-ai-writing-style` — terse responses (hook-injected, always on)
- `nish-ai-coding` — if the chore involves writing or editing source code,
  invoke it (Skill tool) BEFORE the first edit; the PreToolUse anchor is a
  backstop, not the primary path

What does NOT apply:
- `nish-ai-project-planning` — no plan file
- `nish-ai-goal-oriented-coding` — no branch, no commit per step, no handoff ceremony
- `nish-ai-github` planning ceremony — no pre-planned commits, no working branch; user commits at their own discretion. Format rules (prefix, phrasing, no body) still apply when a commit is made.

## Execution

- Run commands directly via `Bash` when the action is clearly safe and reversible (dep bump, file rename, config edit)
- For destructive or ambiguous commands (e.g. `rm -rf`, force-push), show the command and ask before running
- Report what was done in one line

## Re-Categorize Triggers

If the session escalates beyond a chore (e.g. user starts asking for a feature, refactor, or planning), pause and announce:

```
Session direction shifted: chore → <category>. Re-categorize? (was: Quick Task)
```

Wait for user confirmation before re-invoking `nish-ai-prompt-recognition`.

## Lifetime

Session-active after dispatch by `nish-ai-prompt-recognition`. Persists until session ends or user explicitly re-categorizes.

## Output Style (Recency Anchor)

This section sits last on purpose: after dispatch it is the freshest part of the skill body, so task voice cannot displace house style. Every user-facing line this session — chat replies, explanations, and one-line tool preambles ("let me check…", "reading X…") — follows `nish-ai-writing-style` TERMINAL mode: no a/an/the, fragments over full sentences, self-check each line before sending. Committed prose (docs/README/comments/commit messages) uses DOCS mode instead.
