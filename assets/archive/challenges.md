
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