#!/usr/bin/env bash
# verify-cluster.sh — wait for a cluster to become Ready, fetch its kubeconfig,
# and validate that key workloads (nodes, CCM, Canal, EBS CSI) are running.
#
# Usage: verify-cluster.sh <cluster-name> [namespace]
#   cluster-name: e.g. tiny-cluster-1
#   namespace:    defaults to "default"
#
# Optional env:
#   CLUSTER_WAIT_TIMEOUT  (default 20m)
#   NODE_WAIT_TIMEOUT     (default 5m)
#   POD_WAIT_TIMEOUT      (default 5m)
#
# Required env: KUBECONFIG (all other configuration passed by the Makefile)
set -euo pipefail

CLUSTER_WAIT_TIMEOUT="${CLUSTER_WAIT_TIMEOUT:-20m}"
NODE_WAIT_TIMEOUT="${NODE_WAIT_TIMEOUT:-5m}"
POD_WAIT_TIMEOUT="${POD_WAIT_TIMEOUT:-5m}"

log() { echo "==> [$(date +%H:%M:%S)] $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# wait_for_pods <label-selector> <description>
# Polls until at least one Running pod matches the selector, or POD_WAIT_TIMEOUT expires.
wait_for_pods() {
  local selector="$1" desc="$2"
  local deadline=$((SECONDS + pod_wait_seconds))
  log "waiting for ${desc} pods (selector=${selector}, timeout ${POD_WAIT_TIMEOUT})"
  while true; do
    if KUBECONFIG="${wl_kubeconfig}" kubectl get pods \
      -n kube-system -l "${selector}" \
      --field-selector=status.phase=Running --no-headers 2>/dev/null | grep -q .; then
      echo "  ${desc}: running"
      return 0
    fi
    if (( SECONDS >= deadline )); then
      echo "--- kube-system pods ---"
      KUBECONFIG="${wl_kubeconfig}" kubectl get pods -n kube-system || true
      fail "${desc} pods not running in ${cluster} within ${POD_WAIT_TIMEOUT}"
    fi
    sleep 10
  done
}

cluster="${1:?Usage: $0 <cluster-name> [namespace]}"
namespace="${2:-default}"
wl_kubeconfig="/tmp/${cluster}-kubeconfig"

# Convert POD_WAIT_TIMEOUT to seconds for the retry loop
case "${POD_WAIT_TIMEOUT}" in
  *m) pod_wait_seconds=$(( ${POD_WAIT_TIMEOUT%m} * 60 )) ;;
  *s) pod_wait_seconds=${POD_WAIT_TIMEOUT%s} ;;
  *)  pod_wait_seconds=${POD_WAIT_TIMEOUT} ;;
esac

# --- wait for Cluster Ready ---
log "waiting for cluster/${cluster} to be Ready (timeout ${CLUSTER_WAIT_TIMEOUT})"
if ! kubectl wait "cluster/${cluster}" -n "${namespace}" \
  --for=condition=Ready \
  --timeout="${CLUSTER_WAIT_TIMEOUT}"; then
  echo "--- cluster describe ---"
  kubectl describe "cluster/${cluster}" -n "${namespace}" || true
  fail "cluster ${cluster} did not become Ready within ${CLUSTER_WAIT_TIMEOUT}"
fi
echo "  cluster ${cluster}: Ready"

# --- fetch workload kubeconfig ---
log "fetching kubeconfig for ${cluster}"
kubectl get secret "${cluster}-kubeconfig" -n "${namespace}" \
  -o jsonpath='{.data.value}' | base64 -d > "${wl_kubeconfig}"
echo "  kubeconfig saved to ${wl_kubeconfig}"

# --- verify nodes ---
log "waiting for all nodes to be Ready"
KUBECONFIG="${wl_kubeconfig}" kubectl wait nodes --all \
  --for=condition=Ready \
  --timeout="${NODE_WAIT_TIMEOUT}" \
  || fail "nodes not Ready in ${cluster}"
echo "  nodes: Ready"

# --- verify CCM ---
wait_for_pods "k8s-app=aws-cloud-controller-manager" "CCM"

# --- verify Canal CNI ---
wait_for_pods "k8s-app=canal" "Canal CNI"

# --- verify EBS CSI ---
wait_for_pods "app=ebs-csi-controller" "EBS CSI"

# --- verify node providerIDs (CCM initialised) ---
log "checking node providerIDs"
KUBECONFIG="${wl_kubeconfig}" kubectl get nodes \
  -o jsonpath='{.items[*].spec.providerID}' | grep -q 'aws://' \
  || fail "nodes missing AWS providerID in ${cluster} — CCM may not have initialised"
echo "  node providerIDs: present (CCM initialised)"

echo ""
echo "PASS: ${cluster}"
