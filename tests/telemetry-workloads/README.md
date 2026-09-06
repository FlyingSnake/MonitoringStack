# Kind 텔레메트리 워크로드

이 디렉터리는 Kubernetes Alloy의 실제 수집 경로를 검증하는 .NET, Java, Go, Node.js 샘플 애플리케이션입니다.

- 표준 출력 로그는 Alloy DaemonSet이 Loki로 전송합니다.
- `/metrics` 엔드포인트는 Pod annotation을 통해 Alloy가 Mimir로 scrape합니다.
- 애플리케이션 trace는 Alloy OTLP/HTTP 수신기(`alloy.alloy.svc.cluster.local:4318`)로 보냅니다.
- 각 언어의 Pyroscope SDK 또는 에이전트는 Alloy Pyroscope 수신기(`alloy.alloy.svc.cluster.local:9999`)로 profile을 보냅니다.

이미지는 고정된 SDK·런타임 버전으로 로컬 Docker에서 빌드해 Kind에 적재합니다. 자격증명은 사용하지 않으며, 앱은 Gateway에 직접 연결하지 않습니다.

```bash
./tests/telemetry-workloads/build-images.sh
./tests/telemetry-workloads/deploy.sh
./tests/telemetry-workloads/verify.sh
./tests/telemetry-workloads/query.sh
```

`verify.sh`는 워크로드·Alloy·Pyroscope 수신 상태를 확인하고, `query.sh`는 로컬 Vault의 Basic Auth를 사용해 Gateway 보안 회귀와 Loki·Mimir·Tempo·Pyroscope 조회를 수행합니다. 정리는 `./tests/telemetry-workloads/destroy.sh`로 수행합니다. 전체 반복 검증은 `make local-telemetry-smoke`, 정리는 `make local-telemetry-clean`을 사용합니다.

## Grafana 수동 Smoke 절차

1. `https://grafana.demo.flyingsnake.xyz`에 접속해 Keycloak `monitoring` realm으로 로그인합니다.
2. Grafana Explore에서 Loki의 `{namespace="telemetry-workloads"}` 로그, Mimir의 `telemetry_workload_heartbeat_total`, Tempo의 `service.name=telemetry.go` trace를 조회합니다.
3. Pyroscope에서 `service_name=telemetry.go`, `telemetry.java`, `telemetry.nodejs` 프로파일을 확인합니다.

`query.sh`는 위 UI 확인 전에 Gateway HTTPS+Basic Auth 회귀, Loki/Mimir/Tempo API 조회, Pyroscope 수신 로그를 자동 확인합니다.

Grafana 브라우저 OIDC 검증은 Let's Encrypt 인증서가 적용된 실제 도메인과 Keycloak 테스트 계정이 준비된 뒤 수행한다. Let's Encrypt HTTP-01을 사용한다면 해당 도메인의 80/443 접근과 DNS 해석이 가능해야 한다.

## ARM64 Kind의 .NET 프로파일 제한

현재 Apple Silicon Kind 노드에서는 사용 중인 Pyroscope .NET profiler 패키지에 ARM64용 ApiWrapper가 없어 .NET 프로파일러가 비활성화됩니다. entrypoint는 이를 감지해 명시적 경고를 남기고 logs·metrics·traces만 계속 수집합니다. 이 로컬 환경에서는 .NET 로그·메트릭·트레이스를 검증하고, 프로파일은 Java·Go·Node.js에서 검증합니다. x86_64 Linux 노드 또는 ARM64 wrapper를 포함한 profiler 릴리스로 전환하면 .NET 프로파일도 같은 경로로 검증할 수 있습니다.
