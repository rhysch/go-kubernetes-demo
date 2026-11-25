# Helm verification — 2026-11-25

Verified on the existing local Windows/WSL K3s cluster using Helm v3.17.3 and
Kubernetes v1.35.5+k3s1. No AWS resources or hosted VM deployment were used.

| Check | Result |
|---|---|
| Existing Go tests with race detection | Passed |
| Strict Helm lint | Passed |
| Default and VM values rendering | Passed |
| Disabled Ingress, disabled test hook, and TLS values rendering | Passed |
| Invalid replica count, empty image tag, invalid pull policy and wrong application port | Rejected by JSON Schema |
| Service/test-pod selector isolation | Checked; health-test pod cannot receive application traffic |
| Chart packaging | Passed: go-web-0.2.0.tgz |
| Kubernetes server-side dry-run | Passed for local test resources |
| Install revision 1 | Two ready application replicas; native Helm Service health test passed |
| Upgrade revision 2 | Three ready application replicas; health test passed |
| Manual rollback revision 3 | Restored revision 1 settings and two replicas; health test passed |
| Deliberately missing image, revision 4 | Upgrade failed as expected |
| Atomic rollback, revision 5 | Original image restored, release deployed and health test passed |
| Cleanup | Helm release uninstalled; temporary namespace deleted |

The saved [release history](evidence/helm-history.json) records revisions 1–5.
Reproduce these checks using `scripts/verify-helm.sh` as described in README.md.
The script refuses an existing namespace and requires explicit local kubeconfig
and context settings.

## Useful troubleshooting findings

- K3s's bundled kubectl and Helm have different kubeconfig defaults. Set an
  explicit KUBECONFIG so they address the same cluster.
- A successful test pod can be deleted before `helm test --logs` fetches logs.
  The native test uses success cleanup and commands omit that flag. Failed test
  pods remain available for diagnosis.
- The first harness run assumed jq was installed. That dependency was removed;
  the final script uses Helm's status output and standard shell tools.

## Boundaries

The lifecycle test disables Ingress to run on both kind and K3s. It verifies
Service DNS/routing and application health, not live Traefik/TLS behavior.
Ingress and TLS variants were rendered and inspected. The optional VM Helm job
was implemented but not executed. GitHub's kind-based job is configured in the
workflow; only local execution is claimed here until it runs on GitHub.

This file records local verification. The GitHub Actions workflow repeats the lifecycle checks in kind; consult the repository Actions tab for that separate run.
