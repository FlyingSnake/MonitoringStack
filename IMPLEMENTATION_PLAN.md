# Grafana OSS 관측성 스택 GitOps 구현 현황 및 계획

## 현재 구현 현황

`dev` 브랜치에는 중앙 서버와 AWX 기반 Alloy 배포의 1차 구현이 반영되어 있다. Argo CD는 자동 Sync를 사용하지 않으며, 각 Application을 sync wave 순서로 수동 동기화한다.

| 영역 | 구현·검증 상태 |
| --- | --- |
| GitOps 기반 | Argo CD bootstrap, AppProject, 환경별 `targetRevision`, local Git daemon 기반 Kind 소스 검증 완료 |
| 보안·인증 | Vault, External Secrets, Vault PKI, Gateway UI/수집 listener, 수집 mTLS + HTTP Basic Auth 구현 및 로컬 회귀 검증 완료 |
| 인증·UI | Keycloak realm/client 선언, Grafana·Argo CD·AWX OIDC 설정 선언 및 Grafana datasource CR 등록 완료 |
| 저장소·큐 | dev MinIO와 Redpanda, Loki/Mimir/Tempo/Pyroscope의 S3·Kafka 연결 구현 완료 |
| 관측성 | Grafana Operator, Loki Distributed, Mimir, Tempo, Pyroscope, blackbox exporter, 서버 Alloy를 Kind 단일 복제본으로 검증 완료 |
| Kubernetes Alloy | AWX → Vault Kubernetes Auth → 단기 인증서/Basic Auth Secret → Alloy DaemonSet 흐름 검증 완료 |
| Linux Alloy | AWX → SSH fixture → Vault PKI → systemd Alloy 배포와 로그·메트릭·트레이스·프로파일 전송 검증 완료 |
| Windows Alloy | 인벤토리·Job Template·Ansible 역할·Vault credential 계약 구현 및 정적 검증 완료. 실제 WinRM 대상 검증 대기 |
| .NET 워크로드 | 멀티 아키텍처 초기화와 ARM64 graceful fallback 구현. ARM64 Kind에서 로그·메트릭·트레이스 검증 완료, 프로파일은 wrapper 제공 전까지 보류 |

### 현재 후속 작업

- 실제 Windows WinRM 대상에서 Alloy 설치·업그레이드와 Event Log 수집을 검증한다.
- 신뢰할 수 있는 로컬 CA 또는 테스트 계정을 제공한 뒤 Grafana 브라우저 Keycloak 로그인과 datasource Explore 조회를 수행한다.
- x86_64 Linux 또는 ARM64 ApiWrapper를 제공하는 Pyroscope .NET profiler 릴리스에서 .NET 프로파일을 검증한다.
- `stg`/`prd`의 실제 EKS, KMS/IRSA, Gateway, 외부 S3·Kafka 입력값이 준비된 뒤 `make preflight-server ENV=<환경>`을 통과시켜 수동 Sync한다.

## 1. 목표와 범위

이 저장소(`FlyingSnake/MonitoringStack`)는 Kubernetes 기반 중앙 관측성 서버와 Linux, Windows, Kubernetes 에이전트를 하나의 GitOps 흐름으로 관리한다.

- 중앙 서버: 로그(Loki), 메트릭(Mimir), 트레이스(Tempo), 프로파일(Pyroscope), 시각화/운영(Grafana, Argo CD, Keycloak, AWX)을 Kubernetes에 배포한다.
- 에이전트: AWX가 Git으로 관리되는 인벤토리와 Ansible 플레이북을 실행하여 Grafana Alloy를 설치·업그레이드한다.
- 설정: 각 환경의 `values.yaml`이 배포 토폴로지, 엔드포인트, 리소스, 기능 활성화 여부를 제어한다.
- 구성 배포: Argo CD `Application`/`AppProject` CR을 Git에서 선언하고 운영자가 수동 동기화한다.
- 비밀값: Git에 평문으로 저장하지 않는다. SOPS+age 또는 External Secrets를 표준으로 삼고, 환경별 키/시크릿 참조만 Git에 둔다.

