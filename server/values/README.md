# 서버 values 계약

`common.yaml`은 모든 환경이 공유하는 Argo CD Application, 고정 차트 버전, 기본 리소스 설정을 정의합니다. `server/env/<환경>/values.yaml`은 공통값을 오버레이하여 Git revision, Gateway 참조, Vault Kubernetes Auth role, 공개 호스트명, MinIO·Redpanda 활성화 상태, 운영 S3 endpoint와 복제본 수를 설정합니다.

Vault의 실제 값은 Git에 저장하지 않습니다. 다음 경로와 키는 ExternalSecret 계약이며, 배포 전 기존 Vault에 준비해야 합니다.

| Vault 경로 | Kubernetes Secret | 필수 키 |
| --- | --- | --- |
| `monitoring/keycloak` | `keycloak/keycloak-admin` | `admin-password` |
| `monitoring/keycloak-postgresql` | `keycloak/keycloak-postgresql` | `password` |
| `monitoring/minio` | `minio/minio-root` | `root-user`, `root-password` |
| `monitoring/object-storage` | `observability/object-storage-credentials` | `access-key-id`, `secret-access-key` |
| `monitoring/awx` | `awx/awx-admin` | `admin-password` |
