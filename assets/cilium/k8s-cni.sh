#!/usr/bin/env bash

CILIUMV=$1

echo ">>>> CNI Install Start <<<<"

echo "[TASK 1] Install Cilium CLI"
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz >/dev/null 2>&1
tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz

echo "[TASK 2] Install Cilium"
cilium install \
  --version $CILIUMV \
  --dry-run-helm-values \
  --set operator.unmanagedPodWatcher.restart=true \
  --set cni.customConf=false \
  --set policyEnforcementMode=default \
  --set bpf.hostLegacyRouting=false \
  --set bpf.masquerade=true \
  --set ipv6.enabled=false \
  --set ipam.mode="cluster-pool" \
  --set ipam.operator.clusterPoolIPv4PodCIDRList={"10.245.0.0/16"} \
  --set ipv4NativeRoutingCIDR=10.245.0.0/16 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=192.168.10.100 \
  --set k8sServicePort=6443 \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true \
  --set healthChecking=false \
  --set endpointHealthChecking.enabled=false \
  --set installNoConntrackIptablesRules=true \
  --set hubble.enabled=false \
  --set operator.replicas=1 \
  --set debug.enabled=true
  > /vagrant/values-final.yaml

helm upgrade --install --namespace kube-system cilium cilium/cilium --values /vagrant/values-final.yaml

echo ">>>> CNI Install End <<<<"