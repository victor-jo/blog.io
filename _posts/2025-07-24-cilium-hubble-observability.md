---
layout: post
title: "Cilium Hubble을 활용한 쿠버네티스 네트워크 관측성 구축 가이드"
date: 2025-07-24 14:30:00 +0900
categories: cilium observability
tags: [cilium, hubble, observability, prometheus, grafana, metrics, monitoring, ebpf, kubernetes]
---


# Cilium Hubble Observability 실습 가이드

## 0. 실습 환경 구성

### 실습 환경 소개
- 기본 배포 가상 머신: k8s-ctr, k8s-w1, k8s-w2
- kubeadm으로 쿠버네티스 클러스터 구성
- Cilium CNI 설치 상태로 배포

### Vagrant 실습 환경 배포

#### 실습 어셋 다운로드
```bash
mkdir cilium-lab && cd cilium-lab
curl -O https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/init_cfg.sh
curl -O https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/k8s-ctr.sh
curl -O https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/k8s-w.sh
curl -O https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/k8s-cni.sh
curl -o kubeadm-init-config.yaml https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/kubeadm-init-config-without-proxy.yaml
curl -O https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/kubeadm-join-config.yaml
```

#### 실습 환경 배포 실행
```bash
# Vagrantfile 및 스크립트 다운로드
curl -O https://raw.githubusercontent.com/victor-jo/blog.io/main/assets/cilium/Vagrantfile

# 실습 환경 배포
vagrant up
```

### 실습 환경 확인
```bash
# k8s-ctr 노드 접속
vagrant ssh k8s-ctr

# 클러스터 정보 확인
kubectl cluster-info
kubectl get nodes -owide

# Cilium 설치 상태 확인  
cilium status --wait
cilium config view
```

## 1. Network Observability with Hubble

### Hubble 소개
Hubble은 완전히 분산된 네트워킹 및 보안 관측 가능성 플랫폼입니다. Cilium과 eBPF를 기반으로 구축되어 서비스의 통신 및 동작뿐만 아니라 네트워킹 인프라에 대한 깊은 가시성을 제공합니다.

#### Hubble의 주요 기능
- **Service dependencies & communication map**: 서비스 간 통신 및 의존성 시각화
- **Network monitoring & alerting**: 네트워크 통신 실패 감지 및 원인 분석
- **Application monitoring**: HTTP 응답 코드, 지연 시간 등 애플리케이션 메트릭
- **Security observability**: 네트워크 정책에 의해 차단된 연결 추적

### Hubble 설치 및 설정

#### Hubble 활성화
```bash
# Hubble 활성화 (메트릭 설정 포함)
helm upgrade cilium cilium/cilium --version 1.17.6 --namespace kube-system --reuse-values \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set hubble.ui.service.type=NodePort \
  --set hubble.ui.service.nodePort=31234 \
  --set hubble.export.static.enabled=true \
  --set hubble.export.static.filePath=/var/run/cilium/hubble/events.log \
  --set prometheus.enabled=true \
  --set operator.prometheus.enabled=true \
  --set hubble.metrics.enableOpenMetrics=true \
  --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}"

# 설치 확인
cilium status --wait

# Hubble UI 접속 주소 확인
NODEIP=$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo -e "Hubble UI: http://$NODEIP:31234"
```

#### Hubble CLI 설치
```bash
# Hubble CLI 설치
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
HUBBLE_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then HUBBLE_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-${HUBBLE_ARCH}.tar.gz{,.sha256sum}
sudo tar xzvfC hubble-linux-${HUBBLE_ARCH}.tar.gz /usr/local/bin

# Hubble API 포트 포워딩
cilium hubble port-forward&

# Hubble 상태 확인
hubble status
```

### Star Wars Demo 애플리케이션 배포

#### 데모 애플리케이션 배포
```bash
# Star Wars 데모 애플리케이션 배포
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/1.17.6/examples/minikube/http-sw-app.yaml

# 배포 확인
kubectl get pod --show-labels
kubectl get svc,ep deathstar
```

