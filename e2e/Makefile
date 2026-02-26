# E2E Test Suite — CAAPF vs Non-CAAPF Comparison
#
# Prerequisites:
#   - KUBECONFIG pointing at the management cluster
#   - SSH_KEY_NAME set to your AWS keypair name
#   - AWS credentials configured (aws sts get-caller-identity must succeed)
#
# Usage:
#   make SSH_KEY_NAME=my-keypair test-tiny-caapf
#   make SSH_KEY_NAME=my-keypair test-all
#   make clean-all

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ─── configuration ────────────────────────────────────────────────────────────
SSH_KEY_NAME          ?= my-aws-keypair
CLUSTER_WAIT_TIMEOUT  ?= 20m
PROVIDER_WAIT_TIMEOUT ?= 5m
NAMESPACE             ?= default
KUBECONFIG            ?= $(HOME)/.kube/config
RESULTS_DIR           ?= e2e/results

# Clusters under test
CAAPF_CLUSTERS        := tiny-cluster-1 tiny-cluster-2 small-cluster-1 small-cluster-2 medium-cluster-1 medium-cluster-2
NO_CAAPF_CLUSTERS     := tiny-cluster-1 tiny-cluster-2 small-cluster-1 small-cluster-2 medium-cluster-1 medium-cluster-2

# ─── helpers ──────────────────────────────────────────────────────────────────
KUBECTL := kubectl --kubeconfig=$(KUBECONFIG)
TS      := $(shell date +%Y%m%dT%H%M%S)
LOG     = $(RESULTS_DIR)/$(TS)-$@.log

define log_step
	@echo "==> [$(shell date +%H:%M:%S)] $(1)"
endef

define assert_pods_running
	@echo "  checking pods: namespace=$(1) selector=$(2) in cluster kubeconfig $(3)"
	KUBECONFIG=$(3) kubectl wait pods \
	  -n $(1) -l $(2) \
	  --for=condition=Ready \
	  --timeout=5m \
	  || (echo "FAIL: pods not ready: $(2) in $(1)"; exit 1)
endef

# ─── targets ──────────────────────────────────────────────────────────────────

.PHONY: help
help:  ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-30s %s\n", $$1, $$2}'

# ── Phase 1: prerequisites validation ─────────────────────────────────────────

.PHONY: check-prereqs
check-prereqs:  ## Phase 1 – validate management cluster and AWS credentials
	$(call log_step,Phase 1: prerequisites validation)
	@$(KUBECTL) cluster-info --request-timeout=10s \
	  || (echo "FAIL: management cluster not reachable"; exit 1)
	@echo "  management cluster: OK"
	@aws sts get-caller-identity --output text > /dev/null \
	  || (echo "FAIL: AWS credentials invalid"; exit 1)
	@echo "  AWS credentials: OK"
	@$(KUBECTL) wait capiproviders --all -A \
	  --for=condition=Ready \
	  --timeout=$(PROVIDER_WAIT_TIMEOUT) \
	  || (echo "FAIL: one or more CAPIProviders not Ready"; exit 1)
	@echo "  CAPIProviders: Ready"

# ── Phase 2: ClusterClass deployment ──────────────────────────────────────────

.PHONY: apply-clusterclasses-caapf
apply-clusterclasses-caapf:  ## Phase 2 – apply with-CAAPF ClusterClasses
	$(call log_step,Phase 2: apply ClusterClasses (with-caapf))
	@$(KUBECTL) apply -f clusterclasses/with-caapf/tiny.yaml
	@$(KUBECTL) apply -f clusterclasses/with-caapf/small.yaml
	@$(KUBECTL) apply -f clusterclasses/with-caapf/medium.yaml
	@echo "  ClusterClasses applied"

.PHONY: apply-clusterclasses-no-caapf
apply-clusterclasses-no-caapf:  ## Phase 2 – apply without-CAAPF ClusterClasses
	$(call log_step,Phase 2: apply ClusterClasses (without-caapf))
	@$(KUBECTL) apply -f clusterclasses/without-caapf/tiny.yaml
	@$(KUBECTL) apply -f clusterclasses/without-caapf/small.yaml
	@$(KUBECTL) apply -f clusterclasses/without-caapf/medium.yaml
	@echo "  ClusterClasses applied"

# ── Phase 3: addon deployment ──────────────────────────────────────────────────

