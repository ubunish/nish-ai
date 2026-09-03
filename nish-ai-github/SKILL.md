---
name: nish-ai-github
description: >
  Nish's git conventions: commit format, branch naming, PR structure, and
  the planned-commit workflow. Use whenever creating commits, branches, or
  pull requests. Commits are pre-planned and user-approved before execution.
  Claude commits and pushes. Personal repos work straight on main; a branch
  and PR are used only when the plan or the user asks for one. Claude merges
  its own PRs once CI is green, with admin bypass when a review rule is the
  only thing in the way.
---

## Format

`prefix: short phrase` — lowercase prefix, no body, imperative phrase.

No body. No trailers. No `Co-Authored-By` unless the user explicitly asks. Subject line only.

A `SessionStart` hook primes this convention from message one, so subject-only is the default reach rather than a correction — countering the base harness prompt, which asks for a `Co-Authored-By: Claude` trailer and a body. A `PreToolUse` hook backstops it on every `git commit`: a body or `Co-Authored-By` trailer that slips through is stripped automatically — the commit is rewritten to subject-only and runs as-is, keeping any `git add … &&` prefix so staging is not lost. Only violations the hook cannot safely fix (bad prefix, capitalized subject, trailing period) are denied.

| Prefix | Use |
|--------|-----|
| `init` | First commit of a new repo. Extends to the first few while bootstrapping, never after |
| `feat` | New feature, page, or content |
| `fix` | Bug fix or content correction |
| `docs` | Documentation edits that are not fixes |
| `refactor` | Restructure without changing meaning or behavior |
| `chore` | Housekeeping: gitignore, deps, file moves |

Pick the narrowest prefix that fits. If a change spans two, split the commit.

## Commits

Examples:
- `feat: add search bar`
- `fix: login redirect on expired token`
- `refactor: extract auth middleware`
- `chore: bump tailwind to v4`

Not:
- `feat: Added a Search Bar.` (capital, past tense, period)
- `update: stuff` (vague, non-standard prefix)

## Workflow

Commits are planned, not improvised. Claude carries the work through to the remote.

```
plan drafted → commits listed in plan → user approves → Claude commits → Claude pushes
                                                                      └→ (branch) PR → CI green → merge
```

Claude does:
- Commit at planned boundaries with planned messages
- Push after the last planned commit (and after any commit the user asks to ship)
- On a branch: open the PR, wait for checks, merge, delete the branch
- Pause and update the plan if scope shifts mid-execution

Claude does NOT (unless explicitly asked):
- Force-push, or rewrite history that is already on the remote
- Merge on red or pending CI
- Push work that is outside the plan

Admin bypass (`gh pr merge --admin`) is allowed when a required-review rule is
the only blocker — solo repos have no second reviewer. It is never used to get
past a failing check.

## Branches

`main` — canonical, finished, merged. Personal repos work directly on `main`:
no branch, no PR, commit then push.

A working branch is created only when the plan names one, the user asks, or
the repo's own `CONTRIBUTING.md` requires PR-only `main` (First Motive repos
do). Working branches: `prefix/short-phrase` using the same prefix set.

Examples:
- `feat/add-search-bar`
- `fix/login-redirect`
- `refactor/extract-auth`
- `chore/bump-tailwind`

Rules:
- Lowercase, hyphen-separated
- No `:` or spaces (invalid in git)
- Short — branch name is not a description

## Pull Requests

Used whenever work sits on a branch. Claude opens the PR, watches checks, and merges.

```
git push -u origin <branch>
  → gh pr create --title "<prefix: short phrase>" --body-file <body>
  → gh pr checks --watch
  → green: gh pr merge --squash --delete-branch (add --admin only for a review rule)
  → red:   stop, report the failing check, do not merge
```

Title: same format as a commit. `prefix: short phrase`.

Body:

```markdown
## Summary
- <1-3 bullets, why over what>

## Test Plan
- [ ] <verifiable check>
- [ ] <verifiable check>
```

Rules:
- Summary explains motivation, not file-by-file diff
- Test plan is a checklist, not prose
- One PR per branch, one concern per PR
- No attribution footer — the base harness prompt asks for a "Generated with
  Claude Code" line in PR bodies; this convention overrides it, same as the
  commit-trailer ban. Add it only when the user explicitly asks.

## Direct Merge (`/merge`)

The `/merge` command merges the current branch straight into `main` without a pull request and cleans up. Use it for solo, low-risk work that ended up on a branch anyway. For anything reviewed or shared, open a PR instead.

```
current branch
  → checkout main + pull --ff-only
  → merge --ff (fast-forward if possible, merge commit otherwise)
  → push main
  → delete branch (local + remote)
```

Guards, in order:

- Refuses to run on `main` (nothing to merge).
- Refuses on a dirty working tree (commit or stash first).
- `git pull --ff-only` aborts on divergence rather than creating a surprise merge.
- `git branch -d` (safe delete) refuses to drop an unmerged branch.
- Remote steps are skipped when the repo has no `origin`.

Installed as a symlinked slash command via `install.sh`. The command file lives in `commands/merge.md`.
