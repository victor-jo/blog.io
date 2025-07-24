#!/usr/bin/env bash

CILIUMV=$1

echo ">>>> CNI Install Start <<<<"

echo "[TASK 1] Install Cilium CLI"
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz >/dev/null 2>&1
tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin >/dev/null 2>&1
rm cilium-linux-${CLI_ARCH}.tar.gz >/dev/null 2>&1

echo "[TASK 2] Install Cilium"
helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1
helm repo update >/dev/null 2>&1
helm install cilium cilium/cilium --version $CILIUMV \
  --namespace kube-system \
  --set k8sServiceHost=192.168.10.100 \
  --set k8sServicePort=6443 \
  --set ipam.mode="cluster-pool" \
  --set ipam.operator.clusterPoolIPv4PodCIDRList={"172.20.0.0/16"} \
  --set ipv4NativeRoutingCIDR=172.20.0.0/16 \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true \
  --set endpointRoutes.enabled=true \
  --set kubeProxyReplacement=true \
  --set bpf.masquerade=true \
  --set installNoConntrackIptablesRules=true \
  --set endpointHealthChecking.enabled=false \
  --set healthChecking=false \
  --set hubble.enabled=false \
  --set operator.replicas=1 \
  --set debug.enabled=true \
  >/dev/null 2>&1

echo "[TASK 3] Install Cilium CNI Cheat Sheet"
echo '
cx() {
  export CILIUMPOD0=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-ctr -o jsonpath='{.items[0].metadata.name}')
  export CILIUMPOD1=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w1  -o jsonpath='{.items[0].metadata.name}')
  export CILIUMPOD2=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w2  -o jsonpath='{.items[0].metadata.name}')
}

alias c0="kubectl exec -it $CILIUMPOD0 -n kube-system -c cilium-agent -- cilium"
alias c1="kubectl exec -it $CILIUMPOD1 -n kube-system -c cilium-agent -- cilium"
alias c2="kubectl exec -it $CILIUMPOD2 -n kube-system -c cilium-agent -- cilium"
alias c0bpf="kubectl exec -it $CILIUMPOD0 -n kube-system -c cilium-agent -- bpftool"
alias c1bpf="kubectl exec -it $CILIUMPOD1 -n kube-system -c cilium-agent -- bpftool"
alias c2bpf="kubectl exec -it $CILIUMPOD2 -n kube-system -c cilium-agent -- bpftool"
' >> /etc/profile >/dev/null 2>&1

echo ">>>> CNI Install End <<<<"