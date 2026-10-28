---
description: Answer yes or no — can this session be closed safely, without losing work or anything the user needs to know
argument-hint: ""
allowed-tools: Bash(git status:*), Bash(git log:*), Bash(git stash list:*), Bash(ls:*), Read
---

Latest plan: !`ls -t plans/*.md 2>/dev/null | head -1`
Working tree: !`git status --short 2>/dev/null || echo "n/a (not a git repo)"`
Nested repos: !`find . -mindepth 2 -maxdepth 2 -name .git 2>/dev/null | sed "s|^\./||; s|/\.git$||"`
Unpushed: !`git log --oneline @{u}..HEAD 2>/dev/null || echo "n/a (no repo or no upstream)"`
Stashes: !`git stash list 2>/dev/null || echo "n/a (not a git repo)"`

Answer one question: can the user close this session now and lose nothing? This is a read only. Do not start, finish or change any work.

The session is closeable when its goal is met and nothing exists only in this conversation:

| Session was… | Goal is met when |
|--------------|------------------|
| Planning | The plan file is written to `plans/` |
| Executing a plan | Every step is committed and pushed, or merged, with nothing left running |
| Answering a question | The answer was given |
| A quick task or docs | The change is made, and committed if the user asked for a commit |

It is **not** closeable when any of these holds:

- An item the goal needs is unfinished
- Changes are uncommitted or commits are unpushed, and they were meant to land
- A background task, agent or CI run is still going and its result matters
- Something the user must act on or know about (a failing test, a bug found, a decision deferred, a risk) was only said in chat and is not in a plan, issue or backlog file

Judge against the goal, not every detail seen along the way. A side observation that the goal does not need and the user would not miss is not a reason to say no. When in doubt about one, say no and name it rather than leave it out.

Reply in exactly this shape, TERMINAL style, and nothing else:

```
yes
```

or

```
no
- <what is left, one line each, at most three>
Run /wrap to close it out.
```
