#!/usr/bin/env sh

. ./env

etcd_archive=etcd-v${etcd_version}-linux-${arch}.tar.gz
wget -q --show-progress --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/v${etcd_version}/${etcd_archive}"
tar -xvf ${etcd_archive}
sudo cp etcd-v${etcd_version}-linux-${arch}/etcd* /usr/local/bin/

sudo mkdir -p /etc/etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd/
sudo cp ~/auth/ca.pem ~/auth/kubernetes-key.pem ~/auth/kubernetes.pem /etc/etcd/

cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/etcd-io/etcd

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name ${vmname} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://127.0.0.1:2380 \\
  --listen-peer-urls https://127.0.0.1:2380 \\
  --listen-client-urls https://${vmaddr}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://127.0.0.1:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster ${vmname}=https://127.0.0.1:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd
sudo systemctl status etcd.service
