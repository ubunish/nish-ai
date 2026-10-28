---
description: Close a drifting session — realign to its goal, finish small open items, move the rest to issues or the backlog, then stop
argument-hint: "[goal]"
allowed-tools: Bash, Read, Edit, Write, TaskStop, AskUserQuestion
---

Latest plan: !`ls -t plans/*.md 2>/dev/null | head -1`
Current branch: !`git rev-parse --abbrev-ref HEAD 2>/dev/null`
Working tree: !`git status --short 2>/dev/null`
Unpushed: !`git log --oneline @{u}..HEAD 2>/dev/null`

The user wants this session closed. It may have drifted into side fixes, or into waiting on background tasks, agents or CI. Do not continue that drift. The job now is to land what the goal needs, put everything else somewhere durable, and stop.

1. **Stop the drift.** Start no new fix, refactor, investigation or subagent. Stop any background task, agent or CI watch with `TaskStop` unless its result is needed for the goal and due within a minute or two. A stopped wait becomes an open item, not a loss.
2. **Restate the goal** in one line: `$ARGUMENTS` if given, otherwise the session's first request or the plan it was executing.
3. **List open items.** Collect every unfinished todo, plan step, uncommitted change, stopped task, and loose end noticed along the way that the user has not been told about in a durable place. Give each a one-line description and an effort estimate.
4. **Route each item with Jev.** `install.sh` links this command's question file alongside the command. For each item:

   ```bash
   jq -nc --arg goal "$goal" --arg item "$item" --arg effort "$effort" \
     '{goal: $goal, item: $item, effort: $effort}' \
     | "$HOME/.claude/skills/nish-ai-jev/jev" --timeout 5 "$HOME/.claude/commands/wrap.json"
   ```

   Act on `route.choice` when `route.confidence` is at least **0.75**. Below that, on `ask_user`, or when `jev` exits non-zero, the item goes to the user.
5. **Ask once.** Put every item that needs the user into a single `AskUserQuestion` call (up to four questions; group the rest), each offering `finish`, `backlog`, `issue` and `drop`.
6. **Act on the routes.**
   - **finish**: do it now, under the rules of the session's skill (tests, commit gate, `nish-ai-github`). If it grows past its estimate, stop and re-route it as `issue`.
   - **issue**: `gh issue create` with a title, the context a fresh session needs, and the next step. If the repo has no GitHub remote, use the backlog instead.
   - **backlog**: append a line to `plans/BACKLOG.md` as `- [ ] YYYY-MM-DD <item> — <one-line context>`. Confirm with `git check-ignore plans/BACKLOG.md` first; add `plans/` to `.gitignore` if it is not ignored.
   - **drop**: nothing to do. List it in the report so the user sees it went.
7. **Leave no stranded work.** Push commits made in this session. Uncommitted changes that are not a finished step are not committed: name each file and route it like any other item. Never force-push or merge red to close faster.
8. **Report and stop.** Reply in TERMINAL style, then take no further action:

   ```
   Goal: <one line> · <done | partly done>
   Finished: <items, or "none">
   Issues: <#n title, …, or "none">
   Backlog: <items, or "none">
   Dropped: <items, or "none">
   Safe to close.
   ```

   End with `Safe to close.` only when nothing is left running, unpushed, or unrouted. Otherwise end with `Not safe to close: <what is left>`.
