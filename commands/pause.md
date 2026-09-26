---
description: Pause the current task at the next safe point and write a resume note for /unpause
argument-hint: "[note]"
allowed-tools: Bash, Read, Edit, Write
---

Latest plan: !`ls -t plans/*.md 2>/dev/null | head -1`
Current branch: !`git rev-parse --abbrev-ref HEAD 2>/dev/null`
Working tree: !`git status --short 2>/dev/null`
Recent commits: !`git log --oneline -10 2>/dev/null`

The user is stepping away. Bring the current task to a clean stopping point, record where it stands, then stop. Do not stop mid-edit, and do not push on to the end of the task either.

1. **Finish the unit in hand.** Complete the edit, test run or command already in progress so no file is left half-written. Start no new plan step, subagent or refactor.
2. **Reach a safe point.**
   - Run the project's tests if code changed since the last run, and record the result. Do not fix failures now; note them.
   - Commit only if the current step is complete and its planned commit is due anyway. Otherwise leave the tree as is: no WIP commit, no stash.
   - Never push, merge or run anything outward-facing as part of pausing.
3. **Write the resume note** to `plans/.pause.md`, overwriting any earlier one. Create `plans/` if missing, and add `plans/` to `.gitignore` if it is not already ignored, so the note is never committed. Confirm with `git check-ignore plans/.pause.md` before writing; if it is not ignored, stop and tell the user. Use this shape:

   ```markdown
   # Paused: <task in a few words>

   **Paused**: <YYYY-MM-DD HH:MM>
   **Branch**: <branch> @ <short sha>
   **Plan**: <plan path, or "none">
   **Note**: <$ARGUMENTS on one line, or "none">

   ## Done
   - <completed steps or changes>

   ## In Progress
   - <the step that was underway and exactly how far it got>

   ## Next
   1. <first concrete action on resume: file, function, command>
   2. <then>

   ## State
   - Uncommitted: <files and what each change is, or "clean">
   - Tests: <last result and command>
   - Running: <background processes, servers or watchers left running, or "none">

   ## Context
   - <decisions made, dead ends ruled out, user instructions from this session that are not in the plan>
   ```

   **Context** is the section that matters most: it carries what would otherwise be lost with the conversation. Write it for a fresh session that has never seen this one. Never copy a secret value (key, token, password) into the note; name where it lives instead.
4. **Stop.** Reply in TERMINAL style with one line on where work stopped, then `Paused. Run /unpause to pick up.` Take no further action.
