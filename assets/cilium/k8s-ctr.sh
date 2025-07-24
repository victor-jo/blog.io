#!/usr/bin/env bash

echo ">>>> K8S Controlplane config Start <<<<"

echo "[TASK 1] Initial Kubernetes"
if [ -f /vagrant/kubeadm-init-config.yaml ]; then
  echo "Kubeadm init config file exists"
  kubeadm init --config=/vagrant/kubeadm-init-config.yaml >/dev/null 2>&1
else 
  kubeadm init --token 123456.1234567890123456 --token-ttl 0 --pod-network-cidr=10.244.0.0/16 --service-cidr=10.96.0.0/16 --apiserver-advertise-address=192.168.10.100 --cri-socket=unix:///run/containerd/containerd.sock >/dev/null 2>&1
fi

echo "[TASK 2] Setting kube config file"
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown $(id -u):$(id -g) /root/.kube/config


echo "[TASK 3] Source the completion"
echo 'source <(kubectl completion bash)' >> /etc/profile
echo 'source <(kubeadm completion bash)' >> /etc/profile


echo "[TASK 4] Alias kubectl to k"
echo 'alias k=kubectl' >> /etc/profile
echo 'alias kc=kubecolor' >> /etc/profile
echo 'complete -F __start_kubectl k' >> /etc/profile


echo "[TASK 5] Install Kubectx & Kubens"
git clone https://github.com/ahmetb/kubectx /opt/kubectx >/dev/null 2>&1
ln -s /opt/kubectx/kubens /usr/local/bin/kubens
ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx


echo "[TASK 6] Install Kubeps & Setting PS1"
git clone https://github.com/jonmosco/kube-ps1.git /root/kube-ps1 >/dev/null 2>&1
cat <<"EOT" >> /root/.bash_profile
source /root/kube-ps1/kube-ps1.sh
KUBE_PS1_SYMBOL_ENABLE=true
function get_cluster_short() {
  echo "$1" | cut -d . -f1
}
KUBE_PS1_CLUSTER_FUNCTION=get_cluster_short
KUBE_PS1_SUFFIX=') '
PS1='$(kube_ps1)'$PS1
EOT
kubectl config rename-context "kubernetes-admin@kubernetes" "HomeLab" >/dev/null 2>&1


echo "[TASK 7] Install k9s"
K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep "tag_name" | cut -d : -f 2 | tr -d \"\, | awk '{$1=$1};1')
wget https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_arm64.tar.gz >/dev/null 2>&1
tar -zxvf k9s_Linux_arm64.tar.gz >/dev/null 2>&1
mv k9s /usr/local/bin/k9s
rm k9s_Linux_arm64.tar.gz LICENSE README.md >/dev/null 2>&1

echo "[TASK 8] Add Hosts Entry for Worker Nodes"
echo "192.168.10.100 k8s-ctr" >> /etc/hosts
for (( i=1; i<=$1; i++ )); do echo "192.168.10.10$i k8s-w$i" >> /etc/hosts; done

echo "[TASK 9] Install stern"
STERN_VERSION=1.32.0
wget https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_arm64.tar.gz >/dev/null 2>&1
tar -zxvf stern_${STERN_VERSION}_linux_arm64.tar.gz >/dev/null 2>&1
mv stern /usr/local/bin/stern
rm stern_${STERN_VERSION}_linux_arm64.tar.gz

if [ -f /vagrant/k8s-cni.sh ]; then
  chmod +x /vagrant/k8s-cni.sh
  /vagrant/k8s-cni.sh $2
fi

echo ">>>> K8S Controlplane Config End <<<<"
