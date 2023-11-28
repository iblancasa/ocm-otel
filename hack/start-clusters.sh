#!/bin/bash

cd $(dirname ${BASH_SOURCE})

set -ex

hub=${CLUSTER1:-hub}
c1=${CLUSTER1:-cluster1}

hubctx="kind-${hub}"
c1ctx="kind-${c1}"

kind create cluster --name "${hub}"
kind create cluster --name "${c1}"

clusteradm init --wait --context ${hubctx}
joincmd=$(clusteradm get token --context ${hubctx} | grep clusteradm)

$(echo ${joincmd} --force-internal-endpoint-lookup --wait --context ${c1ctx} | sed "s/<cluster_name>/$c1/g")

clusteradm accept --context ${hubctx} --clusters ${c1} --wait

kubectl get managedclusters --all-namespaces --context ${hubctx}
