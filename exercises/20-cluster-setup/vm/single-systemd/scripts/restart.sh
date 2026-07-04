#!/usr/bin/env sh

systemctl restart etcd.service
systemctl restart kube-apiserver.service
systemctl restart kube-controller-manager.service
systemctl restart kube-scheduler.service
systemctl restart containerd.service
systemctl restart kubelet.service
systemctl restart kube-proxy.service
