# Nish AI Skills

Claude Code skills for personal workflow. Auto-active via SessionStart hook.

## Install

```
git clone https://github.com/ubunish/nish-ai.git ~/nish-ai
cd ~/nish-ai && ./install.sh
```

Symlinks skills into `~/.claude/skills/`, slash commands into `~/.claude/commands/`, reviewer agents into `~/.claude/agents/`, adds the router, writing-style, commit-validator, and uv-enforcement hooks to `~/.claude/settings.json`, wires the writing-style statusline badge, installs the `clangd-lsp` code-intelligence plugin, sets `autoMemoryEnabled: false` to disable auto-memory, and merges a set of permission rules into `.permissions` so common safe tools stop prompting. Requires `jq` (`brew install jq`); the plugin step also needs the `claude` CLI.

The diagram-producing skills (`nish-ai-project-planning`, `nish-ai-documentation`, `nish-ai-writing-style`) render mermaid to static images with the Mermaid CLI (`mmdc`) when it is on `PATH`, and fall back to raw mermaid blocks otherwise. It is optional and managed by nish-setup (`brew install mermaid-cli`).

## Commands

| Command | Action |
|---------|--------|
| `./install.sh` | Link skills + add hook (idempotent) |
| `./install.sh uninstall` | Remove symlinks + hook |
| `./install.sh status` | Show what's linked |
| `./tests/run.sh` | Run the commit-hook test suite (no bats; needs `jq` + `perl`) |
| `./tests/uv.sh` | Run the uv-hook test suite (no bats; needs `jq`) |
| `./tests/agents.sh` | Run the reviewer-agent test suite (no bats; needs `jq`) |

## Skills

| Skill | Purpose |
|-------|---------|
| `nish-ai-writing-style` | Auto-active prose style, two modes by surface (TERMINAL / DOCS) |
| `nish-ai-github` | Commit + branch + PR conventions |
| `nish-ai-prompt-recognition` | Session router (fires once) |
| `nish-ai-coding` | Auto-active coding principles |
| `nish-ai-project-planning` | Grill-me planner → `plans/*.md` |
| `nish-ai-user-question` | Answer + recommendation + tradeoff |
| `nish-ai-goal-oriented-coding` | Plan execution workflow |
| `nish-ai-documentation` | Docs writer |
| `nish-ai-quick-task` | Vanilla Claude mode |
| `nish-ai-ros2` | Auto-active ROS2 best practices (rides the always-on tier) |
| `nish-ai-uv` | Auto-active "prefer uv" convention + SessionStart anchor + PreToolUse enforcement hook |

## Slash Commands

Symlinked into `~/.claude/commands/` by `install.sh`.

| Command | Action |
|---------|--------|
| `/merge` | Merge the current branch into `main` without a PR, push, and delete the branch (local + remote) |

## Agents

Fresh-context reviewer subagents, symlinked into `~/.claude/agents/` by `install.sh`. Spawned by `nish-ai-goal-oriented-coding` at the commit gate — a reviewer with no attachment to how the code was written catches residue the writer's own context hides. Both run on Haiku, read-only, and return severity-tagged findings: `high` blocks the commit, `low` surfaces as a note.

| Agent | Lens | Spawns |
|-------|------|--------|
| `nish-ai-code-reviewer` | The seven `nish-ai-coding` principles | Every commit |
| `nish-ai-security-reviewer` | Threat checklist (injection, secrets, auth, traversal, crypto, deserialization, info leak, supply chain) | Only when the diff touches a security surface |

## Permissions

