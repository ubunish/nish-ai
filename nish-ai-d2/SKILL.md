---
name: nish-ai-d2
description: >
  Nish's d2 diagram authoring skill. Loaded by name (like nish-ai-coding),
  not router-dispatched. Invoked by nish-ai-documentation when a doc needs a
  diagram: covers the render command, the commit-.d2-as-source rule, a
  construct-picker map, core syntax (shapes, connections, containers, labels),
  structured diagram types (sequence, ER/sql_table, class, grid), rich labels
  (markdown, code, latex), icons, near positioning, arrowheads, reuse (vars,
  classes, globs), multi-board layers, layout engines (dagre, ELK, TALA),
  layout direction, label style aligned with nish-ai-writing-style, and the
  absent-binary fallback.
  Targets terrastruct's d2 (https://d2lang.com).
---

## When To Use

Loaded by `nish-ai-documentation` when a committed doc needs a diagram. Doc diagrams use d2, not mermaid — d2 gives finer control over layout and styling for non-trivial structure. Planning and chat diagrams keep mermaid: it renders inline on GitHub, d2 does not. Reach for d2 only where an SVG sidecar is viable (committed docs), not for inline or chat diagrams.

## Pick The Right Construct

Match the doc's intent to a d2 construct before writing syntax. Default to box-and-arrow; reach for a structured type only when the data is genuinely that shape.

| Need | Construct |
|------|-----------|
| Box-and-arrow flow | shapes + `->` connections |
| Grouping / nesting | containers (dotted path or block) |
| Time-ordered messages | `shape: sequence_diagram` |
| Entities + relations (ER) | `shape: sql_table` + crow's-foot arrowheads |
| Class / interface | `shape: class` |
| Tiled / matrix layout | `grid-rows` / `grid-columns` |
| Domain glyph | `icon:` URL |
| Prose / formatted text | markdown block label |
| Code listing | code block label |
| Fixed-position title / legend | `near` constant |
| Overview → detail drill-down | `layers` boards |
| Reused style | `classes` + `class:` |
| Reused value | `vars` + `${...}` |

## Render

```
d2 --layout elk --font-regular <font>.ttf --font-bold <font>.ttf --font-italic <font>.ttf diagram.d2 diagram.svg
```

Always render with `--layout elk` and a committed font for diagrams in committed docs. ELK routes edges as straight orthogonal segments, which read cleaner than dagre's curves. See Layout Engines below for the full choice and when a dense architecture map earns TALA instead, and Font below for choosing and passing the font.

Per repo, commit a `render.sh` next to the diagrams that wraps this command with the repo-relative font path, so anyone re-renders without personal tooling.

The `.d2` source is the source of truth — commit it alongside the doc. The `.svg` is a generated artifact, rendered from the source and referenced by the doc. Keep both: the source stays diffable, the SVG is what a reader sees outside a d2-aware viewer.

GitHub does not render `.d2` inline, so reference the rendered SVG in the doc:

```markdown
![architecture](architecture.svg)
```

## Layout Engines

d2 ships three layout engines. ELK is the house default for committed docs.

| Engine | Edges | Best for | Cost |
|--------|-------|----------|------|
| dagre | curved splines | quick hierarchies | built-in |
| ELK | straight orthogonal | house default — every doc diagram | built-in |
| TALA | architecture-tuned | dense software-architecture maps | closed-source, eval watermark until licensed |

Keep ELK as the default — straight edges read cleaner. Reach for TALA only when a dense architecture diagram lays out poorly under ELK; it is built for that case. `install.sh` bundles TALA with d2 (the upstream `--tala` flag), so the `d2plugin-tala` binary is on `PATH`. Confirm with `d2 layout tala`.

Render with TALA by swapping the layout flag:

```
d2 --layout tala --font-regular <font>.ttf --font-bold <font>.ttf --font-italic <font>.ttf diagram.d2 diagram.svg
```

TALA runs in evaluation mode until a `TSTRUCT_TOKEN` is set — diagrams carry a watermark. Fine for drafting; set the token, or fall back to ELK, before committing an SVG a reader sees.

## Absent Binary Fallback

If `d2` is not on `PATH`, keep the raw `.d2` source block in the doc and skip the sidecar — same behavior as mermaid with an absent `mmdc`. `install.sh` provisions d2 with TALA bundled; `command -v d2` confirms the renderer, `d2 layout tala` confirms the TALA plugin.

## Font

Never render with d2's default font. Pick a font, commit its TTF into the repo (e.g. `docs/diagrams/fonts/`), and pass it with `--font-regular` / `--font-bold` / `--font-italic`, so rendering is self-contained for anyone with the repo. A monospace font suits the technical tokens diagrams carry (package names, file paths, identifiers). A project or brand skill may pin a specific font — load it for the exact TTF and flags.

