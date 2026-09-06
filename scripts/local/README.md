# 로컬 Kind 검증 스크립트

이 디렉터리는 Git으로 추적되는 로컬 검증 자동화 코드다. 개인별 values, Vault 초기화 자료, TLS 인증서, SSH 키, bare Git 저장소는 `local/`에만 두며 커밋하지 않는다.

## 준비

1. `scripts/local/server/values.example.yaml`을 `local/server/values.yaml`로 복사하고 Kind API endpoint, Gateway ClusterIP를 현재 Docker 네트워크에 맞춘다. Let’s Encrypt 인증서는 기본적으로 `local/letsencrypt/config/live/demo.flyingsnake.xyz/{fullchain.pem,privkey.pem}`에서 읽는다.
2. Docker Desktop을 시작한 뒤 `scripts/local/server/create-cluster.sh`, `scripts/local/server/install-gateway.sh`, `scripts/local/git-server/start.sh`, `scripts/local/server/deploy-gitops.sh`를 실행한다.
3. Argo CD Application을 수동 Sync하고 Vault가 Running 상태가 되면 `scripts/local/server/bootstrap-vault.sh`를 실행한다. 자동 Sync는 사용하지 않는다. 로컬 Vault가 비영속 상태로 초기화된 경우에도 이 스크립트는 기존 ExternalSecret target Secret의 Keycloak·PostgreSQL·MinIO·AWX·Alloy 수집 자격증명을 새 Vault에 먼저 복원한다. 따라서 실행 중인 stateful 서비스와 자격증명이 불일치하지 않는다. 처음 설치처럼 target Secret이 없을 때만 새 값을 생성한다. 이후 `platform-secrets`를 동기화하고 `make local-k8s-alloy-smoke`로 Alloy가 갱신된 Basic Auth 자격증명을 읽도록 다시 배포한다.
4. `platform-identity`를 동기화한다. `keycloak-config` Hook은 Keycloak이 생성한 confidential OIDC client secret을 Vault에 기록한다. 그 뒤 `platform-secrets`를 한 번 더 동기화해야 Grafana·Argo CD·AWX가 같은 client secret을 ExternalSecret으로 받는다. 이 순서는 OIDC client secret을 Git이나 values에 저장하지 않기 위한 계약이다.

로컬 데모는 인증서의 `*.demo.flyingsnake.xyz` SAN에 맞춰 `grafana`, `argocd`, `keycloak`, `awx`, `loki-ingest`, `mimir-ingest`, `tempo-ingest`, `pyroscope-ingest` 호스트를 사용한다. Gateway를 통해 127.0.0.1로 검증할 때도 curl의 `--resolve`가 인증서 hostname을 유지한다.

로컬 values에서만 `monitoring` realm의 초기 `platform-admin` 사용자를 활성화한다. 사용자명과 비밀번호는 Vault → ExternalSecret → `keycloak/keycloak-bootstrap-user` Secret 흐름으로 주입되며 Git에는 저장하지 않는다. 비밀번호는 필요할 때만 다음 명령으로 로컬 클러스터에서 확인한다.

```bash
kubectl -n keycloak get secret keycloak-bootstrap-user -o jsonpath='{.data.password}' | base64 -d; echo
```

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