.PHONY: apply-addons-caapf
apply-addons-caapf:  ## Phase 3 – apply CAAPF HelmChartProxy addons
	$(call log_step,Phase 3: apply HelmChartProxy addons)
	@$(KUBECTL) apply -f with-caapf/addons/ccm.yaml
	@$(KUBECTL) apply -f with-caapf/addons/csi.yaml
	@echo "  HelmChartProxies applied"
	@$(KUBECTL) wait helmchartproxies --all -n $(NAMESPACE) \
	  --for=condition=Ready \
	  --timeout=2m 2>/dev/null || echo "  (helmchartproxies not yet populated - clusters not running yet)"

.PHONY: apply-addons-no-caapf
apply-addons-no-caapf:  ## Phase 3 – apply ConfigMap + ClusterResourceSet addons
	$(call log_step,Phase 3: apply ConfigMap and ClusterResourceSet addons)
	@$(KUBECTL) apply -f without-caapf/addons/ccm-configmap.yaml
	@$(KUBECTL) apply -f without-caapf/addons/csi-clusterresourceset.yaml
	@echo "  ConfigMap and ClusterResourceSet applied"
	@$(KUBECTL) get clusterresourceset aws-ebs-csi-driver -n $(NAMESPACE) -o wide

# ── Phase 4: cluster lifecycle helpers ────────────────────────────────────────

# Inject SSH_KEY_NAME into cluster yamls on the fly using kustomize-like sed
define apply_cluster
	$(call log_step,creating cluster: $(1) from $(2))
	@sed 's/my-aws-keypair/$(SSH_KEY_NAME)/g' $(2) | $(KUBECTL) apply -f -
	@echo "  cluster $(1) submitted"
endef

define wait_cluster
	$(call log_step,waiting for cluster $(1) to be Ready)
	@$(KUBECTL) wait cluster/$(1) -n $(NAMESPACE) \
	  --for=condition=Ready \
	  --timeout=$(CLUSTER_WAIT_TIMEOUT) \
	  && echo "  cluster $(1): Ready" \
	  || (echo "FAIL: cluster $(1) did not become Ready within $(CLUSTER_WAIT_TIMEOUT)"; \
	      $(KUBECTL) describe cluster/$(1) -n $(NAMESPACE); \
	      exit 1)
endef

define get_kubeconfig
	$(call log_step,fetching kubeconfig for $(1))
	@$(KUBECTL) get secret $(1)-kubeconfig -n $(NAMESPACE) \
	  -o jsonpath='{.data.value}' | base64 -d > /tmp/$(1)-kubeconfig
	@echo "  kubeconfig saved to /tmp/$(1)-kubeconfig"
endef

define verify_workload_cluster
	$(call log_step,verifying workload cluster $(1))
	@KUBECONFIG=/tmp/$(1)-kubeconfig kubectl wait nodes --all \
	  --for=condition=Ready \
	  --timeout=5m \
	  || (echo "FAIL: nodes not Ready in $(1)"; exit 1)
	@echo "  nodes: Ready"
	@KUBECONFIG=/tmp/$(1)-kubeconfig kubectl get pods \
	  -n kube-system -l k8s-app=aws-cloud-controller-manager \
	  --field-selector=status.phase=Running --no-headers | grep -q . \
	  || (echo "FAIL: CCM pods not running in $(1)"; \
	      KUBECONFIG=/tmp/$(1)-kubeconfig kubectl get pods -n kube-system; \
	      exit 1)
	@echo "  CCM: running"
	@KUBECONFIG=/tmp/$(1)-kubeconfig kubectl get pods \
	  -n kube-system -l app=canal \
	  --field-selector=status.phase=Running --no-headers | grep -q . \
	  || (echo "FAIL: Canal CNI pods not running in $(1)"; exit 1)
	@echo "  Canal CNI: running"
	@KUBECONFIG=/tmp/$(1)-kubeconfig kubectl get pods \
	  -n kube-system -l app=ebs-csi-controller \
	  --field-selector=status.phase=Running --no-headers | grep -q . \
	  || (echo "FAIL: EBS CSI controller pods not running in $(1)"; \
	      KUBECONFIG=/tmp/$(1)-kubeconfig kubectl get pods -n kube-system; \
	      exit 1)
	@echo "  EBS CSI: running"
	@KUBECONFIG=/tmp/$(1)-kubeconfig kubectl get nodes \
	  -o jsonpath='{.items[*].spec.providerID}' | grep -q 'aws://' \
	  || (echo "FAIL: nodes missing AWS providerID in $(1) - CCM may not have initialised"; exit 1)
	@echo "  node providerIDs: present (CCM initialised successfully)"
	@echo "  PASS: $(1)"
