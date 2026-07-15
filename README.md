# Ziarmy

A Claude Code plugin bundling two multi-agent team skills — **dev-team** builds, **deploy-team** ships. The main session acts as the manager (coordinates only, never implements); the work is done by a team of agents with a fixed model orchestration:

| Role | Model | Count | Job |
|---|---|---|---|
| Manager | main session | 1 | Break down, dispatch, integrate, ship |
| Executor | Sonnet 5 (`model: "sonnet"`) | many | Implement one task in parallel with the others |
| Reviewer | Opus 4.8 (`model: "opus"`) | many | Gate every task before dependent work proceeds |
| Advisor | Fable 5 (`model: "fable"`) | **exactly 1** | Architecture decisions and critical items |

- **Cap** — at most 10 agents running concurrently.
- **One advisor, ever** — spawned once before any executor; all later escalations return to the same agent via SendMessage so it keeps full context.

## Skills

### dev-team — build

Triggers when a request needs breaking down: multi-part features, cross-cutting refactors, "build X end to end", audits spanning many files, or an explicit ask to parallelize.

How it works:
1. **Break down** — decomposes the request (scoped against the real codebase, not assumptions) into a task graph: every task gets an ID, a verifiable done-check, exclusive file ownership, and dependencies. Tasks group into waves — wave width is where the parallelism comes from.
2. **Advisor gate** — the single Fable 5 advisor validates the breakdown, makes the binding architecture decisions, and flags critical items before anyone writes code.
3. **Execute** — Sonnet 5 executors run one per task, spawned in parallel per wave; worktree isolation when file boundaries aren't airtight.
4. **Review between tasks** — every finished task gets an Opus 4.8 reviewer before dependent tasks may start.
5. **Integrate & verify** — full test suite, then a compact report. Deployable work is offered as a handoff to deploy-team.

No task disappears silently: every task ID ends approved, deferred with a reason, or cancelled by the user.

### deploy-team — ship

Picks up where dev-team ends (or any finished build): GitHub repo/CI, Docker + registries, Kubernetes, Vercel, Supabase, Fly.io/VPS, or mobile stores. Per-provider checklists live in `skills/deploy-team/references/provider-playbooks.md`.

How it works:
1. **Handoff intake** — pins the exact commit SHA, inventories the deployment surface, confirms provider + environment with the user.
2. **Advisor gate** — the advisor decides pipeline shape, secrets posture, and rollout/rollback strategy; production promotion is always a critical item.
3. **Draft artifacts in parallel** — Dockerfile, CI workflows, k8s manifests, provider config — each executor owns distinct files and must dry-run its artifact.
4. **Review** — every artifact is reviewed before it's committed, built, or applied; any secret found in a file is an automatic highest-severity must-fix.
5. **Gated ship sequence** — branch → PR → CI green → build/push image → staging → production, executed by the manager only.
6. **Runbook** — what shipped (SHA, image tag, URL), where secrets live, and the rollback command — written down before it's needed.

Two iron rules:
1. **The provider is always the user's decision** — the team recommends, never picks silently.
2. **Agents draft; only the manager ships** — executors and reviewers work on files and dry-runs; pushes, image pushes, `kubectl apply`, and deploys run from the main session, with explicit user confirmation before production, every time.

## Reviewer fix authority (v1.2.0)

Reviewers don't just report — they may **directly fix the issues they found**, under tight guardrails:

- Only the findings they themselves listed, only within the task's owned files.
- Re-run the done-check after fixing, report `VERDICT: fixed` with a finding→fix mapping, then **return to review-only** — no extra refactors, no "while I'm here" changes.
- `must-fix` is reserved for findings outside that scope (other files, substantial rework) — those go back to an executor.
- Design concerns are never fixed by a reviewer — they ESCALATE to the advisor.
- In deploy-team, fix authority stops at drafts: a reviewer patching an artifact still never pushes, applies, or deploys.

## Graphify-first (v1.2.0)

When the repo has a knowledge graph (`graphify-out/graph.json`), the advisor and all reviewers work from it — `graphify query` / `graphify path` / `graphify explain` — instead of re-reading the codebase. Raw files are opened only for the specific lines the graph points at. This keeps the advisor's and reviewers' context small and their answers grounded in the real dependency structure.

## Caveman mode (v1.1.0)

Tokens go to thinking and code, not talk:

- **Status updates**: one line per event in a fixed format — `[w2] exec 3/5 done | review 2 ok, 1 must-fix | advisor: 0 open` — emitted only on wave start, failure, escalation, wave clear, done.
- **Questions to the user**: one line + 2–4 short options, recommended first, batched when related. Brevity never waives the production confirmation gate — it just makes it short: `deploy PROD now? <sha> → <provider>` yes/no.
- **Agent reports**: hard-capped at ~10 lines; overflow goes to a scratchpad file and the message carries the path. Detail lives in plan files; messages carry deltas and pointers.

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
