# Ziarmy

A Claude Code plugin bundling two multi-agent team skills that share one fixed model orchestration:

- **Executors = Sonnet 5** (`model: "sonnet"`) — implement tasks in parallel
- **Reviewers = Opus 4.8** (`model: "opus"`) — gate every task before dependent work proceeds
- **Advisor = Fable 5** (`model: "fable"`) — exactly one per run; architecture and critical decisions
- **Cap** — at most 10 agents running concurrently
- **Caveman mode** — one-line status updates, one-line questions with short options, agent reports hard-capped at ~10 lines (detail lives in plan files, not messages)

## Skills

### dev-team
Triggers when a request needs breaking down (multi-part features, cross-cutting refactors, "build X end to end"). Decomposes into a dependency-ordered task graph with exclusive file ownership, executes in wide parallel waves, reviews between tasks, escalates design questions to the single advisor, then integrates and verifies.

### deploy-team
Picks up where dev-team ends (or any finished build) and ships it: GitHub repo/CI, Docker + registries, Kubernetes, Vercel, Supabase, Fly.io/VPS, or mobile stores. Two iron rules: the deployment provider is always the user's decision, and agents only draft/dry-run — the manager session performs pushes, applies, and deploys, with explicit user confirmation before production.

## Install

From GitHub:

```
claude plugin marketplace add Ziadabdelsalam/ziarmy
claude plugin install ziarmy@ziarmy
```

Or from a local clone:

```
claude plugin marketplace add /path/to/ziarmy
claude plugin install ziarmy@ziarmy
```

> Note: if the same skills are also active as standalone skills in `~/.claude/skills/` (dev-team, deploy-team), remove those after installing the plugin to avoid duplicate skill listings.

## Updating

The master copies of these skills live in `~/.agents/skills/{dev-team,deploy-team}`. After editing them, re-sync into the plugin, bump the version in both `.claude-plugin/*.json` files, and push:

```
cp -R ~/.agents/skills/dev-team ~/.agents/skills/deploy-team ~/.agents/plugins/ziarmy/skills/
```
