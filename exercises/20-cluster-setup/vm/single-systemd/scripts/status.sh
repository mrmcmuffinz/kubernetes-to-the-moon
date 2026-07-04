#!/usr/bin/env sh

export PAGER=cat

systemctl status etcd.service
systemctl status kube-apiserver.service
systemctl status kube-controller-manager.service
systemctl status kube-scheduler.service
systemctl status containerd.service
systemctl status kubelet.service
systemctl status kube-proxy.service