#### 네트워크 정책 없이 통신 테스트
```bash
# 모니터링 시작
hubble observe -f --pod deathstar --protocol http

# 통신 테스트 (성공)
kubectl exec xwing -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing

# (⎈|HomeLab:N/A) root@k8s-ctr:~# hubble observe -f --pod deathstar
# Jul 24 15:09:42.581: default/xwing (ID:7904) <> default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) post-xlate-fwd TRANSLATED (TCP)
# Jul 24 15:09:42.581: default/xwing:53906 (ID:7904) -> default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: SYN)
# Jul 24 15:09:42.581: default/xwing:53906 (ID:7904) <- default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: SYN, ACK)
# Jul 24 15:09:42.581: default/xwing:53906 (ID:7904) -> default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: ACK)
# Jul 24 15:09:42.581: default/xwing:53906 (ID:7904) <> default/deathstar-8c4c77fb7-2wlfr (ID:14731) pre-xlate-rev TRACED (TCP)
# Jul 24 15:09:42.581: default/xwing:53906 (ID:7904) <> default/deathstar-8c4c77fb7-2wlfr (ID:14731) pre-xlate-rev TRACED (TCP)
# Jul 24 15:09:42.581: default/xwing:53906 (ID:7904) <> default/deathstar-8c4c77fb7-2wlfr (ID:14731) pre-xlate-rev TRACED (TCP)
# Jul 24 15:09:42.581: default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) <> default/xwing (ID:7904) pre-xlate-rev TRACED (TCP)
# Jul 24 15:09:42.581: default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) <> default/xwing (ID:7904) pre-xlate-rev TRACED (TCP)
# Jul 24 15:09:42.582: default/xwing:53906 (ID:7904) -> default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
# Jul 24 15:09:42.582: default/xwing:53906 (ID:7904) <> default/deathstar-8c4c77fb7-2wlfr (ID:14731) pre-xlate-rev TRACED (TCP)
# Jul 24 15:09:42.582: default/xwing:53906 (ID:7904) <> default/deathstar-8c4c77fb7-2wlfr (ID:14731) pre-xlate-rev TRACED (TCP)
# Jul 24 15:09:42.582: default/xwing:53906 (ID:7904) <- default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
# Jul 24 15:09:42.582: default/xwing:53906 (ID:7904) -> default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
# Jul 24 15:09:42.583: default/xwing:53906 (ID:7904) <- default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
# Jul 24 15:09:42.583: default/xwing:53906 (ID:7904) -> default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: ACK)
# Jul 24 15:10:04.812: default/tiefighter (ID:50046) <> default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) post-xlate-fwd TRANSLATED (TCP)
# Jul 24 15:10:04.812: default/tiefighter:47028 (ID:50046) -> default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: SYN)
# Jul 24 15:10:04.812: default/tiefighter:47028 (ID:50046) <- default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: SYN, ACK)
# Jul 24 15:10:04.812: default/tiefighter:47028 (ID:50046) -> default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: ACK)
# Jul 24 15:10:04.812: default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) <> default/tiefighter (ID:50046) pre-xlate-rev TRACED (TCP)
# Jul 24 15:10:04.812: default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) <> default/tiefighter (ID:50046) pre-xlate-rev TRACED (TCP)
# Jul 24 15:10:04.812: default/tiefighter:47028 (ID:50046) -> default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
# Jul 24 15:10:04.812: default/tiefighter:47028 (ID:50046) <> default/deathstar-8c4c77fb7-h59s2 (ID:14731) pre-xlate-rev TRACED (TCP)
# Jul 24 15:10:04.812: default/tiefighter:47028 (ID:50046) <> default/deathstar-8c4c77fb7-h59s2 (ID:14731) pre-xlate-rev TRACED (TCP)
# Jul 24 15:10:04.812: default/tiefighter:47028 (ID:50046) <> default/deathstar-8c4c77fb7-h59s2 (ID:14731) pre-xlate-rev TRACED (TCP)
# Jul 24 15:10:04.812: default/tiefighter:47028 (ID:50046) <> default/deathstar-8c4c77fb7-h59s2 (ID:14731) pre-xlate-rev TRACED (TCP)
# Jul 24 15:10:04.812: default/tiefighter:47028 (ID:50046) <> default/deathstar-8c4c77fb7-h59s2 (ID:14731) pre-xlate-rev TRACED (TCP)
# Jul 24 15:10:04.812: default/tiefighter:47028 (ID:50046) <- default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
# Jul 24 15:10:04.813: default/tiefighter:47028 (ID:50046) -> default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
# Jul 24 15:10:04.814: default/tiefighter:47028 (ID:50046) <- default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
# Jul 24 15:10:04.814: default/tiefighter:47028 (ID:50046) -> default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) to-endpoint FORWARDED (TCP Flags: ACK)
```

