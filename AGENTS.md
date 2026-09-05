# 저장소 기여 지침

## 적용 범위

이 저장소는 `FlyingSnake/MonitoringStack` GitHub 저장소를 관리합니다. `server/`에는 중앙 Kubernetes 플랫폼을 위한 GitOps 선언을, `agents/`에는 Ansible/Grafana Alloy 자동화를 둡니다.

## 공통 규칙

- 환경별 설정은 지정된 `values.yaml`에 두고, 공통 템플릿에 특정 환경을 하드코딩하지 않습니다.
- Helm 차트, 컨테이너 이미지, Ansible 컬렉션, 바이너리 버전을 고정합니다. 변동되는 `latest` 태그를 사용하지 않습니다.
- 평문 자격증명, 개인키, 토큰, kubeconfig, 복호화된 SOPS 파일을 커밋하지 않습니다. External Secrets 참조 또는 암호화된 SOPS 파일을 사용합니다.
- 리소스는 멱등적으로 작성하고, 가능한 경우 `app.kubernetes.io/managed-by` 같은 소유 레이블을 선언합니다.
- 작고 독립적으로 배포할 수 있는 변경을 우선합니다. 저장소·스키마·CRD·자격증명을 변경할 때는 pull request에 마이그레이션과 롤백 영향을 설명합니다.
- 커밋 전 변경 대상에 맞는 YAML, Helm 렌더링, Ansible 문법, Alloy 설정을 검증합니다.

## GitOps 규칙

- 지속적인 서버 배포 변경은 대화형 Helm 명령이 아니라 Argo CD가 동기화합니다.
- AWX 프로젝트, 인벤토리, Job Template, 플레이북은 Git으로 관리하며 문서화되지 않은 UI 전용 설정에 의존하지 않습니다.
- 환경 승격은 `dev` 브랜치 → `stg` 브랜치 → `main` 브랜치(운영) 순서입니다. 검토 없이 운영 값을 하위 환경에 복사하지 않습니다.

영역별 추가 규칙은 가장 가까운 하위 `AGENTS.md`를 확인합니다.

## 미검증 항목과 실행 전제

- Windows Alloy은 선언·정적 검사까지 구현되어 있다. 실제 실행 전에는 WinRM 대상, AWX Machine Credential용 ExternalSecret, 신뢰 가능한 mTLS 인증서 체인, Alloy 설치 파일의 공식 SHA-256을 준비하고 설치·업그레이드·서비스 재시작·Event Log·수집을 검증한다.
- 로컬 Linux 검증 fixture는 Docker 기반 systemd/SSH 컨테이너다. 실제 배포 전에는 대상 OS 배포판, kernel, SELinux/AppArmor, 프록시·DNS, eBPF 권한을 포함한 실제 Linux 호스트에서 재검증한다.
- ARM64 .NET은 프로파일러 wrapper가 없는 경우 로그·메트릭·트레이스만 수집하도록 설계되어 있다. 해당 아키텍처의 프로파일 수집은 지원 artifact가 준비된 뒤 별도로 검증한다.
- 브라우저 OIDC 로그인은 Let's Encrypt 인증서가 적용된 실제 도메인과 테스트 계정이 준비된 뒤 수행한다. 그 전까지 HTTPS·OIDC discovery·API 검증만 수행한다.
- `stg`/`prd`는 EKS Gateway, KMS, IRSA, 외부 S3/Kafka와 실제 도메인 입력이 없으면 Sync하지 않는다. `make preflight-server ENV=stg|prd`가 모든 계약값을 통과한 뒤에만 수동 Sync한다.
- Kind 단일 노드·최소 복제본 검증은 HA, 장애조치, 부하·내구성, 백업·복구, 보존·수명주기 검증을 대체하지 않는다. 운영 전 별도 환경에서 이 항목들을 수행한다.
