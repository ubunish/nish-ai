---
name: nish-ai-github
description: >
  Nish's git conventions: commit format, branch naming, PR structure, and
  the planned-commit workflow. Use whenever creating commits, branches, or
  pull requests. Commits are pre-planned and user-approved before execution.
  Claude commits locally only — user pushes, opens PRs, and merges.
---

## Format

`prefix: short phrase` — lowercase prefix, no body, imperative phrase.

No body. No trailers. No `Co-Authored-By` unless the user explicitly asks. Subject line only.

A `PreToolUse` hook enforces this on every `git commit`. A body or `Co-Authored-By` trailer is stripped automatically — the commit is rewritten to subject-only and runs as-is, keeping any `git add … &&` prefix so staging is not lost. Only violations the hook cannot safely fix (bad prefix, capitalized subject, trailing period) are denied.

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

Commits are planned, not improvised. Claude stops at the local commit.

```
plan drafted → commits listed in plan → user approves → Claude branches + commits → user pushes, opens PR, merges
```

Claude does:
- Create branch
- Commit at planned boundaries with planned messages
- Pause and update the plan if scope shifts mid-execution

Claude does NOT (unless explicitly asked):
- Push to remote
- Open pull requests
- Merge branches

## Branches

`main` — canonical, finished, merged.

Working branches: `prefix/short-phrase` using the same prefix set.

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

Used when Claude is explicitly asked to draft or open a PR. Default flow is user-driven.

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

## Direct Merge (`/merge`)

The default flow stops at the local commit — Claude does not push or merge. The `/merge` command is the explicit, user-invoked exception: it merges the current branch straight into `main` without a pull request and cleans up.

Use it for solo, low-risk work where a PR adds no value. For anything reviewed or shared, open a PR instead.

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