#### L3/L4 네트워크 정책 적용
```bash
# L3/L4 정책 적용 (Empire 소속만 접근 허용)
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/1.17.6/examples/minikube/sw_l3_l4_policy.yaml

# Drop 이벤트 모니터링
hubble observe -f --type drop

# 통신 테스트
kubectl exec xwing -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing --connect-timeout 2  # 실패
kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing  # 성공

# (⎈|HomeLab:N/A) root@k8s-ctr:~# hubble observe -f --type drop
# Jul 24 14:51:15.461: default/xwing:50548 (ID:7904) <> default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) Policy denied DROPPED (TCP Flags: SYN)
```

#### L7 네트워크 정책 적용
```bash
# L7 정책 적용 (특정 HTTP 경로만 허용)
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/1.17.6/examples/minikube/sw_l3_l4_l7_policy.yaml

# L7 모니터링
hubble observe -f --pod deathstar --protocol http

# 통신 테스트
kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing  # 성공
kubectl exec tiefighter -- curl -s -XPUT deathstar.default.svc.cluster.local/v1/exhaust-port  # 실패 (403)

# (⎈|HomeLab:N/A) root@k8s-ctr:~# hubble observe -f --pod deathstar --protocol http
# Jul 24 15:03:48.650: default/tiefighter:51338 (ID:50046) -> default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) http-request FORWARDED (HTTP/1.1 POST http://deathstar.default.svc.cluster.local/v1/request-landing)
# Jul 24 15:03:48.655: default/tiefighter:51338 (ID:50046) <- default/deathstar-8c4c77fb7-2wlfr:80 (ID:14731) http-response FORWARDED (HTTP/1.1 200 5ms (POST http://deathstar.default.svc.cluster.local/v1/request-landing))
# Jul 24 15:03:54.062: default/tiefighter:53884 (ID:50046) -> default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) http-request DROPPED (HTTP/1.1 PUT http://deathstar.default.svc.cluster.local/v1/exhaust-port)
# Jul 24 15:03:54.062: default/tiefighter:53884 (ID:50046) <- default/deathstar-8c4c77fb7-h59s2:80 (ID:14731) http-response FORWARDED (HTTP/1.1 403 0ms (PUT http://deathstar.default.svc.cluster.local/v1/exhaust-port))

```

#### L3/L4/L7 네트워크 정책 삭제
```bash
kubectl delete -f https://raw.githubusercontent.com/cilium/cilium/1.17.6/examples/minikube/sw_l3_l4_l7_policy.yaml
```

### Hubble Flow Logs Export

#### Flow Logs 설정 확인
```bash
# Hubble export 설정 확인
cilium config view | grep hubble-export

# Flow logs 확인
kubectl -n kube-system exec ds/cilium -- tail -f /var/run/cilium/hubble/events.log
```

## 2. Running Prometheus & Grafana

### Prometheus & Grafana 설치

#### 모니터링 스택 배포
```bash
# Prometheus와 Grafana를 포함한 모니터링 예제 배포
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/1.17.6/examples/kubernetes/addons/prometheus/monitoring-example.yaml

# 배포 확인
kubectl get deploy,pod,svc,ep -n cilium-monitoring
kubectl get cm -n cilium-monitoring
```

#### NodePort 설정 (외부 접속용)
```bash
# NodePort 설정
kubectl patch svc -n cilium-monitoring prometheus -p '{"spec": {"type": "NodePort", "ports": [{"port": 9090, "targetPort": 9090, "nodePort": 30001}]}}'
kubectl patch svc -n cilium-monitoring grafana -p '{"spec": {"type": "NodePort", "ports": [{"port": 3000, "targetPort": 3000, "nodePort": 30002}]}}'

# 접속 주소 확인
echo "Prometheus: http://192.168.10.100:30001"
echo "Grafana: http://192.168.10.100:30002"
```

