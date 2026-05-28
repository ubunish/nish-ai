# Nish AI Skills

Claude Code skills for personal workflow. Auto-active via SessionStart hook.

## Install

```
git clone https://github.com/ubunish/nish-ai.git ~/nish-ai
cd ~/nish-ai && ./install.sh
```

Symlinks skills into `~/.claude/skills/`, adds SessionStart hook to `~/.claude/settings.json`, and sets `autoMemoryEnabled: false` to disable auto-memory. Requires `jq` (`brew install jq`).

## Commands

| Command | Action |
|---------|--------|
| `./install.sh` | Link skills + add hook (idempotent) |
| `./install.sh uninstall` | Remove symlinks + hook |
| `./install.sh status` | Show what's linked |

## Skills

| Skill | Purpose |
|-------|---------|
| `nish-ai-writing-style` | Auto-active prose style |
| `nish-ai-github` | Commit + branch + PR conventions |
| `nish-ai-prompt-recognition` | Session router (fires once) |
| `nish-ai-coding` | Auto-active coding principles |
| `nish-ai-project-planning` | Grill-me planner → `plans/*.md` |
| `nish-ai-user-question` | Answer + recommendation + tradeoff |
| `nish-ai-goal-oriented-coding` | Plan execution workflow |
| `nish-ai-documentation` | Docs writer |
| `nish-ai-quick-task` | Vanilla Claude mode |
