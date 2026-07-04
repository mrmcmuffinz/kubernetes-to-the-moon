#!/usr/bin/env sh

. ~/env

wget -q --show-progress --https-only --timestamping \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kubelet"

chmod +x kubelet
sudo cp kubelet /usr/local/bin/

sudo mkdir -p /var/lib/kubelet/ /var/lib/kubernetes/
sudo cp ~/auth/${vmname}-key.pem ~/auth/${vmname}.pem /var/lib/kubelet/
sudo cp ~/auth/${vmname}.kubeconfig /var/lib/kubelet/kubeconfig
sudo cp ~/auth/ca.pem /var/lib/kubernetes/

cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.96.0.10"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${vmname}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${vmname}-key.pem"
containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"
cgroupDriver: "systemd"
EOF

cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kubelet
sudo systemctl start kubelet

systemctl status kubelet