### 메트릭 수집 확인

#### Cilium 메트릭 확인
```bash
# 메트릭 포트 확인
ss -tnlp | grep -E '9962|9963|9965'
# 9962: cilium-agent metrics
# 9963: cilium-operator metrics  
# 9965: hubble metrics

# 메트릭 직접 확인
curl localhost:9962/metrics | grep cilium_
curl localhost:9963/metrics | grep cilium_operator_
curl localhost:9965/metrics | grep hubble_
```

### Grafana 대시보드 활용

#### 사전 구성된 대시보드
- **Cilium Metrics**: Generic, API, BPF, kvstore, Network info, Endpoints, k8s integration
- **Cilium Operator**: IPAM 관련 메트릭
- **Hubble**: General Processing, Network, Network Policy, HTTP, DNS
- **Hubble L7 HTTP Metrics by Workload**: HTTP 요청 분석

#### 주요 PromQL 쿼리 예시
```promql
# BPF Map 작업 수 (상위 5개)
topk(5, avg(rate(cilium_bpf_map_ops_total{k8s_app="cilium"}[5m])) by (pod, map_name, operation))

# Hubble Drop 이벤트
hubble_drop_total

# HTTP 요청률
rate(hubble_http_requests_total[5m])

# DNS 쿼리
rate(hubble_dns_queries_total[5m])
```

### 샘플 애플리케이션 모니터링

#### 테스트 애플리케이션 배포
```bash
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
spec:
  selector:
    app: webpod
  ports:
  - protocol: TCP
    port: 80
  type: ClusterIP
EOF

# curl 파드 배포
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: curl-pod
spec:
  nodeName: k8s-ctr
  containers:
  - name: curl
    image: nicolaka/netshoot
    command: ["tail", "-f", "/dev/null"]
EOF
```

#### 트래픽 생성 및 모니터링
```bash
# 반복 요청 생성
kubectl exec -it curl-pod -- sh -c 'while true; do curl -s webpod | grep Hostname; sleep 1; done'
```

## 3. Monitoring & Metrics

### Cilium Metrics 구성

#### 메트릭 수집 설정
Cilium, Hubble, Cilium Operator는 기본적으로 메트릭을 노출하지 않습니다. 다음 설정으로 활성화합니다:

```bash
# 이미 설정되어 있는 경우 확인
cilium config view | grep -i prometheus

# 메트릭 활성화 설정값
# prometheus.enabled=true: cilium-agent 메트릭 활성화 (포트 9962)
# operator.prometheus.enabled=true: cilium-operator 메트릭 활성화 (포트 9963)
# hubble.metrics.enabled: Hubble 메트릭 활성화 (포트 9965)
```

#### 메트릭 수집 확인
```bash
# Prometheus 타겟 확인
kubectl describe cm -n cilium-monitoring prometheus | grep -A20 "job_name: 'kubernetes-pods'"

# Pod 어노테이션 확인
kubectl describe pod -n kube-system -l k8s-app=cilium | grep prometheus
```

### 주요 메트릭 카테고리

#### Cilium Agent 메트릭
- **Feature Metrics**: 연결성, 로드밸런싱, 컨트롤 플레인, 데이터패스, 네트워크 정책
- **Exported Metrics**: 엔드포인트, 서비스, 클러스터 헬스, 노드 연결성, eBPF, Drop/Forward 이벤트

#### Cilium Operator 메트릭
- BGP Control Operator
- IPAM (IP Address Management)
- LB-IPAM
- CiliumEndpointSlices

#### Hubble 메트릭
- DNS: 쿼리, 응답, 에러
- Drop: 패킷 드롭 이유별 통계
- TCP: 연결 상태, 플래그
- Flow: 프로토콜별 흐름
- HTTP: 요청/응답, 상태 코드, 지연시간

### 메트릭 활용 예시

