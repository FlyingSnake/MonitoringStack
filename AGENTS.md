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
