# Kubernetes dev env
KUBE_VERSION ?= 1.28
KIND_CONFIG ?= kind-$(KUBE_VERSION).yaml

# Tools
KUSTOMIZE ?= $(LOCALBIN)/kustomize
KUSTOMIZE_VERSION ?= v5.0.3

# Go vars
GOOS ?= linux
ARCH ?= $(shell go env GOARCH)
LDFLAGS ?= -s -w

LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

.PHONY: kustomize
kustomize: ## Download kustomize locally if necessary.
	$(call go-get-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v5,$(KUSTOMIZE_VERSION))

# go-get-tool will 'go get' any package $2 and install it to $1.
define go-get-tool
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp ;\
echo "Downloading $(2)" ;\
go get -d $(2)@$(3) ;\
GOBIN=$(LOCALBIN) go install $(2) ;\
rm -rf $$TMP_DIR ;\
}
endef


.PHONY: start-clusters
start-clusters:
	./hack/start-clusters.sh

.PHONY: clusteradm
clusteradm:
	curl -L https://raw.githubusercontent.com/open-cluster-management-io/clusteradm/main/install.sh | bash

addon: bin/addon

bin/addon:
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(ARCH) go build -o bin/addon -ldflags "${LDFLAGS}" cmd/main.go


# Image URL to use all building/pushing image targets;
EXAMPLE_IMAGE ?= addon-examples
IMAGE_REGISTRY ?= quay.io/open-cluster-management
IMAGE_TAG ?= latest
export EXAMPLE_IMAGE_NAME ?= $(IMAGE_REGISTRY)/$(EXAMPLE_IMAGE):$(IMAGE_TAG)

.PHONY: deploy
deploy: kustomize
	kubectx kind-hub
	cd deploy && $(KUSTOMIZE) edit set image quay.io/open-cluster-management/addon-examples=$(EXAMPLE_IMAGE_NAME)
	$(KUSTOMIZE) build deploy | kubectl apply -f - --context=kind-hub

.PHONY: undeploy
undeploy: kustomize
	cd deploy && $(KUSTOMIZE) build deploy | kubectl delete -f - --context=kind-hub

.PHONY: enable-addon
enable-addon:
	clusteradm addon enable --names busybox-addon --namespace open-cluster-management-agent-addon --clusters cluster1

.PHONY: disable-addon
disable-addon:
	clusteradm addon disable --names busybox-addon --all-clusters true

.PHONY: all
all: start-clusters deploy enable-addon