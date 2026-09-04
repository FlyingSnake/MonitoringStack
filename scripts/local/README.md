# 로컬 Kind 검증 스크립트

이 디렉터리는 Git으로 추적되는 로컬 검증 자동화 코드다. 개인별 values, Vault 초기화 자료, TLS 인증서, SSH 키, bare Git 저장소는 `local/`에만 두며 커밋하지 않는다.

## 준비

1. `scripts/local/server/values.example.yaml`을 `local/server/values.yaml`로 복사하고 Kind API endpoint, Gateway ClusterIP를 현재 Docker 네트워크에 맞춘다.
2. Docker Desktop을 시작한 뒤 `scripts/local/server/create-cluster.sh`, `scripts/local/server/install-gateway.sh`, `scripts/local/git-server/start.sh`, `scripts/local/server/deploy-gitops.sh`를 실행한다.
3. Argo CD Application을 수동 Sync하고 Vault가 Running 상태가 되면 `scripts/local/server/bootstrap-vault.sh`를 실행한다. 자동 Sync는 사용하지 않는다.

## 검증 명령

```bash
make local-status
make local-ui-api-smoke
make local-k8s-alloy-smoke
make local-linux-alloy-smoke
make local-telemetry-smoke
make local-telemetry-clean
```

`local-k8s-alloy-smoke`와 `local-linux-alloy-smoke`는 AWX Job Template을 실행한다. Linux smoke는 fixture SSH Secret을 런타임에 생성한 뒤 AWX Config Application을 수동 Sync하여 일회성 Machine Credential과 Template을 만들고, 종료 시 모두 정리한다.

`local-telemetry-smoke`는 .NET, Java, Go, Node.js 앱의 logs·metrics·traces를 모두 조회하고 Java·Go·Node.js profile 수집을 확인한다. ARM64에서는 .NET profile이 지원되지 않아 이를 성공 조건에서 제외한다.