endef

# ── Phase 5: cleanup helpers ──────────────────────────────────────────────────

define delete_cluster
	$(call log_step,deleting cluster: $(1))
	@$(KUBECTL) delete cluster/$(1) -n $(NAMESPACE) --ignore-not-found=true
endef

define wait_cluster_deleted
	@$(KUBECTL) wait cluster/$(1) -n $(NAMESPACE) \
	  --for=delete \
	  --timeout=$(CLUSTER_WAIT_TIMEOUT) \
	  && echo "  cluster $(1): deleted" \
	  || echo "  WARNING: cluster $(1) deletion timed out"
endef

# ── Single-cluster test targets (with-CAAPF) ──────────────────────────────────

.PHONY: test-tiny-caapf
test-tiny-caapf: check-prereqs apply-clusterclasses-caapf apply-addons-caapf  ## Full test: tiny-cluster-1 with CAAPF
	$(call apply_cluster,tiny-cluster-1,with-caapf/clusters/tiny-cluster-1.yaml)
	$(call wait_cluster,tiny-cluster-1)
	$(call get_kubeconfig,tiny-cluster-1)
	$(call verify_workload_cluster,tiny-cluster-1)

.PHONY: test-small-caapf
test-small-caapf: check-prereqs apply-clusterclasses-caapf apply-addons-caapf  ## Full test: small-cluster-1 with CAAPF
	$(call apply_cluster,small-cluster-1,with-caapf/clusters/small-cluster-1.yaml)
	$(call wait_cluster,small-cluster-1)
	$(call get_kubeconfig,small-cluster-1)
	$(call verify_workload_cluster,small-cluster-1)

.PHONY: test-medium-caapf
test-medium-caapf: check-prereqs apply-clusterclasses-caapf apply-addons-caapf  ## Full test: medium-cluster-1 with CAAPF
	$(call apply_cluster,medium-cluster-1,with-caapf/clusters/medium-cluster-1.yaml)
	$(call wait_cluster,medium-cluster-1)
	$(call get_kubeconfig,medium-cluster-1)
	$(call verify_workload_cluster,medium-cluster-1)

# ── Single-cluster test targets (without-CAAPF) ───────────────────────────────

.PHONY: test-tiny-no-caapf
test-tiny-no-caapf: check-prereqs apply-clusterclasses-no-caapf apply-addons-no-caapf  ## Full test: tiny-cluster-1 without CAAPF
	$(call apply_cluster,tiny-cluster-1,without-caapf/clusters/tiny-cluster-1.yaml)
	$(call wait_cluster,tiny-cluster-1)
	$(call get_kubeconfig,tiny-cluster-1)
	$(call verify_workload_cluster,tiny-cluster-1)

.PHONY: test-small-no-caapf
test-small-no-caapf: check-prereqs apply-clusterclasses-no-caapf apply-addons-no-caapf  ## Full test: small-cluster-1 without CAAPF
	$(call apply_cluster,small-cluster-1,without-caapf/clusters/small-cluster-1.yaml)
	$(call wait_cluster,small-cluster-1)
	$(call get_kubeconfig,small-cluster-1)
	$(call verify_workload_cluster,small-cluster-1)

.PHONY: test-medium-no-caapf
test-medium-no-caapf: check-prereqs apply-clusterclasses-no-caapf apply-addons-no-caapf  ## Full test: medium-cluster-1 without CAAPF
	$(call apply_cluster,medium-cluster-1,without-caapf/clusters/medium-cluster-1.yaml)
	$(call wait_cluster,medium-cluster-1)
	$(call get_kubeconfig,medium-cluster-1)
	$(call verify_workload_cluster,medium-cluster-1)

# ── Full matrix test ──────────────────────────────────────────────────────────

