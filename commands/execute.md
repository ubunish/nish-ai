---
description: Auto-execute the most recent plan in plans/ — no confirm gate, stop only if the plan is already done
argument-hint: "[plan-path]"
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Task
---

Latest plan: !`ls -t plans/*.md 2>/dev/null | head -1`
Current branch: !`git rev-parse --abbrev-ref HEAD`
Working tree: !`git status --short`
Recent commits: !`git log --oneline -10`

Execute a plan automatically. This is the no-confirm path: the `nish-ai-goal-oriented-coding` "confirm with user / Proceed?" step is **removed here**. The invocation is the approval — run on sight.

Plan to execute: the file in `$ARGUMENTS` if a path is given, otherwise the latest `plans/*.md` shown above.

1. **Load the plan.** Read it fully.
2. **Already-done guard.** Before any work, check whether the plan is already implemented — its deliverable files exist with the described changes, and its commits already appear in the git history above. If the plan is clearly already achieved, **STOP and report** — re-running is almost certainly a mistake. Do not branch, do not commit.
3. **Execute** per `nish-ai-goal-oriented-coding`: branch (plan prefix + title slug) → dependency analysis → independent steps in parallel via `Agent`, dependent steps sequentially → per-step pre-commit gate (project tests must pass, spawn `nish-ai-code-reviewer` on the staged diff every commit, add `nish-ai-security-reviewer` when the diff touches a security surface) → sequential commits in plan order using each step's declared message.
4. **No confirm gate.** Do not ask "Proceed?" — skip straight from load + guard into execution.
5. **Handoff.** Post the plan's Test Plan checklist. User pushes, opens any PR, merges.

Commit format follows `nish-ai-github` (lowercase prefix, imperative, no body). Each commit boundary verifies `nish-ai-coding` principles.
