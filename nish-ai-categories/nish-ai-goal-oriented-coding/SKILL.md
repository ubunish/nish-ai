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
| Pre-commit gate (test + reviewer subagents) | `think` |
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

The `/execute` slash command runs this same workflow on the latest `plans/*.md` without the confirm step — it executes on sight and stops only when the plan is already done. Use it to skip the manual dispatch and "Proceed?" gate.

1. **Load plan**: read the latest `plans/YYYY-MM-DD-PLAN.md`
2. **Confirm**: announce `Plan loaded: <title>, <N> steps, <M> commits. Proceed?` and wait for approval
3. **Branch**: create working branch using the plan's overall prefix and title slug (per `nish-ai-github`)
4. **Dependency analysis**: from the plan's diagram + step descriptions, identify which steps are independent and which depend on earlier steps
5. **Execute** (loop):
   - Before the first step: invoke `nish-ai-coding` (Skill tool) so the build
     ladder and seven principles load before any code is written — the ladder
     governs what to build, so loading it after the fact defeats it
   - Independent step group → spawn `Agent` subagents in parallel; each
     subagent prompt names the build ladder and seven principles (subagents do
     not inherit this session's loaded skills)
   - Dependent step → execute sequentially after its dependencies finish
   - Per step: write code under `nish-ai-coding` rules
6. **Pre-commit gate** (per step):
   - Run the project's test command — must pass
   - **Spawn `nish-ai-code-reviewer`** (an `Agent` subagent, fresh context) on the staged diff — every commit, no exceptions. A reviewer with no attachment to how the code was written catches residue the writer's own context hides. It replaces inline principle review.
   - **Detect security signals** in the staged diff: auth/authz, secrets or env handling, network calls, file-path construction, untrusted input, crypto. Any present → also **spawn `nish-ai-security-reviewer`** on the diff. No signal → skip it.
   - **Act on severity**:
     - any **high** finding → blocks the commit. Fix it, then re-spawn the same reviewer on the new diff. Repeat until no high findings remain.
     - **low** findings → surface as a note to the user; do not block.
   - Validate the step's planned commit message against `nish-ai-github` format (lowercase prefix, imperative, no body)
   - If the test command fails, fix before committing; do NOT commit broken state
7. **Commit**: invoke `nish-ai-github`, then commit with the step's declared message from the plan
8. **Loop** until all steps complete
9. **Assert the work is still local**: run the check below and read its output.
   The session never claims "done", "shipped", or "merged" — the work is
   unpushed by design, and the handoff must say so in those words.

   ```bash
   git rev-parse --abbrev-ref @{u} 2>/dev/null || echo "NO UPSTREAM — branch never pushed"
   git cherry -v main HEAD | grep -c '^+' || true
   ```

   Report both numbers verbatim in the handoff. A status or session-summary
   file written afterwards states *committed locally on `<branch>`*, never
   *pushed* or *merged*, unless a `git push` in this session actually
   succeeded and its output is in the transcript.

10. **Handoff**: post the plan's Test Plan checklist and say:

    ```
    <N> commits on <branch>, local only — nothing pushed, nothing merged.
    Run the test plan, then push + merge:

    <checklist from plan>
    ```

11. **Stop**. User pushes, opens PR if needed, merges.

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

## Output Style (Recency Anchor)

This section sits last on purpose: after dispatch it is the freshest part of the skill body, so task voice cannot displace house style. Every user-facing line this session — chat replies, explanations, and one-line tool preambles ("let me check…", "reading X…") — follows `nish-ai-writing-style` TERMINAL mode: no a/an/the, fragments over full sentences, self-check each line before sending. Committed prose (docs/README/comments/commit messages) uses DOCS mode instead.
