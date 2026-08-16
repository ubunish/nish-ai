---
name: nish-ai-coding
description: >
  Nish's coding principles and build ladder. Load before writing or editing
  source code in any session — invoke it when a task is about to produce or
  change code. Dispatched explicitly by nish-ai-goal-oriented-coding before
  execution and by nish-ai-quick-task on code-touching chores; a PreToolUse
  hook injects a compact reminder on the first source edit as backstop.
  Seven principles: modular, scalable, consistent, documented, tested, no
  premature abstraction, self-explaining. Off only on "drop coding style".
---

## Build Ladder

Before writing code, climb these rungs in order. Stop at the first that solves the problem. The lower the rung, the less code you own and maintain.

1. **Does it already exist?** — reuse a function, module, or pattern already in the codebase before adding anything new.
2. **Standard library** — solve it with the language's stdlib before reaching outward.
3. **Native platform** — use a built-in platform or framework capability before adding a dependency.
4. **Installed dependency** — use a library already in the project before installing a new one.
5. **One-line addition** — if a new dependency is unavoidable, prefer the smallest one that does the job.
6. **Minimum new code** — write the least code that satisfies the requirement, nothing speculative.

This ladder governs Claude's auto-output — restraint on what Claude builds unprompted. A deliberate own-library choice the user has decided on is the override: when the design lane (`nish-ai-project-planning`) has chosen to build or adopt something, that decision wins over the ladder. The ladder never overrides the Scalable principle in the design lane.

## Principles

1. **Modular** — single responsibility per unit
2. **Scalable** — pattern works at 10x current load
3. **Consistent** — match existing project conventions
4. **Documented** — README + diagram at project/module level
5. **Tested** — code ships with tests
6. **No Premature Abstraction** — Rule of Three
7. **Self-Explaining** — names carry meaning; comments for WHY only

## Rules

### Modular

Single responsibility per function, class, or module. If description needs "and", split it.

Not:
```python
def process_user_and_send_email(user_id):
    user = db.get_user(user_id)
    user.last_active = now()
    db.save(user)
    send_email(user.email, "welcome")
```

Yes:
```python
def touch_user(user_id): ...
def welcome_email(user): ...
```

### Scalable

Pattern works at 10x current data or load without rewrite. Loop over all rows in memory does not scale. Query without index does not scale.

Not: `users = db.get_all_users(); for u in users: ...`
Yes: `for u in db.iter_active_users(): ...` (paginated, indexed)

### Consistent

Match project conventions before personal preference. Naming, structure, error handling, formatting — follow the codebase. Linters, formatters, type checkers configured at project level are authoritative.

No convention exists → establish one, apply uniformly.

### Documented

Project and module level only. Inline comments governed by Self-Explaining.

Each module README answers:
- What it does (1 line)
- Why it exists (1 line)
- How to use it (minimal example)
- Architecture diagram if structure non-trivial — raw mermaid block, optionally rendered to an image sidecar via `mmdc` (Mermaid CLI) for non-GitHub viewers

### Tested

Code ships with tests. New function → new test. Bug fix → regression test. Refactor → existing tests pass.

Test behavior, not implementation. Mock at system boundaries (external APIs, DB clients), not internal collaborators.

### No Premature Abstraction

Rule of Three: write concrete first. Generalize only at 3+ real cases sharing structure. Two similar things is coincidence, not pattern.

DRY applies *after* Rule of Three, not before. Two duplicates is fine — deduplicate when a third appears.

Not (one caller, prematurely generalized):
```python
def fetch_resource(kind, id, transform=None, cache=False, retry=3): ...
fetch_resource("user", 123)
```

Yes:
```python
def fetch_user(id): ...
```

### Self-Explaining

Names carry meaning. Function names describe what they do. Variable names describe what they hold. Comments reserved for WHY, not WHAT.

Not:
```python
# loop through items and add up the prices
t = 0
for i in items:
    t += i.p
```

Yes:
```python
total_price = sum(item.price for item in items)
```

Comment when WHY is non-obvious:
```python
# Stripe rounds to nearest cent; floor to match invoice display
total_cents = math.floor(amount * 100)
```

Mark a deliberately cheap choice with a typed `tradeoff:` comment. It names the ceiling the choice holds to and the upgrade path when that ceiling is hit. This keeps a shortcut honest — visible as a decision, not mistaken for the best option:
```python
# tradeoff: linear scan, fine under ~1k items; switch to an indexed lookup past that
match = next((r for r in records if r.id == target), None)
```

## ROS2

When the code under edit is ROS2 (a `package.xml` with ament, `rclpy`/`rclcpp`, `.msg`/`.srv`/`.action`, or a `launch/`/`config/` folder), load `nish-ai-ros2` and enforce its thirty practices at the commit boundary alongside these seven principles.

## Lifetime

Loaded by explicit dispatch: `nish-ai-goal-oriented-coding` invokes it before executing plan steps, `nish-ai-quick-task` invokes it when a chore touches source. Backstop: a PreToolUse hook (`hooks/coding-pretooluse.sh`) injects the ladder and principles on the first source-file edit of any session, so unrouted sessions still get the ruleset. The `nish-ai-code-reviewer` agent re-checks the same seven principles at commit boundaries with fresh context. "drop coding style" creates `~/.claude/.coding-off`, which silences the hook; delete the marker to re-arm.
