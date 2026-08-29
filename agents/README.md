# 에이전트 및 Grafana Alloy

`agents/`는 AWX가 Linux, Windows, Kubernetes 대상에 Grafana Alloy를 배포하고 설정하는 방식을 정의합니다. Alloy는 로그, 메트릭, 트레이스, 지원되는 프로파일링 데이터를 `server/`의 중앙 스택으로 전달합니다.

## 환경 설정

대상마다 하나의 환경 values 파일을 사용합니다.

```text
agents/env/<environment>/<target>/values.yaml
```

`<environment>`는 `dev`, `stg`, `prd`이고 `<target>`은 `linux`, `windows`, `k8s`입니다. 각 파일은 활성화 여부, 인벤토리 소스, 고정된 Alloy 버전, 원격 설정 리비전, 엔드포인트 참조, 레이블, 리소스 제한, Secret 참조를 제어합니다.

## 계획된 구조

```text
agents/
├── ansible/
│   ├── inventories/  # Git으로 관리하는 AWX 인벤토리 소스
│   ├── playbooks/    # 환경/대상별 배포 진입점
│   └── roles/        # 멱등적인 Alloy 설치 및 수명주기 role
├── alloy/
│   ├── bootstrap/    # 로컬 최소 import.git 구성
│   └── modules/      # 원격 재사용 Alloy declare 모듈
└── env/              # 환경 및 대상별 values
```

AWX는 이 Git 저장소에서 프로젝트를 동기화해야 합니다. 인벤토리 내용과 Ansible 코드는 함께 검토·버전 관리합니다. 호스트에는 최소 로컬 Alloy bootstrap 설정만 유지하고, 수집 파이프라인은 `import.git`으로 이 저장소에서 가져옵니다.

엔드포인트, 보안, 배포 세부 사항은 [../IMPLEMENTATION_PLAN.md](../IMPLEMENTATION_PLAN.md)를 참고하세요.
