#!/usr/bin/env bash
# apply-clusterclasses.sh — apply ClusterClass manifests for a given variant and size.
#
# Usage: apply-clusterclasses.sh <variant> [size...]
#   variant: with-caapf | without-caapf
#   size:    tiny | small | medium  (defaults to all three)
#
# Required env: KUBECONFIG (all other configuration passed by the Makefile)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

log() { echo "==> [$(date +%H:%M:%S)] $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

variant="${1:?Usage: $0 <with-caapf|without-caapf> [size...]}"
shift

# Default to all sizes if none specified
sizes=("$@")
if [[ ${#sizes[@]} -eq 0 ]]; then
  sizes=(tiny small medium)
fi

log "applying ClusterClasses: variant=${variant} sizes=${sizes[*]}"

for size in "${sizes[@]}"; do
  file="${REPO_ROOT}/clusterclasses/${variant}/${size}.yaml"
  [[ -f "$file" ]] || fail "ClusterClass file not found: ${file}"
  echo "  applying ${file}"
  kubectl apply -f "$file"
done

echo "  ClusterClasses applied (${variant}: ${sizes[*]})"
