# ADR — P02 Release Engineering (immutable artifacts, OIDC, GitOps)

- Status: Accepted (Phase 6B)
- Context: P01 (FlashSale-Backend) proved the release contract in Phase 6:
  immutable SHA images, GitHub OIDC → Azure, one shared ACR, GitOps manifest
  pinned to SHA, rollback by revert. P02 (Productionized-LegacyApp) is a
  brownfield Node.js worker with the **same deployment destination** (Phase 7
  AKS runs both). Skipping P02 would split the portfolio into two maturity
  levels and break the shared platform story. This ADR binds P02 to the same
  bar — no new ideas, only ported ones. P02 stays a **productionized legacy
  application**, not a second backend flagship.

## Decision

1. **Same registry, new repository.** Reuse `acrflashsalep6`
   (Do NOT create another registry; the P01-specific name is historical, and
   cloud resources are not renamed for cosmetics). P02 images go to
   `acrflashsalep6.azurecr.io/legacy-app:<git-sha>`. `latest` is never a deploy
   source.
2. **Same identity model.** The GitHub workflow exchanges its OIDC token for
   the portfolio's user-assigned identity (AcrPush on the registry). No
   `ACR_USERNAME`/`ACR_PASSWORD`/`AZURE_CREDENTIALS` long-lived secrets are
   introduced in P02. If the identity needs a new federated subject for the P02
   repo, it is added to the existing identity — no second identity is created.
3. **Same pipeline stages.** `npm ci` → `npm test` (3 node:test smoke tests) →
   Trivy fs (secret + HIGH+ vuln, **blocking**) → Trivy config IaC (blocking)
   → Docker build → Trivy image scan (HIGH+ blocking, `ignore-unfixed` allowed
   as in P01) → digest-verified push → GitOps pin.
4. **Pinned runtime.** `node:22-alpine` for builder and runtime. Rationale with
   evidence: `node:18-alpine` is EOL (since 2025-04-30) and its frozen Alpine
   carried 19 HIGH + 2 CRITICAL OS CVEs (openssl heap overflow, busybox) with
   no published fix on that line; `node:22-alpine` removes those. Remaining
   HIGH npm-audit noise lives in npm's own toolchain temp dirs (`brace-expansion`
   CVEs inside `pacote`/`sigstore` under `ip-address`), which are not shipped in
   the image — documented, not patched by hand.
5. **Docs do not release.** `release-push` is gated on a `detect-changes` job:
   docs-only commits run the cheap quality gates but mint no image and move no
   GitOps SHA. `workflow_dispatch` can still force a release when explicitly
   requested. (P01 had this inefficiency first: a docs-only commit rebuilt the
   same images and moved SHAs anyway. Recorded here so P07 can converge, not
   hidden.)
6. **Kubernetes desired state** (`infrastructure/kubernetes/`): Deployment
   (private registry image placeholder replaced by GitOps pin, `runAsNonRoot`
   uid 1000, container securityContext readOnly + no-priv-esc + drop ALL,
   `/health` liveness+readiness, requests/limits) + ClusterIP Service. No
   Ingress in P02 (shared ingress is P03's). Nothing is deployed yet — ArgoCD in
   Phase 7 reconciles it.
7. **GitOps ownership.** `overlays/prod/kustomization.yaml` is the only file CI
   mutates (`newTag` only). Rollback = revert the bot commit; no rebuild of an
   old version to roll back.

## Trade-offs

- Running one more workflow per commit costs a few extra minutes of runner
  time (Node setup + npm ci + Trivy); acceptable because P02 releases ride on
  their own repo's pushes, and docs-only pushes are already filtered.
- `detect-changes` compares against `github.event.before` / `HEAD~1`; squashed
  or force-pushed histories can misclassify the diff, so the job prints the
  changed-file list in the log as the audit trail.
- JavaScript has no `dotnet list --vulnerable` equivalent with the same
  gate-quality; Trivy fs on `package-lock.json` is the single source of truth
  for dependency CVEs here, plus `npm audit` output during `npm ci`.

## Verified in this phase (Phase 6B evidence doc)

Local: `npm ci` → 0 vulnerabilities; `npm test` → 3/3 pass; container runs as
`node` (uid 1000 in the image); `GET /health` 200; `POST /sync` 200; `docker
stop` drains in <1s with the SIGTERM line in the log. K8s manifests satisfy the
Trivy config gate the same way P01's do. The release evidence
(`docs/evidence/release/phase6b-release-engineering.md`) records the real run:
workflow run ID, commit SHA, ACR repository, tag, digest, test and scan results,
the GitOps bot commit, and the docs-only no-release test.
