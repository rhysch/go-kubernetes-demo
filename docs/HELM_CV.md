# Go Kubernetes Demo — CV and interview notes

## Project entry

**Go Kubernetes Demo — Helm-Based Kubernetes Delivery**

Go · Docker · Kubernetes/K3s · Helm · GitHub Actions · Traefik

- Packaged a Go application as a Helm chart with configurable replicas, image tags, Service, Ingress, probes and resource limits.
- Added JSON Schema input validation and a native Helm health test for the application through its Kubernetes Service.
- Automated chart linting, rendering and local Kubernetes lifecycle checks in GitHub Actions; configured an opt-in Helm deployment job for a self-hosted K3s runner.

The local lifecycle checks passed (see HELM_VERIFICATION.md):

- Tested Helm installation, upgrades and manual rollback; verified atomic recovery from a deliberately failed image upgrade on a local Kubernetes cluster.

Add **Helm** under container orchestration/deployment skills. Do not call local
validation a cloud deployment or say VM deployment was verified unless it was.

## Explain these concepts in an interview

**Chart:** the versioned package containing templates, defaults and metadata.

**Values:** inputs substituted into those templates. `-f` overrides defaults;
`--set-string image.tag=...` keeps a numeric-looking tag as a string.

**Release:** one installation of a chart, identified by a release name and namespace.
Multiple releases use different instance labels, so their Services select their
own application pods.

**Revision:** each install, upgrade and rollback is recorded in Helm's history.
Rolling back creates a new revision from an older configuration.

**Lint versus template versus test:** lint checks chart structure/values; template
renders YAML; Kubernetes API validation checks real resource schemas; `helm test`
runs the chart's health-check pod against the running Service.

**Atomic upgrade:** Helm 3 waits for readiness and attempts to restore the prior
release if upgrade fails. It cannot guarantee every application-level behavior,
restore external data, or eliminate downtime. A separately failing `helm test`
after a successful upgrade does not itself invoke atomic rollback.

**What the local script proves:** correct rendered resources, two ready replicas,
Service/DNS health, a three-replica upgrade, restoration of the earlier replica
count, and recovery of the original image after a missing-image upgrade.

**What was deliberately isolated:** a fresh test namespace on a loopback local
API, explicit kubeconfig/context, no changes to existing app namespaces, and
cleanup of the test release and namespace.

Practice by changing the replica count, inspecting `helm get values` and
`helm get manifest`, reading revision history, and explaining why the health-test
pod uses a different app label from the Service's selector.
