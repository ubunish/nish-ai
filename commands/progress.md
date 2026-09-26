---
description: Report progress on the current task — percent complete, estimated time left, done, next, blockers
argument-hint: "[task]"
allowed-tools: Bash(git status:*), Bash(git log:*), Bash(ls:*), Read
---

Latest plan: !`ls -t plans/*.md 2>/dev/null | head -1`
Working tree: !`git status --short`
Recent commits: !`git log --oneline -10`

Report progress on the task this session is working on (or on `$ARGUMENTS` if given). Do not start, continue, or change any work — this is a status read only. After reporting, pick the task back up only if it was mid-flight before this command.

Measure against the most concrete yardstick available, in this order:

1. The session's todo list, if one exists
2. The latest plan's steps, matched against the commits above
3. The work as scoped in the conversation so far

Reply in exactly this shape, TERMINAL style:

```
██████░░░░ 60% · ~15 min left
Done: <completed steps, one line>
Next: <remaining steps, one line>
Blockers: <anything waiting on the user, or "none">
```

- **Percent**: weight steps by effort, not count. Round to the nearest 5.
- **Time left**: estimate the wall-clock time for the remaining steps at the pace work has moved so far. Give a single figure, not a range. Add `(low confidence)` when the remaining work is not yet scoped.
- **Bar**: ten cells, one `█` per 10%.
- Never report 100% while a step, test, or push is still outstanding.
