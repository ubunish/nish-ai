---
name: nish-ai-documentation
description: >
  Nish's documentation skill. Invoked by nish-ai-prompt-recognition when
  the session's first prompt is to write or restructure docs (Category D,
  `docs` commit prefix). Covers project READMEs, module READMEs, ADRs, and
  external doc sites. Works directly — no plan required. One commit per
  logical change. Style governed by nish-ai-writing-style (auto-active);
  module READMEs follow the structure from nish-ai-coding's Documented
  principle; commits follow nish-ai-github.
---

## Thinking

None. Doc work is structure + prose — mechanical. Do not inject thinking keywords.

## Scope

| Type | Skill applies to |
|------|------------------|
| Project README | Top-level repo README — name, install, usage |
| Module README | Per-module/package docs |
| ADR | Architecture decision records |
| External docs | MkDocs, Docusaurus, wikis, standalone sites |

## Workflow

```
identify doc type → confirm scope with user → edit → commit per logical change → next
```

1. Identify which type of doc is being touched (table above)
2. Announce: `Doc type: <name>. Scope: <files/sections>. Proceed?`
3. Edit the doc, following the type-specific structure below
4. Commit per logical change with `docs:` prefix (per `nish-ai-github`)
5. Continue until session done or scope shifts

No plan required. No branch required (user-driven for branch creation).

## Commit Boundaries

One commit per logical change. Examples:

- `docs: restructure auth section`
- `docs: add JWT example to API page`
- `docs: clarify install steps for windows`

Not:

- `docs: updates` (vague)
- `docs: restructure auth + add example + fix typos` (multiple changes)

A typo fix to existing content uses `fix:` not `docs:` (per `nish-ai-github`). If a session would produce both, split into two commits.

## Type-Specific Structure

### Project README

Sections, in order:

1. **Name** + one-line description
2. **Why** it exists (2-3 sentences)
3. **Install** — copy-pasteable
4. **Usage** — minimal working example
5. **Links** — module docs, contributing, license

### Module README

Per `nish-ai-coding` Documented principle:

- What it does (1 line)
- Why it exists (1 line)
- How to use it (minimal example)
- Architecture diagram (d2) if structure is non-trivial

Draw architecture diagrams with d2 — load `nish-ai-d2` for the syntax and render command. The `.d2` source is the source of truth; commit it alongside the doc. Render it to an SVG sidecar and reference the SVG below the source block:

```
d2 diagram.d2 architecture.svg
```

GitHub does not render `.d2` inline, so the SVG is the viewable artifact — embed it with `![architecture](architecture.svg)`. The `.d2` block stays the source of truth; the SVG is a generated artifact. If `d2` is absent from `PATH`, keep the raw `.d2` source block and skip the sidecar.

### ROS2 Package README

When documenting a ROS2 package, load `nish-ai-ros2` and apply its per-package README practice. One `README.md` per package, documenting each node:

- Short description and overview
- Usage
- API: topics, services, actions
- Parameters: type, description, default value

### ADR

Use the Nygard format:

````markdown
# ADR <NNN>: <decision title>

**Status**: Proposed | Accepted | Superseded by ADR-XXX
**Date**: YYYY-MM-DD

## Context

<what's the situation, what forces are at play>

## Decision

<what we're doing, in one paragraph>

## Consequences

<what becomes easier, what becomes harder, what we accept>
````

Numbered sequentially (`adr/001-...`, `adr/002-...`). Never edit a past ADR — supersede it with a new one.

### External Docs

Follow the existing site's conventions:
- MkDocs → respect `mkdocs.yml` nav structure
- Docusaurus → respect `sidebars.js` + folder layout
- Wikis → respect existing page hierarchy

Do not restructure the site without explicit user direction.

## Re-Categorize Triggers

If the session shifts from docs to code changes ("now update the implementation to match"), pause and announce:

```
Session direction shifted: docs → code. Re-categorize? (was: Documentation)
```

Wait for user confirmation before re-invoking `nish-ai-prompt-recognition`.

## Lifetime

Session-active after dispatch by `nish-ai-prompt-recognition`. Persists until session ends or user explicitly re-categorizes.

## Output Style (Recency Anchor)

This section sits last on purpose: after dispatch it is the freshest part of the skill body, so task voice cannot displace house style. Every user-facing line this session — chat replies, explanations, and one-line tool preambles ("let me check…", "reading X…") — follows `nish-ai-writing-style` TERMINAL mode: no a/an/the, fragments over full sentences, self-check each line before sending. Committed prose (docs/README/comments/commit messages) uses DOCS mode instead.
