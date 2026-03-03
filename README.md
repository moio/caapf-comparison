# CAAPF vs Non-CAAPF: RKE2 on AWS via Cluster API

This repository demonstrates two approaches to deploying cluster addons (AWS CCM and EBS CSI) for RKE2 clusters provisioned on AWS with Cluster API (CAPI). CNI is handled by RKE2's built-in canal plugin in both variants and is not compared here.

## Overview

| Approach | CCM delivery | CSI delivery | Reconciliation |
|----------|-------------|-------------|----------------|
| **With CAAPF** | `HelmOp` (Fleet) | `HelmOp` (Fleet) | Continuous drift correction |
| **Without CAAPF** | `manifestsConfigMapReference` on RKE2ControlPlane | `ClusterResourceSet` | Apply-once (no drift correction) |

Three ClusterClass sizes are provided (tiny / small / medium). Two example Cluster resources per size demonstrate ClusterClass reuse.

## Prerequisites

- **Rancher 2.13+** with Rancher Turtles (CAPI extension) installed on the management cluster
- **kubectl** configured against the management cluster
- **AWS credentials** (access key + secret) with EC2, IAM, and ELB permissions
- **An SSH key pair** already imported into the target AWS region (`us-east-1` by default)
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
  addons/               # ConfigMap (CCM) + ClusterResourceSet (CSI)
  clusters/             # 6 Cluster resources
Makefile                # Test orchestration — see targets below
test/scripts/           # Bash scripts called by Make targets
```

## Quick Start

All operations are driven by `make`. Set four environment variables, then run a target:

```bash
export KUBECONFIG=/path/to/management-cluster.yaml
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export SSH_KEY_NAME=my-aws-keypair       # your EC2 key pair name
```

### Run a single test (with CAAPF)

```bash
make test-tiny-caapf
```

This single command will:
1. Apply prerequisite namespaces, CAPI providers, and AWS identity
2. Apply all three with-CAAPF ClusterClasses (tiny, small, medium)
3. Apply HelmOp addons (CCM + CSI)
4. Create `tiny-cluster-1`, substituting your SSH key, region, and AMI
5. Wait for the cluster to become Ready (~5-10 min)
6. Verify nodes, CCM, Canal CNI, EBS CSI, and providerIDs on the workload cluster

### Run a single test (without CAAPF)

```bash
make test-tiny-no-caapf
```

Same flow, but uses the without-CAAPF ClusterClass, CCM ConfigMap, and CSI ClusterResourceSet instead of HelmOps.

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
| `apply-addons-no-caapf` | Apply ConfigMap + ClusterResourceSet addons |
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

### Optional environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REGION` | `us-east-1` | AWS region |
| `AMI_ID` | `ami-095197d9bbe1d2fb3` | EC2 AMI (openSUSE Leap 16.0, us-east-1) |

Override at invocation time:

```bash
make test-tiny-caapf REGION=eu-west-1 AMI_ID=ami-xxxxxxxxxxxxxxxxx
```

## Comparison

### Lines of YAML / complexity

| Aspect | With CAAPF | Without CAAPF |
|--------|-----------|---------------|
| CCM addon | ~30 lines (HelmOp) | ~120 lines (ConfigMap with embedded manifests) |
| CSI addon | ~35 lines (HelmOp) | ~280 lines (ConfigMap + ClusterResourceSet) |
| ClusterClass | Simpler (no extra fields) | Slightly more (manifestsConfigMapReference) |

### Reconciliation behaviour

**With CAAPF**: Fleet continuously reconciles the Helm releases. If someone manually deletes the CCM DaemonSet, Fleet reinstalls it within seconds. Helm values can be updated in the HelmOp and Fleet rolls out the change to all matching clusters automatically.

**Without CAAPF**: `strategy: ApplyOnce` means the ClusterResourceSet applies the CSI manifests exactly once when a matching cluster is created or the CRS is first applied. If manifests are subsequently deleted or modified in the workload cluster, they are NOT restored. The CCM via `manifestsConfigMapReference` is similarly static - it is embedded at cluster creation time.

### Templating capabilities

**With CAAPF**: `spec.helm.values` in HelmOp supports inline YAML values, allowing per-cluster Helm value overrides. Adding a new cluster size or region-specific config requires only a ClusterClass variable change, not a new HelmOp.

**Without CAAPF**: ConfigMaps contain static manifests. Per-cluster customisation requires separate ConfigMaps per variant, making the approach brittle at scale.

### Upgrade path

**With CAAPF**: Bump `version` in HelmOp. Fleet rolls out the upgrade to all matching clusters in a controlled sequence.

**Without CAAPF**: Update the ConfigMap data and re-apply each affected workload cluster manifest manually. ClusterResourceSet `ApplyOnce` strategy means it will NOT apply again even if the ConfigMap changes - you must either delete the ClusterResourceSetBinding or switch to `strategy: Reconcile` (which has its own caveats).

### Debugging experience

**With CAAPF**: `kubectl get helmops -n default`, `kubectl get bundledeployment -A`, and Fleet UI in Rancher give full visibility into addon state across all clusters.

**Without CAAPF**: Check `kubectl get clusterresourceset` and `kubectl get clusterresourcesetbinding` for CRS status. For CCM, check RKE2 control-plane node logs at `/var/lib/rancher/rke2/agent/logs/rke2.log`.

## Customisation

### Changing the AWS region

Override `REGION` and `AMI_ID` when calling make (the default AMI is specific to `us-east-1`):

```bash
make test-tiny-caapf REGION=eu-west-1 AMI_ID=ami-xxxxxxxxxxxxxxxxx
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
