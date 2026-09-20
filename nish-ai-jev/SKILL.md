---
name: nish-ai-jev
description: >
  Nish's judgment layer. Wraps TypeSafe's Jev (System One) behind a single
  `jev` CLI that hooks, gates and commands call to settle a routing, triage,
  ranking or safety question without spending a Claude turn on it. Load by
  name when writing or debugging a Jev caller, when adding a question file,
  or when a hook's Jev path needs explaining. Carries the data boundary (an
  origin allowlist), the fail-open contract, and the question-design rules.
  Not router-dispatched.
---

## What It Is

`jev` turns one HTTP POST into a typed answer. Claude stays the orchestrator
and the only generator; Jev judges, routes, gates and ranks.

```
caller → state on stdin ─┐
                         ├→ jev → allowlist → API → answers JSON → caller acts
question file ───────────┘                 ↘ any failure → exit ≠ 0 → caller falls back
```

## Calling It

```bash
printf '%s' "$prompt" | "$HOME/.claude/skills/nish-ai-jev/jev" --timeout 1.5 route.json
```

- **stdin** is the state. A JSON object or array is sent structured; anything
  else is sent as a string.
- **argument** is a question file: a JSON object mapping your own question ids
  to typed questions.
- **stdout** is the response's `answers` object, keyed by those same ids.
- **exit status** is 0 only when a real answer came back.

`--timeout` is the whole-request budget in seconds (default 5). `JEV_ENDPOINT`
overrides the API URL; the tests point it at a local stub.

## Fail-Open Contract

Every caller treats a non-zero exit as "Jev said nothing" and does exactly what
it did before Jev existed. A hook that cannot fall back has no business calling
`jev`. These all exit non-zero:

| Cause | Why |
|-------|-----|
| Origin not on `allowlist` | Data boundary — the state never leaves the box |
| No git origin | Unknown repo is treated as off-allowlist |
| `TYPESAFE_API_KEY` unset | No credential, no call |
| Timeout, 4xx, 5xx, malformed JSON | The judgment is simply unavailable |

## Data Boundary

`allowlist` holds one glob per line, matched against the repo's git origin with
the scheme, any credentials and the `.git` suffix stripped and the rest
lowercased. The CLI enforces it, so every caller inherits it and none can opt
out. Adding a line is a deliberate decision about which repo's contents may
reach a third-party API.

## The Key

`TYPESAFE_API_KEY` is read from the environment, exported from the shell
profile. It is never written into this repo, into `settings.json`, or into a
command line — `jev` passes it through a `curl` config file so it stays out of
the process list.

## Writing A Question File

Pick the primitive by what the answer means:

| Need | Type | Answer fields |
|------|------|---------------|
| One of a defined set | `choice` | `choice`, `probabilities`, `confidence` |
| Whether a condition holds | `noul` | `noul` (probability of yes) |
| Degree along an ordered scale | `score` | `score`, `legend`, `probabilities`, `confidence` |

```json
{
  "category": {
    "type": "choice",
    "instructions": "Which track does this request belong to?",
    "criteria": { "build": "Writes or changes code", "ask": "Answers a question" }
  },
  "risky": {
    "type": "noul",
    "instructions": "Is this hard to reverse?",
    "criteria": { "true": "Destroys or publishes something", "false": "Read-only" }
  }
}
```

Rules that matter in practice:

- Ask one narrow judgment per question. Split dimensions that are useful apart.
- Question ids are for your code; the model never sees them, so the meaning
  must live in `instructions`.
- Independent questions over the same state go in **one** file. They run in
  parallel, and adding a question barely changes the response time.
- Reference nested state with a backticked path, such as `` `diff.files[0]` ``.
- A `choice` needs a no-match option whenever nothing may fit.

## Thresholds

A probability is not a decision. Each caller sets its own threshold against the
consequence of being wrong, and `nish-ai-jev/replay` is how a threshold gets
chosen rather than guessed. Current settings live in the README's threshold
table.

## Output Style (Recency Anchor)

Every user-facing line follows `nish-ai-writing-style` TERMINAL mode: no
a/an/the, fragments over full sentences. Committed prose uses DOCS mode.
