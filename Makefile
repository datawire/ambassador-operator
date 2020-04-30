# kernel-style V=1 build verbosity
ifeq ("$(origin V)", "command line")
  BUILD_VERBOSE = $(V)
endif

ifeq ($(BUILD_VERBOSE),1)
  Q =
else
  Q = @
endif

EXE                  = build/ambassador-operator

DEV_KUBECONFIG       = $$HOME/.kube/config

AMB_OPER_REPO        = github.com/datawire/ambassador-operator
AMB_OPER_MAIN_PKG    = $(AMB_OPER_REPO)/cmd/manager

GIT_VERSION          = $(shell git describe --dirty --tags --always)
GIT_COMMIT           = $(shell git rev-parse HEAD)

AMB_OPER_BASE_IMAGE ?= ambassador-operator
AMB_OPER_TAG        ?= dev
ifeq ($(AMB_OPER_TAG),)
override AMB_OPER_TAG = $(GIT_VERSION)
endif

AMB_OPER_IMAGE      ?= $(AMB_OPER_BASE_IMAGE):$(AMB_OPER_TAG)
AMB_OPER_ARCHES     :="amd64"

AMB_OPER_PKGS        = $(shell go list ./...)
AMB_OPER_SRCS        = $(shell find . -name '*.go')
AMB_OPER_SHS         = $(shell find . -name '*.sh')

# manifests that must be loaded (order matters)
AMB_NS               = "ambassador"
AMB_NS_MANIF         = deploy/namespace.yaml

AMB_DEPLOY_MANIF     = deploy/service_account.yaml \
                       deploy/role.yaml \
                       deploy/role_binding.yaml \
                       deploy/operator.yaml

AMB_OPER_MANIF       = $(AMB_NS_MANIF) \
                       $(AMB_DEPLOY_MANIF)

AMB_COVERAGE_FILE   := coverage.txt

# directory where release artifacts go
ARTIFACTS_DIR       ?= build/artifacts
HELM_DIR            ?= deploy/helm/ambassador-operator

# the release manifests
ARTIFACT_CRDS_MANIF  = $(ARTIFACTS_DIR)/ambassador-operator-crds.yaml
ARTIFACT_OPER_MANIF  = $(ARTIFACTS_DIR)/ambassador-operator.yaml

# helm manifests
HELM_CRDS_MANIF      = $(HELM_DIR)/templates/ambassador-operator-crds.yaml
HELM_OPER_MANIF      = $(HELM_DIR)/templates/ambassador-operator.yaml

IMAGE_EXTRA_FILE         ?=
IMAGE_EXTRA_FILE_CONTENT ?=

REL_REGISTRY        ?= quay.io/datawire
REL_AMB_OPER_IMAGE   = $(REL_REGISTRY)/$(AMB_OPER_IMAGE)

# directory for docs
DOCS_API_DIR         := docs/api

# the Cart values.yaml
AMB_OPER_CHART_VALS  := deploy/helm/ambassador-operator/values.yaml

# Go flags
GO_FLAGS             =

CLUSTER_PROVIDER    ?= k3d
export CLUSTER_PROVIDER

CLUSTER_PROVIDERS   ?= $(shell realpath ./ci/cluster-providers)
export CLUSTER_PROVIDERS

# the repo used for generating the API docs
GEN_CRD_API_REPO =  github.com/inercia/gen-crd-api-reference-docs

export CGO_ENABLED:=0
export GO111MODULE:=on
export GO15VENDOREXPERIMENT:=1

.DEFAULT_GOAL:=help

##############################
# Help                       #
##############################

.PHONY: help
help: ## Show this help screen
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Available targets are:'
	@echo ''
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##############################
# Development                #
##############################

##@ Development

.PHONY: all install

all: format build test ## Test and Build the Ambassador Operator

# Code management.
.PHONY: format tidy clean cli-doc lint build

build: $(EXE) ## Build the Ambassador Operator executable

format: ## Format the Go source code
	$(Q)go fmt $(AMB_OPER_PKGS)

format-sh:  ## Format the Shell source code
	$(Q)command -v shfmt >/dev/null && shfmt -w $(AMB_OPER_SHS)