#### Cilium 단축키 설정
```bash
# cilium 파드 이름 설정
export CILIUMPOD0=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-ctr -o jsonpath='{.items[0].metadata.name}')
export CILIUMPOD1=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w1 -o jsonpath='{.items[0].metadata.name}')
export CILIUMPOD2=$(kubectl get -l k8s-app=cilium pods -n kube-system --field-selector spec.nodeName=k8s-w2 -o jsonpath='{.items[0].metadata.name}')

# 단축키 설정
alias c0="kubectl exec -it $CILIUMPOD0 -n kube-system -c cilium-agent -- cilium"
alias c1="kubectl exec -it $CILIUMPOD1 -n kube-system -c cilium-agent -- cilium"
alias c2="kubectl exec -it $CILIUMPOD2 -n kube-system -c cilium-agent -- cilium"
```

#### 엔드포인트 및 서비스 모니터링
```bash
# 엔드포인트 목록
c0 endpoint list
c1 endpoint list
c2 endpoint list

# 서비스 목록
c0 service list
c1 service list
c2 service list

# BPF 맵 정보
c0 bpf lb list
c1 bpf ct list global
c2 bpf nat list
```

### OpenMetrics 지원

OpenMetrics는 메트릭 형식의 표준으로, Exemplar와 같은 고급 기능을 지원합니다.

```bash
# OpenMetrics 활성화 확인
cilium config view | grep enableOpenMetrics

# Exemplar를 포함한 HTTP 메트릭 확인
curl localhost:9965/metrics | grep "# HELP hubble_http"
```

## 4. Layer 7 Protocol Visibility

### L7 가시성 개요

L7 프로토콜 가시성을 사용하면 HTTP, gRPC, Kafka 등의 애플리케이션 레이어 트래픽을 모니터링할 수 있습니다. 이 기능은 L7 프록시(cilium-envoy)를 통해 제공됩니다.

### L7 가시성 설정

#### L7 네트워크 정책 생성
```bash
# L7 가시성을 위한 네트워크 정책
cat <<EOF | kubectl apply -f -
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "l7-visibility"
spec:
  endpointSelector:
    matchLabels:
      "k8s:io.kubernetes.pod.namespace": default
  egress:
  - toPorts:
    - ports:
      - port: "53"
        protocol: ANY
      rules:
        dns:
        - matchPattern: "*"
  - toEndpoints:
    - matchLabels:
        "k8s:io.kubernetes.pod.namespace": default
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      - port: "8080"
        protocol: TCP
      rules:
        http: [{}]
EOF
```

#### L7 트래픽 모니터링
```bash
# HTTP 트래픽 모니터링
hubble observe -f -t l7 -o compact

# 테스트 요청 실행
kubectl exec -it curl-pod -- curl -s webpod

# 응답 헤더 확인 (Envoy 경유 확인)
# X-Envoy-Expected-Rq-Timeout-Ms
# X-Envoy-Internal
# X-Forwarded-Proto
```

### Cilium Envoy 확인

#### Envoy 데몬셋 확인
```bash
# Cilium Envoy 파드 확인
kubectl get ds -n kube-system cilium-envoy
kubectl get pod -n kube-system -l k8s-app=cilium-envoy -owide

# Envoy 설정 확인
kubectl describe ds -n kube-system cilium-envoy
kubectl describe cm -n kube-system cilium-envoy-config
```

### 보안 고려사항

#### 민감정보 제거 설정
```bash
# URL 쿼리 파라미터 제거
helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
  --set extraArgs="{--hubble-redact-enabled,--hubble-redact-http-urlquery}"

# 테스트
kubectl exec -it curl-pod -- sh -c 'curl -s webpod/?user_id=1234&token=secret'

# 모니터링 (쿼리 파라미터가 제거됨)
hubble observe -f -t l7
```

### L7 메트릭 활용

#### Grafana에서 L7 메트릭 확인
- Hubble L7 HTTP Metrics by Workload 대시보드
- HTTP 요청률, 응답 시간, 상태 코드별 분포

