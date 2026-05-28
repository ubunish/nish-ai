---
name: nish-ai-prompt-recognition
description: >
  Nish's session router. Fires ONCE on the first substantive prompt of a
  session to determine its direction. Categorizes into one of five tracks,
  announces the choice, dispatches to the matching skill — which then runs
  for the rest of the session. Do NOT re-invoke unless user explicitly asks
  to re-categorize.
---

## Categories

| ID | Category | Maps To | Skill |
|----|----------|---------|-------|
| A | Project Planning | (no commit, produces plan) | `nish-ai-project-planning` |
| B | User Question | (no commit) | `nish-ai-user-question` |
| C | Goal-Oriented Coding | `feat` / `fix` / `refactor` | `nish-ai-goal-oriented-coding` |
| D | Documentation | `docs` | `nish-ai-documentation` |
| E | Quick Task | `chore` | `nish-ai-quick-task` |

## Decision Rule

1. Match first prompt to the commit prefix it would produce (or "no commit" for A/B)
2. Pick the narrowest category that fits
3. If two or more tie, ask user before dispatching
4. One category per session

## Output Format

Before dispatching, announce in one line:

```
Session category: <name> → invoking <skill>
```

Then call the skill. If asking due to a tie:

```
Ambiguous between <X> and <Y>. Which?
```

## Lifetime

- Fires once, on the first substantive prompt of a session
- Dispatched skill stays active for the rest of the session
- Does NOT re-fire on subsequent prompts
- Re-invoke only if user says "re-categorize" or session direction explicitly pivots
