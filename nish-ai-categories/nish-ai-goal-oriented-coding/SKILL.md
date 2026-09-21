---
name: nish-ai-goal-oriented-coding
description: >
  Nish's goal-oriented coding workflow. Invoked by nish-ai-prompt-recognition
  when the session's first prompt is to build a feature, fix a bug, or
  refactor (Category C). Requires a pre-existing plan in plans/. Executes
  the plan: branch → parallel work on independent steps → test + coding-
  principle review → sequential commits → push (PR + merge when on a branch)
  → handoff with the test plan. Does NOT plan inline.
---

## Thinking

| Phase | Keyword |
|-------|---------|
| Load plan + confirm | `think` |
| Dependency analysis | `think` |
| Code-writing inside a step | none |
| Pre-commit gate (test + reviewer subagents) | `think` |
| Commit + ship + handoff | none |

Inject the keyword at the start of the response that opens the phase. Drop it once the phase is done.

## Prerequisite

A plan must exist at `plans/YYYY-MM-DD-PLAN.md` (latest if multiple).

If no plan exists, stop and tell the user:

```
No plan found in plans/. Start a planning session first (will dispatch to nish-ai-project-planning).
```

## Workflow

```
read plan → confirm with user → (branch) → execute steps → test + commit per step → ship → handoff to user
```

The `/execute` slash command runs this same workflow on the latest `plans/*.md` without the confirm step — it executes on sight and stops only when the plan is already done. Use it to skip the manual dispatch and "Proceed?" gate.

1. **Load plan**: read the latest `plans/YYYY-MM-DD-PLAN.md`
2. **Confirm**: announce `Plan loaded: <title>, <N> steps, <M> commits. Proceed?` and wait for approval
3. **Branch** (conditional): stay on `main` in a personal repo. Create a working branch from the plan's overall prefix and title slug (per `nish-ai-github`) only when the plan names one, the user asks, or the repo's `CONTRIBUTING.md` requires PR-only `main`.
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
6. **Pre-commit gate** (per step): see **Pre-Commit Gate** below. Tests must pass, Jev triages the staged diff, and the reviewers spawn on what the triage says is worth reviewing.
7. **Commit**: invoke `nish-ai-github`, then commit with the step's declared message from the plan
8. **Loop** until all steps complete
9. **Ship** (per `nish-ai-github`):
   - On `main`: `git push`.
   - On a branch: `git push -u origin <branch>` → `gh pr create` → `gh pr checks --watch` → green: `gh pr merge --squash --delete-branch` (`--admin` only for a review rule) → red: stop, report the failing check, leave the PR open.
   - Never force-push. Never merge red.

10. **Assert the remote state**: run the check below and read its output before writing the handoff.

    ```bash
    git status -sb | head -1          # "## main...origin/main" with no [ahead N] means pushed
    git log --oneline -1 origin/HEAD 2>/dev/null || git log --oneline -1 @{u}
    ```

    The handoff says *pushed* or *merged* only when the matching `git push` or `gh pr merge` succeeded in this session and its output is in the transcript. Otherwise it says exactly where the work stopped.

11. **Handoff**: post the plan's Test Plan checklist and say one of:

    ```
    <N> commits pushed to main (<short sha>). Run the test plan:

    <checklist from plan>
    ```

    ```
    <N> commits on <branch>, PR #<n> merged into main. Run the test plan:

    <checklist from plan>
    ```

    ```
    <N> commits on <branch>, PR #<n> open — CI red on <check>. Not merged.

    <checklist from plan>
    ```

12. **Stop**.

## Pre-Commit Gate

The gate runs once per step, on the staged diff, before the commit.

```
tests pass → jev triage (one call, 14 questions)
               ├─ every security noul < 0.3 ──────────────── no security reviewer
               │  any noul ≥ 0.3 ──────────────────────────→ nish-ai-security-reviewer (surfaces named)
               ├─ all 7 principles top level + confident ─── skip the code reviewer, log the skip
               └─ otherwise ──────────────────────────────→ nish-ai-code-reviewer (weakest principles as focus)
                                                             ↓
                                       high findings block · low findings are a note
```

### 1. Tests

Run the project's test command. It must pass. A failing test is fixed before the commit; broken state is never committed.

### 2. Triage

Send the staged diff to Jev. One call answers all fourteen questions:

```bash
git diff --cached | "$HOME/.claude/skills/nish-ai-jev/jev" --timeout 10 \
  "$HOME/.claude/skills/nish-ai-goal-oriented-coding/jev/gate.json"
```

`gate.json` holds six security Nouls (auth, secrets, network, paths, untrusted input, crypto), seven principle Scores on levels 0-3, and a Choice over the commit prefix.

**A non-zero exit is not a pass.** Fallback here means the gate behaves as it did before Jev existed: the code reviewer spawns, and the security reviewer spawns if the diff looks like it touches a security surface.

### 3. Security Reviewer

Any security Noul at or above **0.3** spawns `nish-ai-security-reviewer` on the staged diff, with the surfaces that crossed the threshold named in its prompt. The threshold is deliberately low: a missed security review costs more than a wasted one.

### 4. Code Reviewer, Or A Logged Skip

`nish-ai-code-reviewer` spawns unless **every** one of these holds:

- The Jev call succeeded
- All seven principle Scores are at the top level — `score ≥ 2.5`
- Every one of those seven answers has `confidence ≥ 0.7`
- Every security Noul is below 0.3

Any one of them failing spawns the reviewer. When it spawns, the two lowest-scoring principles go into its prompt as focus, so a fresh reviewer starts where the diff is weakest.

Every skip is logged, so the rule can be checked against reality later:

```bash
jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg repo "$(git remote get-url origin 2>/dev/null)" \
  --arg diff_sha "$(git diff --cached | shasum -a 256 | cut -d' ' -f1)" \
  --argjson answers "$answers" \
  '{ts: $ts, repo: $repo, diff_sha: $diff_sha, answers: $answers}' \
  >> "$HOME/.claude/nish-ai-jev-skips.jsonl"
```

Spot-check the log when a bug reaches `main`: find the commit's diff hash, and read what the gate believed about it.

### 5. Act On Findings

- Any **high** finding blocks the commit. Fix it, then re-spawn the same reviewer on the new diff. Repeat until no high findings remain.
- **Low** findings are surfaced to the user as a note; they do not block.

### 6. Commit Message

Validate the step's planned message against `nish-ai-github` format (lowercase prefix, imperative, no body). Where the triage's prefix Choice disagrees with the plan's declared prefix, the plan wins — say so in one line rather than silently changing it.

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

Session-active after dispatch by `nish-ai-prompt-recognition`. Persists until all plan steps are committed, shipped, and the handoff message is posted. Then waits for the user.

## Output Style (Recency Anchor)

This section sits last on purpose: after dispatch it is the freshest part of the skill body, so task voice cannot displace house style. Every user-facing line this session — chat replies, explanations, and one-line tool preambles ("let me check…", "reading X…") — follows `nish-ai-writing-style` TERMINAL mode: no a/an/the, fragments over full sentences, self-check each line before sending. Committed prose (docs/README/comments/commit messages) uses DOCS mode instead.
