---
name: nish-ai-coding
description: >
  Nish's coding principles. Auto-active whenever Claude writes or edits
  source code in any session. Also invoked explicitly by
  nish-ai-goal-oriented-coding at commit boundaries. Seven principles:
  modular, scalable, consistent, documented, tested, no premature
  abstraction, self-explaining. Off only on "drop coding style".
---

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
- Architecture diagram if structure non-trivial

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

## ROS2

When the code under edit is ROS2 (a `package.xml` with ament, `rclpy`/`rclcpp`, `.msg`/`.srv`/`.action`, or a `launch/`/`config/` folder), load `nish-ai-ros2` and enforce its thirty practices at the commit boundary alongside these seven principles.

## Lifetime

Auto-active when writing or editing source. Invoked explicitly by `nish-ai-goal-oriented-coding` at commit boundaries to verify principles. Off only on "drop coding style".