`install.sh` merges a set of `allow` permission rules into `.permissions` in `~/.claude/settings.json`, so the session stops prompting for tools that are safe to auto-run. The merge is by set membership: existing rules (yours or Claude Code's own "always allow") are preserved, only missing entries are added, and `uninstall` removes exactly these and nothing else.

The rule of thumb: auto-allow the read-only and local-reversible work; let everything else fall through to a normal prompt.

| Tier | Rule | Rules |
|------|------|-------|
| 1 | allow | `Read`, `Grep`, `Glob`, `WebSearch`, `WebFetch`, `cd` — zero side effects |
| 2 | allow | `Edit`, `Write`, `git add\|commit\|branch\|checkout\|merge` — local, reversible |
| 3 | allow | `ls`, `cat`, `pwd`, `which`, `find`, `head`, `tail`, `wc`, `file`, `tree` — read-only shell |
| 4 | allow | `npm test\|run`, `pytest`, `ruff`, `eslint`, `tsc`, `uv run` — test/lint/build, no network |

Tiers 3-4 never touch the network and read project code only. Network installs and arbitrary remote execution (`npm install`, `npx`, `uvx`, `pip install`, ...) are deliberately left off the allow list — they pull and run remote code, so they keep prompting as a supply-chain guard.

Nothing is denied. Anything outside the allow list (`git push`, `git reset --hard`, `rm -rf`, `gh pr merge`, ...) falls through to a normal permission prompt rather than a hard block, so Claude can still run it when asked. The deny logic stays in `install.sh` with an empty list — add an entry to `PERM_DENY_JSON` if a hard block is ever wanted.

Tier 4's `npm run` / `uv run` execute whatever the project's scripts define, so the allow list trusts the contents of the repo you are working in. Tier 2 writes are auto-allowed because the `nish-ai-goal-oriented-coding` commit gate and reviewer agents already catch problems before the commit; push, merge, and release stay manual. A `deny` entry wins over `allow`, so adding one to `PERM_DENY_JSON` keeps that tool prompting even if a broad allow rule lands later.

## Tests

`tests/run.sh` covers the two fragile commit hooks with plain bash assertions — no bats, so it runs anywhere the hooks run. It exercises `validate-commit.sh` (pass / rewrite / deny decisions) and `rewrite-commit.pl` (body and trailer collapse, prefix and tail preservation, bail cases). Needs `jq` and `perl`.

`tests/uv.sh` covers the uv-enforcement hook the same way: deny + rewrite for python/pip/poetry/pipenv/virtualenv, and pass-through for uv, conda, an active `$VIRTUAL_ENV`, and the `drop uv` bypass marker. Needs `jq`.

`tests/agents.sh` covers the reviewer agent layer: every `agents/*.md` declares valid frontmatter (name matching filename, description, `model: haiku`, read-only tools), and `install.sh` links the agents into `~/.claude/agents/`, reports them under `status`, and removes them under `uninstall`. The install cycle runs against a throwaway `HOME` with a stub `claude` on `PATH`, so it never touches the real environment or the network. Needs `jq`.

```
./tests/run.sh
./tests/uv.sh
./tests/agents.sh
```

## Repo Layout

```
nish-ai/
├── install.sh                  link skills + commands, wire hooks
├── commands/                   slash commands → ~/.claude/commands/
│   └── merge.md
├── agents/                      reviewer subagents → ~/.claude/agents/
│   ├── nish-ai-code-reviewer.md
│   └── nish-ai-security-reviewer.md
├── tests/                       hook + agent test suites (run.sh, uv.sh, agents.sh)
├── nish-ai-writing-style/      always-on prose style (+ hooks/)
├── nish-ai-uv/                 always-on "prefer uv" convention (+ hooks/)
├── nish-ai-github/             commit/branch/PR conventions (+ hooks/)
├── nish-ai-prompt-recognition/ session router (+ hooks/)
└── nish-ai-categories/         skills dispatched by the router
    ├── nish-ai-coding/
    ├── nish-ai-project-planning/
    ├── nish-ai-user-question/
    ├── nish-ai-goal-oriented-coding/
    ├── nish-ai-documentation/
    ├── nish-ai-quick-task/
    └── nish-ai-ros2/
```

`install.sh` finds every `SKILL.md` by `find`, so the `nish-ai-categories/` grouping is for repo organization only — skills link into `~/.claude/skills/` by basename, flat. Commands and agents link the same way, from `commands/*.md` and `agents/*.md`.

## Architecture

Two layers: install-time wiring (one-off) and per-session runtime (every session).

### Install Wiring

`install.sh` mutates the Claude Code environment, idempotent and reversible.

```mermaid
flowchart LR
    I["install.sh"] --> S["symlink SKILL.md dirs<br/>→ ~/.claude/skills/"]
    I --> C["symlink commands/*.md<br/>→ ~/.claude/commands/"]
    I --> AG["symlink agents/*.md<br/>→ ~/.claude/agents/"]
    I --> HR["add router hooks<br/>SessionStart + UserPromptSubmit → settings.json"]
    I --> HS["add writing-style hooks<br/>SessionStart + UserPromptSubmit"]
    I --> HV["add commit-format validator + anchor<br/>SessionStart + PreToolUse(Bash) → settings.json"]
    I --> HU["add uv anchor + enforcement hook<br/>SessionStart + PreToolUse(Bash) → settings.json"]
    I --> SL["wire statusline badge<br/>.statusLine → settings.json"]
    I --> PL["install clangd-lsp plugin<br/>claude plugin install"]
    I --> M["set autoMemoryEnabled=false<br/>→ settings.json"]
```

| Action | Effect |
|--------|--------|
| Symlink | Each skill dir linked into `~/.claude/skills/`, each `commands/*.md` into `~/.claude/commands/`, and each `agents/*.md` into `~/.claude/agents/`, so Claude discovers them |
| Router hooks | Hard dispatch, not a soft pointer. SessionStart injects the full router ruleset and arms a once-per-session flag; UserPromptSubmit consumes the flag on the first prompt to force categorize + dispatch. Mirrors the writing-style two-hook pattern |
| Style hooks | SessionStart injects full ruleset; UserPromptSubmit re-injects a reminder each turn |
| Commit validator | PreToolUse(Bash) auto-rewrites a `git commit` carrying a body or `Co-Authored-By` trailer down to subject-only, preserving both a `git add … &&` prefix and a chained tail (`&& git log`, `&& git push`); denies only what it cannot safely fix (bad prefix, capitalized subject, trailing period) or cannot safely collapse (a second `git commit` in the tail, or a trailer that would survive in the tail) |
| uv enforcement | PreToolUse(Bash) blocks a bare `python`/`pip`/`poetry`/`pipenv`/`virtualenv` call and denies it with the uv rewrite (`python app.py` → `uv run app.py`); passes through uv, conda, an active `$VIRTUAL_ENV`, and the `drop uv` bypass marker |
| Statusline badge | Sets `.statusLine` to render the `✎ style:on`/`off` + category badge, only when no status line is set yet; a custom `.statusLine` is left untouched |
| Plugin install | Installs the `clangd-lsp` code-intelligence plugin via the `claude plugin` CLI (marketplace `anthropics/claude-plugins-official`), idempotent; skipped if the `claude` CLI is absent |
| Auto-memory off | Disables built-in auto-memory; this system owns workflow state |

All hooks are idempotent; `uninstall` and `status` cover every hook above.

### Runtime Dispatch

Every session: SessionStart arms the router and loads its ruleset, the first prompt consumes the flag and forces dispatch, the chosen category skill owns the rest of the session.

```mermaid
flowchart TD
    SS["SessionStart hook<br/>inject ruleset + arm flag"] --> P1["first substantive prompt"]
    UP["UserPromptSubmit hook<br/>consume flag → force dispatch"] --> P1
    P1 --> R["nish-ai-prompt-recognition<br/>(router, fires once)"]
    R --> CAT{"categorize by<br/>commit prefix"}

    CAT -->|A · no commit| PLAN["nish-ai-project-planning<br/>grill → plans/*.md"]
    CAT -->|B · no commit| QN["nish-ai-user-question<br/>answer + rec + tradeoff"]
    CAT -->|C · feat/fix/refactor| GOC["nish-ai-goal-oriented-coding<br/>execute plan"]
    CAT -->|D · docs| DOC["nish-ai-documentation<br/>write docs"]
    CAT -->|E · chore| QT["nish-ai-quick-task<br/>vanilla mode"]

    GOC -.commit gate.-> RV["reviewer agents<br/>code + security (Haiku)"]
    GOC -.commit gate.-> GH["nish-ai-github"]
    DOC -.commit gate.-> GH
    PLAN -.next session.-> GOC
```

### Always-On Layer

Five skills run across every category, not dispatched by the router. They differ by mechanism.

```mermaid
flowchart TD
    subgraph hook["hook-enforced"]
        SS["SessionStart hook<br/>inject full ruleset"]
        UP["UserPromptSubmit hook<br/>per-turn reminder + off-flag toggle"]
        SL["statusLine hook<br/>render style:on/off badge"]
        PV["PreToolUse(Bash) hook<br/>validate commit message"]
        PU["PreToolUse(Bash) hook<br/>block bare python/pip → uv"]
        SS --> WS["nish-ai-writing-style"]
        UP --> WS
        SL --> WS
        PV --> GH["nish-ai-github"]
        PU --> UV["nish-ai-uv"]
    end
    subgraph disc["skill-discovery"]
        CD["nish-ai-coding<br/>auto-active on code write"]
        RO["nish-ai-ros2<br/>auto-active on ROS2 code"]
        UVD["nish-ai-uv<br/>auto-active on Python signals"]
    end
    WS -.applies to.-> ALL["every session + category"]
    CD -.applies to.-> ALL
    RO -.applies to.-> ALL
    GH -.applies to.-> ALL
    UV -.applies to.-> ALL
```

| Skill | Mechanism | Triggers on | Off switch |
|-------|-----------|-------------|------------|
| `nish-ai-writing-style` | Hooks (SessionStart + UserPromptSubmit + statusLine badge) | Every session + every turn | "drop style" / "verbose mode" → off-flag; "resume style" → on |
| `nish-ai-coding` | Skill discovery | Any source-code write or edit | "drop coding style" |
| `nish-ai-ros2` | Skill discovery | ROS2 signals: `package.xml` (ament), `rclpy`/`rclcpp`, `.msg`/`.srv`/`.action`, `launch/`/`config/` | "drop ros2" |
| `nish-ai-github` | SessionStart anchor + PreToolUse(Bash) validator + explicit invoke | Every session; every `git commit`; commit / branch / PR boundary | validator auto-fixes or denies malformed commits, not user-toggleable |
| `nish-ai-uv` | Skill discovery + SessionStart anchor + PreToolUse(Bash) hook | Every session; Python signals: `*.py`, `pip`/`poetry`/`pipenv`/`virtualenv`, `requirements.txt`, `pyproject.toml` | "drop uv" → writes `~/.claude/.uv-off` marker; anchor and hook stand down, skill stops applying |

Beyond auto-activation, `nish-ai-ros2` folds into three category skills at their boundaries: `nish-ai-coding` enforces its thirty practices at the commit gate, `nish-ai-project-planning` folds its architectural decisions (node split, custom-interface packages, services-vs-actions) into the plan, and `nish-ai-documentation` applies its per-package README structure. Off on "drop ros2".

`nish-ai-uv` mirrors the writing-style architecture: a passive auto-active skill carries the WHY and the command mapping, a SessionStart anchor primes the mapping from message one so uv is the default reach, and an active PreToolUse(Bash) hook backstops it by blocking any bare `python`/`pip`/`poetry`/`pipenv`/`virtualenv` that slips through and returning the uv rewrite. nish-setup owns the uv binary and builds the `~/.venvs/*` environments; this skill owns Claude's behavior. "drop uv" writes `~/.claude/.uv-off`, which the hook checks first — present → no-op. Conda is never redirected.

Off-flag lives at `~/.claude/.nish-style-off`. Present → both style hooks no-op. Toggled by phrase, persists across turns. The `statusLine` hook (`style-statusline.sh`) reads the same flag and renders a `✎ style:on` / `✎ style:off` badge so the active state is visible. `install.sh` wires it into the `statusLine` setting, but only when no status line is set yet — a custom `.statusLine` is left untouched.

#### Writing-Style Modes

`nish-ai-writing-style` picks one of two modes per response, chosen by output surface:

| Mode | Surface | Rule |
|------|---------|------|
| `TERMINAL` | Chat replies, explanations Nish reads (ephemeral) | Unconditional caveman — never use a/an/the, drop and/but/so, cut filler, fragments OK. No per-sentence judgement, so no drift. |
| `DOCS` | Committed artifacts others read (docs, README, code comments, PR/commit messages) | Readable-terse — keep articles and full sentences, still cut filler. Stays professional for a cold reader. |

```
chat / explanations          → TERMINAL
docs / README / comments     → DOCS
PR / commit messages         → DOCS
security / destructive / "explain more"  → exempt, full prose
```

Both modes share: state idea once, simple word over complex, diagram over text, Title Case headings, sentence case body.

### Categories

| ID | First prompt is… | Commit prefix | Skill |
|----|------------------|---------------|-------|
| A | Draft a plan | none | `nish-ai-project-planning` |
| B | A question, no code change | none | `nish-ai-user-question` |
| C | Build / fix / refactor | `feat`/`fix`/`refactor` | `nish-ai-goal-oriented-coding` |
| D | Write / restructure docs | `docs` | `nish-ai-documentation` |
| E | Light housekeeping | `chore` | `nish-ai-quick-task` |

Router picks the narrowest fit, one category per session. Re-categorizes only if the user's intent visibly pivots.
