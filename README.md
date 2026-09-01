# MonitoringStack

Grafana OSS 기반 중앙 관측성 플랫폼과 Grafana Alloy 에이전트를 GitOps 방식으로 관리하는 저장소입니다.

로그(Loki), 메트릭(Mimir), 트레이스(Tempo), 프로파일(Pyroscope)을 수집하고 Grafana에서 통합 조회합니다. Argo CD는 Kubernetes 서버 스택을 동기화하고, AWX는 Git으로 관리되는 인벤토리와 Ansible 플레이북으로 Linux, Windows, Kubernetes 환경에 Alloy를 배포합니다.

## 디렉터리 구성

```text
.
├── server/    # Argo CD가 배포·관리하는 중앙 Kubernetes 플랫폼
└── agents/    # AWX/Ansible과 Alloy 구성으로 관리하는 수집 에이전트
```

환경별 배포 값은 다음 경로에 둡니다.

- 서버: `server/env/<dev|stg|prd>/values.yaml`
- 에이전트: `agents/env/<dev|stg|prd>/<linux|windows|k8s>/values.yaml`

전체 아키텍처와 단계별 구현 순서는 [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)를 참고하세요.
환경별 배포 승격 규칙은 [BRANCH_STRATEGY.md](BRANCH_STRATEGY.md)를 참고하세요.

## 운영 원칙

- GitHub 원격 저장소는 `FlyingSnake/MonitoringStack`입니다.
- 모든 배포 변경은 Git pull request와 Argo CD/AWX 동기화로 반영합니다.
- Helm 차트와 컨테이너 이미지는 재현 가능하도록 버전을 고정합니다.
- 비밀값은 평문으로 커밋하지 않습니다. SOPS로 암호화하거나 External Secrets 참조만 커밋합니다.
- `prd` 변경에는 검증과 승인 절차를 적용합니다.

## 현재 상태

현재는 디렉터리와 설계 문서를 준비한 초기 단계입니다. 구현은 계획 문서의 “단계별 구현 순서”를 따릅니다.
