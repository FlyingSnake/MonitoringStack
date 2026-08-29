# 서버 GitOps

`server/`는 중앙 관측성 플랫폼을 위한 선언형 Kubernetes 설정을 담습니다.

Argo CD는 Helm으로 한 번 부트스트랩한 뒤 `Application`, `ApplicationSet`, `AppProject` CR을 통해 자신과 모든 플랫폼 애플리케이션을 동기화합니다. 대상 워크로드는 Keycloak, 선택적 MinIO, Grafana Operator/Grafana, Loki, Tempo, Mimir, Pyroscope, blackbox exporter, AWX Operator, AWX입니다.

## 환경 설정

환경마다 하나의 values 파일을 사용합니다.

```text
server/env/
├── dev/values.yaml
├── stg/values.yaml
└── prd/values.yaml
```

values에는 이미지/차트 버전, 복제본 수, 리소스 제한, StorageClass, 오브젝트 스토리지 참조, Ingress/TLS, 보존 기간, 테넌트, 기능 플래그를 노출합니다. 자격증명은 값이 아닌 Secret 참조만 사용합니다.

## 계획된 구조

```text
server/
├── applications/  # Argo CD AppProject, Application, ApplicationSet 매니페스트
├── charts/        # 필요한 경우 이 저장소가 소유하는 wrapper 차트
├── crds/          # 선언형 사용자 정의 리소스와 보조 매니페스트
├── env/           # 환경별 values
└── values/        # 공통 및 차트별 values 조각
```

컴포넌트를 추가하거나 배포 순서를 변경하기 전 [../IMPLEMENTATION_PLAN.md](../IMPLEMENTATION_PLAN.md)를 확인하세요.
