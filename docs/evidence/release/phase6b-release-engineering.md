# Phase 6B — Productionized-LegacyApp Release Engineering (evidence)

Status: **PASS** — real release run with `release-push` + `gitops-update` green,
plus a docs-only proof run that correctly published nothing.
Design: `docs/adr-release-engineering.md` (P02).

## 1) P02 state before (audit, not rewrite)

| Area | State found | Verdict |
|---|---|---|
| Source | Express app, layered `routes/services/middleware`, `server.js` entry with SIGTERM drain | usable, kept as-is (no business rewrite) |
| Tests | `src/test/smoke.test.js`, 3 `node:test` cases | usable |
| Dockerfile | multi-stage, `USER node`, HEALTHCHECK on `/health` — but base `node:18-alpine` | **EOL base image, 19 HIGH + 2 CRITICAL OS CVEs** |
| CI `ci.yml` | tests ran, but **Trivy `exit-code: 0`** (advisory only) and a `deploy` job using `ACR_USERNAME`/`ACR_PASSWORD`/`AZURE_CREDENTIALS`, pushing `:latest` and `az webapp restart` | **not a gate, long-lived credentials, mutable tag** |
| Kubernetes manifests | none | **missing for Phase 7** |
| Terraform | Web App for Containers + `data azurerm_container_registry "sharedacr"` in `rg-shared-infra` (does not exist) | stale/aspirational, left untouched |
| `.github` trigger paths | `paths: ['02-Productionized-LegacyApp/**']` while this repo IS the app root | dead trigger (would never fire) |

Nothing was rewritten: the legacy app logic (`syncInventory()` no-op) stays as
documented, which is the point of a productionization project.

## 2) Local runtime verification

```text
$ docker run -d -p 3001:3000 legacy-check:nonpm
user=node                                  # non-root (uid 1000 in the image)
health={"status":"healthy","version":"1.0.0"}
sync={"message":"Inventory synced successfully"}
$ docker stop … → STOP_SECONDS=0
log: {"level":"info",…,"msg":"received SIGTERM, draining"}   # graceful shutdown
```

## 3) Test result

```text
$ cd src && npm ci --omit=dev     → found 0 vulnerabilities
$ npm test                        → tests 3 / pass 3 / fail 0   (186 ms)
```

## 4) Security gate (now blocking, with a documented policy)

| Scan | Before | After |
|---|---|---|
| `trivy fs --scanners vuln,secret --severity HIGH,CRITICAL` on `src` | advisory (`exit-code 0`) | **blocking** — 0 findings at this pin |
| `trivy config` (Dockerfile + repo IaC) | not run | **blocking** — clean |
| `trivy image legacy-app` | advisory | **blocking** — see below |

Image findings, and the fixes that actually removed them:

```text
node:18-alpine runtime      → 19 HIGH + 2 CRITICAL  (openssl heap overflow, busybox; EOL base)
node:22-alpine runtime      → 10 HIGH + 1 CRITICAL  (all inside npm's bundled toolchain:
                                                     tar, pacote, sigstore, brace-expansion,
                                                     picomatch, ip-address)
node:22-alpine minus npm    → 0 HIGH / 0 CRITICAL   ← shipped configuration
```

The last step is the interesting one: this is a **runtime** image for
`node server.js`; npm/npx are build-time tools. Deleting `/usr/local/lib/node_modules/npm`,
`corepack` and the `npm`/`npx` shims removes the entire vulnerable toolchain from
the shipped artefact (and shrinks it), verified locally with
`trivy image --exit-code 1` → exit 0 and in CI (`docker-build-scan` green).

Severity policy (documented in the ADR): HIGH and CRITICAL **fail** the build;
`ignore-unfixed: true` is used for the image scan only (unfixable base-image
noise must not block a release), while `fs` scans keep `ignore-unfixed: false`
because a fix is available by definition when the lock file can move. LOW/MEDIUM
are reported in the log and never block.

