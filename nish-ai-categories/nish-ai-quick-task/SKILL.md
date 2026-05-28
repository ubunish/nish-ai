---
name: nish-ai-quick-task
description: >
  Nish's quick-task / chore skill. Invoked by nish-ai-prompt-recognition
  when the session's first prompt is light-touch housekeeping (Category E,
  `chore` commit prefix): dep bumps, file moves, gitignore/config edits,
  one-line bash operations. Vanilla Claude mode — no plan, no commit gate.
  Auto-active skills (nish-ai-writing-style, nish-ai-coding if code is
  touched) still apply. User commits at their own discretion.
---

## Scope

Light-touch housekeeping. Common cases:

- Dep bumps (`npm update`, `pip install -U`, etc.)
- File moves and renames
- `.gitignore`, `.editorconfig`, formatter / linter config edits
- One-line bash operations the user wants run

## Mode

Vanilla Claude. Do the task, report the result. No plan, no commit workflow, no pre-commit gate.

What still applies (because auto-active):
- `nish-ai-writing-style` — terse responses
- `nish-ai-coding` — if the chore involves writing code

What does NOT apply:
- `nish-ai-project-planning` — no plan file
- `nish-ai-goal-oriented-coding` — no branch, no commit per step, no handoff ceremony
- `nish-ai-github` commit workflow — user commits at their own discretion

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
