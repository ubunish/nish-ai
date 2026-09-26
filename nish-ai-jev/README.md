# nish-ai-jev

One typed judgment per HTTP request, for the hooks and gates that used to spend a Claude turn deciding something small.

## Why It Exists

Most nish-ai hooks either run a regex or inject text asking Claude to make a judgment. The regex cannot read intent; the injected text costs a turn. TypeSafe's Jev returns a typed answer with a calibrated probability from one POST, so a hook can settle the judgment itself and inject a result instead of a question. Claude stays the orchestrator and the only generator. Jev judges, routes, gates and ranks.

## How It Fits Together

```
              ┌──────────────── callers ────────────────┐
              │                                         │
  router hook · drift hook · bash gate · commit gate · /cut · grill
              │                                         │
              └────────────┬────────────────────────────┘
                           │  state on stdin + a question file
                           ▼
                        nish-ai-jev/jev
                           │
                  ┌────────┴────────┐
                  │ origin allowlist│  no match → exit ≠ 0
                  └────────┬────────┘
                           │  TYPESAFE_API_KEY
                           ▼
              api.typesafe.ai/v1/systemone
                           │
                           ▼
                  answers JSON on stdout
                           │
         exit 0 → caller acts     exit ≠ 0 → caller falls back
```

## Use It

```bash
printf '%s' "$state" | "$HOME/.claude/skills/nish-ai-jev/jev" --timeout 1.5 question.json
```

Stdin is the state — a JSON object or array is sent structured, anything else as a string. The argument is a question file mapping your own ids to typed questions. Stdout is the `answers` object under those same ids. A non-zero exit means no answer came back, for any reason, and the caller does what it did before Jev existed.

`SKILL.md` carries the full contract and the question-design rules. `replay` scores a question file against sessions that already happened:

```bash
nish-ai-jev/replay --limit 200 ../nish-ai-prompt-recognition/jev/route.json
```

## Data Boundary

`allowlist` holds one glob per line, matched against the repo's git origin with the scheme, any credentials and the `.git` suffix stripped and the rest lowercased. The CLI enforces it, so every caller inherits it. A repo with an unknown origin, or none, never reaches the API — which is what keeps work that is not ours off a third-party service.

`TYPESAFE_API_KEY` comes from the shell profile. It is never written into this repo, into `settings.json`, or into a command line.

## Thresholds

Each caller sets its own threshold against the cost of being wrong. These are the current values; `replay` is how they move.

| Caller | Judgment | Threshold | What crossing it does |
|--------|----------|-----------|------------------------|
| Router | `category` Choice confidence | 0.75 | Settles the category; below it, two are named |
| Router | `pasted_only` Noul | 0.50 | Drops the judgment, model reads the prompt itself |
| Drift | `drifted` Noul | 0.70 | Injects the direction-shifted line |
| Bash gate | `risky` Noul | 0.50 | Returns `ask`, surfacing the permission prompt |
| Commit gate | security Nouls | 0.30 | Spawns the security reviewer |
| Commit gate | principle Scores | 2.5 of 3, confidence 0.70 | All seven together skip the code reviewer |
| Commit gate | `real` Noul on a finding | 0.50 | Below it, the finding is tagged `unverified` |
| Grill | `answer` Choice confidence | 0.75 | Auto-answers instead of asking |

Security thresholds are deliberately low and skip thresholds deliberately high: a wasted review costs a minute, a missed one costs more.

These values live here and nowhere else. The project README links to this table rather than repeating it, so a threshold changes in one place.

A reviewer skip is the one judgment that removes a check, so every one is logged to `~/.claude/nish-ai-jev-skips.jsonl` with the diff hash, the repo and the scores behind it. When a bug reaches `main`, find that commit's diff hash in the log and read what the gate believed about it.

## Tests

`../tests/jev.sh` covers the CLI and `replay`; `../tests/bash-gate.sh` and `../tests/router.sh` cover the two hooks. Every request in every suite goes to `../tests/fixtures/jev-stub.py`, so the tests never touch the network and never spend an API call.

`../tests/bash-gate-calibrate.sh` is the exception, and is not part of any suite: it sends each labelled command in `../tests/fixtures/bash-gate-cases.tsv` to the live API and prints the highest `safe` and lowest `risky` score. Run it after changing `hooks/bash-gate.json`, and keep the bash gate's threshold in the gap between the two.
