# Argo CD 부트스트랩

Argo CD 자신은 Argo CD가 없기 때문에 최초 한 번만 Helm으로 설치합니다. 이후에는 이 저장소의 Root Application이 모든 변경을 관리합니다.

```bash
ENVIRONMENT=dev ./bootstrap/install-argocd.sh
kubectl apply -f bootstrap/root-applications/dev.yaml
```

`ENVIRONMENT`는 `dev`, `stg`, `prd` 중 하나입니다. 실행 전 해당 환경의 Gateway, Vault, S3 관련 값을 `server/env/<환경>/values.yaml`에 채워야 합니다.

External Secrets CRD는 최초 설치 시 server-side apply가 필요합니다. 따라서 Argo CD 설치 전에 다음을 한 번 실행합니다.

```bash
./bootstrap/install-external-secrets-crds.sh
```

Root Application과 하위 Application은 자동 동기화하지 않습니다. 환경별 sync wave 순서에 따라 Argo CD UI 또는 API에서 수동 Sync하고, `stg`/`prd`는 먼저 `make preflight-server ENV=<환경>`을 통과해야 합니다. Kind에서는 `local/git-server/`를 시작·갱신한 뒤 `local/server/deploy-gitops.sh`를 사용합니다.
