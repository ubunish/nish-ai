---
description: Audit the whole repository for deletable code — a ranked, deletion-only pass via the code reviewer in repo mode
argument-hint: "[path]"
allowed-tools: Task, Bash
---

Run a repo-wide cut audit. Spawn the `nish-ai-code-reviewer` agent in **repo mode** on the repository (or the path in `$ARGUMENTS` if given).

This is a deletion-only pass: the reviewer proposes removals, never additions or rewrites. It tags each candidate (`delete`/`stdlib`/`native`/`yagni`/`shrink`), ranks by payoff, and closes with a `net: -N lines, -M deps` total.

Tell the agent:
- Mode: **repo**
- Scope: the repository root, or `$ARGUMENTS` if a path is provided
- It is read-only — output is a ranked list for me to act on, not edits

## Scoring Pass

The reviewer ranks by payoff alone. Jev re-ranks the candidates on the dimensions payoff cannot see. `install.sh` links this command's question file alongside the command itself, so for **each** candidate the reviewer returned, send that one candidate as the state:

```bash
printf '%s' "$candidate" | "$HOME/.claude/skills/nish-ai-jev/jev" \
  --timeout 5 "$HOME/.claude/commands/cut.json"
```

`$candidate` is a JSON object carrying the candidate's tag, path, description, and the reviewer's rationale — everything Jev needs to judge it without reading the repository itself. The three questions run in parallel inside one call, so a candidate costs one request.

### Weights

Each answer is a `score` from 0 to 4. `coupling` is inverted, because entanglement is a cost:

| Dimension | Weight | Direction |
|-----------|--------|-----------|
| `safety` | 0.55 | Higher is better |
| `payoff` | 0.30 | Higher is better |
| `coupling` | 0.15 | Inverted — `4 - coupling` |

```
rank = 0.55 × safety + 0.30 × payoff + 0.15 × (4 − coupling)
```

Safety dominates because the two errors are not symmetric: a wrong deletion costs a debugging session and a revert, while a missed deletion costs nothing but the lines staying one more week.

Present the candidates sorted by `rank`, highest first, each showing its three scores alongside the reviewer's original tag and rationale.

## Fallback

`jev` exits non-zero on any failure, and a failure is never an argument for or against a cut:

- **One candidate fails** — it keeps the reviewer's own rank position and is marked `unscored`.
- **Every candidate fails** — skip the scoring pass entirely and present the reviewer's list exactly as it stands, with no weights, no scores, and no mention of Jev.

Relay the agent's findings verbatim. Do not apply any cut yourself — I decide what to remove.
