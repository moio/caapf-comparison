#!/usr/bin/env bash
# apply-addons.sh — apply addon resources for a given variant.
#
# Usage: apply-addons.sh <variant>
#   variant: with-caapf | without-caapf
#
# with-caapf:    applies HelmOp resources (CCM + CSI)
# without-caapf: applies CCM ConfigMap + CSI ClusterResourceSet
#
# Required env: KUBECONFIG (all other configuration passed by the Makefile)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

log() { echo "==> [$(date +%H:%M:%S)] $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

variant="${1:?Usage: $0 <with-caapf|without-caapf>}"

log "applying addons: variant=${variant}"

case "${variant}" in
  with-caapf)
    kubectl apply -f "${REPO_ROOT}/with-caapf/addons/ccm.yaml"
    kubectl apply -f "${REPO_ROOT}/with-caapf/addons/csi.yaml"
    echo "  HelmOps applied"
    ;;
  without-caapf)
    kubectl apply -f "${REPO_ROOT}/without-caapf/addons/ccm-configmap.yaml"
    kubectl apply -f "${REPO_ROOT}/without-caapf/addons/csi-clusterresourceset.yaml"
    echo "  ConfigMap and ClusterResourceSet applied"
    ;;
  *)
    fail "unknown variant: ${variant} (expected with-caapf or without-caapf)"
    ;;
esac

echo "  addons applied (${variant})"