## 2. 권장 아키텍처

```text
                         GitHub: FlyingSnake/MonitoringStack
                                      │
                   ┌──────────────────┴──────────────────┐
                   │                                     │
        server/ GitOps 선언                        agents/ Ansible/Alloy 선언
                   │                                     │
      (초기 Helm bootstrap 후)                         AWX Project SCM sync
                   │                                     │
              Argo CD Application CRs ─────────────► AWX Job Template
                   │                                     │
     ┌─────────────┼─────────────────┐          ┌────────┴─────────┐
     │             │                 │          │                  │
 Keycloak      Grafana Operator    AWX      Linux/Windows      Kubernetes
     │             │                 │          Alloy             Alloy
     │          Grafana              │             │                 │
     └─────────────┴─────────────────┘             └───────┬─────────┘
                                                           │ TLS + 인증
                      ┌────────────────────────────────────┼───────────────────┐
                      │                │                   │                   │
                    Loki             Mimir               Tempo             Pyroscope
                   (logs)          (metrics)            (traces)          (profiles)
                      └────────────────────── S3 호환 Object Storage ───────────┘
                                         (MinIO: dev/stg 선택, prd: 외부 저장소 권장)
```

모든 수집 엔드포인트는 외부에 직접 노출하지 않고 Ingress/Gateway 뒤에서 TLS, Keycloak OIDC 또는 별도 인증 프록시, NetworkPolicy로 보호한다. Loki와 Tempo 자체에는 인증 계층이 없으므로 이 경계는 필수다.

## 3. 설계 결정

| 항목 | 결정 | 이유 |
| --- | --- | --- |
| GitOps 단위 | Argo CD App-of-Apps | 플랫폼 차트별 수명주기와 동기화 순서를 독립 관리 |
| Helm values | 차트별 공통 값 + 환경 오버레이 | 환경 값은 분리하되 중복을 줄임 |
| 저장소 | S3 호환 Object Storage | Loki/Tempo/Mimir/Pyroscope의 분산 구성에 공통 사용 |
| MinIO | dev/stg는 선택 가능, prd는 외부/관리형 S3 권장 | 단일 MinIO를 운영 데이터 내구성 경계로 쓰지 않음 |
| Alloy 구성 | 로컬 bootstrap + `import.git` 모듈 | 시작 설정은 안정적으로 남기고 파이프라인은 Git 변경으로 갱신 |
| 에이전트 실행 | AWX Job Template | 인벤토리, 자격증명, 승인, 실행 이력을 중앙 관리 |
| 비밀값 | SOPS/External Secrets | Argo CD와 Git 이력에 비밀을 노출하지 않음 |

> 주의: Loki의 과거 `loki-distributed` 차트 대신 현재 지원되는 `loki` 차트의 `deploymentMode: Distributed`를 사용한다. Simple Scalable 모드는 사용하지 않는다. Tempo의 microservices 구성에는 Kafka 호환 durable queue가 필요하므로 Kafka/Redpanda를 별도 의존성으로 명시한다.

## 4. 목표 저장소 구조

현재의 `agents/` 디렉터리명은 유지한다.

```text
.
├── README.md
├── IMPLEMENTATION_PLAN.md
├── bootstrap/
│   ├── argocd/                         # Argo CD Helm values 및 최초 설치 스크립트
│   └── root-application.yaml           # bootstrap 직후 한 번 적용하는 root Application
├── server/
│   ├── applications/                   # AppProject, Application/AppSet 템플릿
│   │   ├── platform/                   # Keycloak, External Secrets, ingress, cert-manager
│   │   ├── observability/              # Grafana, Loki, Tempo, Mimir, Pyroscope, blackbox
│   │   └── automation/                 # AWX Operator 및 AWX 인스턴스
│   ├── charts/                         # 이 저장소가 소유하는 얇은 wrapper Helm charts
│   ├── crds/                           # AWX/Grafana/Argo CR 정의 리소스
│   ├── env/
│   │   ├── dev/values.yaml
│   │   ├── stg/values.yaml
│   │   └── prd/values.yaml
│   └── values/                         # 환경 공통 defaults 및 차트별 values 조각
├── agents/
│   ├── ansible/
│   │   ├── inventories/{dev,stg,prd}/  # Git 관리 static inventory 또는 inventory source
│   │   ├── playbooks/                  # install-alloy-linux/windows/kubernetes.yaml
│   │   ├── roles/grafana_alloy/
│   │   └── collections/requirements.yaml
│   ├── alloy/                          # Alloy import.git 대상 모듈
│   │   ├── modules/{common,linux,windows,kubernetes}/
│   │   └── bootstrap/
│   └── env/
│       ├── dev/{linux,windows,k8s}/values.yaml
│       ├── stg/{linux,windows,k8s}/values.yaml
│       └── prd/{linux,windows,k8s}/values.yaml
└── secrets/                            # 암호화된 SOPS 파일만 허용
```

