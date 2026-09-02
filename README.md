# MonitoringStack

Grafana OSS 기반 중앙 관측성 플랫폼과 Grafana Alloy 에이전트를 GitOps 방식으로 관리하는 저장소입니다.

로그(Loki), 메트릭(Mimir), 트레이스(Tempo), 프로파일(Pyroscope)을 수집하고 Grafana에서 통합 조회합니다. Argo CD는 Kubernetes 서버 스택을 동기화하고, AWX는 Git으로 관리되는 인벤토리와 Ansible 플레이북으로 Linux, Windows, Kubernetes 환경에 Alloy를 배포합니다.

## 디렉터리 구성

```text
.
├── bootstrap/ # Argo CD 최초 설치와 Root Application
├── server/    # Argo CD가 배포·관리하는 중앙 Kubernetes 플랫폼
├── agents/    # AWX/Ansible과 Alloy 구성으로 관리하는 수집 에이전트
└── local/     # Kind, 로컬 Git daemon, 테스트 워크로드 (Git 추적 제외)
```

환경별 배포 값은 다음 경로에 둡니다.

- 서버: `server/env/<dev|stg|prd>/values.yaml`
- 에이전트: `agents/env/<dev|stg|prd>/<linux|windows|k8s>/values.yaml`

전체 아키텍처와 단계별 구현 순서는 [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)를 참고하세요.
환경별 배포 승격 규칙은 [BRANCH_STRATEGY.md](BRANCH_STRATEGY.md)를 참고하세요.

## 운영 원칙

- GitHub 원격 저장소는 `FlyingSnake/MonitoringStack`입니다.
- 모든 배포 변경은 Git pull request와 Argo CD/AWX 동기화로 반영합니다.
- Argo CD Application은 모든 환경에서 자동 Sync를 사용하지 않습니다. 검증된 Git revision을 운영자가 수동 Sync합니다.
- Helm 차트와 컨테이너 이미지는 재현 가능하도록 버전을 고정합니다.
- 비밀값은 평문으로 커밋하지 않습니다. SOPS로 암호화하거나 External Secrets 참조만 커밋합니다.
- `prd` 변경에는 검증과 승인 절차를 적용합니다.

## 현재 상태

`dev`에는 다음 선언형 구성이 구현되어 있으며, Kind 로컬 검증으로 동작을 확인했습니다.

- Vault, cert-manager, External Secrets, Keycloak, MinIO, Redpanda, Grafana Operator, Loki, Mimir, Tempo, Pyroscope, blackbox exporter, 서버 Alloy, AWX를 Argo CD Application으로 분리했습니다.
- 수집 경로는 `*.ingest.<환경>.<도메인>`으로 고정하고 Envoy Gateway의 mTLS와 HTTP Basic Auth를 함께 요구합니다. UI/OIDC 경로는 별도의 `ui-https` listener를 사용합니다.
- AWX는 Git 인벤토리와 Job Template로 Kubernetes·Linux·Windows Alloy 역할을 관리합니다. Linux와 Kubernetes는 Kind에서 Vault 단기 인증서와 수집 자격증명을 사용하는 흐름을 검증했습니다.
- Kind 테스트 워크로드는 Java, Go, Node.js와 .NET의 로그·메트릭·트레이스를 검증합니다. Apple Silicon ARM64에서는 현재 Pyroscope .NET profiler wrapper가 없어 .NET 프로파일만 안전하게 비활성화됩니다.

로컬 실행과 smoke test 절차는 [local/README.md](local/README.md), 실제 구현 상태와 남은 작업은 [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)를 참고하세요.
