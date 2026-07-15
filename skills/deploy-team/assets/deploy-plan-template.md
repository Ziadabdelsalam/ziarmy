# Deploy Plan — {one-line goal}

meta:
- date: {YYYY-MM-DD}
- shipping: {branch} @ {sha}
- provider: {user's decision} | environment: {preview/staging → production}
- registry: {if containers} | image: {registry/name:tag}
- mode: waves | solo
- team-cap: {N ≤ 10}

## Advisor decisions
- D1: {pipeline shape / security / rollout decision} — {rationale}

## Critical items
<!-- Steps/tasks requiring advisor sign-off + user confirmation. Production promotion is always here. -->
- {T# or ship-step} — {why}

## Secrets checklist
<!-- Names only. NEVER values. -->
| name | needed by | source | store |
|---|---|---|---|
| {SECRET_NAME} | {artifact/service} | {user/password manager} | {gh secret / vercel env / k8s secret} |

## Tasks
### T1: {artifact, e.g. Dockerfile}
- status: pending | executing | in-review | fixed | approved | must-fix | deferred | cancelled
- owns: {files}
- playbook: {provider section name}
- done-check: `{dry-run command}`
- result:

## Ship log (manager only, append as executed)
<!-- step — command — result — confirmation ref (for gated steps) -->

## Runbook (final)
- deployed: {sha} | image {tag+digest} | url {live url}
- verify: `{smoke test command}`
- rollback: `{exact command}`
- secrets live in: {stores}

## Escalations log

## Retro (filled at end of run)
- shipped: yes/partial/rolled-back — {one line}
- reviewer verdicts: {approve}/{fixed}/{must-fix} | secrets caught: {n}
- lesson: {one line}
