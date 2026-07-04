#!/usr/bin/env sh

. ~/env

cni_plugins_archive=cni-plugins-linux-${arch}-v${cni_plugins_version}.tgz

wget -q --show-progress --https-only --timestamping \
  "https://github.com/containernetworking/plugins/releases/download/v${cni_plugins_version}/${cni_plugins_archive}"

sudo mkdir -p /opt/cni/bin
sudo tar -xvf ${cni_plugins_archive} -C /opt/cni/bin/

sudo mkdir -p /etc/cni/net.d

cat <<EOF | sudo tee /etc/cni/net.d/10-bridge.conf
{
    "cniVersion": "${cni_spec_version}",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${pod_cidr}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF

cat <<EOF | sudo tee /etc/cni/net.d/99-loopback.conf
{
    "cniVersion": "${cni_spec_version}",
    "name": "lo",
    "type": "loopback"
}
EOF
