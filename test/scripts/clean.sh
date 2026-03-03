#!/usr/bin/env bash
# clean.sh — delete clusters, addons, and/or ClusterClasses.
#
# Usage: clean.sh <what> [args...]
#   clean.sh clusters   <variant> [cluster-name...]   — delete specific clusters (or all 6)
#   clean.sh addons     [variant]                      — delete addon resources
#   clean.sh clusterclasses [variant]                  — delete ClusterClass resources
#   clean.sh all                                       — delete everything
#
# Required env: KUBECONFIG (all other configuration passed by the Makefile)
# Optional env: CLUSTER_WAIT_TIMEOUT (default 20m)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLUSTER_WAIT_TIMEOUT="${CLUSTER_WAIT_TIMEOUT:-20m}"
NAMESPACE="${NAMESPACE:-default}"
ALL_CLUSTERS=(tiny-cluster-1 tiny-cluster-2 small-cluster-1 small-cluster-2 medium-cluster-1 medium-cluster-2)

log() { echo "==> [$(date +%H:%M:%S)] $*"; }

delete_clusters() {
  local variant="$1"; shift
  local clusters=("$@")
  if [[ ${#clusters[@]} -eq 0 ]]; then
    clusters=("${ALL_CLUSTERS[@]}")
  fi

  log "deleting clusters (${variant}): ${clusters[*]}"
  for c in "${clusters[@]}"; do
    kubectl delete "cluster/${c}" -n "${NAMESPACE}" --ignore-not-found=true
  done
  for c in "${clusters[@]}"; do
    kubectl wait "cluster/${c}" -n "${NAMESPACE}" \
      --for=delete --timeout="${CLUSTER_WAIT_TIMEOUT}" 2>/dev/null \
      && echo "  ${c}: deleted" \
      || echo "  ${c}: already gone"
  done
}

delete_addons() {
  local variant="${1:-all}"
  log "removing addon resources (${variant})"
  if [[ "$variant" == "with-caapf" || "$variant" == "all" ]]; then
    kubectl delete -f "${REPO_ROOT}/with-caapf/addons/" --ignore-not-found=true
  fi
  if [[ "$variant" == "without-caapf" || "$variant" == "all" ]]; then
    kubectl delete -f "${REPO_ROOT}/without-caapf/addons/" --ignore-not-found=true
  fi
}

delete_clusterclasses() {
  local variant="${1:-all}"
  log "removing ClusterClasses (${variant})"
  if [[ "$variant" == "with-caapf" || "$variant" == "all" ]]; then
    kubectl delete -f "${REPO_ROOT}/clusterclasses/with-caapf/" --ignore-not-found=true
  fi
  if [[ "$variant" == "without-caapf" || "$variant" == "all" ]]; then
    kubectl delete -f "${REPO_ROOT}/clusterclasses/without-caapf/" --ignore-not-found=true
  fi
}

what="${1:?Usage: $0 <clusters|addons|clusterclasses|all> [args...]}"
shift

case "${what}" in
  clusters)
    variant="${1:?Usage: $0 clusters <with-caapf|without-caapf> [cluster-name...]}"
    shift
    delete_clusters "$variant" "$@"
    ;;
  addons)
    delete_addons "${1:-all}"
    ;;
  clusterclasses)
    delete_clusterclasses "${1:-all}"
    ;;
  all)
    delete_clusters "with-caapf"
    delete_clusters "without-caapf"
    delete_addons "all"
    delete_clusterclasses "all"
    rm -f /tmp/*-kubeconfig
    echo "  cleanup complete"
    ;;
  *)
    echo "Unknown command: ${what}" >&2
    echo "Usage: $0 <clusters|addons|clusterclasses|all> [args...]" >&2
    exit 1
    ;;
esac
