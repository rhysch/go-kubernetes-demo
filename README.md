# Go Kubernetes Demo — Helm and CI/CD

A Go HTTP application packaged with Docker and a configurable Helm 3 chart.
The chart deploys a Kubernetes Deployment, ClusterIP Service and optional Traefik
Ingress. A native Helm test checks the application's health through the Service.

```text
Commit / PR → Go tests → Helm lint and render → local kind lifecycle checks
                                                  ↓
                           install → test → upgrade → rollback → failed-upgrade recovery
                                                  ↓
Main / manual run → publish commit-tagged Docker image
                                                  ↓
Explicitly enabled manual deployment → VM runner → Helm release on K3s
                                                  ↓
Browser → Traefik Ingress → Service → ready Go pods
```

**Local checks do not provision AWS or start a cloud VM.** VM deployment is
manual-only and skipped unless `ENABLE_VM_DEPLOYMENT=true` is configured. The VM
values file contains an example hostname, not a promise of an active hosted demo.

## What this project demonstrates

- Go application and handler test; race-enabled testing in CI.
- Multi-stage Docker build with a non-root runtime.
- Helm values for image tags, replicas, Service, Ingress, probes and resources.
- JSON Schema checks for invalid chart inputs.
- Two default replicas, HTTP readiness/liveness probes, and resource limits.
- Non-root pod configuration, read-only container filesystem and dropped capabilities.
- Native `helm test` Service check, revision history, manual rollback and atomic upgrade recovery.
- CI lifecycle testing in a disposable kind cluster before image publishing.

## Local application

```bash
go test -race ./...
docker build -t go-web:local .
docker run --rm -p 8080:8080 go-web:local
```

Visit http://localhost:8080. `/healthz` returns `ok`. The Go application always
listens on 8080; the chart schema intentionally keeps `containerPort=8080`.
`service.port` can be changed independently.

## Chart structure

```text
charts/go-web/
├── Chart.yaml                       # Chart version and application metadata
├── values.yaml                      # Default settings
├── values-vm.yaml                   # Example VM hostname override
├── values.schema.json               # Input validation
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    └── tests/test-connection.yaml     # helm test health-check pod
scripts/verify-helm.sh                # Isolated local lifecycle verification
```

`Chart.yaml` version tracks the deployment package; `appVersion` describes the
application. CI deploys the full Git commit SHA as `image.tag`.

## Lint and render without a cluster

Install the pinned Helm version used in CI, Helm **v3.17.3**, or another compatible
Helm 3 version. Helm 4 uses different failure-handling flags; these examples target
Helm 3.

```bash
helm lint charts/go-web --strict
helm template go-web charts/go-web --namespace go-cicd-helm
helm template go-web charts/go-web --namespace go-cicd-helm -f charts/go-web/values-vm.yaml
```

Linting and rendering do not install anything. `values.schema.json` rejects inputs
such as a negative replica count, an empty image tag or an invalid pull policy.
Kubernetes server-side dry-run in the lifecycle script additionally validates the
rendered resources against a real API.

## Install on a local cluster

Always select the intended kubeconfig and context. K3s's bundled `kubectl` finds
its kubeconfig automatically, but Helm does not. On a local K3s installation,
when your account can read this file:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl config get-contexts
helm upgrade --install go-web charts/go-web \
  --namespace go-cicd-helm --create-namespace --atomic --timeout 180s
helm test go-web -n go-cicd-helm
kubectl get pods,svc,ingress -n go-cicd-helm
```

Use a separate namespace from the legacy `go-cicd` resources. Helm will not
silently adopt objects previously managed by kubectl; their selectors also differ.
Do not add takeover flags or remove ownership labels to bypass this distinction.

For local Ingress access, map `127.0.0.1 go-web-helm.local` in your browser
machine's hosts file, then forward the existing Traefik Service:

```bash
kubectl port-forward -n kube-system svc/traefik 9996:80
curl -H 'Host: go-web-helm.local' http://127.0.0.1:9996/healthz
```

The chart does not install Traefik. Without an Ingress controller, set
`--set ingress.enabled=false` and use a Service port-forward instead.

## Upgrade and rollback

```bash
helm upgrade go-web charts/go-web -n go-cicd-helm \
  --reuse-values --set replicaCount=3 --atomic --timeout 180s