## 5) OIDC and the shared portfolio ACR

- **No second registry.** `legacy-app` lives in the same `acrflashsalep6`
  created for P01 (Terraform: same account, same resource group; P02 only reads
  its login server through a repo variable).
- **No second identity.** The portfolio's user-assigned identity gained two
  repo-scoped federated subjects for this repository
  (`gh-legacy-main-immutable-ids`, `gh-legacy-pr-immutable-ids`, same numeric-ID
  subject form Phase 6 discovered) via the P01 release Terraform root — the job
  `Azure login (OIDC)` uses the same `vars.AZURE_CLIENT_ID/TENANT_ID`, and the
  same `AcrPush` grant covers `legacy-app`.
- Verified: CI pushed with **zero** `secrets.ACR_*` / `secrets.AZURE_*`
  references (the old deploy job that consumed them is deleted).

## 6) Real release run

```text
run 35547330339 (main, sha 2d5d070)
  detect-changes     success   runtime=true
  test-and-scan      success   npm ci (0 vuln) + npm test 3/3 + Trivy fs + config
  docker-build-scan  success   image built; Trivy image HIGH+ → 0 findings
  sonarqube          skipped   (same honest contract as P01: needs SONAR_TOKEN + UI toggle)
  ci-gate            success
  release-push       success   OIDC login → push legacy-app:2d5d070… → tag resolves to digest
  gitops-update      success   bot commit b98d99b
```

```text
$ az acr manifest list-metadata --registry acrflashsalep6 --name legacy-app
tag= 2d5d070840b06d0da28645c9774965b63b4ac783  digest= sha256:671bbc4e667f…
$ git log --oneline -2
b98d99b gitops: pin prod overlay to legacy-app:2d5d070840b06d0da28645c9774965b63b4ac783
2d5d070 Phase 6B fix: drop npm/npx from the runtime image …
$ tail -2 infrastructure/kubernetes/overlays/prod/kustomization.yaml
  - name: acrflashsalep6.azurecr.io/legacy-app
    newTag: 2d5d070840b06d0da28645c9774965b63b4ac783
```

The bot commit did not spawn a follow-up release (bot-loop guard held).

## 7) Docs-only release test (STEP-10 proof)

Commit `2594699 docs: record the docs-only release expectation` changes only
documentation:

```text
run 35547604045 (main, sha 2594699)
  detect-changes     success   runtime=false
  test-and-scan      success   (cheap checks still run)
  docker-build-scan  success   (build verified, nothing pushed)
  ci-gate            success
  release-push       skipped   ← no image minted
  gitops-update      skipped   ← no SHA moved
```

Post-run verification: ACR tags for `legacy-app` still only
`2d5d070840b06d0da28645c9774965b63b4ac783`; overlay `newTag` unchanged; no new
bot commit. The same `detect-changes` hardening was ported to the P01 workflow
(P01 run 35548093941: docs-only → release-push/gitops-update skipped, ACR tags
and overlay SHA unchanged).

## 8) Files changed / evidence added

- `.github/workflows/ci.yml` (rewritten): 7 jobs, blocking scanners, OIDC
  release, docs-only detection, GitOps pin, aggregate gate
- `Dockerfile`: node:22 LTS + npm removed from the runtime image
- `infrastructure/kubernetes/{base,overlays/prod}`: Deployment (non-root uid
  1000, hardened securityContext, /health probes, limits), ClusterIP Service,
  prod overlay pinned to `<sha>` by the bot
- `docs/adr-release-engineering.md`, this evidence file, README release contract
- P01 (shared): `detect-changes` + gate ported to `.github/workflows/ci.yml`

## 9) Rollback contract

Revert the GitOps commit (`b98d99b` → overlay points at the previous SHA).
Never rebuild an old version to roll back; the tagged SHAs in ACR *are* the
rollback set.
