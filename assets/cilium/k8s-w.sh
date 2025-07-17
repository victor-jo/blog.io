#!/usr/bin/env bash

echo ">>>> K8S Node config Start <<<<"

NODE_HOSTNAME=$(hostname)
NODE_IP=$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

echo "[TASK 1] K8S Controlplane Join" 
if [ -f /vagrant/kubeadm-join-config.yaml ]; then
  echo "Kubeadm join config file exists"

  sed -i "s/192.168.10.101/${NODE_IP}/g" /vagrant/kubeadm-join-config.yaml
  sed -i "s/k8s-w1/${NODE_HOSTNAME}/g" /vagrant/kubeadm-join-config.yaml

  kubeadm join --config=/vagrant/kubeadm-join-config.yaml >/dev/null 2>&1
else
  kubeadm join --token 123456.1234567890123456 --discovery-token-unsafe-skip-ca-verification 192.168.10.100:6443  >/dev/null 2>&1
fi

echo ">>>> K8S Node config End <<<<"
