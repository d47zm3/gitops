#!/usr/bin/env bash

# shellcheck disable=SC1091
source /dev/stdin <<<"$( curl -sS https://raw.githubusercontent.com/d47zm3/bash-framework/master/bash.sh )"

# designed for Ubuntu 20.04 LTS, execute as root

hostname="basement"
network_interface="ens3"
ip_address="192.168.1.220"
gateway_address="192.168.1.216"
pod_network_cidr="172.16.0.0/12"

decho "starting ${hostname} setup..."

if [ "$EUID" -ne 0 ]
then
  decho "[error] run as root/sudo!"
  exit 1
fi

decho "network setup..."
rm -f /etc/netplan/*
sed -e "s/NETWORK_INTERFACE/${network_interface}/g" -e "s/IP_ADDRESS/${ip_address}/g" -e  "s/GATEWAY_ADDRESS/${gateway_address}/g" "./00-netplan.yaml" > /etc/netplan/00-netplan.yaml
netplan apply

decho "disable swap..."
swapoff /swap.img
sed -i -r 's/(.+ swap .+)/#\1/' /etc/fstab

decho "containerd setup..."
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Setup required sysctl params, these persist across reboots.
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Apply sysctl params without reboot
sysctl --system
apt-get update && apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key --keyring /etc/apt/trusted.gpg.d/docker.gpg add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

apt-get update && apt-get install -y containerd.io
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
systemctl restart containerd

decho "kubelet setup..."
apt-get update && apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF | tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl daemon-reload
systemctl restart kubelet

decho "kubeadm init..."
kubeadm init --pod-network-cidr="${pod_network_cidr}"
mkdir -p "$HOME/.kube"
cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
chown "$(id -u):$(id -g)" "$HOME/.kube/config"

decho "installing network overlay..."
kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml

wget https://docs.projectcalico.org/manifests/custom-resources.yaml
sed -i -e "s@cidr:.*@cidr: ${pod_network_cidr}@g"  custom-resources.yaml
kubectl apply -f custom-resources.yaml
rm -f custom-resources.yaml

decho "untaint master node..."
kubectl taint nodes --all node-role.kubernetes.io/master-
watch kubectl get pods -n calico-system
kubectl get nodes -o wide

decho "installation finished!"