## 5. 서버 구현 계획

### 5.1 Bootstrap

1. `bootstrap/argocd`에 Argo CD Helm values를 만든다. HA 여부, Ingress, OIDC(Keycloak), repository credential template, SOPS 플러그인/Secret 접근 권한을 환경 값으로 제어한다.
2. 클러스터에 Argo CD CRD와 Argo CD Helm chart를 한 번 설치한다. 이는 Argo CD가 아직 존재하지 않아 자기 자신을 배포할 수 없는 유일한 bootstrap 단계다.
3. `bootstrap/root-application.yaml`을 적용해 `server/applications`를 Argo CD가 관리하게 한다. 이후 변경은 Git commit만으로 반영한다.

### 5.2 Argo CD 계층과 동기화 순서

`AppProject`는 `platform`, `observability`, `automation`으로 분리하고, 차트 버전은 모두 고정한다. 모든 환경은 자동 동기화 없이 운영자가 sync wave 순서에 따라 수동 Sync하며, `prune`은 마이그레이션·삭제 영향 검토 후에만 사용한다.

1. `00-prerequisites`: namespace, CRD, External Secrets/SOPS, cert-manager, ingress/gateway, StorageClass/NetworkPolicy
2. `10-identity`: Keycloak 및 OIDC client/realm 초기 설정
3. `20-storage`: MinIO(필요 환경만), S3 bucket/credential Secret, Kafka/Redpanda(Tempo distributed 선택 시)
4. `30-observability`: Grafana Operator와 `Grafana`/datasource/dashboard CR, Loki, Tempo, Mimir, Pyroscope, blackbox exporter
5. `40-automation`: AWX Operator, `AWX` CR, AWX Project/Inventory/Credential/JobTemplate 설정

차트는 Argo CD `Application.spec.sources`의 multi-source 기능 또는 저장소 내부 wrapper chart로 환경 values를 결합한다. 각 `Application`이 `server/env/<env>/values.yaml`의 해당 차트 블록만 사용하도록 설계해 모든 설정을 한 파일에서 제어한다.

### 5.3 중앙 서비스별 기준

- **Keycloak**: PostgreSQL(운영은 HA/백업 포함), realm/client/role은 Git 선언 또는 관리 Job으로 초기화한다. Grafana, Argo CD, AWX에 OIDC를 연결한다.
- **Object Storage**: 서비스별 bucket을 분리(`loki`, `tempo`, `mimir`, `pyroscope`)하고 lifecycle/retention/암호화 정책을 지정한다. MinIO는 환경 플래그가 참일 때만 배포한다.
- **Grafana Operator**: Grafana 인스턴스, `GrafanaDatasource`, `GrafanaDashboard`, alerting 리소스를 CR로 관리한다. Loki/Mimir/Tempo/Pyroscope datasource를 자동 생성한다.
- **Loki**: `deploymentMode: Distributed`, TSDB schema, replication, gateway, compactor, ruler, object storage를 설정한다.
- **Tempo**: distributed chart + Kafka 호환 큐 + object storage, OTLP gRPC/HTTP receiver, metrics-generator를 설정한다.
- **Mimir**: distributed chart + object storage, ruler/alertmanager/compactor/store-gateway/ingester resource와 tenancy/limits를 설정한다.
- **Pyroscope**: distributed chart + object storage, ingestion/query frontend/compactor를 설정한다.
- **Blackbox exporter**: HTTP/HTTPS, TCP, ICMP, DNS probe 모듈과 Mimir scrape 구성을 배포한다.
- **AWX**: AWX Operator와 PostgreSQL/Redis, TLS ingress, Keycloak OIDC, 실행 환경(필요 collection 포함)을 선언한다.

