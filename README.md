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
- **An SSH key pair** already imported into the target AWS region (`eu-central-1` by default)
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
e2e/                    # Makefile-based test suite
```

## Installation

### 1. Shared prerequisites (both variants)

```bash
# Create namespaces
kubectl apply -f prerequisites/namespaces.yaml

# Install CAPI providers (CAPA + CAPRKE2)
kubectl apply -f prerequisites/capi-providers.yaml

# Wait for providers to become ready (~2-3 minutes)
kubectl wait capiproviders --all --for=condition=Ready --timeout=5m -A

# Configure AWS identity - edit the file first!
# Replace <AWS_ACCESS_KEY_ID> and <AWS_SECRET_ACCESS_KEY>
kubectl apply -f prerequisites/aws-identity.yaml
```

### 2a. Additional prerequisite for with-CAAPF variant

```bash
kubectl apply -f prerequisites/caapf-provider.yaml
kubectl wait capiprovider fleet -n fleet-addon-system --for=condition=Ready --timeout=5m
```

## Usage: With CAAPF

```bash
# 1. Apply ClusterClasses
kubectl apply -f clusterclasses/with-caapf/tiny.yaml
kubectl apply -f clusterclasses/with-caapf/small.yaml
kubectl apply -f clusterclasses/with-caapf/medium.yaml

# 2. Apply HelmOps (CAAPF will install these on matching clusters automatically)
kubectl apply -f with-caapf/addons/ccm.yaml
kubectl apply -f with-caapf/addons/csi.yaml

# 3. Create clusters (edit sshKeyName value before applying)
kubectl apply -f with-caapf/clusters/tiny-cluster-1.yaml
kubectl apply -f with-caapf/clusters/tiny-cluster-2.yaml

# Wait for a cluster to be ready (up to 20 minutes)
kubectl wait cluster/tiny-cluster-1 --for=condition=Ready --timeout=20m
```

## Usage: Without CAAPF

```bash
# 1. Apply ClusterClasses
kubectl apply -f clusterclasses/without-caapf/tiny.yaml
kubectl apply -f clusterclasses/without-caapf/small.yaml
kubectl apply -f clusterclasses/without-caapf/medium.yaml

# 2. Apply addon resources
# CCM ConfigMap (must exist before clusters are created)
kubectl apply -f without-caapf/addons/ccm-configmap.yaml
# EBS CSI ClusterResourceSet + ConfigMap
kubectl apply -f without-caapf/addons/csi-clusterresourceset.yaml

# 3. Create clusters (edit sshKeyName value before applying)
kubectl apply -f without-caapf/clusters/tiny-cluster-1.yaml
kubectl apply -f without-caapf/clusters/tiny-cluster-2.yaml

kubectl wait cluster/tiny-cluster-1 --for=condition=Ready --timeout=20m
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

## Cleanup

```bash
# Delete clusters first (triggers AWS resource cleanup)
kubectl delete -f with-caapf/clusters/
kubectl delete -f without-caapf/clusters/

# Wait for clusters to be fully deleted before removing ClusterClasses
kubectl wait clusters --all --for=delete --timeout=20m

# Remove addons
kubectl delete -f with-caapf/addons/
kubectl delete -f without-caapf/addons/

# Remove ClusterClasses
kubectl delete -f clusterclasses/

# Remove providers and identity (optional - preserves management cluster config)
# kubectl delete -f prerequisites/
```

## Customisation

### Changing the AWS region

Override the `region` variable per cluster:

```yaml
variables:
  - name: region
    value: us-east-1
  - name: sshKeyName
    value: my-us-keypair
```

Update `amiID` too - the default AMI is specific to `eu-central-1`.

### Finding the latest openSUSE Leap AMI

```bash
aws ec2 describe-images \
  --owners aws-marketplace \
  --filters "Name=name,Values=openSUSE-Leap-15.6*" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --region eu-central-1
```

### Adding a new cluster size

1. Copy `clusterclasses/with-caapf/small.yaml`, rename resources with the new size name.
2. Adjust `instanceType`, `rootVolume.size`, and replica counts.
3. Add the new ClusterClass name to `HelmOp.spec.targets[].clusterSelector` if needed (or use a shared label approach).
4. Repeat for the without-caapf variant.
