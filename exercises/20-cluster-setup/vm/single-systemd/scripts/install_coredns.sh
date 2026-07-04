#!/usr/bin/env sh

helm repo add coredns https://coredns.github.io/helm

echo "Helm install"
helm install -n kube-system coredns coredns/coredns \
  --set service.clusterIP=10.96.0.10 \
  --set replicaCount=1
