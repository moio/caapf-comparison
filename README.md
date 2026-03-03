# CAAPF vs Non-CAAPF: RKE2 on AWS via Cluster API

This repository demonstrates two approaches to deploying cluster addons (AWS CCM and EBS CSI) for RKE2 clusters provisioned on AWS with Cluster API (CAPI). CNI is handled by RKE2's built-in canal plugin in both variants and is not compared here.

## Overview

| Approach | CCM delivery | CSI delivery | Reconciliation |
|----------|-------------|-------------|----------------|
| **With CAAPF** | `HelmOp` (Fleet) | `HelmOp` (Fleet) | Continuous drift correction (Fleet) |
| **Without CAAPF** | `ClusterResourceSet` → `HelmChart` CR | `ClusterResourceSet` → `HelmChart` CR | CRS apply-once; then RKE2 Helm controller reconciles within each cluster |

Three ClusterClass sizes are provided (tiny / small / medium). Two example Cluster resources per size demonstrate ClusterClass reuse.

## Prerequisites

- **Rancher 2.13+** with Rancher Turtles (CAPI extension) installed on the management cluster
- **kubectl** configured against the management cluster
- **AWS credentials** (access key + secret) with EC2, IAM, and ELB permissions
- **An SSH key pair** already imported into the target AWS region (`us-east-1` by default)
- **An existing VPC** with a public subnet and a private subnet (see [VPC setup](#vpc-setup) below)
- For the with-CAAPF variant: CAAPF (Fleet addon provider) installed

## Directory Layout

```
prerequisites/          # namespaces, CAPIProviders, AWS identity
clusterclasses/
  with-caapf/           # ClusterClasses: aws-rke2-{tiny,small,medium}
  without-caapf/        # ClusterClasses: aws-rke2-{tiny,small,medium}-no-caapf
with-caapf/
  addons/               # HelmOp for CCM and EBS CSI
  clusters/             # 6 Cluster resources
without-caapf/
  addons/               # ClusterResourceSets for CCM and EBS CSI
  clusters/             # 6 Cluster resources
Makefile                # Test orchestration — see targets below
test/scripts/           # Bash scripts called by Make targets
```

## Quick Start

All operations are driven by `make`. Set the required environment variables, then run a target:

```bash
export KUBECONFIG=/path/to/management-cluster.yaml
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export SSH_KEY_NAME=my-aws-keypair       # your EC2 key pair name
export VPC_ID=vpc-0abc...                # existing VPC (see VPC setup below)
export PRIVATE_SUBNET_ID=subnet-0abc...  # private subnet with NAT pre-configured
export PUBLIC_SUBNET_ID=subnet-0def...   # public subnet for load balancers
```

### Run a single test (with CAAPF)

```bash
make test-tiny-caapf
```

This single command will:
1. Apply prerequisite namespaces, CAPI providers, and AWS identity
2. Apply all three with-CAAPF ClusterClasses (tiny, small, medium)
3. Apply HelmOp addons (CCM + CSI)
4. Create `tiny-cluster-1`, injecting your SSH key, region, AMI, VPC, and subnet IDs
5. Wait for the cluster to become Ready (~5-10 min)
6. Verify nodes, CCM, Canal CNI, EBS CSI, and providerIDs on the workload cluster

### Run a single test (without CAAPF)

```bash
make test-tiny-no-caapf
```

Same flow, but uses the without-CAAPF ClusterClass and ClusterResourceSets (CCM + CSI via HelmChart CRs) instead of HelmOps.

### Cleanup

```bash
make clean-all
```

Deletes all workload clusters (waits for AWS resource cleanup), removes addons, and removes ClusterClasses.

## Makefile Targets

Run `make help` to list all targets (works without env vars). Key targets:

| Target | Description |
|--------|-------------|
| `apply-prereqs` | Validate cluster + AWS creds, apply namespaces, CAPI providers, and AWS identity |
| `apply-clusterclasses-caapf` | Apply all with-CAAPF ClusterClasses |
| `apply-clusterclasses-no-caapf` | Apply all without-CAAPF ClusterClasses |
| `apply-addons-caapf` | Apply HelmOp addons (CCM + CSI) |
| `apply-addons-no-caapf` | Apply ClusterResourceSet addons (CCM + CSI) |
| `test-tiny-caapf` | End-to-end: prereqs + clusterclasses + addons + create + verify (tiny, CAAPF) |
| `test-small-caapf` | Same for small size |
| `test-medium-caapf` | Same for medium size |
| `test-tiny-no-caapf` | End-to-end (tiny, no CAAPF) |
| `test-small-no-caapf` | Same for small size |
| `test-medium-no-caapf` | Same for medium size |
| `test-all-caapf` | Run all 6 with-CAAPF clusters sequentially |
| `test-all-no-caapf` | Run all 6 without-CAAPF clusters sequentially |
| `test-all` | Full matrix — both variants, all sizes |
| `clean-caapf-clusters` | Delete all with-CAAPF workload clusters |
| `clean-no-caapf-clusters` | Delete all without-CAAPF workload clusters |
| `clean-addons` | Remove addon resources |
| `clean-clusterclasses` | Remove all ClusterClasses |
| `clean-all` | Full cleanup: clusters + addons + ClusterClasses |
| `status` | Show current clusters, HelmOps, and ClusterResourceSets |

### Required environment variables

| Variable | Description |
|----------|-------------|
| `KUBECONFIG` | Path to management cluster kubeconfig |
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `SSH_KEY_NAME` | EC2 key pair name already imported in the target region |
| `VPC_ID` | Existing VPC ID (e.g. `vpc-0123456789abcdef0`) |
| `PRIVATE_SUBNET_ID` | Existing private subnet ID; NAT gateway must be pre-configured externally |
| `PUBLIC_SUBNET_ID` | Existing public subnet ID used for the NLB |

### Optional environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REGION` | `us-east-1` | AWS region |
| `AMI_ID` | `ami-095197d9bbe1d2fb3` | EC2 AMI (openSUSE Leap 16.0, us-east-1) |

Override at invocation time:

```bash
make test-tiny-caapf REGION=eu-west-1 AMI_ID=ami-xxxxxxxxxxxxxxxxx
```

## VPC Setup

All clusters share a single pre-existing VPC. CAPA will reuse the VPC and subnets you provide and will **not** create any VPC, subnets, NAT gateways, or internet gateways.

### Required VPC infrastructure

You must create the following before running any `make` target (once, shared by all clusters):

1. **VPC** — any CIDR block (e.g. `10.0.0.0/16`)
2. **Internet Gateway** — attached to the VPC
3. **Public subnet** — route to the Internet Gateway; tag with `kubernetes.io/role/elb=1`
4. **NAT Gateway** — in the public subnet, with an Elastic IP
5. **Private subnet** — route to the NAT Gateway; tag with `kubernetes.io/role/internal-elb=1`

Both subnets should also carry `kubernetes.io/cluster/<cluster-name>=shared` (or `owned`) for each cluster that will use them, so the AWS cloud provider can discover them.

### Example (AWS CLI)

```bash
# VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --query Vpc.VpcId --output text)

# Internet gateway
IGW_ID=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# Public subnet
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID \
  --cidr-block 10.0.0.0/24 --availability-zone us-east-1a \
  --query Subnet.SubnetId --output text)
aws ec2 create-tags --resources $PUBLIC_SUBNET_ID \
  --tags Key=kubernetes.io/role/elb,Value=1
PUB_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id $PUB_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUBLIC_SUBNET_ID

# NAT gateway
EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
NAT_ID=$(aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUBNET_ID \
  --allocation-id $EIP_ALLOC --query NatGateway.NatGatewayId --output text)
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_ID

# Private subnet
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 --availability-zone us-east-1a \
  --query Subnet.SubnetId --output text)
aws ec2 create-tags --resources $PRIVATE_SUBNET_ID \
  --tags Key=kubernetes.io/role/internal-elb,Value=1
PRIV_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id $PRIV_RT --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_ID
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIVATE_SUBNET_ID

echo "VPC_ID=$VPC_ID"
echo "PUBLIC_SUBNET_ID=$PUBLIC_SUBNET_ID"
echo "PRIVATE_SUBNET_ID=$PRIVATE_SUBNET_ID"
```

Export the three IDs and you are ready to run `make test-*`.

## Comparison

### Lines of YAML / complexity

| Aspect | With CAAPF | Without CAAPF |
|--------|-----------|---------------|
| CCM addon | ~34 lines (HelmOp) | ~66 lines (ConfigMap with HelmChart CR + ClusterResourceSet) |
| CSI addon | ~38 lines (HelmOp) | ~68 lines (ConfigMap with HelmChart CR + ClusterResourceSet) |
| ClusterClass | Identical | Identical |

### Reconciliation behaviour

**With CAAPF**: Fleet continuously reconciles the Helm releases across all matching clusters. If someone manually deletes the CCM DaemonSet, Fleet reinstalls it within seconds. Helm values can be updated in the HelmOp and Fleet rolls out the change to all matching clusters automatically.

**Without CAAPF**: `strategy: ApplyOnce` means the ClusterResourceSet delivers the `HelmChart` CR to each matching cluster exactly once. From that point, RKE2's built-in Helm controller takes over and continuously reconciles the release within that cluster — so drift inside a cluster is corrected. However, there is no cross-cluster orchestration: updating the HelmChart version in the ConfigMap on the management cluster does NOT trigger an upgrade on already-bound clusters. To upgrade, you must delete the `ClusterResourceSetBinding` (to force re-delivery of the updated CR) or patch the `HelmChart` CR directly in each workload cluster.

### Templating capabilities

**With CAAPF**: `spec.helm.values` in HelmOp supports inline YAML values, allowing per-cluster Helm value overrides. Adding a new cluster size or region-specific config requires only a ClusterClass variable change, not a new HelmOp.

**Without CAAPF**: The `HelmChart` CR's `valuesContent` field contains static Helm values. All clusters targeted by a given ClusterResourceSet receive the same values. Per-cluster customisation requires separate ConfigMaps per variant, making the approach brittle at scale. That said, the without-CAAPF variant now uses the same upstream chart as the with-CAAPF variant — no hand-maintained manifests, no risk of image tag drift.

### Upgrade path

**With CAAPF**: Bump `version` in HelmOp. Fleet rolls out the upgrade to all matching clusters in a controlled sequence.

**Without CAAPF**: Bump `spec.version` in the `HelmChart` CR inside the ConfigMap on the management cluster. The ClusterResourceSet will NOT re-apply to already-bound clusters (ApplyOnce). To trigger the upgrade, delete the `ClusterResourceSetBinding` for each target cluster, which causes the CRS to re-deliver the updated `HelmChart` CR. RKE2's Helm controller then performs the Helm upgrade within each cluster.

### Debugging experience

**With CAAPF**: `kubectl get helmops -n default`, `kubectl get bundledeployment -A`, and Fleet UI in Rancher give full visibility into addon state across all clusters.

**Without CAAPF**: Check `kubectl get clusterresourceset` and `kubectl get clusterresourcesetbinding` for CRS delivery status. Then check `kubectl get helmchart -n kube-system` in the workload cluster to see if the `HelmChart` CRs were delivered and what state the Helm controller reports. CCM and CSI pods can be inspected directly in `kube-system`.

## Customisation

### Changing the AWS region

Override `REGION` and `AMI_ID` when calling make (the default AMI is specific to `us-east-1`). You must also supply `VPC_ID`, `PRIVATE_SUBNET_ID`, and `PUBLIC_SUBNET_ID` for a VPC in that region:

```bash
make test-tiny-caapf REGION=eu-west-1 AMI_ID=ami-xxxxxxxxxxxxxxxxx \
  VPC_ID=vpc-… PRIVATE_SUBNET_ID=subnet-… PUBLIC_SUBNET_ID=subnet-…
```

### Finding the latest openSUSE Leap AMI

```bash
aws ec2 describe-images \
  --owners aws-marketplace \
  --filters "Name=name,Values=openSUSE-Leap-15.6*" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --region us-east-1
```

### Adding a new cluster size

1. Copy `clusterclasses/with-caapf/small.yaml`, rename resources with the new size name.
2. Adjust `instanceType`, `rootVolume.size`, and replica counts.
3. Add the new ClusterClass name to `HelmOp.spec.targets[].clusterSelector` if needed (or use a shared label approach).
4. Repeat for the without-caapf variant.
