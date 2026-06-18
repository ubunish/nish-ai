---
name: nish-ai-d2
description: >
  Nish's d2 diagram authoring skill. Loaded by name (like nish-ai-coding),
  not router-dispatched. Invoked by nish-ai-documentation when a doc needs a
  diagram: covers the render command, the commit-.d2-as-source rule, core d2
  syntax (shapes, connections, containers, labels), layout direction, label
  style aligned with nish-ai-writing-style, and the absent-binary fallback.
  Targets terrastruct's d2 (https://d2lang.com).
---

## When To Use

Loaded by `nish-ai-documentation` when a committed doc needs a diagram. Doc diagrams use d2, not mermaid — d2 gives finer control over layout and styling for non-trivial structure. Planning and chat diagrams keep mermaid: it renders inline on GitHub, d2 does not. Reach for d2 only where an SVG sidecar is viable (committed docs), not for inline or chat diagrams.

## Render

```
d2 diagram.d2 diagram.svg
```

The `.d2` source is the source of truth — commit it alongside the doc. The `.svg` is a generated artifact, rendered from the source and referenced by the doc. Keep both: the source stays diffable, the SVG is what a reader sees outside a d2-aware viewer.

GitHub does not render `.d2` inline, so reference the rendered SVG in the doc:

```markdown
![architecture](architecture.svg)
```

## Absent Binary Fallback

If `d2` is not on `PATH`, keep the raw `.d2` source block in the doc and skip the sidecar — same behavior as mermaid with an absent `mmdc`. `install.sh` provisions the binary; `command -v d2` confirms it.

## Core Syntax

### Shapes

A shape is a name, declared bare or with a label.

```
server
db: Database
```

### Connections

```
server -> db: query
db -> server: rows
```

`->` directed, `--` undirected, `<->` bidirectional.

### Containers

Nest shapes with a dotted path or a block.

```
api.handler -> api.router

cloud: {
  worker
  queue
  worker -> queue
}
```

### Labels And Styling

```
server: Web Server {
  shape: rectangle
}
server -> db: { style.stroke: blue }
```

## Layout Direction

Set once at the top of the file.

```
direction: right
```

Values: `up` / `down` / `left` / `right`. Default is `down`. Match the diagram's natural flow — a pipeline reads `right`, a hierarchy reads `down`.

## Label Style

Labels follow `nish-ai-writing-style`:

- Title Case for node labels and short headings
- Sentence case for longer edge descriptions
- State the idea once — a label names a thing, it does not explain it
- Simple word over complex

## Lifetime

Loaded by name when diagram work is needed, mainly by `nish-ai-documentation`. Not auto-active, not router-dispatched. No off switch — load it when you need d2, ignore it otherwise.