## Shared Styles

Define reused colours and classes once in a `styles.d2`, then import them with `...@styles` so every diagram in a repo pulls the same palette:

```
classes: {
  box:    { style.fill: transparent; style.stroke: "#333333" }
  zoom:   { style.fill: transparent; style.stroke: "#333333"; style.stroke-dash: 4 }
  accent: { style.fill: "#4C78A8"; style.font-color: "#FFFFFF" }
}
(* -> *).style.stroke: "#333333"
```

This skill covers the mechanism, not a specific palette. A project or brand skill carries the actual colours and any block grammar built on them — load it for those.

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

### Shapes Catalog

`shape:` sets a node's form. Default is `rectangle`. Pick the shape that names the thing — a `cylinder` for a store, a `person` for an actor, a `queue` for a buffer.

```
disk: { shape: cylinder }
user: { shape: person }
q:    { shape: queue }
doc:  { shape: document }
pick: { shape: diamond }
```

Catalog: `rectangle` `square` `circle` `oval` `diamond` `hexagon` `cylinder` `queue` `package` `document` `page` `parallelogram` `person` `stored_data` `callout` `step` `cloud` `image` `sql_table` `class` `sequence_diagram`. Add `style.3d: true` to a `rectangle`, `square`, or `hexagon` for a 3-D block.

## Structured Diagram Types

Four shapes turn a container into a purpose-built diagram. Use them when the data is that shape — not for decoration.

### Sequence

`shape: sequence_diagram`. Declaration order fixes actor order; each `->` is a time-ordered message.

```
flow: { shape: sequence_diagram
  user -> api: request
  api -> db: query
  db -> api: rows
  api -> user: response
}
```

### ER Table

`shape: sql_table`. Each row is `name: type`; `{constraint: ...}` tags a key. Connect columns across tables, carry cardinality on crow's-foot arrowheads.

```
users: { shape: sql_table
  id: int {constraint: primary_key}
  email: varchar
}
orders: { shape: sql_table
  id: int {constraint: primary_key}
  user_id: int {constraint: foreign_key}
}
orders.user_id -> users.id
```

### Class

`shape: class`. Rows are fields and methods; `+` `-` `#` mark visibility, trailing `()` marks a method.

```
Repo: { shape: class
  +items: List
  +get(id): Item
  -cache: Map
}
```

### Grid

`grid-rows` / `grid-columns` tile children with no edges; `grid-gap` sets spacing. A banded-block grammar (carried by a project skill) builds on this.

## Rich Labels

Block strings carry formatted content. Open with `|tag`, close with `|`.

```
note: |md
  ## Summary
  - point one
  - point two
|

snippet: |go
  func main() { println("hi") }
|

eq: |latex
  E = mc^2
|
```

## Icons And Images

`icon:` overlays a glyph; `shape: image` makes the icon the whole node.

```
svc:  API { icon: https://icons.terrastruct.com/dev/go.svg }
logo: { shape: image; icon: https://example.com/logo.png }
```

## Positioning With near

`near` pins a node to a constant or another node — for titles, legends, and captions that sit outside the layout flow.

```
title: System Map { near: top-center; shape: text }
```

Constants: `top-left` `top-center` `top-right` `center-left` `center-right` `bottom-left` `bottom-center` `bottom-right`.

## Arrowheads

Style either end of a connection; crow's-foot heads carry ER cardinality.

```
a -> b: { target-arrowhead.shape: triangle }
orders.user_id -> users.id: {
  source-arrowhead.shape: cf-many
  target-arrowhead.shape: cf-one
}
```

Heads: `triangle` `arrow` `diamond` `circle` `box` `cross`; ER `cf-one` `cf-many` `cf-one-required` `cf-many-required`.

## Reuse: vars And Classes

`vars` holds reused values, referenced with `${...}`. `classes` holds reused styles, applied with `class:` (see Shared Styles above). A glob applies one rule across every match.

```
vars: { primary: "#4C78A8" }
node: { style.fill: ${primary} }

*.style.border-radius: 8
```

## Multi-Board: layers, scenarios, steps

For a diagram that drills from overview to detail, declare boards in one file instead of separate files.

```
layers: {
  overview: { ... }
  detail:   { ... }
}
```

- `layers` — independent boards (overview → zoom).
- `scenarios` — boards that inherit the base, then override (states of one system).
- `steps` — boards that accumulate (build up a sequence).

Pairs with a dashed `zoom` class (`style.stroke-dash`): a dashed block names where it expands into a deeper board.

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