## 6. 에이전트 및 Alloy 구현 계획

### 6.1 환경별 values 계약

각 `agents/env/<env>/<target>/values.yaml`에는 적어도 아래 값을 둔다.

```yaml
environment: dev
target: linux # linux | windows | k8s
enabled: true
inventory:
  source: agents/ansible/inventories/dev/linux/hosts.yml
alloy:
  version: "<pinned-version>"
  config:
    repository: https://github.com/FlyingSnake/MonitoringStack.git
    revision: dev
    modulePath: agents/alloy/modules/linux/alloy.alloy
    pullFrequency: 5m
endpoints:
  loki: https://loki.example.internal/loki/api/v1/push
  mimir: https://mimir.example.internal/api/v1/push
  tempo: https://tempo.example.internal
  pyroscope: https://pyroscope.example.internal
security:
  tlsSecretRef: alloy-client-tls
  authSecretRef: alloy-write-credentials
```

실제 비밀값은 `authSecretRef`로만 참조한다. 환경별 URL, 테넌트 ID, 레이블, resource limit, 수집 기능 로그/메트릭/트레이스/프로파일 활성화 여부도 values로 제어한다.

### 6.2 AWX 관리 모델

1. Argo CD가 AWX Operator 및 AWX CR을 배포한다.
2. AWX의 Project는 이 저장소의 `agents/ansible`을 SCM source로 사용한다.
3. 환경·대상별 Git inventory를 AWX Inventory Source로 동기화한다. 동적 인벤토리가 필요하면 inventory plugin 구성도 Git으로 관리한다.
4. AWX Credential에는 SSH 키(Linux), WinRM 인증서/계정(Windows), Kubernetes credential을 분리 저장한다.
5. `install-alloy-linux`, `install-alloy-windows`, `install-alloy-kubernetes` Job Template를 만들고 inventory/credential/extra vars를 연결한다.
6. `awx.awx` collection을 이용한 AWX objects 선언 playbook을 idempotent하게 작성하고, Argo CD post-sync Job 또는 운영 승인 Job으로 적용한다.

### 6.3 대상별 Alloy 배포

- **Linux**: Ansible role이 패키지/바이너리, systemd unit, 최소 bootstrap 설정, CA/인증서를 설치한다. journald와 파일 로그, host metrics, OTLP 수신, eBPF 프로파일링(지원 커널만)을 모듈로 분리한다.
- **Windows**: Ansible WinRM으로 MSI/ZIP과 Windows service를 설치한다. Windows Event Log, IIS/서비스 지표, OTLP 수신을 설정한다. 프로파일링은 지원되는 런타임과 권한을 사전 검증한다.
- **Kubernetes**: AWX Job이 Helm/Kubernetes collection으로 Alloy DaemonSet(노드 로그·kubelet/cAdvisor)과 Deployment(클러스터 이벤트·singleton scrape)를 배포한다. Kubernetes Monitoring Helm chart를 사용한다면 동일 역할과 중복 수집되지 않도록 단일 방식을 선택한다.

### 6.4 `import.git` 구성 관리

각 호스트에는 작고 변경이 드문 로컬 `config.alloy`만 둔다. 이 파일은 `import.git`으로 이 저장소의 환경/대상 모듈을 주기적으로 가져오고, 모듈은 `declare` 블록만 포함한다. private repository 접근 토큰은 OS/Kubernetes Secret에 설치하고 Git에 넣지 않는다. 모듈 변경은 PR → CI lint/test → 환경 브랜치 병합 → Alloy pull 주기의 흐름으로 반영된다.

