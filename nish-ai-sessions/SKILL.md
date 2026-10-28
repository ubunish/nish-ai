---
name: nish-ai-sessions
description: >
  Nish's session coordination layer. Keeps parallel Claude sessions on one
  repo out of each other's way through a `nish-session` CLI and the hooks
  that call it: shared state for which sessions are live in a repo and a
  per-session event inbox. Load by name when debugging a coordination hook or
  reading the state it writes. Not router-dispatched.
---

## What It Is

Claude Code already keeps a live registry of sessions (`~/.claude/sessions/<pid>.json`: session id, cwd, name, busy/idle). This layer adds the conditions for when sessions should hear about each other, and the shared state that carries it.

```
~/.claude/sessions/<pid>.json         Claude Code's registry (read-only here)
            │  + kill -0 pid
            ▼
nish-session peers ──→ live sessions sharing this repo's git common dir
nish-session emit  ──→ ~/.claude/nish-ai-sessions/inbox/<session_id>.jsonl
                       + events.jsonl (shared log the dashboard reads)
nish-session drain ──→ prints and clears one session's inbox
```

Worktrees of one repo share a git common dir, so a session in a worktree is a peer of a session in the primary checkout.

## CLI

```bash
nish-session peers [--cwd DIR] [--self SID]   # one JSON object per live peer
echo '{"type":"main_moved"}' | nish-session emit SID
nish-session drain SID                        # one JSON event per line
```

`--self` defaults to `$CLAUDE_CODE_SESSION_ID`, which Claude Code sets in its Bash tool, so a call from Claude excludes its own session. Each peer line carries `pid`, `session_id`, `name`, `cwd`, `status`, `started_at` and `toplevel`. A registry entry whose pid is no longer running is skipped; pid reuse after a crash can briefly count an unrelated process as live, which costs at most one spurious event.

`emit` stamps `ts` on the event. An emit and a drain on the same state never interleave: both take a `mkdir` lock, so an event is either in the batch a drain prints or in the next one. The lock records its holder's pid: after two seconds a lock whose holder has exited is taken over, while one held by a live process fails the call rather than letting it run unlocked. One residual gap is accepted: if two callers time out on the same crashed holder at once, both can take over and one event may be lost.

## Claims

A claim says which work a session has taken on, so two sessions on one repo do not fix the same bug. Claims live in `~/.claude/nish-ai-sessions/claims/<repo-key>.jsonl`, keyed by a hash of the git common dir, and die with their session's pid.

```
first prompt of 20+ chars ──→ goal claim (unjudged, once per session)
off-goal fix ──→ nish-session claim "<topic>"
                   ├─ no live claims      → record → clear
                   ├─ jev: overlaps ≥ 0.5 → owned by <name>   (nothing recorded)
                   ├─ jev: apart          → record → clear
                   └─ jev failed          → record → print live claims for Claude to judge, exit 0
```

The overlap question is `jev/overlap.json`, a single noul the CLI asks once per live peer claim (at most a goal and the latest claim per session, since a new claim replaces the last), asking whether the two pieces of work are the same bug, feature or change however they are phrased. A session with a live peer in the repo is told at SessionStart to claim before any off-goal fix. `nish-session claims` lists the live claims, one JSON object per line. Topics, including the goal taken from a session's first prompt of 20+ characters, are sent to Jev for an allowlisted origin only; on the fail-open path they are printed cut to plain characters and labelled as data. Pass `--` before a topic that starts with a dash.

## Dashboard

A read-only TUI over the same state, built on nish-tui and refreshed every two seconds:

```bash
uv run ~/.claude/skills/nish-ai-sessions/dash/dash.py
```

| Panel | Shows |
|-------|-------|
| sessions | Each live session: name, repo, branch (marked when it is a worktree), busy/idle, pending inbox events |
| claims | Every live claim across repos: session, goal or claim, topic |
| recent events | The last 20 entries of `events.jsonl`, which `emit` appends to and trims to 500 lines once it passes 1000 |

`dash/state.py` collects the state with the standard library only, so it runs and is tested without the TUI's dependencies; `uv run --no-project dash/state.py` prints it as JSON. The TUI collects in a worker thread with two git calls per distinct checkout, so a slow mount delays a refresh rather than freezing the screen. Its `nish-tui` dependency is pinned to a commit.

## State Safety

A session id becomes a path segment, so it is stripped to `[A-Za-z0-9_-]`. A symlink at an inbox is never followed: `emit` refuses it and `drain` leaves it alone. State is written with umask 077. Needs git 2.31 or newer.

## Hooks

Each hook is silent unless an event concerns its session, so a solo session spends no tokens on this layer.

| Hook | Event | Fires when |
|------|-------|------------|
| `sessions-session-start.sh` | SessionStart | A live peer that started earlier sits in the same checkout: injects an instruction to `EnterWorktree`, named after the goal, before the first edit. Only the newer session moves. Any session with a live peer in the repo is also told to `claim` off-goal fixes first. |
| `sessions-post-merge.sh` | PostToolUse (Bash) | This session finished `gh pr merge` (not `--auto`), a `git push` whose refspec names `main` (`main`, `HEAD:main`, `refs/heads/main`), or a bare `git push` / `git push origin HEAD` from `main`: appends `{type: main_moved, sha, from}` to every live peer's inbox. The command is read per segment, following `cd` hops up to the push, so `cd <repo> && git push` routes to that repo. Deletes and dry runs are ignored; merges made outside a Claude session are not seen. |
| `sessions-prompt-submit.sh` | UserPromptSubmit | Every prompt of 20 or more characters: records the session's goal claim if it has none yet, so an acknowledgement like "done" is never taken as the goal. Then, when the inbox holds a `main_moved` event: fetches `origin main`, then syncs a clean checkout — fast-forward on `main`, `git rebase origin/main` on a branch none of whose commits are on a remote, `git merge origin/main` on a branch with an upstream or pushed commits (pushed history is never rewritten). Injects one line naming the changed files so Claude re-reads them. A dirty tree, detached HEAD, diverged `main`, failed fetch or conflict changes nothing: a note is injected once and the event is re-queued, so the sync lands on the first prompt after the cause clears. Untracked files do not block. Branch and file names are cut to one plain-charset word of at most 80 characters and labelled as data; event fields never reach the model. |
