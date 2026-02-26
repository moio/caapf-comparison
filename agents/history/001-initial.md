# PLAN: CAAPF vs Non-CAAPF Comparison for AWS RKE2 Clusters via CAPI

## Goal

Produce a set of YAML files and documentation that demonstrate provisioning RKE2 clusters on AWS using Cluster API, comparing two approaches for deploying cluster addons (CCM, CSI):

1. **With CAAPF** - using `HelmOp` resources from the Cluster API Addon Provider Fleet
2. **Without CAAPF** - using `manifestsConfigMapReference` on RKE2ControlPlane (for CCM) and `ClusterResourceSet` (for CSI)

CNI is handled by RKE2's built-in canal plugin (`serverConfig.cni: canal`), so it is identical in both twins and not part of the comparison.

Three ClusterClass sizes (tiny, small, medium) are defined. Multiple example Cluster resources are created per size to demonstrate ClusterClass reuse.

---

## Directory Structure

```
caapf-comparison/
├── PLAN.md                          # this file
├── README.md                        # full usage documentation
├── prerequisites/
│   ├── namespaces.yaml              # shared namespaces for providers
│   ├── capi-providers.yaml          # CAPIProvider resources (CAPA, CAPRKE2 bootstrap+CP)
│   ├── caapf-provider.yaml          # CAPIProvider for CAAPF (only for the with-CAAPF variant)
│   └── aws-identity.yaml           # AWSClusterStaticIdentity + Secret template
├── clusterclasses/
│   ├── with-caapf/
│   │   ├── tiny.yaml                # ClusterClass: aws-rke2-tiny
│   │   ├── small.yaml               # ClusterClass: aws-rke2-small
│   │   └── medium.yaml              # ClusterClass: aws-rke2-medium
│   └── without-caapf/
│       ├── tiny.yaml                # ClusterClass: aws-rke2-tiny-no-caapf
│       ├── small.yaml               # ClusterClass: aws-rke2-small-no-caapf
│       └── medium.yaml              # ClusterClass: aws-rke2-medium-no-caapf
├── with-caapf/
│   ├── addons/
│   │   ├── ccm.yaml                 # HelmOp for AWS Cloud Controller Manager
│   │   └── csi.yaml                 # HelmOp for AWS EBS CSI Driver
│   └── clusters/
│       ├── tiny-cluster-1.yaml      # Cluster from aws-rke2-tiny
│       ├── tiny-cluster-2.yaml      # Cluster from aws-rke2-tiny (reuse demo)
│       ├── small-cluster-1.yaml     # Cluster from aws-rke2-small
│       ├── small-cluster-2.yaml     # Cluster from aws-rke2-small (reuse demo)
│       ├── medium-cluster-1.yaml    # Cluster from aws-rke2-medium
│       └── medium-cluster-2.yaml    # Cluster from aws-rke2-medium (reuse demo)
├── without-caapf/
│   ├── addons/
│   │   ├── ccm-configmap.yaml       # ConfigMap for manifestsConfigMapReference
│   │   └── csi-clusterresourceset.yaml  # ClusterResourceSet + ConfigMap for EBS CSI
│   └── clusters/
│       ├── tiny-cluster-1.yaml
│       ├── tiny-cluster-2.yaml
│       ├── small-cluster-1.yaml
│       ├── small-cluster-2.yaml
│       ├── medium-cluster-1.yaml
│       └── medium-cluster-2.yaml
└── e2e/
    └── test-plan.md                 # E2E test automation suggestion
```

---

## Design Decisions

### ClusterClass Sizing

| Size   | CP Instances | CP Type     | Worker Instances | Worker Type  | Root Volume |
|--------|-------------|-------------|------------------|-------------|-------------|
| tiny   | 1           | t3.medium   | 1                | t3.medium   | 30 GiB      |
| small  | 1           | t3.large    | 2                | t3.large    | 50 GiB      |
| medium | 3           | t3.xlarge   | 3                | t3.xlarge   | 80 GiB      |

Each ClusterClass is a **separate resource** (`aws-rke2-tiny`, `aws-rke2-small`, `aws-rke2-medium`) with appropriate defaults baked in. Topology variables allow overriding region, SSH key, and identity.

