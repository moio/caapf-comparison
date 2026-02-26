# E2E Test Plan

This document describes the test phases automated by `e2e/Makefile`.

## Running the tests

```bash
# Prerequisite check only
make -f e2e/Makefile SSH_KEY_NAME=my-keypair check-prereqs

# Single cluster, quick smoke-test (fastest: ~15-20 min)
make -f e2e/Makefile SSH_KEY_NAME=my-keypair test-tiny-caapf
make -f e2e/Makefile SSH_KEY_NAME=my-keypair test-tiny-no-caapf

# Full matrix (all 6 clusters per variant, ~2-3 hours with AWS provisioning)
make -f e2e/Makefile SSH_KEY_NAME=my-keypair test-all

# Print results summary
make -f e2e/Makefile report

# Cleanup
make -f e2e/Makefile clean-all
```

## Phase 1 — Prerequisites validation (`check-prereqs`)

| Check | Command | Pass criteria |
|-------|---------|---------------|
| Management cluster reachable | `kubectl cluster-info` | Exit 0 |
| AWS credentials valid | `aws sts get-caller-identity` | Exit 0 |
| CAPIProviders ready | `kubectl wait capiproviders --all --for=condition=Ready` | All Ready within 5 min |

## Phase 2 — ClusterClass deployment

| Check | Command | Pass criteria |
|-------|---------|---------------|
| ClusterClasses accepted | `kubectl apply -f clusterclasses/...` | No webhook rejections |

## Phase 3 — Addon deployment

### With CAAPF

| Check | Command | Pass criteria |
|-------|---------|---------------|
| HelmChartProxies accepted | `kubectl apply -f with-caapf/addons/` | No webhook rejections |

### Without CAAPF

| Check | Command | Pass criteria |
|-------|---------|---------------|
| CCM ConfigMap applied | `kubectl apply -f without-caapf/addons/ccm-configmap.yaml` | No errors |
| ClusterResourceSet applied | `kubectl apply -f without-caapf/addons/csi-clusterresourceset.yaml` | No errors |

## Phase 4 — Cluster creation and validation

For each cluster under test:

| Step | Command | Timeout |
|------|---------|---------|
| Submit Cluster | `kubectl apply -f ...` | — |
| Wait for Ready | `kubectl wait cluster/<name> --for=condition=Ready` | 20 min |
| Fetch kubeconfig | `kubectl get secret <name>-kubeconfig` | — |
| All nodes Ready | `kubectl wait nodes --all --for=condition=Ready` | 5 min |
| CCM pods running | label: `k8s-app=aws-cloud-controller-manager` | 5 min |
| Canal CNI running | label: `app=canal` | 5 min |
| EBS CSI running | label: `app=ebs-csi-controller` | 5 min |
| Node providerIDs set | `kubectl get nodes -o jsonpath='{.items[*].spec.providerID}'` | — |

Node providerIDs (`aws://...`) confirm that the CCM successfully initialised the nodes.

## Phase 5 — Cleanup

```
clean-caapf-clusters     → delete Cluster objects, wait for AWS teardown
clean-no-caapf-clusters  → same for without-CAAPF clusters
clean-addons             → delete HelmChartProxies, ConfigMaps, ClusterResourceSets
clean-clusterclasses     → delete all ClusterClass objects
```

## Phase 6 — Report

Results are written to `e2e/results/caapf-results.txt` and `e2e/results/no-caapf-results.txt` in the format:

```
PASS tiny-cluster-1 847s
PASS small-cluster-1 923s
FAIL medium-cluster-1
```

`make report` prints a combined summary to stdout.

## Idempotency

All `apply` operations are idempotent. Targets can be re-run safely after a partial failure. The `check-prereqs` target is always included as a dependency for test targets to prevent false starts.

## Timeouts

| Operation | Default | Override |
|-----------|---------|----------|
| Cluster ready | 20 min | `CLUSTER_WAIT_TIMEOUT=30m` |
| Provider ready | 5 min | `PROVIDER_WAIT_TIMEOUT=10m` |
| Pod ready | 5 min | hardcoded in verify step |
