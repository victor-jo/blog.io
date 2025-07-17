---
layout: post
title: "Cilium 이란 무엇인가? Cilium 과 Flannel 의 비교"
date: 2025-01-16 14:30:00 +0900
categories: cilium study
tags: [cilium, victor, chris, kubernetes, cni, docker, what, flannel, containerd, vagrant]
---


### 실습 환경설정 (macOS)
#### Brew 설치
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### VirtualBox 설치
```bash
brew install --cask virtualbox
```

#### Vagrant 설치
```bash
brew install --cask vagrant
```

#### 실습 구성 파일들 실행
```bash
mkdir cilium-study
cd cilium-study

curl -O https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/init_cfg.sh
curl -O https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/Vagrantfile 
curl -O https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/k8s-ctr.sh
curl -O https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/k8s-w.sh

vagrant up
```

#### 쿠버네티스 노드가 사용하는 이더넷 설정
쿠버네티스 노드들이 Vagrant 로 프로비저닝 되었기 때문에 기본값으로 노드들의 eth0 IP로 설정됩니다. <br/> 따라서, 사용할 이더넷 어댑터에 맞는 IP를 설정해 주어야 합니다.
```bash
# 노드들의 eth1 IP 확인
for i in ctr w1 w2 ; do 
  echo ">> node : k8s-$i <<"
  vagrant ssh k8s-$i -c 'ip -c -4 addr show dev eth1'
  echo
done

# SSH 접속
vagrant ssh k8s-ctr   # Control Plane 노드
vagrant ssh k8s-w1    # Worker 노드 1
vagrant ssh k8s-w2    # Worker 노드 2

# 각 노드에 접속해서 Kubelet 이 사용하는 Node IP 를 eth1 IP 로 설정
NODEIP=$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
sed -i "s/^\(KUBELET_KUBEADM_ARGS=\"\)/\1--node-ip=${NODEIP} /" /var/lib/kubelet/kubeadm-flags.env
systemctl daemon-reexec && systemctl restart kubelet

# eth1 IP 로 전체 설정 후 노드 Internal IP 확인
k get nodes -owide
```

