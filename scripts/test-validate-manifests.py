#!/usr/bin/env python3
"""Mutation-test scripts/validate-manifests.sh (P02 edition).

Same principle as the P01 harness, scaled to P02's workload set: an assertion
that cannot fail manufactures confidence. The validator is fed BROKEN renders
(text-level mutations of the honest render — no PyYAML round-trip) and each
assertion must catch ITS mutant: non-zero exit naming the broken thing.

No cluster, no kubeconfig: one `kubectl kustomize` render of the prod overlay,
then per-mutation validator runs in pre-rendered mode.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OVERLAY = os.path.join(ROOT, "infrastructure", "kubernetes", "overlays", "prod")
VALIDATOR = os.path.join(ROOT, "scripts", "validate-manifests.sh")


def split_docs(text):
    parts, cur = [], []
    for line in text.splitlines(keepends=True):
        if line.rstrip("\n") == "---":
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(line)
    parts.append("".join(cur))
    return parts


def join_docs(docs):
    out = []
    for d in docs:
        if out:
            out.append("---\n")
        out.append(d if d.endswith("\n") else d + "\n")
    return "".join(out)


def dep_doc(docs):
    i = next(i for i, d in enumerate(docs) if re.search(r"(?m)^kind: Deployment$", d))
    return i


def mut_latest(docs):
    i = dep_doc(docs)
    new = re.sub(r"image: (\S*legacy-app):[0-9a-f]{40}", r"image: \1:latest", docs[i], count=1)
    if new == docs[i]:
        raise KeyError("pinned-SHA image line not found")
    docs[i] = new
    return docs


def mut_placeholder(docs):
    i = dep_doc(docs)
    new = re.sub(r"(?m)^(\s+)image: \S+$", r"\1image: acrflashsalep6.azurecr.io/legacy-app:PLACEHOLDER_SHA_SET_BY_CI", docs[i], count=1)
    if new == docs[i]:
        raise KeyError("image line not found")
    docs[i] = new
    return docs


def mut_wrong_registry(docs):
    i = dep_doc(docs)
    docs[i] = docs[i].replace("acrflashsalep6.azurecr.io", "otherregistry.azurecr.io", 1)
    return docs


def mut_root_runtime(docs):
    i = dep_doc(docs)
    docs[i] = docs[i].replace("runAsNonRoot: true\n", "runAsNonRoot: false\n", 1)
    return docs


def mut_readonly_removed(docs):
    i = dep_doc(docs)
    new = re.sub(r"(?m)^\s+readOnlyRootFilesystem: true\n", "", docs[i], count=1)
    if new == docs[i]:
        raise KeyError("readOnlyRootFilesystem line not found")
    docs[i] = new
    return docs


def mut_resources_removed(docs):
    i = dep_doc(docs)
    # Rendered indent: `resources:` is a container child (8 spaces), limits/cpu at 10+.
    new = re.sub(r"(?m)^        resources:\n(?:          .*\n)+", "", docs[i], count=1)
    if new == docs[i]:
        raise KeyError("resources block not found")
    docs[i] = new
    return docs


def mut_probe_removed(docs):
    i = dep_doc(docs)
    new = re.sub(r"(?m)^        livenessProbe:\n(?:          .*\n)+", "", docs[i], count=1)
    if new == docs[i]:
        raise KeyError("livenessProbe block not found")
    docs[i] = new
    return docs


def mut_public_service(docs):
    i = next(i for i, d in enumerate(docs) if re.search(r"(?m)^kind: Service$", d))
    docs[i] = docs[i].replace("type: ClusterIP", "type: LoadBalancer", 1)
    return docs


def mut_no_namespace(docs):
    i = dep_doc(docs)
    new = re.sub(r"(?m)^  namespace: .*\n", "", docs[i], count=1)
    if new == docs[i]:
        raise KeyError("namespace line not found")
    docs[i] = new
    return docs


MUTATIONS = [
    ("image_latest_tag", "pins an image to :latest", mut_latest),
    ("image_placeholder", "PLACEHOLDER", mut_placeholder),
    ("image_wrong_registry", "is not pinned to", mut_wrong_registry),
    ("root_runtime_allowed", "runAsNonRoot: true", mut_root_runtime),
    ("readonly_root_removed", "readOnlyRootFilesystem: true", mut_readonly_removed),
    ("resources_removed", "must declare both cpu and memory", mut_resources_removed),
    ("liveness_probe_removed", "no livenessProbe", mut_probe_removed),
    ("service_public_lb", "exposed as LoadBalancer", mut_public_service),
    ("namespace_missing", "not in namespace legacy-prod", mut_no_namespace),
]


def run_validator(path):
    return subprocess.run(["bash", VALIDATOR, path],
                          capture_output=True, text=True, timeout=120)


def main():
    render = subprocess.run(["kubectl", "kustomize", OVERLAY],
                            capture_output=True, text=True, timeout=120)
    if render.returncode != 0:
        sys.exit(f"kustomize render failed:\n{render.stderr}")
    clean = render.stdout

    # Sanity: the CLEAN manifest must PASS first.
    with tempfile.TemporaryDirectory() as tmp:
        clean_path = os.path.join(tmp, "clean.yaml")
        with open(clean_path, "w") as fh:
            fh.write(clean)
        clean_run = run_validator(clean_path)
        if clean_run.returncode != 0:
            sys.exit("validator FAILS the clean render - fix that first:\n"
                     + (clean_run.stdout + clean_run.stderr)[-2000:])

        failures = []
        for name, expected, mutate in MUTATIONS:
            docs = split_docs(clean)
            try:
                docs = mutate(docs)
            except KeyError as exc:
                failures.append(f"{name}: mutation itself failed: {exc}")
                continue
            path = os.path.join(tmp, f"{name}.yaml")
            with open(path, "w") as fh:
                fh.write(join_docs(docs))

            proc = run_validator(path)
            combined = proc.stdout + proc.stderr
            if proc.returncode == 0:
                failures.append(f"{name}: validator PASSED a broken manifest (expected FAIL)")
            elif expected not in combined:
                failures.append(
                    f"{name}: validator failed but without the expected message\n"
                    f"    expected substring: {expected!r}\n"
                    f"    output: {combined.strip()[:300]}")
            else:
                print(f"  caught: {name}")

    if failures:
        print("\nMUTATION TESTS FAILED:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"\nALL {len(MUTATIONS)} mutations caught - every assertion can fail.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
