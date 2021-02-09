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

decho "install docker..."
apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
apt-key fingerprint 0EBFCD88
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu lsb_release -cs)"
apt-get update
apt-get install docker-ce docker-ce-cli containerd.io
docker run hello-world