![Kubernetes Node Information](/assets/cilium//images/k-get-nodes.png)

#### kubeadm init / join 과정에서 Config 하기
```bash

# 설정 파일들
curl -O https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/kubeadm-init-config.yaml
curl -O https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/kubeadm-join-config.yaml

# 기존 리소스 정리
vagrant destroy -f && rm -rf .vagrant/

# 리소스 정리 후 그대로 Run
vagrant up
```

### 🌐 Flannel CNI 소개 및 설치

#### Flannel CNI 아키텍처

![Flannel Architecture](/assets/cilium/images/kube-network-model-vxlan.png)

#### 설치 전 확인
```bash
# 클러스터 CIDR 확인
kubectl cluster-info dump | grep -m 2 -E "cluster-cidr|service-cluster-ip-range"

# CoreDNS 상태 확인 (Pending 상태가 '정상', CNI 설치 전이기 때문에)
kubectl get pod -n kube-system -l k8s-app=kube-dns -owide

# 네트워크 상태 확인
ip -c link
ip -c route

# 없는게 정상, 브릿지 구성 하나도 안되어져 있음
brctl show
tree /etc/cni/net.d/
```

#### Flannel CNI 설치
```bash
# Namespace 생성
kubectl create ns kube-flannel
kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged

# Helm 레포지토리 추가
helm repo add flannel https://flannel-io.github.io/flannel/
helm repo list
helm search repo flannel

# 설정 파일 생성
cat << EOF > flannel-values.yaml
podCidr: "10.244.0.0/16"

flannel:
  args:
  - "--ip-masq"
  - "--kube-subnet-mgr"
  - "--iface=eth1"  
EOF

# Helm 설치
helm install flannel --namespace kube-flannel flannel/flannel -f flannel-values.yaml
helm list -A

# 설치 확인
kc describe pod -n kube-flannel -l app=flannel
```

#### 설치 후 네트워크 확인
```bash
# CNI 바이너리 및 설정 확인
tree /opt/cni/bin/
tree /etc/cni/net.d/
cat /etc/cni/net.d/10-flannel.conflist | jq

# ConfigMap 확인
kc describe cm -n kube-flannel kube-flannel-cfg

# 라우팅 테이블 확인
ip -c route | grep 10.244.

# Worker 노드 상태 확인
for i in w1 w2 ; do 
  echo ">> node : k8s-$i <<"
  sshpass -p 'vagrant' ssh -o StrictHostKeyChecking=no vagrant@k8s-$i ip -c route
  echo
done

# CoreDNS Running 상태 확인
kubectl get pod -n kube-system -l k8s-app=kube-dns -owide
```

#### Flannel CNI 동작
Flannel CNI 는 각 노드에 고유한 네트워크 서브넷을 할당하고, 같은 노드 내의 파드간 통신은 `cni0` 브릿지를 통해 처리하고, <br/>
다른 노드에 있는 파드간 통신할 때는 `flannel.1` 터널을 통해 전달되는 것을 확인할 수 있습니다. <br/>
또한 CNI 가 설치되었기 때문에 CoreDNS 가 Running 상태로 활성화 됩니다.

### 📦 샘플 애플리케이션 배포 및 테스트

#### 애플리케이션 배포
```bash
# 웹 애플리케이션 배포
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webpod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webpod
  template:
    metadata:
      labels:
        app: webpod
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - webpod
            topologyKey: "kubernetes.io/hostname"
      containers:
      - name: webpod
        image: traefik/whoami
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: webpod
  labels:
    app: webpod
spec:
  selector:
    app: webpod
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
EOF

# 테스트용 curl 파드 배포
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: curl-pod
  labels:
    app: curl
spec:
  nodeName: k8s-ctr
  containers:
    - name: curl
      image: alpine/curl
      command: ["sleep", "36000"]
EOF
```

#### 배포 확인 및 통신 테스트
```bash
# 배포 상태 확인
k get all -l app=webpod

# 컨트롤 플레인에서 다른 노드의 파드에 접근
POD1IP=$(k get pods -l app=webpod -owide | awk 'NR==2 {print $6}')
kubectl exec -it curl-pod -- curl $POD1IP

# 서비스 IP 확인 및 통신, DNS 질의 확인
k get svc -l app=webpod
kubectl exec -it curl-pod -- nslookup webpod
kubectl exec -it curl-pod -- curl webpod
```

#### iptables 규칙 확인
```bash
# 서비스 IP 확인 및 iptables 규칙 분석
SVCIP=$(kubectl get svc webpod -o jsonpath="{.spec.clusterIP}")
iptables -t nat -S | grep $SVCIP

# Worker 노드의 iptables 규칙 확인
for i in w1 w2 ; do 
  echo ">> node : k8s-$i <<"
  sshpass -p 'vagrant' ssh -o StrictHostKeyChecking=no vagrant@k8s-$i sudo iptables -t nat -S | grep $SVCIP
  echo
done

# -A KUBE-SERVICES -d 10.96.46.189/32 -p tcp -m comment --comment "default/webpod cluster IP" -m tcp --dport 80 -j KUBE-SVC-CNZCPOCNCNOROALA
# -A KUBE-SVC-CNZCPOCNCNOROALA ! -s 10.244.0.0/16 -d 10.96.46.189/32 -p tcp -m comment --comment "default/webpod cluster IP" -m tcp --dport 80 -j KUBE-MARK-MASQ

# 규칙대로 조회해보면 결국 50% 확률로 각 Pod IP 를 가리키는 것을 볼 수 있다.
iptables -t nat -S | grep KUBE-SVC-CNZCPOCNCNOROALA

# -A KUBE-SVC-CNZCPOCNCNOROALA -m comment --comment "default/webpod -> 10.244.1.2:80" -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-PQBQBGZJJ5FKN3TB
# -A KUBE-SVC-CNZCPOCNCNOROALA -m comment --comment "default/webpod -> 10.244.2.2:80" -j KUBE-SEP-WEW7NHLZ4Y5A5ZKF
```

#### 🚨 대규모 환경에서 iptables의 한계

서비스가 증가할수록 iptables 규칙이 기하급수적으로 증가하여 성능 문제가 발생합니다.

### Cilium CNI 소개 및 설치

#### Cilium CNI 아키텍처

![Cilium Architecture](/assets/cilium/images/ebpf_hostrouting.png)

#### 🛠️ Flannel CNI -> Cilium CNI 최소 중단 마이그레이션

```bash
# Pod CIDR 확인
kubectl cluster-info dump | grep -m 1 cluster-cidr
```

지정된 CIDR 외에 추가로 선정할 Pod CIDR 설정 (예: `10.245.0.0/16`)

```bash
# Cilium CLI 설치
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz >/dev/null 2>&1
tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz

# Helm 추가
helm repo add cilium https://helm.cilium.io/
helm repo update

# Values 파일 추가
cat > cilium-values.yaml <<EOF
operator:
  unmanagedPodWatcher:
    restart: false # Migration: Don't restart unmigrated pods
routingMode: tunnel # Migration: Optional: default is tunneling, configure as needed
tunnelProtocol: vxlan # Migration: Optional: default is VXLAN, configure as needed
tunnelPort: 8473 # Migration: Optional, change only if both networks use the same port by default
cni:
  customConf: true # Migration: Don't install a CNI configuration file
  uninstall: false # Migration: Don't remove CNI configuration on shutdown
ipam:
  mode: "cluster-pool"
  operator:
    clusterPoolIPv4PodCIDRList: ["10.245.0.0/16"] # Migration: Ensure this is distinct and unused
policyEnforcementMode: "never" # Migration: Disable policy enforcement
bpf:
  hostLegacyRouting: true # Migration: Allow for routing between Cilium and the existing overlay
EOF
cilium install --version 1.17.6 --values cilium-values.yaml --dry-run-helm-values > values-initial.yaml

# Cilium 설치
helm install cilium cilium/cilium --version 1.17.6 \
  --namespace kube-system \
  --values values-initial.yaml
```

#### Cilium 상태 확인
```bash
# Cilium Pod 상태 확인
kubectl -n kube-system get pods -l k8s-app=cilium

# Cilium CNI 상태 확인
kubectl -n kube-system exec -it $(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}') -- cilium status
```

#### Cilium CNI 인수 설정
```bash
# Cilium CNI 인수 설정
cat <<EOF | kubectl apply --server-side -f -
apiVersion: cilium.io/v2
kind: CiliumNodeConfig
metadata:
  namespace: kube-system
  name: cilium-default
spec:
  nodeSelector:
    matchLabels:
      io.cilium.migration/cilium-default: "true"
  defaults:
    write-cni-conf-when-ready: /host/etc/cni/net.d/05-cilium.conflist
    custom-cni-conf: "false"
    cni-chaining-mode: "none"
    cni-exclusive: "true"
EOF
```

#### 노드별 순차 마이그레이션

각 노드에 대하여 순차적으로 다음 작업 수행:

#### 노드 준비
```bash
# 노드 이름 설정
NODE_NAME="k8s-ctr"  # 실제 노드 이름으로 변경 (컨트롤 플레인부터 수행하는 것은 권장하지 않습니다.)

# 노드 cordon (새 Pod 스케줄링 방지)
kubectl cordon $NODE_NAME

# 노드 drain (기존 Pod 이동)
kubectl drain $NODE_NAME --ignore-daemonsets --delete-emptydir-data
```

#### 노드 라벨링 및 Cilium 재시작
```bash
# Cilium 마이그레이션 라벨 추가
kubectl label node $NODE_NAME --overwrite "io.cilium.migration/cilium-default=true"

# Cilium 재시작
kubectl -n kube-system delete pod --field-selector spec.nodeName=$NODE_NAME -l k8s-app=cilium
kubectl -n kube-system rollout status ds/cilium -w
```

#### 노드 재부팅
```bash
# 해당 노드의 내부에서
sudo reboot
```

#### 노드 검증
```bash
# 노드의 Pod 가 Cilium CIDR 에 있고, API Server 와의 연결이 가능한지 검증
kubectl get -o wide node $NODE_NAME
kubectl -n kube-system run --attach --rm --restart=Never verify-network \
  --overrides='{"spec": {"nodeName": "'$NODE_NAME'", "tolerations": [{"operator": "Exists"}]}}' \
  --image ghcr.io/nicolaka/netshoot:v0.8 -- /bin/bash -c 'ip -br addr && curl -s -k https://$KUBERNETES_SERVICE_HOST/healthz && echo'

# NAME     STATUS                     ROLES    AGE   VERSION   INTERNAL-IP      EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION     CONTAINER-RUNTIME
# k8s-w1   Ready,SchedulingDisabled   <none>   11m   v1.33.2   192.168.10.101   <none>        Ubuntu 24.04.2 LTS   6.8.0-53-generic   containerd://1.7.27
# lo               UNKNOWN        127.0.0.1/8 ::1/128 
# eth0@if11        UP             10.245.0.179/32 fe80::ec5c:58ff:fe7e:9837/64 
# ok
# pod "verify-network" deleted

# 노드가 Ready 상태인지 확인
kubectl get node $NODE_NAME

# 노드 Pod 스케쥴링 비활성화 해제
kubectl uncordon $NODE_NAME

# Cilium CNI 상태 확인
kubectl -n kube-system exec -it $(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}') -- cilium status
```

#### 전체 노드 순회 후
```bash
# 전체 Pod 들의 IP 분배가 Cilium 의 CIDR 로 이루어졌는지 확인
k get pods -A -owide

# 초기 마이그레이션 설정 값 외 다른 부분들 수정
cilium install \
  --version 1.17.6 \
  --values values-initial.yaml \
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
  > values-final.yaml

# kube-proxy 제거
kubectl -n kube-system delete ds kube-proxy
kubectl -n kube-system delete cm kube-proxy

# Helm Upgrade
helm upgrade --namespace kube-system cilium cilium/cilium --values values-final.yaml
kubectl -n kube-system rollout restart daemonset cilium

# Cilium CNI 상태 확인
cilium status --wait

# CNI 인수 설정 해제
kubectl delete -n kube-system ciliumnodeconfig cilium-default

```

#### 이전 CNI Flannel 삭제
```bash
# Helm 제거
helm uninstall -n kube-flannel flannel
kubectl delete ns kube-flannel

# vnic 제거
ip link del flannel.1
ip link del cni0
for i in w1 w2 ; do echo ">> node : k8s-$i <<"; sshpass -p 'vagrant' ssh -o StrictHostKeyChecking=no vagrant@k8s-$i sudo ip link del flannel.1 ; echo; done
for i in w1 w2 ; do echo ">> node : k8s-$i <<"; sshpass -p 'vagrant' ssh -o StrictHostKeyChecking=no vagrant@k8s-$i sudo ip link del cni0 ; echo; done

# IP Table 초기화
iptables-save | grep -v KUBE | grep -v FLANNEL | iptables-restore
iptables-save

sshpass -p 'vagrant' ssh vagrant@k8s-w1 "sudo iptables-save | grep -v KUBE | grep -v FLANNEL | sudo iptables-restore"
sshpass -p 'vagrant' ssh vagrant@k8s-w1 sudo iptables-save

sshpass -p 'vagrant' ssh vagrant@k8s-w2 "sudo iptables-save | grep -v KUBE | grep -v FLANNEL | sudo iptables-restore"
sshpass -p 'vagrant' ssh vagrant@k8s-w2 sudo iptables-save
```

---

## 📚 추가 자료

- [Cilium 공식 문서](https://docs.cilium.io/)
- [eBPF 소개](https://ebpf.io/)
- [Kubernetes 네트워킹 개념](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [Flannel 프로젝트](https://github.com/flannel-io/flannel)

---