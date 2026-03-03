#!/usr/bin/env bash
# apply-prereqs.sh — ensure namespaces and CAPI providers exist, validate the
# management cluster and AWS credentials, create/update the
# cluster-identity-credentials Secret, and apply the AWSClusterStaticIdentity.
# Safe to run repeatedly (idempotent).
#
# Usage: apply-prereqs.sh
#
# Required env: KUBECONFIG, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
# Optional env: PROVIDER_WAIT_TIMEOUT (default 5m)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROVIDER_WAIT_TIMEOUT="${PROVIDER_WAIT_TIMEOUT:-5m}"

log() { echo "==> [$(date +%H:%M:%S)] $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- management cluster reachable ---
log "checking management cluster connectivity"
kubectl cluster-info --request-timeout=10s >/dev/null 2>&1 \
  || fail "management cluster not reachable (check KUBECONFIG)"
echo "  management cluster: OK"

# --- AWS credentials ---
log "checking AWS credentials"
aws sts get-caller-identity --output text >/dev/null 2>&1 \
  || fail "AWS credentials invalid (check AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)"
echo "  AWS credentials: OK"

# --- namespaces ---
log "applying prerequisite namespaces"
kubectl apply -f "${REPO_ROOT}/prerequisites/namespaces.yaml"
echo "  namespaces: applied"

# --- CAPI providers ---
log "applying CAPI providers (idempotent)"
kubectl apply -f "${REPO_ROOT}/prerequisites/capi-providers.yaml"
echo "  CAPI providers: applied"

# --- CAPIProviders ready ---
log "waiting for CAPIProviders to be Ready (timeout ${PROVIDER_WAIT_TIMEOUT})"
kubectl wait capiproviders --all -A \
  --for=condition=Ready \
  --timeout="${PROVIDER_WAIT_TIMEOUT}" \
  || fail "one or more CAPIProviders not Ready"
echo "  CAPIProviders: Ready"

# --- create/update cluster-identity-credentials secret ---
log "applying cluster-identity-credentials Secret"
kubectl create secret generic cluster-identity-credentials \
  --namespace=capa-system \
  --from-literal=AccessKeyID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=SecretAccessKey="${AWS_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "  cluster-identity-credentials: applied"

# --- apply AWSClusterStaticIdentity ---
log "applying AWSClusterStaticIdentity"
kubectl apply -f "${REPO_ROOT}/prerequisites/aws-identity.yaml"
echo "  AWSClusterStaticIdentity: applied"

echo ""
echo "All prerequisites satisfied."
