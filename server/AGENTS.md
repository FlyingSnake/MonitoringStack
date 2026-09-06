# 서버 영역 지침

- 장기 운영 서버 워크로드 변경은 Argo CD 리소스로 렌더링·동기화해야 합니다. 직접 `helm install`은 문서화된 최초 Argo CD 부트스트랩에만 허용됩니다.
- `Application` 동기화 순서를 명시합니다. 순서는 기반 리소스 → 인증/저장소 → 관측성 → AWX 자동화입니다.
- 독립 운영 서비스마다 별도 namespace, release 이름, Argo CD Application을 사용합니다.
- 외부 Helm 차트 버전은 고정하고 차트의 `main` 또는 `latest`를 추적하지 않습니다. 이 저장소를 소스로 하는 Argo CD Application의 `targetRevision`은 환경별로 `dev`, `stg`, `main`을 사용합니다.
- 환경 차이는 `server/env/<environment>/values.yaml`로 처리합니다. 공통 기본값은 복제된 매니페스트가 아닌 `server/values/`에 둡니다.
- TLS, 인증/프록시 정책, NetworkPolicy 검토 없이 Loki, Tempo, Mimir, Pyroscope 수집 엔드포인트를 노출하지 않습니다.
- 스토리지 bucket 이름, 보존 기간, 복제, CRD, Secret 참조는 운영 영향 변경으로 취급합니다. 이러한 변경에는 백업·마이그레이션·롤백 근거를 포함합니다.
- 커밋 전 영향받는 모든 환경에 맞는 YAML 검증과 Helm 렌더링을 실행합니다.

## 미검증 대상 운영 계약

- `stg`/`prd`는 실제 EKS API CIDR, Gateway/listener, base domain, Vault AWS KMS key ARN, IRSA role ARN, 외부 S3 bucket 및 Kafka/Redpanda endpoint가 주입되기 전에는 Argo CD Sync를 수행하지 않습니다. 수동 Sync 직전에 `make preflight-server ENV=stg|prd`를 실행합니다.
- Kind는 최소 복제본과 임시 Vault 상태를 사용하는 개발 검증 환경이다. Vault HA·KMS auto-unseal, S3/Kafka 장애, 백엔드 복제/zone-aware 구성, 백업·복구, 보존·수명주기, 부하·장시간 soak test는 실제 환경에서 별도 검증합니다.
- 브라우저 OIDC는 Let's Encrypt 인증서가 적용된 실제 도메인과 테스트 계정이 준비되기 전까지 UI 로그인 검증 대상이 아니다. 그 전에는 HTTPS redirect, Keycloak discovery, Grafana/AWX/Argo CD API 및 Gateway 인증 정책만 검증합니다.
- Gateway 서버 TLS·Basic Auth의 갱신·폐기·장애 복구 절차는 운영 CA와 실제 agent 대상에서 검증해야 합니다. 수집 클라이언트 인증서는 사용하지 않습니다.
