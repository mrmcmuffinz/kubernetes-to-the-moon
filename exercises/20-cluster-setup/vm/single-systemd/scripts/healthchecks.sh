#!/usr/bin/env sh
 
# kube-apiserver
curl -k https://127.0.0.1:6443/healthz
curl -k https://127.0.0.1:6443/readyz
curl -k https://127.0.0.1:6443/livez
 
# kube-controller-manager
curl -k https://127.0.0.1:10257/healthz
 
# kube-scheduler
curl -k https://127.0.0.1:10259/healthz
 
# kubelet
curl http://127.0.0.1:10248/healthz
 
# kube-proxy
curl http://127.0.0.1:10256/healthz
 
# etcd
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem

# containerd
sudo crictl info
sudo crictl ps

# node readiness
kubectl get nodes
kubectl describe node | grep -A 10 Conditions

# coredns
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system rollout status deployment/coredns
