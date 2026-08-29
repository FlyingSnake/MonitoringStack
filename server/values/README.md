# 서버 values 및 Vault 계약

`common.yaml`에는 고정된 Helm chart 버전, Argo CD Application sync wave, 공통 서비스 설정을 둡니다. `server/env/<환경>/values.yaml`은 Git revision, 도메인, 기존 Gateway listener, Vault 방식, 스토리지와 복제본만 오버레이합니다.

`dev`는 단일 Raft Vault를 운영자가 초기화·Unseal합니다. `stg`, `prd`는 EKS IRSA와 AWS KMS Auto-Unseal을 사용하며, `REQUIRED_*` 값은 실제 인프라 값으로 교체하기 전에는 배포하지 않습니다.

## Vault 초기 bootstrap

Vault 자체는 GitOps로 설치하지만 다음 작업은 root token 또는 recovery key가 필요하므로 운영자가 안전한 세션에서 수행합니다.

1. Vault를 초기화한다. dev는 Unseal key를 Git 외부의 비밀 저장소에 보관한다.
2. Kubernetes Auth를 활성화하고 External Secrets용 `monitoring-stack` role을 만든다.
3. KV v2 mount `monitoring/`과 PKI mount `pki_int/`를 만들고, cert-manager 및 AWX용 PKI role을 만든다.
4. 아래 key를 입력한 뒤 ExternalSecret이 `Ready` 상태인지 확인한다.

## 필수 KV 경로

| Vault KV 경로 | 대상 Secret | 필수 key |
| --- | --- | --- |
| `monitoring/keycloak` | `keycloak/keycloak-admin` | `admin-password` |
| `monitoring/keycloak-postgresql` | `keycloak/keycloak-postgresql` | `password` |
| `monitoring/oidc` | Keycloak/Grafana/AWX/Argo CD OIDC Secret | `argocd-client-secret`, `grafana-client-secret`, `awx-client-secret` |
| `monitoring/minio` | 각 backend `object-storage-credentials` | `access-key-id`, `secret-access-key` |
| `monitoring/awx` | `awx/awx-admin` | `admin-password` |
| `monitoring/ingestion` | 각 backend `ingestion-basic-auth` | `htpasswd` |
| `monitoring/pki` | Gateway `monitoring-ingest-ca` | `ingest-ca-crt` |

`ingestion.htpasswd`는 Envoy Gateway Basic Auth가 요구하는 SHA htpasswd 형식이다. Alloy에 제공하는 평문 사용자·암호와 PKI client certificate는 AWX credential/Vault PKI role로만 배포하며 Git에 저장하지 않는다.

## Gateway 계약

기존 Gateway는 두 HTTPS listener를 제공해야 합니다.

- `ui-https`: Grafana, Argo CD, Keycloak, AWX의 OIDC 브라우저 트래픽
- `ingest-https`: `*.ingest.<env>.<baseDomain>`의 Alloy 수집 트래픽. Envoy Gateway mTLS와 HTTP Basic Auth를 모두 적용

Gateway TLS Secret은 `monitoring-ui-tls`, `monitoring-ingest-tls`이며 cert-manager Vault Issuer가 갱신합니다. 운영 Gateway가 이미 존재하더라도 listener와 certificateRef는 이 이름을 참조하도록 준비해야 합니다.