## 7. 검증 및 CI/CD

PR마다 다음을 실행한다.

1. YAML schema/format 검증, Helm `lint` 및 환경별 `helm template`.
2. Argo Application manifest schema 검증과 `argocd app diff`(가능한 환경).
3. Ansible `ansible-lint`, inventory parse, `--check` 및 Molecule(가능한 역할).
4. `alloy fmt` 및 `alloy run`/syntax 검증으로 `agents/alloy` 모듈 테스트.
5. SOPS 평문/토큰/개인키 탐지 및 정책 검사.
6. `dev` 수동 Sync → smoke test(각 endpoint write/read, Grafana datasource, AWX job) → `stg` 승인·수동 Sync → `main`(prd) 승인·수동 Sync 순으로 승격.

운영 확인 항목은 수집 성공률, remote-write 오류, object storage 용량, compactor/ring 상태, Alloy configuration reload, AWX job 결과, 인증서 만료를 포함한다.

## 8. 단계별 구현 순서

1. **기반 골격**: 완료. 디렉터리, `.gitignore`, README, Makefile/task runner, YAML·Helm·Ansible 검증을 추가했다.
2. **Argo CD bootstrap**: 완료. 환경 values, Argo CD Helm values, Root Application, AppProject와 local Git source를 구현했다.
3. **공통 인프라**: 완료(dev/local). Vault, cert-manager, External Secrets, Keycloak, MinIO, Redpanda, Gateway·NetworkPolicy를 구현했다.
4. **관측성 백엔드**: 완료(dev/local). Grafana Operator/Grafana, Loki, Mimir, Tempo, Pyroscope, blackbox와 서버 Alloy를 배포·검증했다.
5. **AWX**: 완료(dev/local). AWX Operator/AWX CR, 실행 환경, SCM Project, Git inventory, 선언형 Job Template을 구현했다.
6. **Ansible/Alloy**: Kubernetes와 Linux 실제 검증 완료, Windows는 선언형 구현·정적 검증 완료 상태다.
7. **보안·운영화**: mTLS·Basic Auth·Vault PKI·기본 NetworkPolicy는 완료했다. Windows 실대상, 백업/복구, retention·alerting/dashboard 확장, 부하·장애 테스트는 후속 작업이다.

## 9. 구현 전 확정할 운영 입력값

코드를 시작하기 전에 아래 값은 환경별로 확정해야 한다.

- Kubernetes 배포판/버전, 노드 수·가용 영역, StorageClass, Ingress 또는 Gateway API
- 도메인/TLS 발급 방식과 내부·외부 네트워크 경계
- S3 제공자와 bucket lifecycle, 보존 기간, 예상 일별 수집량/테넌트 수
- Tempo distributed를 위한 Kafka/Redpanda 운영 방식
- Linux SSH·Windows WinRM·Kubernetes 접근 방식 및 AWX credential 보관 방식
- 프로파일링 대상 언어/런타임과 eBPF 사용 가능 커널/권한
- dev/stg/prd의 HA, 리소스, 수동 Sync 절차 및 변경 승인 정책

## 참고한 공식 문서

- [Argo CD Declarative Setup](https://argo-cd.readthedocs.io/en/release-3.2/operator-manual/declarative-setup/), [Helm 지원](https://argo-cd.readthedocs.io/en/latest/user-guide/helm/), [Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Grafana Alloy 원격 구성 및 import.git](https://grafana.com/docs/alloy/latest/configure/load-remote-configuration/)
- [Loki Helm deployment modes](https://grafana.com/docs/loki/latest/setup/install/helm/concepts/)
- [Tempo Kubernetes/Helm 배포](https://grafana.com/docs/tempo/latest/set-up-for-tracing/setup-tempo/deploy/kubernetes/), [Tempo deployment modes](https://grafana.com/docs/tempo/latest/configuration/)
- [Tempo 메타 모니터링과 Alloy/Mimir/Grafana](https://grafana.com/docs/tempo/latest/operations/monitor/set-up-monitoring/)
