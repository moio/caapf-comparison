#!/usr/bin/env bash
# apply-cluster.sh — submit a Cluster resource, substituting the SSH key name
# and injecting region / AMI / VPC topology variables.
#
# Usage: apply-cluster.sh <variant> <cluster-name> <ssh-key-name> <region> <ami-id> <vpc-id> <private-subnet-id> <public-subnet-id>
#   variant:           with-caapf | without-caapf
#   cluster-name:      e.g. tiny-cluster-1
#   ssh-key-name:      AWS keypair name
#   region:            AWS region (e.g. us-east-1)
#   ami-id:            EC2 AMI ID (must match region)
#   vpc-id:            existing VPC ID (e.g. vpc-0123456789abcdef0)
#   private-subnet-id: existing private subnet ID (NAT must be pre-configured)
#   public-subnet-id:  existing public subnet ID (for load balancers)
#
# Required env: KUBECONFIG
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

log() { echo "==> [$(date +%H:%M:%S)] $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

variant="${1:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id> <vpc-id> <private-subnet-id> <public-subnet-id>}"
cluster="${2:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id> <vpc-id> <private-subnet-id> <public-subnet-id>}"
ssh_key="${3:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id> <vpc-id> <private-subnet-id> <public-subnet-id>}"
region="${4:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id> <vpc-id> <private-subnet-id> <public-subnet-id>}"
ami_id="${5:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id> <vpc-id> <private-subnet-id> <public-subnet-id>}"
vpc_id="${6:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id> <vpc-id> <private-subnet-id> <public-subnet-id>}"
private_subnet_id="${7:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id> <vpc-id> <private-subnet-id> <public-subnet-id>}"
public_subnet_id="${8:?Usage: $0 <variant> <cluster-name> <ssh-key-name> <region> <ami-id> <vpc-id> <private-subnet-id> <public-subnet-id>}"

file="${REPO_ROOT}/${variant}/clusters/${cluster}.yaml"
[[ -f "$file" ]] || fail "cluster file not found: ${file}"

log "creating cluster: ${cluster} (variant=${variant} sshKeyName=${ssh_key} region=${region} amiID=${ami_id} vpcID=${vpc_id} privateSubnetID=${private_subnet_id} publicSubnetID=${public_subnet_id})"

# Render: substitute SSH key placeholder, then inject topology variables
# (region, amiID, vpcID, privateSubnetID, publicSubnetID) before the "workers:" block.
extra_file=$(mktemp)
trap 'rm -f "$extra_file"' EXIT

cat >> "$extra_file" <<EOF
      - name: region
        value: ${region}
      - name: amiID
        value: ${ami_id}
      - name: vpcID
        value: ${vpc_id}
      - name: privateSubnetID
        value: ${private_subnet_id}
      - name: publicSubnetID
        value: ${public_subnet_id}
EOF

sed "s/my-aws-keypair/${ssh_key}/g" "$file" \
  | awk -v f="$extra_file" '
      /^    workers:/ { while ((getline line < f) > 0) print line; close(f) }
      { print }
    ' \
  | kubectl apply -f -

echo "  cluster ${cluster} submitted"