#### PromQL 쿼리 예시
```promql
# HTTP 요청률
rate(hubble_http_requests_total[5m])

# HTTP 응답 시간 (P95)
histogram_quantile(0.95, rate(hubble_http_request_duration_seconds_bucket[5m]))

# HTTP 에러율
rate(hubble_http_requests_total{http_status_code=~"5.."}[5m])
```

## 5. pwru (Packet, where are you?)

### pwru 소개

pwru는 eBPF 기반의 Linux 커널 네트워킹 디버거로, 패킷이 커널 내부에서 어떻게 처리되는지 추적할 수 있습니다.

### pwru 설치

#### Prerequisites
```bash
sudo apt update
sudo apt install -y clang llvm gcc make flex bison byacc yacc libpcap-dev golang
```

#### 소스에서 빌드
```bash
# pwru 리포지토리 클론
git clone https://github.com/cilium/pwru.git
cd pwru

# 빌드
make

# 실행 권한 확인
sudo ./pwru --help
```

### pwru 사용 예시

#### ICMP 패킷 추적
```bash
# ping 트래픽 추적
sudo ./pwru --output-tuple icmp

# 다른 터미널에서 ping 실행
ping -c 3 8.8.8.8
```

#### 특정 IP 주소 트래픽 추적
```bash
# 특정 소스 IP 추적
sudo ./pwru 'src host 10.245.0.0/16'

# 특정 목적지 포트 추적
sudo ./pwru 'dst port 80'
```

#### Kubernetes Pod 트래픽 추적
```bash
# Pod IP 확인
PODIP=$(kubectl get pod curl-pod -o jsonpath='{.status.podIP}')

# Pod 트래픽 추적
sudo ./pwru "host $PODIP"

# 트래픽 생성
kubectl exec curl-pod -- curl webpod
```

## 주요 도전 과제

### 도전과제1: Dynamic Hubble Exporter 설정
```bash
helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
  --set hubble.export.dynamic.enabled=true \
  --set hubble.export.dynamic.config.content[0].name=system \
  --set hubble.export.dynamic.config.content[0].filePath=/var/run/cilium/hubble/events-system.log \
  --set hubble.export.dynamic.config.content[0].includeFilters[0].source_pod[0]='kube_system/'
```

### 도전과제2: Hubble TLS 설정
```bash
# TLS 인증서 생성 및 설정
helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
  --set hubble.tls.enabled=true \
  --set hubble.tls.auto.enabled=true
```

### 도전과제3: Prometheus Stack 설치
```bash
# Prometheus Operator 설치
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

# ServiceMonitor 생성으로 Cilium 메트릭 수집
```

## 운영 시 고려사항

### 성능 최적화
- 대규모 클러스터에서는 헬스체크 비활성화 고려
- Hubble flow logs 선택적 수집 (필터링)
- 메트릭 수집 간격 조정

### 보안
- Hubble UI/API HTTPS 설정
- 민감정보 redaction 설정
- 네트워크 정책 적용 시 철저한 테스트

### 모니터링
- 핵심 메트릭: drop율, 지연시간, 에러율
- L7 가시성은 필요한 경우에만 활성화
- Grafana 알림 설정으로 이상 감지

## 추가 자료 및 참고 링크

### 공식 문서
- [Cilium Observability Documentation](https://docs.cilium.io/en/stable/observability/)
- [Hubble Documentation](https://docs.cilium.io/en/stable/observability/hubble/)
- [Cilium Metrics Reference](https://docs.cilium.io/en/stable/observability/metrics/)

### 관련 도구
- [pwru - Packet Where Are You](https://github.com/cilium/pwru)
- [Tetragon - Security Observability](https://github.com/cilium/tetragon)
- [Prometheus](https://prometheus.io/)
- [Grafana](https://grafana.com/)

### 커뮤니티 리소스
- [eCHO (eBPF & Cilium Office Hours) YouTube Playlist](https://www.youtube.com/playlist?list=PLDg_GiBbAx-mY3VFLPbLHcxo6wUjejAOC)
- [Cilium Slack](https://cilium.herokuapp.com/)
- [CNCF Slack #cilium channel](https://cloud-native.slack.com/)

---

*이 가이드는 Cilium v1.17.6 기준으로 작성되었습니다.*