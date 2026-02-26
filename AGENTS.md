# AGENTS.md

## Project

A YAML-only reference repository comparing two approaches to deploying cluster addons (AWS CCM and EBS CSI) on RKE2 clusters provisioned on AWS via Cluster API (CAPI) and managed by Rancher Turtles.

- **With CAAPF** — addons delivered by `HelmChartProxy` resources (Fleet, continuous reconciliation)
- **Without CAAPF** — addons delivered by `manifestsConfigMapReference` on the RKE2ControlPlane (CCM) and a `ClusterResourceSet` (CSI, apply-once)

CNI is RKE2's built-in canal plugin in both variants and is not part of the comparison.

## Structure

```
prerequisites/              # namespaces, CAPIProvider resources, AWSClusterStaticIdentity
clusterclasses/
  with-caapf/               # ClusterClass: aws-rke2-{tiny,small,medium}
  without-caapf/            # ClusterClass: aws-rke2-{tiny,small,medium}-no-caapf
with-caapf/
  addons/                   # HelmChartProxy for CCM and EBS CSI
  clusters/                 # 6 Cluster resources (2 per size)
without-caapf/
  addons/                   # ConfigMap (CCM) + ClusterResourceSet + ConfigMap (CSI)
  clusters/                 # 6 Cluster resources (2 per size)
e2e/
  Makefile                  # test targets: check-prereqs, test-tiny-caapf, test-all, clean-all, …
  test-plan.md              # human-readable description of each test phase
```

Each ClusterClass file is a multi-document YAML containing all subordinate templates in a single file (ClusterClass, AWSClusterTemplate, RKE2ControlPlaneTemplate, two AWSMachineTemplates, RKE2ConfigTemplate).

## Key invariants

- Every ClusterClass exposes four topology variables: `region`, `sshKeyName` (required), `awsClusterIdentityName`, `amiID`. Defaults target `eu-central-1` with the openSUSE Leap 15.6 AMI.
- `serverConfig.cni: canal` and `serverConfig.cloudProviderName: external` are set identically in both variants.
- The **only** structural difference between a with-caapf and without-caapf ClusterClass is the presence of `manifestsConfigMapReference` on the RKE2ControlPlaneTemplate.
- With-CAAPF cluster labels: `cloud-provider: aws`, `csi: aws-ebs-csi-driver`.
- Without-CAAPF cluster labels: `ccm: external`, `csi: external`.
- All Cluster resources use namespace `default` and pod CIDR `192.168.0.0/16`.
- `sshKeyName` in cluster files is set to the placeholder `my-aws-keypair`; callers substitute their real key name (the e2e Makefile does this with `sed`).

## Quality expectations

- **No duplication of logic between twins.** Shared characteristics (CNI, cloud provider config, etcd backup, NLB ports, Canal ingress rules, preRKE2Commands, rollout strategy) must be identical in corresponding with-caapf and without-caapf ClusterClasses. If you change one, change the other.
- **All resource names are namespaced by size and variant.** Pattern: `aws-rke2-{size}[-no-caapf]-{role}`. Never reuse a name across variants.
- **ClusterClass files are self-contained.** All subordinate templates referenced by a ClusterClass live in the same file as the ClusterClass itself.
- **Addon files target by label, not by name.** `HelmChartProxy.spec.clusterSelector` and `ClusterResourceSet.spec.clusterSelector` use label selectors; they must never hard-code cluster names.
- **ConfigMap data keys in `ccm-configmap.yaml` must each be valid standalone YAML** — they are written verbatim to `/var/lib/rancher/rke2/server/manifests/` by RKE2.
- **e2e Makefile targets are idempotent.** Every `apply` step must be safe to re-run. Cleanup targets must use `--ignore-not-found=true`.
- **No secrets in tracked files.** `prerequisites/aws-identity.yaml` contains only placeholder tokens (`<AWS_ACCESS_KEY_ID>`, `<AWS_SECRET_ACCESS_KEY>`). Real credentials must never be committed.
- **Versions are pinned, not floating.** Chart versions in HelmChartProxy, container image tags in ConfigMap manifests, and the RKE2 version in Cluster files must all be explicit. Do not use `latest` or unversioned references.
