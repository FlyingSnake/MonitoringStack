# 서버 GitOps

`server/`는 중앙 관측성 플랫폼을 위한 선언형 Kubernetes 설정을 담습니다. Application sync wave는 Namespace 기반 리소스 → Vault → 인증서/Secret → Keycloak → 저장소 → 관측성 → Gateway 정책 → AWX 순서입니다. 독립적으로 수동 Sync하는 Helm Application이 대상 namespace를 먼저 요구하므로, foundation 차트가 유일하게 `-01` wave를 사용합니다.

Argo CD는 Helm으로 한 번 부트스트랩한 뒤 `Application`과 `AppProject` CR을 통해 모든 플랫폼 애플리케이션을 수동 동기화합니다. 대상 워크로드는 Vault, cert-manager, External Secrets, Keycloak, MinIO/Redpanda, Grafana Operator/Grafana, Loki, Tempo, Mimir, Pyroscope, blackbox exporter, 서버 Alloy, AWX Operator, AWX입니다. `dev` Kind 검증에서는 위 Application이 모두 `Synced`·`Healthy` 상태여야 합니다.

Mimir와 Tempo는 공용 `monitoring-stack-server` namespace에 배포되며 Redpanda Kafka를 공용으로 사용합니다. Loki와 Pyroscope는 각각 별도 namespace를 유지합니다.

External Secrets CRD는 크기가 커서 Kubernetes의 client-side apply annotation 한도를 초과합니다. 각 클러스터에서는 ESO Application을 처음 수동 Sync하기 전에 `bootstrap/install-external-secrets-crds.sh`를 한 번 실행합니다. 이 스크립트는 고정된 CRD 버전을 server-side apply하고, 이후 ESO controller 자체는 Argo CD가 관리합니다.

## 환경 설정

환경마다 하나의 values 파일을 사용합니다.

```text
server/env/
├── dev/values.yaml
├── stg/values.yaml
└── prd/values.yaml
```

values에는 이미지/차트 버전, 복제본 수, 리소스 제한, StorageClass, 오브젝트 스토리지 참조, Ingress/TLS, 보존 기간, 테넌트, 기능 플래그를 노출합니다. 자격증명은 값이 아닌 Secret 참조만 사용합니다.

`dev` Vault는 운영자가 수동 초기화·Unseal하며, `stg`와 `prd` Vault는 EKS IRSA와 AWS KMS Auto-Unseal을 사용합니다. 실제 값이 없는 `REQUIRED_*` 항목 또는 `example.internal` 도메인이 남아 있으면 운영 사전검사가 배포를 거부합니다.

stg/prd Argo CD 수동 Sync 직전에는 반드시 아래 명령을 실행합니다. 이 검사는 Vault KMS·IRSA, Gateway 이름·listener·환경 DNS, 운영 외부 저장소/Kafka 계약이 렌더링 가능한지 확인합니다.

```bash
make preflight-server ENV=stg
make preflight-server ENV=prd
```

## 계획된 구조

```text
server/
├── charts/        # App-of-Apps 및 foundation/secrets/identity/observability/gateway/AWX wrapper 차트
├── crds/          # 선언형 사용자 정의 리소스와 보조 매니페스트
├── env/           # 환경별 values
└── values/        # 공통 및 차트별 values 조각
```

컴포넌트를 추가하거나 배포 순서를 변경하기 전 [../IMPLEMENTATION_PLAN.md](../IMPLEMENTATION_PLAN.md)를 확인하세요.

## dev/Kind 검증 범위

로컬 Kind는 `server/env/dev/values.yaml` 위에 `local/server/values.yaml`을 겹쳐 모든 서버 컴포넌트를 단일 복제본·비영속 스토리지로 기동합니다. local Git daemon의 `dev` 브랜치를 Argo CD source로 사용하므로 원격 push 없이도 수동 Sync를 검증할 수 있습니다.

수집 endpoint는 `loki|mimir|tempo|pyroscope.ingest.localhost`이며, Gateway에서 mTLS와 HTTP Basic Auth를 동시에 검증합니다. Vault bootstrap 뒤에만 ExternalSecret, Gateway TLS, AWX용 PKI와 Alloy client certificate를 생성합니다. 자세한 실행 순서는 [../local/README.md](../local/README.md)를 참고하세요.
