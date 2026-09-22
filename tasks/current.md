# Current Tasks — Productionized-LegacyApp (P02)

> Updated: 2026-09-21 | Single status source for this repo (same practice as P01/P03).

## Current state: Phase 6B — PASS

Evidence: `docs/evidence/release/phase6b-release-engineering.md`
Design: `docs/adr-release-engineering.md`

Verified live 2026-09-21 (not inferred from docs):

- `legacy-app` exists in ACR `acrflashsalep6`, tagged with the immutable
  commit SHA `2d5d0708…` (no `:latest`).
- `kubectl kustomize infrastructure/kubernetes/overlays/prod` renders
  `acrflashsalep6.azurecr.io/legacy-app:2d5d0708…` — i.e. the GitOps pin is
  actually applied, not silently skipped.
- Resource requests are small; compatible with the shared AKS foundation.
- No Terraform state or plan artifacts are tracked in Git.

## Ownership boundary

P03 `AKS-SRE-Platform` owns the shared Azure/AKS runtime (resource group,
cluster, ACR, gateway, GitOps). **P02 owns only** application code, its image,
and its Kubernetes manifests. Do not provision P02-owned standalone Azure
infrastructure from this repo.

## Next: Phase 7D — deploy to shared AKS via GitOps

**P02 offline readiness gate: DONE 2026-09-22** (commit pending push):
`scripts/validate-manifests.sh` + `scripts/test-validate-manifests.py`
(**ALL 9 mutations caught** — PIN SHA, latest, placeholder, wrong-registry,
root runtime, readOnlyRootFilesystem removed, resources removed, probe
removed, LoadBalancer, missing namespace) + `manifest-validation` wired into
CI `ci-gate`. Ported principles from P01 7C, sized to P02's workload set
(1 Deployment + 1 Service); `/tmp` scratch mount deliberately NOT added —
P02's Node app has no evidence of needing writable temp like P01's .NET
`Path.GetTempPath()` path, and imports must be justified, not copied.

Blocked behind platform Phase 7B (AKS capacity gate is currently BLOCKED on a
manual quota approval) and 7C (P01 first deployment).

Before 7D, close these known gaps:

- [ ] **Manifest render gate is missing here.** P01 was bitten by exactly this:
      CI proved the image while the rendered overlay still pointed at a broken
      image reference. P02's overlay currently works because base and overlay
      use the *same* registry-qualified image name — but that coupling is
      invisible: change either side and Kustomize skips the transform silently.
      Port `scripts/validate-manifests.sh` from P01 rather than re-deriving it.
- [ ] No `Service`/Gateway API route yet — north-south ingress is a 7B/7D
      platform concern (Gateway API + Envoy Gateway), not an app concern.
- [ ] Add `readOnlyRootFilesystem` + explicit non-root `securityContext` parity
      check against the P01 bar before 7D (Trivy KSV-0014/KSV-0118).

## Stale infrastructure — do not apply

`infrastructure/terraform/` is a **historical, never-applied blueprint** from
the pre-AKS Web App for Containers plan. It is not part of any deployment path:

- references `rg-shared-infra` and an ACR named `sharedacr` — neither exists;
- requires ACR `admin_enabled = true`, which contradicts the actual security
  posture (`acrflashsalep6` has `adminUserEnabled=false`, private pull via the
  AKS kubelet identity's `AcrPull` role);
- pulls a mutable `:latest` tag, which ADR-011 forbids;
- has no backend configured and no state.

Kept in place for brownfield traceability (it documents what the app used to
target). Superseded by `infrastructure/kubernetes/` + P03. See the header
comment in `infrastructure/terraform/main.tf`.
