---
name: deploy-team
description: This skill should be used when built work needs to be shipped — deploying an app or service, setting up or fixing CI/CD, dockerizing a project, pushing images to a registry, Kubernetes manifests/rollouts, GitHub repo and release management, or when the user says "deploy this", "ship it", "set up the pipeline", or hands off a completed dev-team build. Runs deployment as a team of up to 10 agents with the fixed model orchestration — Sonnet 5 executors, Opus 4.8 reviewers between tasks, one Fable 5 advisor — and treats the deployment provider as the user's decision, never the team's.
---

# Deploy Team — Multi-Agent Deployment Orchestration

Take work the dev-team skill (or any build) has finished and get it deployed: GitHub repo state, CI/CD, container builds, image pushes, Kubernetes, or provider-native deploys. Same team model as dev-team — the main session is the **manager** (coordinates only), **Sonnet 5 executors** produce deployment artifacts, **Opus 4.8 reviewers** gate every artifact before it is used, and **one Fable 5 advisor** owns the deployment architecture.

## Team Roles and Model Assignment

Set via the Agent tool's `model` parameter:

| Role | Model param | Model | Count | Job |
|---|---|---|---|---|
| Manager | (main session) | — | 1 | Handoff intake, provider decision with user, dispatch, run the gated ship steps. |
| Executor | `model: "sonnet"` | Sonnet 5 | many | Produce one deployment artifact (Dockerfile, workflow, manifest…) and dry-run it. |
| Reviewer | `model: "opus"` | Opus 4.8 | many | Review one artifact before it is committed, built, or applied. |
| Advisor | `model: "fable"` | Fable 5 | **exactly 1** | Deployment architecture, security/secrets posture, rollout & rollback strategy. |

Hard limits (identical to dev-team):
- **At most 10 agents running concurrently.**
- **Never spawn a second advisor** — spawn once, escalate later via `SendMessage` to the same agent.
- **Scale to the job.** Honor user sizing args (`team=N`, `--solo`); a one-artifact deploy is one executor + one reviewer.

**Agent types**: when the ziarmy agents are installed (`~/.claude/agents/` or the ziarmy plugin), spawn by type — `subagent_type: "ziarmy-advisor" / "ziarmy-deploy-executor" / "ziarmy-deploy-reviewer"` (plugin-namespaced: `ziarmy:ziarmy-deploy-executor`, …). Draft-only and no-secrets guardrails are baked in; the spawn prompt carries only task-specific lines. Fallback: `general-purpose` with the `model` param and the full templates in `references/role-prompts.md`.

## Communication — caveman mode

Spend tokens on artifacts and verification, not on talk. Detail lives in the deploy plan/runbook; messages carry deltas and pointers only.

- **Status to user**: one line per event: `[draft] 4/5 ok | ci: green | image: pushed sha-abc123`. Emit only on: stage start, failure, escalation, stage clear, done.
- **Questions to user**: one line + AskUserQuestion options, recommended first, batched when related. Provider choice: `Q: provider?` + options with a one-line reason each. Production gate stays explicit but short: `deploy PROD now? <sha> → <provider>` yes/no — brevity never waives the confirmation.
- **Agent ↔ manager**: structured return blocks from `references/role-prompts.md`, hard cap ~10 lines; overflow goes to a scratchpad file, message carries the path.
- **Final report**: compact bullets — shipped (sha/tag/url) / rollback command / findings that mattered / deferred+why. The runbook file holds the rest.

## Two Iron Rules

1. **The provider is the user's decision.** If the user has not named the deployment provider (Vercel, Supabase, a Docker registry + Kubernetes, Fly.io, a VPS, app stores, …), ask with AskUserQuestion before spawning any agent. Recommend one with reasons, but never pick silently. Record the decision in the deploy plan file.
2. **Agents draft; only the manager ships.** Executors and reviewers work on files and dry-runs only. Every outward-facing or hard-to-reverse action — creating/renaming a GitHub repo, pushing to a remote, pushing an image to a registry, `kubectl apply`, promoting to production, deleting infrastructure — is executed by the manager session, after review approval, and after explicit user confirmation for production-facing steps. Secrets never appear in committed files, agent prompts, or logs; they go in the provider's secret store (`gh secret set`, Vercel env, k8s Secrets).

## Workflow

### Step 1 — Handoff intake

