# AGENTS.md

## Project

A YAML-only reference repository comparing two approaches to deploying cluster addons (AWS CCM and EBS CSI) on RKE2 clusters provisioned on AWS via Cluster API (CAPI) and managed by Rancher Turtles.

- **With CAAPF** — addons delivered by `HelmOp` resources
- **Without CAAPF** — addons delivered by `ClusterResourceSet` (both CCM and CSI)

CNI is RKE2's built-in canal plugin in both variants and is not part of the comparison.

## Structure

```
prerequisites/              # namespaces, CAPIProvider resources, AWSClusterStaticIdentity
clusterclasses/
  with-caapf/               # ClusterClass: aws-rke2-{tiny,small,medium}
  without-caapf/            # ClusterClass: aws-rke2-{tiny,small,medium}-no-caapf
with-caapf/
  addons/                   # HelmOp resources for CCM and CSI
  clusters/                 # Cluster resources
without-caapf/
  addons/
    ccm-clusterresourceset.yaml   # ConfigMap (CCM) + ClusterResourceSet
    csi-clusterresourceset.yaml   # ConfigMap (CSI) + ClusterResourceSet
  clusters/                 # Cluster resources

Makefile                    # thin wrapper calling test/scripts/*
test/
  scripts/                  # bash scripts: apply-prereqs, apply-clusterclasses, apply-addons, etc.
```

Each ClusterClass file is a multi-document YAML containing all subordinate templates in a single file (ClusterClass, AWSClusterTemplate, RKE2ControlPlaneTemplate, two AWSMachineTemplates, RKE2ConfigTemplate).

## Key invariants

- Every ClusterClass exposes four topology variables: `region`, `sshKeyName` (required), `awsClusterIdentityName`, `amiID`. Defaults target `us-east-1` with the openSUSE Leap AMI.
- `serverConfig.cni: canal` and `serverConfig.cloudProviderName: external` are set identically in both variants.
- The **only** structural difference between a with-caapf and without-caapf ClusterClass is that the without-caapf variant relies on ClusterResourceSets for addon delivery instead of Fleet HelmOps. The ClusterClasses themselves are otherwise identical.
- All Cluster resources use namespace `default` and pod CIDR `192.168.0.0/16`.
- `sshKeyName` in cluster files is set to the placeholder `my-aws-keypair`, Makefile replaces it with `sed`.

## Quality expectations

- **No duplication of logic between twins.** Shared characteristics (CNI, cloud provider config, etcd backup, NLB ports, Canal ingress rules, preRKE2Commands, rollout strategy) must be identical in corresponding with-caapf and without-caapf ClusterClasses. If you change one, change the other.
- **All resource names are namespaced by size and variant.** Pattern: `aws-rke2-{size}[-no-caapf]-{role}`. Never reuse a name across variants.
- **ClusterClass files are self-contained.** All subordinate templates referenced by a ClusterClass live in the same file as the ClusterClass itself.
- **Addon files target by label, not by name.** `HelmOp.spec.targets[].clusterSelector` and `ClusterResourceSet.spec.clusterSelector` use label selectors; they must never hard-code cluster names.
- **ConfigMap data keys in ClusterResourceSet manifests must each be valid standalone YAML** — they are applied verbatim to the workload cluster.
- **e2e Makefile targets are idempotent.** Every `apply` step must be safe to re-run. Cleanup targets must use `--ignore-not-found=true`.
- **No secrets in tracked files.** `prerequisites/aws-identity.yaml` contains no credentials — it only references a Secret by name (`cluster-identity-credentials`) that is created at runtime by `apply-prereqs.sh`. Real credentials must never be committed.
- **Versions are pinned, not floating.** Chart versions in HelmOp, container image tags in ConfigMap manifests, and the RKE2 version in Cluster files must all be explicit. Do not use `latest` or unversioned references.
