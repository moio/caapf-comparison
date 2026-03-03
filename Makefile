# E2E Test Suite — CAAPF vs Non-CAAPF Comparison
#
# Required environment variables (the build fails immediately if any is unset):
#   KUBECONFIG             — path to management cluster kubeconfig
#   AWS_ACCESS_KEY_ID      — AWS access key
#   AWS_SECRET_ACCESS_KEY  — AWS secret key
#   SSH_KEY_NAME           — AWS EC2 keypair name (e.g. moio)
#   VPC_ID                 — existing AWS VPC ID (e.g. vpc-0123456789abcdef0)
#   PRIVATE_SUBNET_ID      — existing private subnet ID with NAT configured (e.g. subnet-0abc…)
#   PUBLIC_SUBNET_ID       — existing public subnet ID for load balancers (e.g. subnet-0def…)
#
# Optional environment variables (overridable, concrete defaults shown below):
#   REGION  — AWS region            (default: us-east-1)
#   AMI_ID  — EC2 AMI for RKE2 nodes (default: ami-095197d9bbe1d2fb3, openSUSE Leap 16.0 us-east-1)
#
# Usage:
#   export KUBECONFIG=... AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... SSH_KEY_NAME=moio \
#          VPC_ID=vpc-0123456789abcdef0 PRIVATE_SUBNET_ID=subnet-0abc… PUBLIC_SUBNET_ID=subnet-0def…
#   make test-tiny-caapf
#   make clean-all

.DEFAULT_GOAL := help

# ── optional env vars with concrete defaults ───────────────────────────────────
REGION ?= us-east-1
AMI_ID ?= ami-095197d9bbe1d2fb3

SCRIPTS = test/scripts

# ── required env var guards (checked per-recipe, not globally) ─────────────────
# Targets that need these vars depend on _check-env (below).
# Targets like help and status work without any env vars.
.PHONY: _check-env
_check-env:
	@test -n "$(KUBECONFIG)" || { echo "error: KUBECONFIG is not set" >&2; exit 1; }
	@test -n "$(AWS_ACCESS_KEY_ID)" || { echo "error: AWS_ACCESS_KEY_ID is not set" >&2; exit 1; }
	@test -n "$(AWS_SECRET_ACCESS_KEY)" || { echo "error: AWS_SECRET_ACCESS_KEY is not set" >&2; exit 1; }
	@test -n "$(SSH_KEY_NAME)" || { echo "error: SSH_KEY_NAME is not set" >&2; exit 1; }
	@test -n "$(VPC_ID)" || { echo "error: VPC_ID is not set" >&2; exit 1; }
	@test -n "$(PRIVATE_SUBNET_ID)" || { echo "error: PRIVATE_SUBNET_ID is not set" >&2; exit 1; }
	@test -n "$(PUBLIC_SUBNET_ID)" || { echo "error: PUBLIC_SUBNET_ID is not set" >&2; exit 1; }

# ── targets ────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-30s %s\n", $$1, $$2}'

# ── prerequisites ──────────────────────────────────────────────────────────────

.PHONY: apply-prereqs
apply-prereqs: _check-env ## Validate cluster+creds, apply providers, create identity secret
	@$(SCRIPTS)/apply-prereqs.sh

# ── ClusterClasses ─────────────────────────────────────────────────────────────

.PHONY: apply-clusterclasses-caapf
apply-clusterclasses-caapf: _check-env ## Apply with-CAAPF ClusterClasses (all sizes)
	@$(SCRIPTS)/apply-clusterclasses.sh with-caapf

.PHONY: apply-clusterclasses-no-caapf
apply-clusterclasses-no-caapf: _check-env ## Apply without-CAAPF ClusterClasses (all sizes)
	@$(SCRIPTS)/apply-clusterclasses.sh without-caapf

# ── addons ─────────────────────────────────────────────────────────────────────

.PHONY: apply-addons-caapf
apply-addons-caapf: _check-env ## Apply CAAPF HelmOp addons
	@$(SCRIPTS)/apply-addons.sh with-caapf

.PHONY: apply-addons-no-caapf
apply-addons-no-caapf: _check-env ## Apply ConfigMap + ClusterResourceSet addons
	@$(SCRIPTS)/apply-addons.sh without-caapf

# ── single-cluster tests (with-CAAPF) ─────────────────────────────────────────

.PHONY: test-tiny-caapf
test-tiny-caapf: apply-prereqs apply-clusterclasses-caapf apply-addons-caapf ## Full test: tiny-cluster-1 with CAAPF
	@$(SCRIPTS)/apply-cluster.sh with-caapf tiny-cluster-1 $(SSH_KEY_NAME) $(REGION) $(AMI_ID) $(VPC_ID) $(PRIVATE_SUBNET_ID) $(PUBLIC_SUBNET_ID)
	@$(SCRIPTS)/verify-cluster.sh tiny-cluster-1

.PHONY: test-small-caapf
test-small-caapf: apply-prereqs apply-clusterclasses-caapf apply-addons-caapf ## Full test: small-cluster-1 with CAAPF
	@$(SCRIPTS)/apply-cluster.sh with-caapf small-cluster-1 $(SSH_KEY_NAME) $(REGION) $(AMI_ID) $(VPC_ID) $(PRIVATE_SUBNET_ID) $(PUBLIC_SUBNET_ID)
	@$(SCRIPTS)/verify-cluster.sh small-cluster-1

