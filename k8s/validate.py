#!/usr/bin/env python3
"""Render every chart the way ArgoCD will, then check what comes out.

Mirrors magoneai-awnic-deploy/k8s/validate.py. Needs helm and PyYAML, and no
cluster: it never talks to Kubernetes, so it is safe to run anywhere and fast
enough for a pre-commit hook.

The point is not that helm produced valid YAML. Helm does that happily for
manifests that would be rejected, or accepted and then quietly do nothing. Each
check below exists because the mistake it catches fails late and blames the
wrong component.

Usage:
    k8s/validate.sh              every chart
    k8s/validate.sh be fe        named charts only
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import yaml

CHARTS_DIR = Path(__file__).parent / "charts"

# Workload kinds whose pod template we inspect.
WORKLOADS = {"Deployment", "StatefulSet", "DaemonSet"}

# Tags that move. Deploying one means you can never tell what is running,
# because the same tag points somewhere else next week.
MOVING_TAGS = {"latest", "dev", "main", "prod", "stable", "predev"}


class Failure(Exception):
    """A check failed."""


def render(chart: Path) -> list[dict]:
    """Run `helm template` exactly as ArgoCD's repo-server does.

    --include-crds matters: `helm template` skips a chart's top-level crds/
    directory by default, but ArgoCD does not. Without it you validate
    something different from what the cluster receives.
    """
    result = subprocess.run(
        ["helm", "template", chart.name, str(chart), "--include-crds"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise Failure(f"helm template failed:\n{result.stderr.strip()}")
    return [doc for doc in yaml.safe_load_all(result.stdout) if doc]


def containers_of(doc: dict) -> list[dict]:
    spec = doc["spec"]["template"]["spec"]
    return spec.get("initContainers", []) + spec.get("containers", [])


def check_image_is_pinned(doc: dict, errors: list[str]) -> None:
    """Every image must name an exact build.

    A moving tag also silently breaks imagePullPolicy: IfNotPresent, because a
    cached layer for ":dev" is assumed current forever.
    """
    for container in containers_of(doc):
        image = container.get("image", "")
        if "@sha256:" in image:
            continue
        tag = image.rsplit(":", 1)[-1] if ":" in image else ""
        if not tag:
            errors.append(f"{doc['kind']}/{doc['metadata']['name']}: image has no tag ({image})")
        elif tag in MOVING_TAGS:
            errors.append(
                f"{doc['kind']}/{doc['metadata']['name']}: moving tag ':{tag}'. "
                "Pin dev-<sha> or a @sha256 digest"
            )


def check_resources_set(doc: dict, errors: list[str]) -> None:
    """Requests and limits on every container.

    No requests means the scheduler assumes the pod is free and overcommits the
    node. No memory limit means one leak can evict its neighbours.
    """
    for container in containers_of(doc):
        resources = container.get("resources", {})
        for field in ("requests", "limits"):
            if not resources.get(field):
                errors.append(
                    f"{doc['kind']}/{doc['metadata']['name']}"
                    f"/{container['name']}: no resources.{field}"
                )


def check_probes_set(doc: dict, errors: list[str]) -> None:
    """Long-running containers need both probes.

    Without readiness, a Service sends traffic to a pod that is still starting.
    Without liveness, a wedged process is never restarted. Init containers are
    exempt: they run once and exit.
    """
    spec = doc["spec"]["template"]["spec"]
    for container in spec.get("containers", []):
        for probe in ("livenessProbe", "readinessProbe"):
            if probe not in container:
                errors.append(
                    f"{doc['kind']}/{doc['metadata']['name']}"
                    f"/{container['name']}: no {probe}"
                )


def check_no_hardcoded_namespace(doc: dict, errors: list[str]) -> None:
    """Templates must not pin a namespace.

    The namespace comes from `helm --namespace`, and later from the ArgoCD
    Application's destination. Hardcoding it makes the chart deployable to
    exactly one place and silently ignores what the caller asked for.
    """
    if doc.get("metadata", {}).get("namespace"):
        errors.append(
            f"{doc['kind']}/{doc['metadata']['name']}: hardcoded namespace "
            f"'{doc['metadata']['namespace']}'"
        )


def check_selector_matches_pod_labels(doc: dict, errors: list[str]) -> None:
    """The selector must actually match the pod template's labels.

    Get this wrong and everything looks healthy: the object is accepted, the
    Deployment reports no error, and nothing ever matches. This is the single
    most common self-inflicted Kubernetes bug.
    """
    selector = doc["spec"].get("selector", {}).get("matchLabels", {})
    pod_labels = doc["spec"]["template"]["metadata"].get("labels", {})
    for key, value in selector.items():
        if pod_labels.get(key) != value:
            errors.append(
                f"{doc['kind']}/{doc['metadata']['name']}: selector {key}={value} "
                f"does not match pod label {key}={pod_labels.get(key)!r}"
            )


def check_service_has_a_target(docs: list[dict], errors: list[str]) -> None:
    """Every Service selector must match some workload in the same chart.

    A Service whose selector matches nothing is created successfully, lists no
    endpoints, and refuses every connection with no warning anywhere.
    """
    pod_label_sets = [
        doc["spec"]["template"]["metadata"].get("labels", {})
        for doc in docs
        if doc.get("kind") in WORKLOADS
    ]
    for doc in docs:
        if doc.get("kind") != "Service":
            continue
        selector = doc["spec"].get("selector")
        if not selector:
            continue
        matched = any(
            all(labels.get(k) == v for k, v in selector.items())
            for labels in pod_label_sets
        )
        if not matched:
            errors.append(
                f"Service/{doc['metadata']['name']}: selector {selector} "
                "matches no pod template in this chart"
            )


def validate(chart: Path) -> list[str]:
    errors: list[str] = []
    try:
        docs = render(chart)
    except Failure as exc:
        return [str(exc)]

    if not docs:
        return ["chart rendered nothing"]

    for doc in docs:
        check_no_hardcoded_namespace(doc, errors)
        if doc.get("kind") in WORKLOADS:
            check_image_is_pinned(doc, errors)
            check_resources_set(doc, errors)
            check_probes_set(doc, errors)
            check_selector_matches_pod_labels(doc, errors)

    check_service_has_a_target(docs, errors)
    return errors


def main(argv: list[str]) -> int:
    wanted = set(argv[1:])
    charts = sorted(p for p in CHARTS_DIR.iterdir() if (p / "Chart.yaml").exists())
    if wanted:
        charts = [c for c in charts if c.name in wanted]
        missing = wanted - {c.name for c in charts}
        if missing:
            print(f"no such chart: {', '.join(sorted(missing))}", file=sys.stderr)
            return 2

    if not charts:
        print("no charts found", file=sys.stderr)
        return 2

    total = 0
    for chart in charts:
        errors = validate(chart)
        total += len(errors)
        if errors:
            print(f"FAIL  {chart.name}")
            for error in errors:
                print(f"        {error}")
        else:
            print(f"ok    {chart.name}")

    print()
    if total:
        print(f"{total} problem(s) in {len(charts)} chart(s)")
        return 1
    print(f"{len(charts)} chart(s) OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
