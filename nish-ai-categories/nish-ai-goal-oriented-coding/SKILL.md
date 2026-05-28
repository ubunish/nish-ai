---
name: nish-ai-goal-oriented-coding
description: >
  Nish's goal-oriented coding workflow. Invoked by nish-ai-prompt-recognition
  when the session's first prompt is to build a feature, fix a bug, or
  refactor (Category C). Requires a pre-existing plan in plans/. Executes
  the plan: branch → parallel work on independent steps → test + coding-
  principle review → sequential commits → user handoff for test + push +
  merge. Does NOT plan inline.
---

## Thinking

| Phase | Keyword |
|-------|---------|
| Load plan + confirm | `think` |
| Dependency analysis | `think` |
| Code-writing inside a step | none |
| Pre-commit gate (test + principle review) | `think` |
| Commit + handoff | none |

Inject the keyword at the start of the response that opens the phase. Drop it once the phase is done.

## Prerequisite

A plan must exist at `plans/YYYY-MM-DD-PLAN.md` (latest if multiple).

If no plan exists, stop and tell the user:

```
No plan found in plans/. Start a planning session first (will dispatch to nish-ai-project-planning).
```

## Workflow

```
read plan → confirm with user → branch → execute steps → test + commit per step → handoff to user
```

1. **Load plan**: read the latest `plans/YYYY-MM-DD-PLAN.md`
2. **Confirm**: announce `Plan loaded: <title>, <N> steps, <M> commits. Proceed?` and wait for approval
3. **Branch**: create working branch using the plan's overall prefix and title slug (per `nish-ai-github`)
4. **Dependency analysis**: from the plan's diagram + step descriptions, identify which steps are independent and which depend on earlier steps
5. **Execute** (loop):
   - Independent step group → spawn `Agent` subagents in parallel
   - Dependent step → execute sequentially after its dependencies finish
   - Per step: write code (with `nish-ai-coding` auto-active)
6. **Pre-commit gate** (per step):
   - Run the project's test command — must pass
   - Explicitly invoke `nish-ai-coding` for principle review of the changes
   - If either fails, fix before committing; do NOT commit broken state
7. **Commit**: use the step's declared commit message from the plan
8. **Loop** until all steps complete
9. **Handoff**: post the plan's Test Plan checklist and say:

   ```
   All steps committed locally. Run the test plan, then push + merge:

   <checklist from plan>
   ```

10. **Stop**. User pushes, opens PR if needed, merges.

## Parallel Execution Rules

- Parallel work happens at the *agent* level: independent steps run as concurrent `Agent` subagent calls in a single message
- Commits remain sequential on the branch — Claude waits for all parallel agents in a group to finish, then commits in plan order
- A step group is independent if no step in the group reads or writes state produced by another step in the group

## Scope Drift

If mid-execution the work no longer matches the plan:

1. Pause execution
2. Announce: `Scope shift detected: <what changed>. Update plan before continuing?`
3. Wait for user direction
4. If user updates the plan, re-read it before resuming

Do NOT commit work that is not in the plan.

## Lifetime

Session-active after dispatch by `nish-ai-prompt-recognition`. Persists until all plan steps are committed and handoff message is posted. Then waits for user — does not auto-push or auto-merge.