.PHONY: test-all-caapf
test-all-caapf: check-prereqs apply-clusterclasses-caapf apply-addons-caapf  ## Run all 6 with-CAAPF clusters sequentially
	@mkdir -p $(RESULTS_DIR)
	@PASS=0; FAIL=0; \
	for cluster in $(CAAPF_CLUSTERS); do \
	  echo "==> testing $$cluster (with-caapf)"; \
	  START=$$(date +%s); \
	  sed 's/my-aws-keypair/$(SSH_KEY_NAME)/g' \
	    with-caapf/clusters/$$cluster.yaml | $(KUBECTL) apply -f - \
	  && $(KUBECTL) wait cluster/$$cluster -n $(NAMESPACE) \
	       --for=condition=Ready --timeout=$(CLUSTER_WAIT_TIMEOUT) \
	  && $(KUBECTL) get secret $$cluster-kubeconfig -n $(NAMESPACE) \
	       -o jsonpath='{.data.value}' | base64 -d > /tmp/$$cluster-kubeconfig \
	  && KUBECONFIG=/tmp/$$cluster-kubeconfig kubectl wait nodes --all \
	       --for=condition=Ready --timeout=5m \
	  && KUBECONFIG=/tmp/$$cluster-kubeconfig kubectl get pods \
	       -n kube-system -l k8s-app=aws-cloud-controller-manager \
	       --field-selector=status.phase=Running --no-headers | grep -q . \
	  && KUBECONFIG=/tmp/$$cluster-kubeconfig kubectl get pods \
	       -n kube-system -l app=ebs-csi-controller \
	       --field-selector=status.phase=Running --no-headers | grep -q . \
	  && END=$$(date +%s) \
	  && ELAPSED=$$((END - START)) \
	  && echo "PASS: $$cluster ($${ELAPSED}s)" \
	  && echo "PASS $$cluster $${ELAPSED}s" >> $(RESULTS_DIR)/caapf-results.txt \
	  && PASS=$$((PASS+1)) \
	  || (echo "FAIL: $$cluster" \
	      && echo "FAIL $$cluster" >> $(RESULTS_DIR)/caapf-results.txt \
	      && FAIL=$$((FAIL+1))); \
	done; \
	echo ""; \
	echo "=== with-CAAPF results: PASS=$$PASS FAIL=$$FAIL ==="; \
	[ "$$FAIL" -eq 0 ]

.PHONY: test-all-no-caapf
test-all-no-caapf: check-prereqs apply-clusterclasses-no-caapf apply-addons-no-caapf  ## Run all 6 without-CAAPF clusters sequentially
	@mkdir -p $(RESULTS_DIR)
	@PASS=0; FAIL=0; \
	for cluster in $(NO_CAAPF_CLUSTERS); do \
	  echo "==> testing $$cluster (without-caapf)"; \
	  START=$$(date +%s); \
	  sed 's/my-aws-keypair/$(SSH_KEY_NAME)/g' \
	    without-caapf/clusters/$$cluster.yaml | $(KUBECTL) apply -f - \
	  && $(KUBECTL) wait cluster/$$cluster -n $(NAMESPACE) \
	       --for=condition=Ready --timeout=$(CLUSTER_WAIT_TIMEOUT) \
	  && $(KUBECTL) get secret $$cluster-kubeconfig -n $(NAMESPACE) \
	       -o jsonpath='{.data.value}' | base64 -d > /tmp/$$cluster-kubeconfig \
	  && KUBECONFIG=/tmp/$$cluster-kubeconfig kubectl wait nodes --all \
	       --for=condition=Ready --timeout=5m \
	  && KUBECONFIG=/tmp/$$cluster-kubeconfig kubectl get pods \
	       -n kube-system -l k8s-app=aws-cloud-controller-manager \
	       --field-selector=status.phase=Running --no-headers | grep -q . \
	  && KUBECONFIG=/tmp/$$cluster-kubeconfig kubectl get pods \
	       -n kube-system -l app=ebs-csi-controller \
	       --field-selector=status.phase=Running --no-headers | grep -q . \
	  && END=$$(date +%s) \
	  && ELAPSED=$$((END - START)) \
	  && echo "PASS: $$cluster ($${ELAPSED}s)" \
	  && echo "PASS $$cluster $${ELAPSED}s" >> $(RESULTS_DIR)/no-caapf-results.txt \
	  && PASS=$$((PASS+1)) \
	  || (echo "FAIL: $$cluster" \
	      && echo "FAIL $$cluster" >> $(RESULTS_DIR)/no-caapf-results.txt \
	      && FAIL=$$((FAIL+1))); \
	done; \
	echo ""; \
	echo "=== without-CAAPF results: PASS=$$PASS FAIL=$$FAIL ==="; \
	[ "$$FAIL" -eq 0 ]

.PHONY: test-all
test-all: test-all-caapf test-all-no-caapf report  ## Run full matrix (both variants) and print report

# ── Phase 6: report ───────────────────────────────────────────────────────────

