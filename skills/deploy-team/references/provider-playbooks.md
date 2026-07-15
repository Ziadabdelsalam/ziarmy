# Provider Playbooks

Load only the section for the provider the user chose. Each playbook lists the artifacts to draft, the dry-run done-checks, and the manager's gated ship steps. Universal rules from SKILL.md always apply: no secrets in git, pinned versions, user confirmation before production.

## GitHub repo & CI (applies to almost every deploy)

Artifacts: `.github/workflows/*.yml` (build + test on PR; deploy on tag or main), branch protection expectations, release/tag convention.
- Prefer the `github-actions-templates` skill for workflow scaffolding; the `github` skill (`gh`) for repo operations.
- Pin actions (`actions/checkout@v4` minimum; SHA-pin for anything third-party). Least-privilege `permissions:` block per workflow — never rely on the default token scope.
- Secrets via `gh secret set NAME` — the value comes from the user or their password manager, never from a file in the repo.
- Dry-run: `gh workflow view` after push isn't a dry-run — lint YAML locally (`actionlint` if available) before commit.
- Manager ship steps: branch → push → PR → CI green → merge. New repo creation (`gh repo create`) or settings changes → user confirmation first.

## Docker + registry

Artifacts: multi-stage `Dockerfile`, `.dockerignore`, optional `compose.yaml` for local parity.
- Multi-stage: build stage with full toolchain, runtime stage minimal (distroless/alpine where sane). Non-root `USER`. `HEALTHCHECK` or documented probe. Pin base image tag (+digest for production).
- `.dockerignore` must exclude `.git`, env files, build caches — check image size is sane.
- Dry-run: `docker build .` must succeed locally; `docker run` + hit the health endpoint when feasible.
- Registry (GHCR/Docker Hub/cloud registry): tag as `registry/name:{git-sha}` plus a moving tag (`latest`/`staging`); auth via `docker login` with a scoped token (GHCR: `ghcr.io`, token needs `write:packages`).
- Manager ship steps: build → push image (confirmation if this registry/repo is new) → record image digest in the deploy plan.

## Kubernetes

Artifacts: `k8s/` manifests or Helm chart values — Deployment, Service, Ingress, ConfigMap; Secrets referenced by name only (created out-of-band or via external-secrets).
- Every Deployment: liveness + readiness probes, resource requests/limits, explicit image tag (never `latest` in prod), `imagePullSecrets` if registry is private, rolling-update strategy with sane surge/unavailable.
- Dry-run: `kubectl apply --dry-run=client -f k8s/` (or `helm template | kubectl apply --dry-run=client -f -`); `kubeval`/`kubeconform` when available.
- Manager ship steps: apply to staging namespace → `kubectl rollout status` → smoke test → user confirmation → apply to prod. Rollback: `kubectl rollout undo deployment/<name>` — record it in the runbook before deploying, not after.

## Vercel

Artifacts: `vercel.json` (only if defaults need overriding), env var checklist per environment.
- Use the `vercel:deploy`, `vercel:env`, and `vercel:status` skills — they encode current CLI behavior; don't hand-roll `vercel` commands from memory.
- Flow: link project → sync env vars (`vercel:env`) → preview deploy → verify preview URL → user confirmation → production (`vercel:deploy` with `prod`).
- Prefer Git-integration deploys (push → preview, merge → prod) over CLI deploys when a GitHub repo is connected — then this playbook reduces to the GitHub CI section plus env var management.

## Supabase (backend pieces)

Artifacts: migrations under `supabase/migrations/`, Edge Functions under `supabase/functions/`, `config.toml`.
- Load the `supabase:supabase` skill for any Supabase work — it covers CLI, migrations, and deploy specifics.
- Migrations are production-critical items by definition: advisor sign-off + user confirmation before `supabase db push` / migration apply against the cloud project. Verify against a local/branch database first when possible.
- Edge Functions: `supabase functions deploy <name>` per function; secrets via `supabase secrets set`.

## Fly.io / Railway / plain VPS

Artifacts: `fly.toml` / `railway.json` / systemd unit + reverse-proxy config; Dockerfile per the Docker section.
- Fly: `fly launch --no-deploy` to generate config, review it, `fly deploy` gated. Secrets: `fly secrets set`.
- VPS: never store SSH keys or host credentials in the repo; deploys go through CI with a deploy key, or the user runs the documented command themselves. Always draft the rollback (previous release symlink / previous image tag) before the first deploy.

## Mobile app stores (Flutter/iOS/Android)

"Deploy" means store delivery — a different beast; keep the team small and expect user-owned steps.
- Artifacts: CI workflow producing signed builds (`flutter build appbundle` / `flutter build ipa`), fastlane config if used, store metadata files.
- Signing material (keystores, provisioning profiles, App Store Connect keys) is user-provided and lives only in CI secrets — never in the repo, never echoed in logs.
- Store submission (Play Console / App Store Connect upload, release rollout percentage) is always a user-confirmed critical item; prefer internal-testing/TestFlight tracks first.
