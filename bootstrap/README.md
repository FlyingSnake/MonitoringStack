# Argo CD 부트스트랩

Argo CD 자신은 Argo CD가 없기 때문에 최초 한 번만 Helm으로 설치합니다. 이후에는 이 저장소의 Root Application이 모든 변경을 관리합니다.

```bash
ENVIRONMENT=dev ./bootstrap/install-argocd.sh
kubectl apply -f bootstrap/root-applications/dev.yaml
```

`ENVIRONMENT`는 `dev`, `stg`, `prd` 중 하나입니다. 실행 전 해당 환경의 Gateway, Vault, S3 관련 값을 `server/env/<환경>/values.yaml`에 채워야 합니다.
