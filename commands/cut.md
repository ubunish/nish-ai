---
description: Audit the whole repository for deletable code — a ranked, deletion-only pass via the code reviewer in repo mode
argument-hint: "[path]"
allowed-tools: Task
---

Run a repo-wide cut audit. Spawn the `nish-ai-code-reviewer` agent in **repo mode** on the repository (or the path in `$ARGUMENTS` if given).

This is a deletion-only pass: the reviewer proposes removals, never additions or rewrites. It tags each candidate (`delete`/`stdlib`/`native`/`yagni`/`shrink`), ranks by payoff, and closes with a `net: -N lines, -M deps` total.

Tell the agent:
- Mode: **repo**
- Scope: the repository root, or `$ARGUMENTS` if a path is provided
- It is read-only — output is a ranked list for me to act on, not edits

Relay the agent's findings verbatim. Do not apply any cut yourself — I decide what to remove.