tidy: ## Update dependencies
	$(Q)go mod tidy -v

clean: ## Clean up the build artifacts
	$(Q)rm -rf $(EXE) \
		build/_output $(ARTIFACTS_DIR) \
		$(ARTIFACT_CRDS_MANIF) $(ARTIFACT_OPER_MANIF)
	$(Q)docker rmi $(AMB_OPER_IMAGE) >/dev/null 2>&1 || /bin/true
	$(Q)docker rmi $(REL_AMB_OPER_IMAGE) >/dev/null 2>&1 || /bin/true

lint-dev:  ## Run golangci-lint with all checks enabled (development purpose only)
	./hack/tests/check-lint.sh dev

lint-fix: ## Run golangci-lint automatically fix (development purpose only)
	$(Q)./hack/tests/check-lint.sh fix

lint: ## Run golangci-lint with all checks enabled in the ci
	$(Q)./hack/tests/check-lint.sh ci


##############################
# Generate Artifacts         #
##############################
##@ Generate

$(ARTIFACTS_DIR):
	$(Q)rm -rf $(ARTIFACTS_DIR)
	$(Q)mkdir -p $(ARTIFACTS_DIR)

gen-k8s:  ## Generate k8s code from CRD definitions
	@echo ">>> Generating k8s sources..."
	@operator-sdk generate k8s

gen-crds:  ## Generate CRDs manifests from CRD definitions
	@echo ">>> Generating CRDs..."
	$(Q)operator-sdk generate crds
	@echo ">>> CRDs available at deploy/crds"

# needs `go get github.com/ahmetb/gen-crd-api-reference-docs`
gen-crds-docs: ## Generate the docs for the CRDs
	@echo ">>> Generating API docs..."
	$(Q)command -v gen-crd-api-reference-docs >/dev/null || { \
  		echo "FATAL: gen-crd-api-reference-docs not installed" ; \
  		echo "FATAL: just run 'go get $(GEN_CRD_API_REPO)'" ; \
  		exit 1 ; \
  	}
	$(Q)gen-crd-api-reference-docs \
            -template-dir "$(DOCS_API_DIR)/templates" \
            -config "$(DOCS_API_DIR)/templates/crds-gen-config.json" \
            -api-dir "$(AMB_OPER_REPO)/pkg/apis/getambassador/v2" \
            -out-file "$(DOCS_API_DIR)/index.md"
	@echo ">>> API docs available at $(DOCS_API_DIR)"

generate: gen-k8s gen-crds gen-crds-docs ## Run all generate targets
.PHONY: generate gen-k8s gen-crds

##############################
# Release                    #
##############################
##@ Release

# Build/install/release
.PHONY: release_builds release

release_builds := \
	build/ambassador-operator-$(GIT_VERSION)-x86_64-linux-gnu \
	build/ambassador-operator-$(GIT_VERSION)-x86_64-apple-darwin \
	build/ambassador-operator-$(GIT_VERSION)-ppc64le-linux-gnu

