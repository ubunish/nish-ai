---
description: Merge the current branch into main without a PR, push, and delete the branch (local + remote)
argument-hint: ""
allowed-tools: Bash(git rev-parse:*), Bash(git status:*), Bash(git remote:*), Bash(git checkout:*), Bash(git pull:*), Bash(git merge:*), Bash(git push:*), Bash(git branch:*), Bash(git ls-remote:*)
---

Current branch: !`git rev-parse --abbrev-ref HEAD`
Working tree: !`git status --short`
Remote: !`git remote`

Merge the current branch into `main` without a pull request, then clean up. This is the no-PR shortcut for solo work that ended up on a branch — `nish-ai-github`'s default branch path opens a PR instead.

Run the steps in order. Stop and report immediately if any step fails — never force-push or override a failed merge.

1. **Guard branch** — if the current branch is `main`, stop: there is nothing to merge.
2. **Guard working tree** — if it is dirty (changes shown above), stop and ask me to commit or stash first.
3. **Detect remote** — if an `origin` remote exists, the repo is remote-backed; otherwise treat every `origin` step below as a no-op (local-only repo).
4. **Update main** — `git checkout main`, then `git pull --ff-only origin main` (skip the pull if local-only). If the pull is not a fast-forward, stop and report divergence.
5. **Merge** — `git merge --ff <branch>`: fast-forward when possible, merge commit otherwise.
6. **Push main** — `git push origin main` (skip if local-only).
7. **Delete local branch** — `git branch -d <branch>`: the safe delete refuses if the branch is not fully merged.
8. **Delete remote branch** — if the branch exists on `origin` (`git ls-remote --exit-code --heads origin <branch>`), run `git push origin --delete <branch>`.

Report the result: which branch merged, the new `main` HEAD, and what was deleted (local, remote, or both).
