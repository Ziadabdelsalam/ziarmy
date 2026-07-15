# Ziarmy

A Claude Code plugin bundling three multi-agent team skills — **dev-team** builds, **integrator** verifies it all works together, **deploy-team** ships. The main session acts as the manager (coordinates only, never implements); the work is done by a team of agents with a fixed model orchestration:

| Role | Model | Count | Job |
|---|---|---|---|
| Manager | main session | 1 | Break down, dispatch, integrate, ship |
| Executor | Sonnet 5 (`model: "sonnet"`) | many | Implement one task in parallel with the others |
| Reviewer | Opus 4.8 (`model: "opus"`) | many | Gate every task before dependent work proceeds |
| Integrator | Opus 4.8 (`model: "opus"`) | **exactly 1** | End-to-end gate: seams between tasks, GO/NO-GO |
| Advisor | Fable 5 (`model: "fable"`) | **exactly 1** | Architecture decisions and critical items |

- **Cap** — at most 10 agents running concurrently, and the team scales to the job: `team=N` / `--solo` sizing args are honored, so a two-file change never spins up a 10-agent army.
- **One advisor, ever** — spawned once before any executor; all later escalations return to the same agent via SendMessage so it keeps full context.

## Bundled agent definitions (v1.3.0)

The roles aren't just prompts — the plugin ships real agent definitions in `agents/`, so the guardrails are enforced by tool restrictions, not requested by prose:

| Agent | Model | Enforced restrictions |
|---|---|---|
| `ziarmy-advisor` | Fable 5 | Read-only: no Write/Edit, no subagent spawning |
| `ziarmy-executor` | Sonnet 5 | Full dev tools; cannot spawn subagents |
| `ziarmy-reviewer` | Opus 4.8 | Can edit (fix authority) but not spawn subagents |
| `ziarmy-integrator` | Opus 4.8 | Seam-slip fix authority only; never redesigns, commits, or ships |
| `ziarmy-deploy-executor` | Sonnet 5 | Draft-only + no-secrets rules baked into the system prompt |
| `ziarmy-deploy-reviewer` | Opus 4.8 | Secrets scan first; fix authority; drafts only |

Installed via the plugin they're namespaced (`ziarmy:ziarmy-executor`); `scripts/sync.sh` also copies them to `~/.claude/agents/` for standalone use. Spawning by agent type means the manager sends only the task-specific lines (plan path, task ID, owned files, done-check) — the standing rules live in the definitions. Without the agents installed, the skills fall back to `general-purpose` + the full templates in `references/role-prompts.md`.

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

### integrator — verify the whole

Per-task reviewers see one task inside its file boundary; integration bugs live *between* boundaries. After the final dev-team wave clears review (or standalone, on "does it all work together"), exactly one integrator agent checks the seams — contracts, data shapes, naming across ownership boundaries, using `graphify path` when a knowledge graph exists — runs the full suite, and **drives the real flows**, not just exit codes.

Outcomes: **GO** → proceed. **FIXED-GO** → it fixed seam slips itself (only its own findings, minimal diffs, suite re-run). **NO-GO** → it writes an ADVISOR BRIEF that the manager forwards verbatim to the advisor; the advisor answers with fix tasks that run through the normal dev-team machinery (executors implement, reviewers gate), and the same integrator re-verifies. Two NO-GO rounds on the same seam → the decision goes to the user, never a silent loop. A GO verdict is a prerequisite before deploy-team will start its ship sequence on a multi-agent build.

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

## Structured plan files & live tracking (v1.3.0)

Every run is driven by a parseable plan file with fixed headings — `skills/dev-team/assets/plan-template.md` for builds, `skills/deploy-team/assets/deploy-plan-template.md` for deploys (the deploy variant adds a secrets checklist, ship log, and runbook). Agents parse their task by heading; the manager mirrors the task graph into the harness task list (TaskCreate/TaskUpdate) so progress is visible live at zero message cost. The plan file is also the handoff contract from dev-team to deploy-team.

## Workflow mode (v1.3.0)

At ≥6 tasks, ≥2 waves, or a user token budget ("+500k"), dev-team switches from hand-dispatched agents to the Workflow tool (`skills/dev-team/references/workflow-mode.md`): a deterministic execute→review pipeline where each task's review starts the moment its executor finishes, concurrency is enforced by the runtime, crashed runs resume from cache, and token budgets are honored. The advisor, must-fix rounds, escalations, and integration stay with the manager.

## Retro loop (v1.3.0)

After every run, the manager appends 2–5 caveman lines to `.ziarmy/retro.md` in the target repo: tasks approved/total, breakdown corrections the advisor made, reviewer verdict counts, one lesson. Future runs read it before decomposing — the only feature here that compounds.

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

The master copies of the skills live in `~/.agents/skills/{dev-team,deploy-team}`; the agents' masters live here in `agents/`. After editing, run the sync script — it copies skills into the plugin, installs agents to `~/.claude/agents/`, and validates:

```
./scripts/sync.sh
```

Then bump the version in both `.claude-plugin/*.json` files and push. CI (`.github/workflows/validate.yml`) validates the plugin, checks the versions match across manifests, and auto-tags `vX.Y.Z` on main when the version changes.
