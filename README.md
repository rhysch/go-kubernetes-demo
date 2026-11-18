# Go application on Kubernetes

A Go website packaged with Docker and deployed to K3s through GitHub Actions.

```text
Commit → GitHub Actions tests → Docker build → Docker Hub
                                            ↓
                              VM runner → K3s rolling update
                                            ↓
Browser → Traefik → Ingress → Service → Ready Go pods
```

## Local development

```bash
go test -race ./...
docker build -t go-web:local .
docker run --rm -p 8080:8080 go-web:local
```

Visit http://localhost:8080. The app also serves `/healthz`.

## Kubernetes

The Deployment runs two pods using a non-root image, resource requests/limits,
and an HTTP readiness probe. The ClusterIP Service forwards port 80 to 8080.

Apply shared resources and exactly one Ingress configuration:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
```

For local access, map `go-web.local` to `127.0.0.1` in your browser machine's
hosts file, then run:

```bash
kubectl port-forward -n kube-system svc/traefik 9999:80
```

Visit http://go-web.local:9999. A hostname avoids conflicting with other apps
such as an Ingress matching `localhost`.

For the VM, use `k8s/ingress-vm.yaml` instead of `k8s/ingress.yaml`.
Do not apply the entire `k8s/` directory: both Ingress files configure the same
resource for different environments.

VM URL: http://go-web.13.201.98.93.sslip.io/

The public DNS service sslip.io resolves that name to the embedded IP address.
The VM needs public HTTP port 80 permitted and running K3s/Traefik. This demo
uses HTTP; configure your own domain and TLS before using sensitive data.
Update the VM hostname in both its manifest and workflow if its IP changes.

## CI/CD

`.github/workflows/ci.yaml` runs on pushes to main, pull requests targeting main,
and manual dispatches.

- Pull requests: run Go tests and build the Docker image on a GitHub runner.
- Main pushes/manual runs: also publish `rhys561d/go-web:<commit SHA>`.
- After a successful publish: deploy using the VM runner labelled `go-vm`.
- Wait for readiness and verify `/healthz` through Traefik.
- Print Kubernetes diagnostics if deployment fails.

Required repository secrets: `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.
The Docker Hub repository must be public for unauthenticated Kubernetes pulls.
The VM runner needs passwordless `sudo k3s kubectl` access. Only trusted main
branch jobs deploy; pull requests do not run on the VM runner. Restrict repository
write access and protect main when collaborating.

The workflow downloads code itself; manually copying code to the VM is unnecessary.

## Verify and troubleshoot

```bash
sudo k3s kubectl get pods,svc,ingress -n go-cicd
sudo k3s kubectl logs deployment/go-web -n go-cicd
sudo k3s kubectl get events -n go-cicd --sort-by=.metadata.creationTimestamp
curl -H 'Host: go-web.13.201.98.93.sslip.io' http://127.0.0.1/healthz
```

Rollback after a bad release:

```bash
sudo k3s kubectl rollout undo deployment/go-web -n go-cicd
sudo k3s kubectl rollout status deployment/go-web -n go-cicd
```

Then fix or revert the source commit and push it. Rollback is manual; the pipeline
does not automatically revert failed deployments.