### AMI Strategy: openSUSE Leap with Online RKE2 Install

Instead of requiring a pre-built AMI via image-builder, we use a **generic openSUSE Leap 15.6 AMI** and install RKE2 online at boot time:

- `airGapped` is not set (defaults to `false`) - CAPRKE2 uses the online installer (`https://get.rke2.io`)
- The AMI ID is a ClusterClass variable with a default pointing to the official openSUSE Leap 15.6 AMI in `eu-central-1`
- `preRKE2Commands` sets the hostname (required for AWS instances)
- `gzipUserData: false` to avoid cloud-init issues on openSUSE
- openSUSE Leap includes `cloud-init`, `systemd`, and `curl` by default, which is all CAPRKE2 needs

### AWS Region

Default: `eu-central-1`, exposed as a ClusterClass variable.

### AWS Identity

Uses `AWSClusterStaticIdentity` with a user-provided Secret containing `AccessKeyID` and `SecretAccessKey` in `capa-system`. The identity name defaults to `cluster-identity` and is a ClusterClass variable.

### Why Separate ClusterClasses Per Twin

The `manifestsConfigMapReference` field lives on the `RKE2ControlPlaneTemplate`, which is part of the ClusterClass definition. This means the without-CAAPF variant needs structurally different ClusterClasses. We create separate ClusterClasses with a `-no-caapf` suffix rather than trying to use JSON patches to conditionally set/unset this field, because:

- It makes the comparison immediately visible
- ClusterClass JSON patches cannot cleanly add/remove entire optional struct fields
- It honestly reflects how these two approaches differ at the infrastructure level

This gives us **six ClusterClasses total**: three for with-CAAPF, three for without-CAAPF.

---

## Detailed File Specifications

### 1. `prerequisites/namespaces.yaml`

Creates namespaces:
- `capa-system` - CAPA infrastructure provider
- `rke2-bootstrap-system` - CAPRKE2 bootstrap provider
- `rke2-control-plane-system` - CAPRKE2 control plane provider
- `fleet-addon-system` - CAAPF addon provider

### 2. `prerequisites/capi-providers.yaml`

CAPIProvider resources for:
- **CAPA** in `capa-system` with `AWS_B64ENCODED_CREDENTIALS: ""` and `clusterResourceSet: true`
- **CAPRKE2 Bootstrap** (`type: bootstrap`, `name: rke2`) in `rke2-bootstrap-system`
- **CAPRKE2 Control Plane** (`type: controlPlane`, `name: rke2`) in `rke2-control-plane-system`

The `clusterResourceSet: true` feature is enabled on CAPA for the without-CAAPF variant.

### 3. `prerequisites/caapf-provider.yaml`

CAPIProvider for CAAPF:
```yaml
apiVersion: turtles-capi.cattle.io/v1alpha1
kind: CAPIProvider
metadata:
  name: fleet
  namespace: fleet-addon-system
spec:
  name: rancher-fleet
  type: addon
```

### 4. `prerequisites/aws-identity.yaml`

Template for `AWSClusterStaticIdentity` + Secret. User substitutes `<AWS_ACCESS_KEY_ID>` and `<AWS_SECRET_ACCESS_KEY>`.

### 5. ClusterClass Files

Each ClusterClass YAML includes all subordinate templates in a single multi-document YAML:
- `ClusterClass`
- `AWSClusterTemplate`
- `RKE2ControlPlaneTemplate`
- `AWSMachineTemplate` (control plane)
- `AWSMachineTemplate` (worker)
- `RKE2ConfigTemplate` (worker bootstrap)

#### Key differences between with-CAAPF and without-CAAPF ClusterClasses:

| Aspect | with-CAAPF | without-CAAPF |
|--------|-----------|---------------|
| ClusterClass name | `aws-rke2-{size}` | `aws-rke2-{size}-no-caapf` |
| `manifestsConfigMapReference` | absent | set to `aws-ccm-manifests` ConfigMap |
| Expected cluster labels | `cloud-provider: aws`, `csi: aws-ebs-csi-driver` | `ccm: external`, `csi: external` |