1. Locate what is being shipped: the dev-team plan file (`<scratchpad>/team-plan.md`) if this follows a dev-team run, otherwise the current branch. Confirm the working tree is clean, tests pass, and note the exact commit SHA being deployed. If the build came from a multi-agent run, an integrator **GO verdict** (see the `integrator` skill — check the plan file's `## Integration` section, run the gate if missing) is a prerequisite for the ship sequence.
2. Inventory the deployment surface: `gh repo view` for repo state, existing Dockerfiles / workflow files / manifests / provider configs, and how the project is built (run `graphify query` first when `graphify-out/graph.json` exists).
3. Confirm the provider with the user (Iron Rule 1) plus the target environment (preview/staging vs production) and image registry if containers are involved.
4. Write a **deploy plan** to `<scratchpad>/deploy-plan.md` using `assets/deploy-plan-template.md` — keep its field names exactly; agents parse by heading. It carries the provider decision, commit SHA, task list, secrets checklist (names only), ship log, and runbook. Agents receive the file path plus their task ID.
5. Mirror tasks and ship steps into the harness task list (`TaskCreate` / `TaskUpdate`) for live progress at zero message cost. If `.ziarmy/retro.md` exists, read it first.

### Step 2 — Advisor kickoff (deployment architecture gate)

Spawn the single Fable 5 advisor (`run_in_background: false`) with the deploy plan path. When `graphify-out/graph.json` exists, instruct it to work from the knowledge graph (`graphify query` / `graphify path` / `graphify explain`) instead of re-reading the codebase — raw files only for specific lines the graph points at. Ask it to decide:
- Pipeline shape: what CI must run, build strategy (multi-stage Docker, provider build, mobile build), artifact flow from commit to running deployment.
- Security posture: secret inventory and where each lives, registry auth, least-privilege tokens, what must never land in git.
- Rollout and rollback: how the deploy is verified, how it is rolled back, and which steps are **critical items** requiring its sign-off before the manager executes them.

Apply corrections to the deploy plan. All later escalations go to this same agent via `SendMessage`.

### Step 3 — Draft artifacts in parallel

Deployment artifacts are separate files, so one wave is usually wide. Spawn all executors **in a single message**, `model: "sonnet"`, each owning distinct files, e.g.:

- `Dockerfile` + `.dockerignore` (multi-stage, pinned base images, non-root user) — must dry-run `docker build`.
- CI workflow (`.github/workflows/*.yml` — lean on the `github-actions-templates` skill) — validate syntax, reference secrets by name only.
- Kubernetes manifests or Helm values (Deployment/Service/Ingress, probes, resource limits) — must pass `kubectl apply --dry-run=client` or `kubeval` when available.
- Provider config (`vercel.json`, `fly.toml`, `supabase/config.toml`, store metadata…).
- Env/secrets checklist: every variable the app needs, where it comes from, which store holds it.

Prompt templates are in `references/role-prompts.md`; per-provider checklists in `references/provider-playbooks.md` — point executors at the playbook section for the chosen provider.

### Step 4 — Review between tasks (the gate)

Every artifact gets an Opus 4.8 reviewer before the manager commits or uses it, in parallel as executor results arrive (10-agent cap applies). Reviewers orient with `graphify query` when `graphify-out/graph.json` exists instead of re-reading the codebase, and check, beyond correctness: **no secrets or tokens in any file**, pinned versions (base images, actions by SHA/major), least privilege, health checks and rollback paths present, and provider-playbook conformance.

Verdicts: **approve** / **fixed** / **must-fix** / **ESCALATE** (design concern → advisor via `SendMessage`):
- **Reviewer fix authority**: the reviewer may directly fix the issues it found — strictly its own listed findings, within the artifact's owned files, re-running the dry-run done-check after. Then it **returns to review-only**: no extra changes beyond its findings. Fixing never extends to shipping — the draft-only rule still binds reviewers.
- **must-fix** is reserved for findings outside that scope (other files, substantial rework) → back to an executor and re-review.

### Step 5 — Gated ship sequence (manager only)

Execute in order, only with approved artifacts, checking the advisor's critical-item list at each step:

1. **Repo**: commit artifacts on a branch, push, open a PR (`gh pr create`). Creating a new repo or changing repo settings → confirm with user first.
2. **CI green**: let the pipeline run; failures go back to an executor as a must-fix task.
3. **Build & push image** (if containerized): build locally or in CI, push to the chosen registry.
4. **Deploy to preview/staging first** whenever the provider supports it; verify with real checks (health endpoint, smoke test, logs) — not just exit codes.
5. **Production**: explicit user confirmation immediately before this step, every time, even if earlier steps were pre-authorized. Then deploy, verify, and record the rollback command in the deploy plan.

### Step 6 — Verify, document, report

1. Post-deploy verification: run the provider's smoke test from `references/provider-playbooks.md` — hit the deployed surface, check logs/status (`gh run watch`, `kubectl rollout status`, provider status CLI). Exit codes alone don't count.
2. Update the deploy plan file into a **runbook**: what was deployed (SHA, image tag), where, how to roll back, where secrets live.
3. Report to the user: outcome per task, review findings that mattered, advisor decisions, the live URL/environment, and the rollback path. Report failures faithfully — a red pipeline is reported red.
4. Append a retro to `.ziarmy/retro.md`: shipped yes/partial/rolled-back, reviewer verdict counts, secrets caught, one lesson. 2–5 lines.

## Failure handling

- Failed deploy or failed post-deploy verification → roll back first (advisor's documented strategy), diagnose second.
- Executor returns null → respawn once; twice-failed goes to the advisor with error context.
- CI flakiness is not "retry until green" — a persistently red check becomes a must-fix task with an owner.
- Never leave the system half-shipped silently: every task ID ends approved-and-shipped, deferred (with reason), or rolled back — and the final report says which.

## References

- `references/role-prompts.md` — prompt templates for the deployment advisor, executors, and reviewers.
- `references/provider-playbooks.md` — per-provider checklists (Docker/registry, GitHub Actions, Kubernetes, Vercel, Supabase, Fly.io/VPS, mobile stores). Load only the section for the chosen provider.
