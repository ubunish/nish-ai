---
description: Merge the current branch into main without a PR, push, and delete the branch (local + remote)
argument-hint: ""
allowed-tools: Bash(git rev-parse:*), Bash(git status:*), Bash(git remote:*), Bash(git checkout:*), Bash(git pull:*), Bash(git merge:*), Bash(git push:*), Bash(git branch:*), Bash(git ls-remote:*), Bash(git fetch:*), Bash(git rebase:*), ExitWorktree
---

Current branch: !`git rev-parse --abbrev-ref HEAD`
Working tree: !`git status --short`
Remote: !`git remote`
Git dir: !`git rev-parse --path-format=absolute --git-dir`
Common dir: !`git rev-parse --path-format=absolute --git-common-dir`

Merge the current branch into `main` without a pull request, then clean up. This is the no-PR shortcut for solo work that ended up on a branch — `nish-ai-github`'s default branch path opens a PR instead.

Run the steps in order. Stop and report immediately if any step fails — never force-push or override a failed merge.

1. **Guard branch** — if the current branch is `main`, stop: there is nothing to merge.
2. **Guard working tree** — if it is dirty (changes shown above), stop and ask me to commit or stash first.
3. **Detect remote** — if an `origin` remote exists, the repo is remote-backed; otherwise treat every `origin` step below as a no-op (local-only repo).
4. **Detect worktree** — if the git dir differs from the common dir above, this session is in a worktree: `main` is checked out in the primary checkout and cannot be checked out here. Follow **Worktree path** below instead of steps 5-9.
5. **Update main** — `git checkout main`, then `git pull --ff-only origin main` (skip the pull if local-only). If the pull is not a fast-forward, stop and report divergence.
6. **Merge** — `git merge --ff <branch>`: fast-forward when possible, merge commit otherwise.
7. **Push main** — `git push origin main` (skip if local-only).
8. **Delete local branch** — `git branch -d <branch>`: the safe delete refuses if the branch is not fully merged.
9. **Delete remote branch** — if the branch exists on `origin` (`git ls-remote --exit-code --heads origin <branch>`), run `git push origin --delete <branch>`.

**Worktree path** (remote-backed repos only; in a local-only repo, stop and say the merge has to run from the primary checkout):

1. `git fetch origin`
2. `git rebase origin/main` — on a conflict, stop and report; once it is resolved, continue from step 3. Never force-push.
3. `git push origin HEAD:main` — if rejected because `main` moved again, go back to step 1.
4. If the current branch (shown above) exists on `origin`, `git push origin --delete <branch>`.
5. `ExitWorktree` with action `remove`: it deletes the worktree and its branch. It compares against the stale local `main`, so it may refuse over commits that are already on `origin/main`. If it does, confirm with `git merge-base --is-ancestor HEAD origin/main`, then ask me before retrying with `discard_changes`. The primary checkout is never touched; its session syncs when it hears `main` moved and its tree is clean.

Report the result: which branch merged, the new `main` HEAD, and what was deleted (local, remote, worktree).
