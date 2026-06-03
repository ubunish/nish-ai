---
name: nish-ai-ros2
description: >
  Nish's ROS2 best practices, tailored from Henki's reference set. Targets ROS2
  Humble Hawksbill (LTS). Auto-active
  whenever Claude writes or edits ROS2 code in any session — detected by ROS2
  signals: a `package.xml` with `ament_cmake`/`ament_python`, `rclpy`/`rclcpp`
  imports, `.msg`/`.srv`/`.action` interface files, a `launch/` or `config/`
  folder, or `colcon`/`rosdep`/`ros2` tooling. Thirty practices across nodes,
  launch, params, logging, messages, actions/services, code style, performance,
  executors, dependencies, docs, and testing. Rides the auto-active tier
  alongside nish-ai-writing-style and nish-ai-coding. Off only on "drop ros2".
---

## Target Distribution

These practices target **ROS2 Humble Hawksbill** — the current LTS distribution.
Tooling, APIs, and conventions assume Humble unless a rule says otherwise. On a
different distro, verify API and tooling compatibility before applying.

## Detection

Load this skill when the working context shows any ROS2 signal:

```
package.xml with ament_cmake / ament_python   → ROS2 package
import rclpy  /  #include <rclcpp/...>          → ROS2 node code
*.msg / *.srv / *.action                        → interface definitions
launch/ folder, *.launch.py, *.launch.xml       → launch surface
config/*.yaml param files                        → param surface
colcon / rosdep / ros2 / vcs CLI usage           → ROS2 workspace
```

No signal → do not load. A plain-Python or plain-C++ edit with none of the
above is not ROS2 work.

## Principles

Twelve groups, thirty practices. Terse by design — each line is a rule, not an
essay.

### Nodes

1. Single responsibility per node.
2. Separate application logic from ROS comms — logic in its own class/library, node handles only communication. Improves clarity, testability, maintainability.

### Launch

3. Launch files live in `launch/`.
4. Prefer Python launch files; use XML when it is simpler for the case.
5. No node params in launch files — use config files instead.

### Parameters and Config

6. Node params in YAML under `config/`.
7. Package-level YAML holds defaults; users override in their own copies, never edit defaults directly.
8. Runtime-changeable params → make dynamic via parameter callbacks.

### Logging

9. Use the ROS2 logger, never `print()` or `std::cout`.
10. Correct log levels: `INFO` normal operation, `WARN` recoverable surprise, `ERROR` critical failure needing action.
11. Throttle logs on high-frequency callbacks to avoid flooding.

### Message Interfaces

12. Reuse existing messages first (e.g. `common_interfaces`: `geometry_msgs`, `sensor_msgs`, `nav_msgs`, `tf2_msgs`).
13. Custom messages live in their own `_msgs` package — reusable without depending on the full package.
14. No primitive `std_msgs`/`example_interfaces` types (`Float32`, `Bool`, `String`) for real data; use a semantically named custom message. General types like `std_msgs/Header` are fine.
15. Simulate enums in messages with integer constants (see `level` in `DiagnosticStatus`).

### Actions and Services

16. Services for fast tasks (<1s, e.g. get/set state); actions for slow, cancellable, or multi-error tasks.
17. Prefer enum-style error codes over string messages — clients parse reliably, enables localized messages.

### Code Style

18. Follow the official ROS2 code style guide.
19. Match existing project style on legacy code; apply updated practices only to new or refactored nodes.

### Performance

20. C++ for performance-critical nodes (high-frequency loops, high-bandwidth data); Python for tooling, orchestration, testing, prototyping.
21. C++ composable nodes with intra-process comms for large data (images, point clouds) — avoids memory and DDS overhead.

### Executors

22. Prefer `SingleThreadedExecutor` — cleaner, deterministic, lower overhead. Reach for `MultiThreadedExecutor` only when genuinely required.

### Dependencies

23. Declare dependencies at package level: `package.xml` + `rosdep`.
24. Pin exact external versions (`requirements.txt` for Python); use `vcstool` + `.repos` with commit hash or tag for source dependencies.
25. Do not rebuild external packages to change config or launch — copy those files into your workspace and edit there.

### Documentation

26. Per-package `README.md` documenting each node: short description, usage, API (topics/services/actions), and parameters with type, description, default.

### Testing

27. Unit-test core application logic with mocks; nodes themselves skip unit tests when logic is well-separated.
28. Test node communication behavior in integration tests.
29. Aim for high coverage (90-100%).
30. No arbitrary sleeps in tests — use synchronization or wait-with-timeout to avoid flakiness.

## Lifetime

Auto-active when writing or editing ROS2 code, detected by the signals above.
Enforced at the commit boundary by `nish-ai-goal-oriented-coding` alongside
`nish-ai-coding`. Off only on "drop ros2".