#### Shared characteristics (both twins):
- `serverConfig.cloudProviderName: external`
- `serverConfig.cni: canal` (RKE2 built-in CNI - identical in both twins, not externally managed)
- `agentConfig.kubelet.extraArgs: [--cloud-provider=external]`
- `preRKE2Commands` for hostname setup
- Online install (no `airGapped` flag)
- `serverConfig.etcd.backupConfig` with sensible defaults
- `rolloutStrategy: RollingUpdate` with `maxSurge: 1`
- NLB with RKE2-specific ports (9345, 2379, 2380, 6443) and Canal CNI ingress rules
- VPC with `availabilityZoneUsageLimit: 1`

#### ClusterClass variables:
- `region` (string, default: `eu-central-1`)
- `sshKeyName` (string, required)
- `awsClusterIdentityName` (string, default: `cluster-identity`)
- `amiID` (string, default: openSUSE Leap 15.6 AMI for eu-central-1)

### 6. With-CAAPF Addon Files

Based on upstream Turtles examples, adapted for our ClusterClass names.

#### `with-caapf/addons/ccm.yaml` - HelmOp
- Chart: `aws-cloud-controller-manager` from `https://kubernetes.github.io/cloud-provider-aws`
- `templateValues` for per-cluster node selector configuration
- Targets: `cloud-provider: aws` + `clusterclass-name` in `[aws-rke2-tiny, aws-rke2-small, aws-rke2-medium]`

#### `with-caapf/addons/csi.yaml` - HelmOp
- Chart: `aws-ebs-csi-driver` from `https://kubernetes-sigs.github.io/aws-ebs-csi-driver`
- `templateValues` for host networking
- Targets: `csi: aws-ebs-csi-driver` + matching clusterclass names

### 7. Without-CAAPF Addon Files

#### `without-caapf/addons/ccm-configmap.yaml`
A ConfigMap named `aws-ccm-manifests` containing full AWS CCM manifest set:
- ServiceAccount `cloud-controller-manager` in `kube-system`
- ClusterRole `system:cloud-controller-manager` with full permissions
- ClusterRoleBinding
- RoleBinding for `apiserver-authentication-reader`
- DaemonSet `aws-cloud-controller-manager` with node selector, tolerations, host networking

Referenced by `manifestsConfigMapReference` in the without-CAAPF RKE2ControlPlaneTemplate. RKE2 copies each data entry to `/var/lib/rancher/rke2/server/manifests/` for auto-deployment.

#### `without-caapf/addons/csi-clusterresourceset.yaml`
- `ConfigMap` with full AWS EBS CSI driver manifests (DaemonSet, Deployment, RBAC, CSIDriver, PDB)
- `ClusterResourceSet` with `strategy: ApplyOnce`, selector: `csi: external`

### 8. Cluster Files

Each cluster file defines a single `Cluster` resource with:
- `cluster-api.cattle.io/rancher-auto-import: "true"` label
- Appropriate addon labels for the variant
- Topology referencing the matching ClusterClass
- Variable overrides
- Worker `machineDeployments` with `class: default-worker`
- Pod CIDR: `192.168.0.0/16`

#### With-CAAPF cluster labels:
```yaml
labels:
  cluster-api.cattle.io/rancher-auto-import: "true"
  cloud-provider: aws
  csi: aws-ebs-csi-driver
```

#### Without-CAAPF cluster labels:
```yaml
labels:
  cluster-api.cattle.io/rancher-auto-import: "true"
  ccm: external
  csi: external
```

### 9. README.md

Sections:
1. **Overview** - what this project demonstrates and why
2. **Prerequisites** - Rancher 2.13 with Turtles, kubectl, AWS credentials, SSH key pair
3. **Installation** - step-by-step applying prerequisites (shared, then variant-specific)
4. **Usage: With CAAPF** - applying ClusterClasses, HelmOps, creating clusters
5. **Usage: Without CAAPF** - applying ClusterClasses, ConfigMaps, ClusterResourceSets, creating clusters
6. **Comparison** - side-by-side analysis highlighting:
   - Lines of YAML / complexity
   - Reconciliation behavior (continuous vs apply-once)
   - Templating capabilities
   - Upgrade path
   - Debugging experience