helm test go-web -n go-cicd-helm
helm history go-web -n go-cicd-helm
helm rollback go-web 1 -n go-cicd-helm --wait --timeout 180s
helm test go-web -n go-cicd-helm
```

A rollback creates a new revision using a prior revision's configuration. It does
not erase history. Check actual history before choosing a revision number.
Helm 3 `--atomic` waits for an upgrade and rolls back a failed upgrade; on a failed
first install it removes the attempted installation. It does not make Kubernetes
updates inherently zero-downtime.

Successful test pods are removed by the hook deletion policy; failed test pods remain for diagnosis. The commands omit `--logs` because a successful hook may be deleted before Helm can fetch its logs.

`helm test` is a separate command. If the post-deployment test or Ingress check
fails after an upgrade succeeded, CI reports failure but does not automatically
roll back that separately detected failure. Diagnose it and choose a rollback.

## Reproduce the local lifecycle checks

Requirements: Helm 3, kubectl, Bash, and an existing **local** cluster with a loopback
API endpoint. The script requires an explicit kubeconfig/context, refuses an
existing namespace, and cleans up only the namespace it creates.

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
KUBE_CONTEXT=default \
HELM_TEST_NAMESPACE=go-web-helm-check-practice \
HELM_REPORT_DIR=/tmp/go-web-helm-practice \
bash scripts/verify-helm.sh
```

It installs two replicas, runs the Service health hook, upgrades to three replicas,
rolls back to revision 1, and deliberately tries a missing image to verify atomic
recovery. It then uninstalls the release and deletes its test namespace. It does
not modify other applications. Test Ingress is disabled for portability to kind;
the native test exercises Kubernetes DNS, the ClusterIP Service and `/healthz`.

On kind, load a locally built image and set `HELM_TEST_IMAGE_REPOSITORY` and
`HELM_TEST_IMAGE_TAG`; CI demonstrates this. By default the local script uses the
project's public `rhys561d/go-web:v1` image. It downloads that image and BusyBox if
not already available. `HELM_KEEP_TEST_NAMESPACE=true` is an explicit debugging
option; clean up that namespace yourself afterward.

## CI and optional VM deployment

`.github/workflows/ci.yaml` runs on main pushes, pull requests and manual dispatch.
Before publishing an image it runs Go tests, Helm lint/render, and the lifecycle
script against a disposable kind cluster. Reports are uploaded as
`helm-verification` artifacts. The cluster is deleted even on a failed check.
Pull requests do not publish images and do not use the VM runner.

For an explicitly requested deployment to an **already provisioned** K3s VM:

1. Configure `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository secrets for publishing.
2. Use a public Docker Hub image repository so K3s can pull it without registry credentials.
3. Prepare a trusted self-hosted Linux x64 runner labelled `go-vm`; it needs passwordless access to `sudo k3s kubectl` and the Helm binary.
4. Set repository variable `HELM_INGRESS_HOST` to a hostname resolving to that VM.
5. Only when you want that deployment, set `ENABLE_VM_DEPLOYMENT=true` and manually run the workflow from main.

The job uses `helm upgrade --install --atomic`, the commit-tagged image,
`helm test`, Deployment image verification and a Traefik health check. It uses
namespace `go-cicd-helm`, leaving the legacy namespace alone. No workflow creates
or powers on an AWS instance. An independently hosted VM can still incur its own
provider charges; keep VM deployment disabled for local-only learning.

For a manual VM install, use its kubeconfig and pass `-f charts/go-web/values-vm.yaml`;
replace the example hostname first. Repeat your environment values file on future
upgrades, or deliberately use `--reuse-values` to retain the chosen settings.

TLS is optional through `ingress.tls`. Create the referenced TLS Secret in the
release namespace first. The chart does not issue certificates or configure HTTPS
redirects.

## Legacy manifests and troubleshooting

The original `k8s/` files remain as a plain-manifest learning reference. Do not
apply that whole directory: the local and VM Ingress files describe the same
resource with different hostnames. Do not mix those objects with a Helm release.

```bash
helm status go-web -n go-cicd-helm
helm get values go-web -n go-cicd-helm
helm get manifest go-web -n go-cicd-helm
helm history go-web -n go-cicd-helm
kubectl logs deployment/go-web -n go-cicd-helm
kubectl get events -n go-cicd-helm --sort-by=.metadata.creationTimestamp
```

`helm uninstall go-web -n go-cicd-helm` removes this release's resources. Helm does
not delete a namespace created through `--create-namespace`; delete it separately
only if it belongs exclusively to this demonstration.

## CV and interview preparation

See [CV-ready wording](docs/HELM_CV.md) and [verification results](docs/HELM_VERIFICATION.md).
Use claims that match the checks actually completed; local testing is not proof
of a hosted VM deployment.

References: [Helm 3 upgrade behavior](https://helm.sh/docs/v3/helm/helm_upgrade/),
[Helm 3 rollback](https://helm.sh/docs/v3/helm/helm_rollback/),
[kind local clusters and image loading](https://kind.sigs.k8s.io/docs/user/quick-start/).