# collect all the final manifests that should be part of a release.
# can be invoked with a different registry in "REL_REGISTRY"
release-collect-manifests: $(ARTIFACTS_DIR) gen-crds
	@echo ">>> Preparing release manifests in $(ARTIFACTS_DIR)"
	$(Q)rm -f $(ARTIFACT_CRDS_MANIF) $(ARTIFACT_OPER_MANIF)
	$(Q)cat deploy/crds/*_crd.yaml > $(ARTIFACT_CRDS_MANIF)
	$(Q)cat $(AMB_OPER_MANIF) | sed -e "s|REPLACE_IMAGE|$(REL_AMB_OPER_IMAGE)|g" > $(ARTIFACT_OPER_MANIF)
	@echo -n ">>> Files generated: " && ls $(ARTIFACTS_DIR)

release-manifests-helm:
	@echo "Cleaning $(HELM_DIR)/templates/"
	$(Q)rm -rf $(HELM_DIR)/templates/*

	@echo ">>> Preparing release manifests in $(ARTIFACTS_DIR)"
	$(Q)cat deploy/crds/*_crd.yaml > $(HELM_CRDS_MANIF)
	$(Q)cat $(AMB_DEPLOY_MANIF) | sed -e "s|REPLACE_IMAGE|$(REL_AMB_OPER_IMAGE)|g" > $(HELM_OPER_MANIF)
	@echo -n ">>> Files generated: " && ls $(HELM_DIR)/templates/

release-manifests: release-collect-manifests

release: clean release-manifests $(release_builds) ## Release the Ambassador Operator

build/ambassador-operator-%-x86_64-linux-gnu: GOARGS = GOOS=linux GOARCH=amd64
build/ambassador-operator-%-x86_64-apple-darwin: GOARGS = GOOS=darwin GOARCH=amd64
build/ambassador-operator-%-ppc64le-linux-gnu: GOARGS = GOOS=linux GOARCH=ppc64le
build/ambassador-operator-%-linux-gnu: GOARGS = GOOS=linux

build/%: $(AMB_OPER_SRCS)
	@echo ">>> Building $@"
	$(Q)$(GOARGS) go build \
		-gcflags "all=-trimpath=${GOPATH}" \
		-asmflags "all=-trimpath=${GOPATH}" \
		-ldflags " \
			-X '${AMB_OPER_REPO}/version.GitVersion=${GIT_VERSION}' \
			-X '${AMB_OPER_REPO}/version.GitCommit=${GIT_COMMIT}' \
		" \
		$(GO_FLAGS) \
		-o $@ $(AMB_OPER_MAIN_PKG)

.PHONY: image image-build image-push

image: image-build image-push ## Build and push all images

image-build: $(EXE) ## Build images
	@echo ">>> Building image $(AMB_OPER_IMAGE)"
	$(Q)./hack/image/build-amb-oper-image.sh $(AMB_OPER_IMAGE)
	$(Q)if [ -n "$(IMAGE_EXTRA_FILE)" ] && [ -n "$(IMAGE_EXTRA_FILE_CONTENT)" ] ; then \
  		./hack/image/add-file-to-image.sh \
			--path "$(IMAGE_EXTRA_FILE)" --content "$(IMAGE_EXTRA_FILE_CONTENT)" --image $(AMB_OPER_IMAGE) --check ; \
		fi

image-push: image-build ## Push images to the registry
	$(Q)./hack/image/push-image-tags.sh $(AMB_OPER_IMAGE) $(REL_AMB_OPER_IMAGE)

chart-push: ## Push the Helm chart (will need some AWS env vars)
	@echo ">>> Preparing Helm chart values with image=$(REL_AMB_OPER_IMAGE)"
	$(Q)mv $(AMB_OPER_CHART_VALS) $(AMB_OPER_CHART_VALS).bak
	$(Q)cat $(AMB_OPER_CHART_VALS).bak | sed -e "s|ambassador-operator:dev|$(REL_AMB_OPER_IMAGE)|g" > $(AMB_OPER_CHART_VALS)
	@echo ">>> ... new values:"
	$(Q)cat $(AMB_OPER_CHART_VALS)
	@echo ""
	@echo ">>> ... we are ready to push the Helm chart."
	$(Q)bash ./ci/push_chart.sh
	$(Q)mv $(AMB_OPER_CHART_VALS).bak $(AMB_OPER_CHART_VALS)

##############################
# Tests                      #
##############################
##@ Tests

test: ## Run the Go tests
	@echo ">>> Running the Go tests..."
	$(Q)go test -coverprofile=$(AMB_COVERAGE_FILE) -covermode=atomic -v $(GO_FLAGS) $(AMB_OPER_PKGS)

$(AMB_COVERAGE_FILE): test

e2e: ## Run the e2e tests. options: VERBOSE=1, TEST=<some-test.sh>
	@echo ">>> Running e2e tests"
	$(Q)AMB_OPER_IMAGE=$(AMB_OPER_IMAGE) ./tests/e2e/runner.sh \
		--image-name=$(AMB_OPER_BASE_IMAGE) --image-tag=$(AMB_OPER_TAG) check $(TEST)

##############################
# Utils                      #
##############################
##@ Utils

.PHONY: create-namespace
create-namespace:
	@echo ">>> Creating namespace $(AMB_NS)"
	$(Q)kubectl create namespace $(AMB_NS) 2>/dev/null || /bin/true

load-crds: create-namespace release-collect-manifests  ## Load the CRDs in the current cluster
	@echo ">>> Loading CRDs"
	$(Q)[ -n $KUBECONFIG ] || echo "WARNING: no KUBECONFIG defined: using default kubeconfig"
	$(Q)kubectl apply -n $(AMB_NS) -f $(ARTIFACT_CRDS_MANIF)

load: create-namespace release-collect-manifests load-crds   ## Load the CRDs and manifests in the current cluster
	@echo ">>> Loading manifests (with REPLACE_IMAGE=$(AMB_OPER_IMAGE))"
	$(Q)[ -n $KUBECONFIG ] || echo "WARNING: no KUBECONFIG defined: using default kubeconfig"
	$(Q)kubectl apply -n $(AMB_NS) -f $(ARTIFACT_OPER_MANIF)

live: build load-crds ## Try to run the operator in the current cluster pointed by KUBECONFIG
	$(Q)[ -n $KUBECONFIG ] || echo "WARNING: no DEV_KUBECONFIG defined: using default $(DEV_KUBECONFIG)"
	@echo ">>> Starting operator with kubeconfig=$(DEV_KUBECONFIG)"
	$(Q)WATCH_NAMESPACE="default" OPERATOR_NAME="ambassador-operator" \
		$(EXE) --kubeconfig=$(DEV_KUBECONFIG) --zap-devel

##############################
# CI                         #
##############################

# NOTE: CI can only start jobs from this section

ci/lint: lint

ci/check-format-gen: format generate
	$(Q)./hack/tests/check-dirty.sh

ci/build: lint build image-build

ci/test: test

ci/e2e: e2e

ci/all: ci/lint ci/build ci/test ci/e2e

ci/release: release-collect-manifests gen-crds-docs

ci/publish-image: image-push

ci/publish-image-cloud: clean
	$(Q)[ -n "$(CLUSTER_REGISTRY)" ] || { echo "FATAL: no CLUSTER_REGISTRY defined" ; exit 1 ; }
	$(Q)[ -n "$(CLUSTER_PROVIDER)" ] || { echo "FATAL: no CLUSTER_PROVIDER defined" ; exit 1 ; }
	@echo ">>> Creating a registry in the cloud (with $(CLUSTER_REGISTRY))"
	$(Q)$(CLUSTER_PROVIDERS)/providers.sh create-registry && \
		eval `$(CLUSTER_PROVIDERS)/providers.sh get-env 2>/dev/null` && \
		REL_REGISTRY="$$DEV_REGISTRY" make ci/publish-image

ci/publish-image-cloud/azure:
	# for Azure, create an image with an extra Helm Values file.
	# This file will be loaded automatically by the operator and used for setting
	# some custom Helm variables like "deploymentTool"
	$(Q)[ "$(CLUSTER_PROVIDER)" = "azure" ] || { echo "FATAL: CLUSTER_PROVIDER is not azure" ; exit 1 ; }
	make ci/publish-image-cloud \
		IMAGE_EXTRA_FILE="/tmp/cloud-values.yaml" \
		IMAGE_EXTRA_FILE_CONTENT="deploymentTool: amb-oper-azure"

ci/publish-chart: chart-push

ci/publish-coverage: $(AMB_COVERAGE_FILE)
	$(Q)./ci/coverage.sh

ci/after-success: ci/publish-coverage

ci/cluster-setup:
	@echo ">>> Setting up cluster-provider CI"
	$(Q)$(CLUSTER_PROVIDERS)/providers.sh setup

ci/cluster-cleanup:
	@echo ">>> Cleaning up cluster-provider CI"
	$(Q)$(CLUSTER_PROVIDERS)/providers.sh cleanup

ci/setup:
	@echo ">>> Setting up CI"
	$(Q)./ci/setup.sh
	$(Q)./tests/e2e/runner.sh setup

ci/cleanup:
	@echo ">>> Cleaning up CI"
	$(Q)./tests/e2e/runner.sh cleanup
	$(Q)./ci/cleanup.sh

