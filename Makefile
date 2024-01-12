# Kubernetes dev env
KUBE_VERSION ?= 1.28
KIND_CONFIG ?= kind-$(KUBE_VERSION).yaml

OTEL_OPERATOR_VERSION ?= 0.89.0
CERTMANAGER_VERSION ?= 1.13.2

# Tools
KUSTOMIZE ?= $(LOCALBIN)/kustomize
KUSTOMIZE_VERSION ?= v5.0.3

# Go vars
GOOS ?= linux
ARCH ?= $(shell go env GOARCH)
LDFLAGS ?= -s -w

# Image URL to use all building/pushing image targets;
IMG_NAME ?= otel-addon
IMAGE_REGISTRY ?= ttl.sh
IMAGE_TAG ?= latest
IMG ?= $(IMAGE_REGISTRY)/$(IMG_NAME):$(IMAGE_TAG)

LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

GOLANGCI_LINT ?= $(LOCALBIN)/golangci-lint
GOLANGCI_LINT_VERSION ?= v1.54.0

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

.PHONY: clusteradm
clusteradm:
	curl -L https://raw.githubusercontent.com/open-cluster-management-io/clusteradm/main/install.sh | bash

.PHONY: fmt
fmt:
	go fmt ./...

golangci-lint:
	$(call go-get-tool,$(GOLANGCI_LINT),github.com/golangci/golangci-lint/cmd/golangci-lint,$(GOLANGCI_LINT_VERSION))

.PHONY: lint
lint: golangci-lint
	cd cmd && $(GOLANGCI_LINT) run

addon: bin/addon

bin/addon:
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(ARCH) go build -o bin/addon_${ARCH} -ldflags "${LDFLAGS}" ./cmd/main.go


.PHONY: container
container: GOOS = linux
container: addon
	docker buildx build -t ${IMG} . --platform  $(ARCH) --push

.PHONY: deploy
deploy: kustomize
	cd deploy && $(KUSTOMIZE) edit set image quay.io/open-cluster-management/addon-examples=$(IMG)
	$(KUSTOMIZE) build deploy | kubectl apply -f -

.PHONY: undeploy
undeploy: kustomize
	$(KUSTOMIZE) build deploy | kubectl delete -f - --ignore-not-found=true

.PHONY: enable-addon
enable-addon:
	clusteradm addon enable --names otel-addon --namespace open-cluster-management-agent-addon --cluster cluster1

.PHONY: disable-addon
disable-addon:
	clusteradm addon disable --names otel-addon --cluster cluster1

.PHONY: install-addon
install-addon: container deploy enable-addon

.PHONY: deploy-otel-operator-hub
deploy-otel-operator-hub:
	kubectl apply -f ./cmd/manifests/operator-namespace.yaml
	kubectl apply -f ./cmd/manifests/operator-group.yaml
	kubectl apply -f ./cmd/manifests/operator-subscription.yaml
	go run ./hack/check-operator-ready.go

.PHONY: demo
demo: deploy-otel-operator-hub certs install-addon
	kubectl create -f ./demo/otel.yaml

.PHONY: certs
certs:
	kubectl create namespace observability
	kubectl apply -f ./demo/certs/cert-manager-ss-issuer.yaml
	sleep 5
	kubectl apply -f ./demo/certs/cert-manager-ca-cert.yaml
	sleep 5
	kubectl apply -f ./demo/certs/cert-manager-ca-issuer.yaml
	sleep 5
	kubectl apply -f ./demo/certs/test-server-cert.yaml



.PHONY: all
all: install-addon demo

