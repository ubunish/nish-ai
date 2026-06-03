---
name: nish-ai-uv
description: >
  Nish's "always prefer uv" convention. Auto-active whenever Claude runs or
  writes Python tooling in any session — detected by Python signals: a `*.py`
  edit, a `pip` / `poetry` / `pipenv` / `virtualenv` invocation, a
  `requirements.txt`, or a `pyproject.toml`. Carries the command mapping that
  redirects python/pip/poetry/pipenv/virtualenv to their uv equivalents. The
  mapping applies to commands Claude runs AND to commands Claude suggests in
  chat — including echoes of a README that still says pip/python. Rides the
  auto-active tier alongside nish-ai-writing-style and nish-ai-coding, and is
  backed by a PreToolUse hook that blocks bare calls and returns the uv
  rewrite. Off only on "drop uv".
---

## Detection

Load this skill when the working context shows any Python signal:

```
*.py edit                                  → Python source
pip / pip3 invocation                      → package management
poetry / pipenv / virtualenv invocation    → environment / dependency tooling
requirements.txt                           → pinned deps
pyproject.toml                             → project metadata
```

No signal → do not load. Conda work is out of scope and never redirected.

## Scope: Run AND Suggest

The mapping applies to two surfaces, not one:

```
EXECUTE   command Claude runs via a tool   → PreToolUse hook enforces
SUGGEST   command Claude writes in chat     → this skill enforces, no hook
```

The hook only fires on tool invocations. A `python` or `pip` command typed into
a chat reply never reaches it, so the model must apply the mapping itself before
sending. Rewrite every command in prose, code block, and instruction the same
way you would rewrite one you were about to run.

This includes echoes of project docs. When a README or existing file shows
`pip install` or `python -m mod`, convert it to the uv form in the suggestion —
the convention overrides the source text. Flag the doc drift for a separate
`docs` pass; do not propagate it.

## Why

nish-setup already installs uv and builds the `~/.venvs/*` environments with
it. uv is faster, resolves deterministically, and replaces the whole
python/pip/poetry/pipenv/virtualenv stack with one tool. This skill carries the
convention so Claude reaches for uv on its own; the companion PreToolUse hook
enforces it by blocking bare calls and returning the rewrite.

## Command Mapping

```
python script.py        → uv run script.py
python -m mod           → uv run -m mod
python   (REPL)         → uv run python
python3 ...             → uv run ...
pip install X           → uv pip install X
pip ...                 → uv pip ...
python -m venv .venv    → uv venv .venv
poetry add X            → uv add X
poetry install          → uv sync
pipenv install X        → uv add X
virtualenv .venv        → uv venv .venv
conda ...               → untouched
```

## Exclusions

The redirect does not apply when:

- The command already starts with `uv` — nothing to rewrite.
- `$VIRTUAL_ENV` is set — running the venv's own python is legitimate.
- The bypass marker `~/.claude/.uv-off` is present — see Off-Switch.
- The command is a conda invocation — conda is a separate ecosystem, never touched.

## Off-Switch

"drop uv" disables both layers for the session: the model stops applying this
mapping, and the bypass marker `~/.claude/.uv-off` is written so the hook stops
blocking. Re-enabling removes the marker. Matches the "drop style" / "drop ros2"
pattern — one phrase, fully off.
