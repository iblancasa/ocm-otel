#!/bin/bash

cd $(dirname ${BASH_SOURCE})

set -e

hub=${CLUSTER1:-hub}
c1=${CLUSTER1:-cluster1}

hubctx="kind-${hub}"
c1ctx="kind-${c1}"

kind create cluster --name "${hub}" --config hub.yaml
kind create cluster --name "${c1}"  --config cluster1.yaml

clusteradm init --wait --context ${hubctx}
joincmd=$(clusteradm get token --context ${hubctx} | grep clusteradm)

$(echo ${joincmd} --force-internal-endpoint-lookup --wait --context ${c1ctx} | sed "s/<cluster_name>/$c1/g")

clusteradm accept --context ${hubctx} --clusters ${c1} --wait

kubectl get managedclusters --all-namespaces --context ${hubctx}

kubectl create -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.0.1/deploy/static/provider/kind/deploy.yaml --context kind-hub
kubectl wait --for=condition=available deployment ingress-nginx-controller -n ingress-nginx --timeout=5m --context kind-hub