7. **Cleanup** - deleting clusters and resources in correct order
8. **Customization** - changing region, sizes, AMI, adding new sizes

### 10. E2E Test Plan (`e2e/test-plan.md`)

Structured as an automatable sequence:

```
Phase 1: Prerequisites validation
  - Management cluster reachable
  - CAPIProviders reach Ready state (kubectl wait)
  - AWS credentials work (aws sts get-caller-identity)

Phase 2: ClusterClass deployment
  - Apply ClusterClasses
  - Verify no webhook rejections

Phase 3: Addon deployment
  - With-CAAPF: apply HelmOps, verify accepted
  - Without-CAAPF: apply ConfigMaps + ClusterResourceSets

Phase 4: Cluster creation (start with tiny for speed)
  - Apply cluster YAMLs
  - kubectl wait --for=condition=Ready cluster/<name> --timeout=20m
  - Verify CP initialization
  - Verify worker MachineDeployment ready
  - Get workload cluster kubeconfig
  - Verify on workload cluster:
    - All nodes Ready
    - CCM running (kubectl get pods -n kube-system -l k8s-app=aws-cloud-controller-manager)
    - CNI running (canal pods in kube-system, managed by RKE2 - same in both twins)
    - CSI running (ebs-csi-controller pods)
    - Nodes have provider IDs (indicates CCM worked)

Phase 5: Cleanup
  - Delete clusters, wait for AWS cleanup
  - Delete ClusterClasses and addons

Phase 6: Report
  - Pass/fail per cluster
  - Provisioning times
  - Behavioral differences
```

Suggested implementation: Makefile with targets like `test-tiny-caapf`, `test-all`, etc. Each step is idempotent. Timeouts are generous (20min for cluster creation). Structured output for agent iteration.

---

## Implementation Order

1. `prerequisites/` files (namespaces, providers, identity)
2. `clusterclasses/with-caapf/` (tiny, small, medium)
3. `clusterclasses/without-caapf/` (tiny-no-caapf, small-no-caapf, medium-no-caapf)
4. `with-caapf/addons/` (ccm, csi HelmOps)
5. `without-caapf/addons/` (ccm ConfigMap, csi ClusterResourceSet)
6. `with-caapf/clusters/` (6 cluster definitions)
7. `without-caapf/clusters/` (6 cluster definitions)
8. `README.md`
9. `e2e/test-plan.md`

---

## Key Technical Notes

### manifestsConfigMapReference
- Data entries are copied to `/var/lib/rancher/rke2/server/manifests/` on CP nodes
- RKE2 auto-deploys any YAML in that directory
- Runs only on **control plane nodes** but deploys cluster-wide resources
- ConfigMap must exist in the **same namespace** as the RKE2ControlPlane

### ClusterResourceSet
- CAPI built-in addon mechanism
- Label-based cluster targeting
- `strategy: ApplyOnce` - applied once, not reconciled
- Requires `clusterResourceSet: true` feature on CAPA provider
- ConfigMaps must be in the **same namespace** as the Cluster

### CAAPF HelmOp
- Fleet-based continuous reconciliation
- Auto-creates Fleet Cluster Groups per ClusterClass
- Adds `clusterclass-name.fleet.addons.cluster.x-k8s.io` label automatically
- `templateValues` for per-cluster Helm templating using `.ClusterValues`
- Full lifecycle management (install, upgrade, rollback)

---

## Open Questions / Risks

1. **openSUSE Leap AMI ID stability** - AMI IDs change. README documents how to find the latest one. Default may become stale.

2. **CAPRKE2 + openSUSE compatibility** - `get.rke2.io` officially supports SLES/openSUSE, but the combination is less tested than Ubuntu in upstream examples.

3. **ConfigMap size limits** - Kubernetes ConfigMaps have a 1 MiB limit. The full EBS CSI manifest is large. May need to split across multiple ConfigMap data keys. This is a real pain point that highlights a CAAPF advantage.
