#!/usr/bin/env bash
# apply-cluster.sh — submit a Cluster resource, substituting the SSH key name
# and injecting region / AMI topology variables.
#
# Usage: apply-cluster.sh <variant> <cluster-name> <ssh-key-name> <region> <ami-id>
#   variant:      with-caapf | without-caapf
#   cluster-name: e.g. tiny-cluster-1
#   ssh-key-name: AWS keypair name
#   region:       AWS region (e.g. us-east-1)
#   ami-id:       EC2 AMI ID (must match region)
#
# Required env: KUBECONFIG
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

log() { echo "==> [$(date +%H:%M:%S)] $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

variant="${1:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id>}"
cluster="${2:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id>}"
ssh_key="${3:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id>}"
region="${4:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id>}"
ami_id="${5:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id>}"

file="${REPO_ROOT}/${variant}/clusters/${cluster}.yaml"
[[ -f "$file" ]] || fail "cluster file not found: ${file}"

log "creating cluster: ${cluster} (variant=${variant} sshKeyName=${ssh_key} region=${region} amiID=${ami_id})"

# Render: substitute SSH key placeholder, then inject region and amiID topology
# variables before the "workers:" block.
extra_file=$(mktemp)
trap 'rm -f "$extra_file"' EXIT

cat >> "$extra_file" <<EOF
      - name: region
        value: ${region}
      - name: amiID
        value: ${ami_id}
EOF

sed "s/my-aws-keypair/${ssh_key}/g" "$file" \
  | awk -v f="$extra_file" '
      /^    workers:/ { while ((getline line < f) > 0) print line; close(f) }
      { print }
    ' \
  | kubectl apply -f -

echo "  cluster ${cluster} submitted"