.PHONY: test-medium-caapf
test-medium-caapf: apply-prereqs apply-clusterclasses-caapf apply-addons-caapf ## Full test: medium-cluster-1 with CAAPF
	@$(SCRIPTS)/apply-cluster.sh with-caapf medium-cluster-1 $(SSH_KEY_NAME) $(REGION) $(AMI_ID) $(VPC_ID) $(PRIVATE_SUBNET_ID) $(PUBLIC_SUBNET_ID)
	@$(SCRIPTS)/verify-cluster.sh medium-cluster-1

# ── single-cluster tests (without-CAAPF) ──────────────────────────────────────

.PHONY: test-tiny-no-caapf
test-tiny-no-caapf: apply-prereqs apply-clusterclasses-no-caapf apply-addons-no-caapf ## Full test: tiny-cluster-1 without CAAPF
	@$(SCRIPTS)/apply-cluster.sh without-caapf tiny-cluster-1 $(SSH_KEY_NAME) $(REGION) $(AMI_ID) $(VPC_ID) $(PRIVATE_SUBNET_ID) $(PUBLIC_SUBNET_ID)
	@$(SCRIPTS)/verify-cluster.sh tiny-cluster-1

.PHONY: test-small-no-caapf
test-small-no-caapf: apply-prereqs apply-clusterclasses-no-caapf apply-addons-no-caapf ## Full test: small-cluster-1 without CAAPF
	@$(SCRIPTS)/apply-cluster.sh without-caapf small-cluster-1 $(SSH_KEY_NAME) $(REGION) $(AMI_ID) $(VPC_ID) $(PRIVATE_SUBNET_ID) $(PUBLIC_SUBNET_ID)
	@$(SCRIPTS)/verify-cluster.sh small-cluster-1

.PHONY: test-medium-no-caapf
test-medium-no-caapf: apply-prereqs apply-clusterclasses-no-caapf apply-addons-no-caapf ## Full test: medium-cluster-1 without CAAPF
	@$(SCRIPTS)/apply-cluster.sh without-caapf medium-cluster-1 $(SSH_KEY_NAME) $(REGION) $(AMI_ID) $(VPC_ID) $(PRIVATE_SUBNET_ID) $(PUBLIC_SUBNET_ID)
	@$(SCRIPTS)/verify-cluster.sh medium-cluster-1

# ── full matrix ────────────────────────────────────────────────────────────────

.PHONY: test-all
test-all: test-all-caapf test-all-no-caapf ## Run full matrix (both variants)

.PHONY: test-all-caapf
test-all-caapf: apply-prereqs apply-clusterclasses-caapf apply-addons-caapf ## Run all 6 with-CAAPF clusters
	@for cluster in tiny-cluster-1 tiny-cluster-2 small-cluster-1 small-cluster-2 medium-cluster-1 medium-cluster-2; do \
	  $(SCRIPTS)/apply-cluster.sh with-caapf $$cluster $(SSH_KEY_NAME) $(REGION) $(AMI_ID) $(VPC_ID) $(PRIVATE_SUBNET_ID) $(PUBLIC_SUBNET_ID) && \
	  $(SCRIPTS)/verify-cluster.sh $$cluster || exit 1; \
	done

.PHONY: test-all-no-caapf
test-all-no-caapf: apply-prereqs apply-clusterclasses-no-caapf apply-addons-no-caapf ## Run all 6 without-CAAPF clusters
	@for cluster in tiny-cluster-1 tiny-cluster-2 small-cluster-1 small-cluster-2 medium-cluster-1 medium-cluster-2; do \
	  $(SCRIPTS)/apply-cluster.sh without-caapf $$cluster $(SSH_KEY_NAME) $(REGION) $(AMI_ID) $(VPC_ID) $(PRIVATE_SUBNET_ID) $(PUBLIC_SUBNET_ID) && \
	  $(SCRIPTS)/verify-cluster.sh $$cluster || exit 1; \
	done

# ── cleanup ────────────────────────────────────────────────────────────────────

.PHONY: clean-caapf-clusters
clean-caapf-clusters: _check-env ## Delete all with-CAAPF workload clusters
	@$(SCRIPTS)/clean.sh clusters with-caapf

.PHONY: clean-no-caapf-clusters
clean-no-caapf-clusters: _check-env ## Delete all without-CAAPF workload clusters
	@$(SCRIPTS)/clean.sh clusters without-caapf

.PHONY: clean-addons
clean-addons: _check-env ## Remove addon resources (HelmOps, CRS, ConfigMaps)
	@$(SCRIPTS)/clean.sh addons

.PHONY: clean-clusterclasses
clean-clusterclasses: _check-env ## Remove all ClusterClasses
	@$(SCRIPTS)/clean.sh clusterclasses

.PHONY: clean-all
clean-all: _check-env ## Full cleanup: clusters, addons, ClusterClasses
	@$(SCRIPTS)/clean.sh all

# ── debugging ──────────────────────────────────────────────────────────────────

.PHONY: status
status: ## Show cluster and addon status on the management cluster
	@echo "=== Clusters ==="
	@kubectl get clusters -n default -o wide 2>/dev/null || echo "  none"
	@echo ""
	@echo "=== HelmOps ==="
	@kubectl get helmops -n default 2>/dev/null || echo "  none"
	@echo ""
	@echo "=== ClusterResourceSets ==="
	@kubectl get clusterresourcesets -n default 2>/dev/null || echo "  none"
