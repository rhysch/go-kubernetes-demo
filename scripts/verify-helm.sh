#!/usr/bin/env bash
set -euo pipefail
# Use only a disposable namespace on an explicitly selected LOCAL cluster.
: "${KUBE_CONTEXT:?Set KUBE_CONTEXT to a local cluster context}"
: "${KUBECONFIG:?Set KUBECONFIG explicitly so Helm and kubectl use the same local cluster}"
helm version --short | grep -q '^v3\.' || { echo "This verification script requires Helm 3" >&2; exit 1; }
[[ -f $KUBECONFIG ]] || { echo "KUBECONFIG must name one readable kubeconfig file" >&2; exit 1; }
namespace=${HELM_TEST_NAMESPACE:-go-web-helm-check}
release=${HELM_TEST_RELEASE:-go-web}
image_repository=${HELM_TEST_IMAGE_REPOSITORY:-rhys561d/go-web}
image_tag=${HELM_TEST_IMAGE_TAG:-v1}
chart=${HELM_TEST_CHART:-charts/go-web}
report=${HELM_REPORT_DIR:-$(mktemp -d)}
[[ $namespace =~ ^go-web-helm-check(-[a-z0-9-]+)?$ ]] || { echo "Use a go-web-helm-check namespace" >&2; exit 1; }
[[ $release =~ ^[a-z0-9][a-z0-9-]{0,38}$ ]] || exit 1
mkdir -p "$report"
kube() { kubectl --kubeconfig "$KUBECONFIG" --context "$KUBE_CONTEXT" "$@"; }
h() { helm --kubeconfig "$KUBECONFIG" --kube-context "$KUBE_CONTEXT" "$@"; }
server=$(kube config view --minify -o jsonpath='{.clusters[0].cluster.server}')
[[ $server =~ ^https?://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]+)?/?$ ]] || {
  echo "Refusing a non-loopback API; this script is for local verification only" >&2; exit 1;
}
# Refuse to own or delete an existing namespace, even if the name matches.
existing=$(kube get namespace "$namespace" --ignore-not-found -o name)
[[ -z $existing ]] || { echo "Namespace already exists; choose a new HELM_TEST_NAMESPACE" >&2; exit 1; }
kube create namespace "$namespace"
cleanup() {
  result=$?
  trap - EXIT
  if [[ $result -ne 0 ]]; then
    h history "$release" -n "$namespace" || true
    kube get pods,events -n "$namespace" || true
    kube logs -n "$namespace" -l "app.kubernetes.io/instance=$release" --all-containers --tail=30 || true
  fi
  if [[ ${HELM_KEEP_TEST_NAMESPACE:-false} == true ]]; then
    echo "Kept test namespace: $namespace"
  else
    h uninstall "$release" -n "$namespace" --wait --timeout 90s || true
    kube delete namespace "$namespace" --wait --timeout=90s || true
  fi
  echo "Reports: $report"
  exit "$result"
}
trap cleanup EXIT
common=(--namespace "$namespace" --set-string "image.repository=$image_repository" --set-string "image.tag=$image_tag" --set image.pullPolicy=IfNotPresent --set ingress.enabled=false)
helm lint "$chart" --strict
helm template "$release" "$chart" "${common[@]}" > "$report/rendered.yaml"
kube apply --dry-run=server -f "$report/rendered.yaml" > "$report/api-validation.txt"
h upgrade --install "$release" "$chart" "${common[@]}" --atomic --timeout 180s
h test "$release" -n "$namespace" --timeout 90s
[[ $(kube get deployment "$release" -n "$namespace" -o jsonpath='{.status.readyReplicas}') == 2 ]]
echo "PASS: install, two ready replicas and Service health hook"
h upgrade "$release" "$chart" "${common[@]}" --set replicaCount=3 --atomic --timeout 180s
[[ $(kube get deployment "$release" -n "$namespace" -o jsonpath='{.status.readyReplicas}') == 3 ]]
h test "$release" -n "$namespace" --timeout 90s
echo "PASS: revision 2 upgrade, three ready replicas and health hook"
h rollback "$release" 1 -n "$namespace" --wait --timeout 180s
[[ $(kube get deployment "$release" -n "$namespace" -o jsonpath='{.spec.replicas}') == 2 ]]
[[ $(kube get deployment "$release" -n "$namespace" -o jsonpath='{.status.readyReplicas}') == 2 ]]
h test "$release" -n "$namespace" --timeout 90s
h history "$release" -n "$namespace" -o json > "$report/history.json"
echo "PASS: manual rollback to revision 1 values, two ready replicas and health hook"
# An invalid tag must fail; Helm --atomic must restore the last working values.
if h upgrade "$release" "$chart" "${common[@]}" --set-string image.tag=helm-check-missing-image --atomic --timeout 45s > "$report/failed-upgrade.log" 2>&1; then
  echo "Unexpected success for missing-image upgrade" >&2; exit 1
fi
[[ $(kube get deployment "$release" -n "$namespace" -o jsonpath='{.spec.template.spec.containers[0].image}') == "$image_repository:$image_tag" ]]
kube rollout status deployment/"$release" -n "$namespace" --timeout=120s
h status "$release" -n "$namespace" | grep -qx 'STATUS: deployed'
h test "$release" -n "$namespace" --timeout 90s
h history "$release" -n "$namespace" -o json > "$report/history.json"
echo "PASS: failed upgrade automatically rolled back; original image and health restored"
