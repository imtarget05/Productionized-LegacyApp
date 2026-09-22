#!/usr/bin/env bash
# Validate the RENDERED prod overlay of P02 (legacy-app), not the source files.
#
# Principle ported from P01 (FlashSale-Backend), NOT its assertion list: P02 has
# exactly one Deployment + one Service, so this gate is deliberately smaller.
# The failure it guards against is the same one P01 was bitten by: CI proves the
# image while the rendered overlay still points at an unpullable reference,
# because the base/overlay image-name coupling is invisible until something
# renders it.
#
# NOTE on the coupling this gate exists to watch: base declares the image
# REGISTRY-QUALIFIED (`acrflashsalep6.azurecr.io/legacy-app:PLACEHOLDER...`) and
# the overlay only rewrites `newTag`. That works today, but the transform keys on
# an exact name match — change either side and Kustomize silently skips it. The
# rendered-output assertions below are what turns that silent skip into a red
# gate.
#
# Runs on any machine with kubectl (kustomize is built in) — no cluster needed.
set -euo pipefail

cd "$(dirname "$0")/.."
OVERLAY=infrastructure/kubernetes/overlays/prod

# Usage: validate-manifests.sh [pre-rendered.yaml]
# With a file argument, validates THAT file — the seam test-validate-manifests.py
# uses to prove every assertion below can actually fail.
INPUT_FILE="${1:-}"

RENDERED=$(mktemp)
trap 'rm -f "$RENDERED"' EXIT

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

if [ -n "$INPUT_FILE" ]; then
  [ -f "$INPUT_FILE" ] || { echo "FAIL: no such rendered file: $INPUT_FILE" >&2; exit 1; }
  cp "$INPUT_FILE" "$RENDERED"
  echo "== validating pre-rendered input: $INPUT_FILE =="
else
  echo "== render $OVERLAY =="
  if ! kubectl kustomize "$OVERLAY" >"$RENDERED" 2>/tmp/kustomize.err; then
    cat /tmp/kustomize.err >&2
    echo "FAIL: kustomize render failed" >&2
    exit 1
  fi
fi
echo "rendered $(grep -c '^kind: ' "$RENDERED") objects"

echo "== assertions =="

# 1. The rendered image must be OUR registry, pinned to one immutable 40-char
#    SHA (ADR-011). Registry asserted literally; anchored so a rewritten line
#    cannot half-match.
grep -Eq "^[[:space:]]+image: acrflashsalep6\\.azurecr\\.io/legacy-app:[0-9a-f]{40}[[:space:]]*$" "$RENDERED" \
  || err "legacy-app image is not pinned to acrflashsalep6.azurecr.io/legacy-app:<40-char sha>"

# 2. Mutable tags forbidden.
grep -E 'image: [^ ]+:latest$' "$RENDERED" >/dev/null \
  && err "rendered manifest pins an image to :latest"

# 3. No CI placeholder may survive into rendered output (the overlay newTag
#    transform silently skipping is exactly how this used to happen).
grep -q 'PLACEHOLDER' "$RENDERED" \
  && err "rendered manifest still contains 'PLACEHOLDER' (overlay pin did not apply)"

# Extract the single Deployment document.
doc_of() {
  awk -v kind="$1" -v name="$2" '
    { doc[n] = doc[n] $0 "\n" }
    /^---$/ { n++ }
    END {
      for (i = 0; i <= n; i++)
        if (doc[i] ~ ("(^|\n)kind: " kind "(\n|$)") &&
            doc[i] ~ ("(^|\n)  name: " name "(\n|$)")) { printf "%s", doc[i]; found = 1; exit }
      exit !found
    }' "$RENDERED"
}
DEP=$(doc_of Deployment legacy-app) || { err "rendered manifest has no Deployment/legacy-app"; DEP=""; }

if [ -n "$DEP" ]; then
  # 4. Namespace: the overlay must place the workload in legacy-prod — never
  #    let an app land in `default`.
  printf '%s' "$DEP" | grep -q "^  namespace: legacy-prod$" \
    || err "Deployment/legacy-app is not in namespace legacy-prod"

  # 5. Pod-level non-root identity.
  printf '%s' "$DEP" | grep -q "runAsNonRoot: true" \
    || err "pod securityContext missing runAsNonRoot: true"
  printf '%s' "$DEP" | grep -q "runAsUser:" \
    || err "pod securityContext missing explicit runAsUser"

  # 6. Container-level hardening (Trivy KSV-0014/KSV-0118 bar, same as P01).
  printf '%s' "$DEP" | grep -q "allowPrivilegeEscalation: false" \
    || err "container securityContext missing allowPrivilegeEscalation: false"
  printf '%s' "$DEP" | grep -q "readOnlyRootFilesystem: true" \
    || err "container securityContext missing readOnlyRootFilesystem: true"
  printf '%s' "$DEP" | grep -A2 "capabilities:" | grep -q "ALL" \
    || err "container capabilities must drop ALL"

  # 7. Scheduling math needs requests; runtime safety needs limits.
  for section in requests limits; do
    printf '%s' "$DEP" | awk -v s="$section" '
      /^          (requests|limits):$/ { insec = ($0 ~ s) }
      insec && /^            cpu: /   { c = 1 }
      insec && /^            memory: / { m = 1 }
      END { exit !(c && m) }' \
      || err "container resources.$section must declare both cpu and memory"
  done

  # 8. Both probes must exist — a pod without them is unverifiable at runtime.
  printf '%s' "$DEP" | grep -q "livenessProbe:"   || err "no livenessProbe"
  printf '%s' "$DEP" | grep -q "readinessProbe:"  || err "no readinessProbe"
fi

# 9. The Service must not expose a public IP (ClusterIP by design; ingress is a
#    P03 platform concern, not an app concern).
grep -Eq "type: LoadBalancer" "$RENDERED" \
  && err "Service is exposed as LoadBalancer (public IP)"

if [ "$fail" -ne 0 ]; then
  echo "== RESULT: FAIL ==" >&2
  exit 1
fi
echo "== RESULT: PASS (rendered prod overlay is deployable) =="