.PHONY: report
report:  ## Print combined pass/fail and timing report
	@echo ""
	@echo "╔══════════════════════════════════════════════════════╗"
	@echo "║           E2E Test Report                            ║"
	@echo "╚══════════════════════════════════════════════════════╝"
	@echo ""
	@echo "--- with-CAAPF ---"
	@cat $(RESULTS_DIR)/caapf-results.txt 2>/dev/null || echo "  (no results yet)"
	@echo ""
	@echo "--- without-CAAPF ---"
	@cat $(RESULTS_DIR)/no-caapf-results.txt 2>/dev/null || echo "  (no results yet)"
	@echo ""

# ── Cleanup ───────────────────────────────────────────────────────────────────

.PHONY: clean-caapf-clusters
clean-caapf-clusters:  ## Delete all with-CAAPF workload clusters
	$(call log_step,deleting with-CAAPF clusters)
	@for cluster in $(CAAPF_CLUSTERS); do \
	  $(KUBECTL) delete cluster/$$cluster -n $(NAMESPACE) --ignore-not-found=true; \
	done
	@for cluster in $(CAAPF_CLUSTERS); do \
	  $(KUBECTL) wait cluster/$$cluster -n $(NAMESPACE) \
	    --for=delete --timeout=$(CLUSTER_WAIT_TIMEOUT) 2>/dev/null \
	    && echo "  $$cluster: deleted" || echo "  $$cluster: already gone"; \
	done

.PHONY: clean-no-caapf-clusters
clean-no-caapf-clusters:  ## Delete all without-CAAPF workload clusters
	$(call log_step,deleting without-CAAPF clusters)
	@for cluster in $(NO_CAAPF_CLUSTERS); do \
	  $(KUBECTL) delete cluster/$$cluster -n $(NAMESPACE) --ignore-not-found=true; \
	done
	@for cluster in $(NO_CAAPF_CLUSTERS); do \
	  $(KUBECTL) wait cluster/$$cluster -n $(NAMESPACE) \
	    --for=delete --timeout=$(CLUSTER_WAIT_TIMEOUT) 2>/dev/null \
	    && echo "  $$cluster: deleted" || echo "  $$cluster: already gone"; \
	done

.PHONY: clean-addons
clean-addons:  ## Remove addon resources (HelmChartProxies, CRS, ConfigMaps)
	$(call log_step,removing addon resources)
	@$(KUBECTL) delete -f with-caapf/addons/ --ignore-not-found=true
	@$(KUBECTL) delete -f without-caapf/addons/ --ignore-not-found=true

.PHONY: clean-clusterclasses
clean-clusterclasses:  ## Remove all ClusterClasses (run after clusters are deleted)
	$(call log_step,removing ClusterClasses)
	@$(KUBECTL) delete -f clusterclasses/with-caapf/ --ignore-not-found=true
	@$(KUBECTL) delete -f clusterclasses/without-caapf/ --ignore-not-found=true

.PHONY: clean-all
clean-all: clean-caapf-clusters clean-no-caapf-clusters clean-addons clean-clusterclasses  ## Full cleanup: clusters, addons, ClusterClasses
	@rm -f /tmp/*-kubeconfig
	@echo "  cleanup complete"

# ── Debugging helpers ─────────────────────────────────────────────────────────

.PHONY: status
status:  ## Show cluster and addon status on the management cluster
	@echo "=== Clusters ==="
	@$(KUBECTL) get clusters -n $(NAMESPACE) -o wide 2>/dev/null || echo "  none"
	@echo ""
	@echo "=== HelmChartProxies ==="
	@$(KUBECTL) get helmchartproxies -n $(NAMESPACE) 2>/dev/null || echo "  none"
	@echo ""
	@echo "=== ClusterResourceSets ==="
	@$(KUBECTL) get clusterresourcesets -n $(NAMESPACE) 2>/dev/null || echo "  none"
	@echo ""
	@echo "=== ClusterResourceSetBindings ==="
	@$(KUBECTL) get clusterresourcesetbindings -n $(NAMESPACE) 2>/dev/null || echo "  none"

.PHONY: describe-cluster
describe-cluster:  ## Describe a specific cluster (usage: make describe-cluster CLUSTER=tiny-cluster-1)
	@$(KUBECTL) describe cluster/$(CLUSTER) -n $(NAMESPACE)
	@$(KUBECTL) describe rke2controlplane -n $(NAMESPACE) \
	  -l cluster.x-k8s.io/cluster-name=$(CLUSTER) 2>/dev/null || true
	@$(KUBECTL) describe machinedeployment -n $(NAMESPACE) \
	  -l cluster.x-k8s.io/cluster-name=$(CLUSTER) 2>/dev/null || true
