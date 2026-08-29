# 에이전트 영역 지침

- 인벤토리, 플레이북, role, AWX 객체 선언, Alloy 모듈을 Git에서 관리합니다. 필수 AWX UI 전용 변경을 만들지 않습니다.
- 모든 Ansible role은 멱등적으로 작성하고, 기반 패키지/서비스 모듈이 허용하면 check mode를 지원합니다.
- 대상별 동작은 `linux`, `windows`, `k8s` role/모듈에 두고, 공통 엔드포인트와 레이블 로직은 공통 코드에 둡니다.
- Grafana Alloy 버전을 고정하고, 환경별 values 파일에서 고정 설정 리비전 또는 승인된 브랜치 전략을 참조합니다.
- 로컬 Alloy bootstrap 파일에는 시작 수준 설정과 `import.git` 연결만 둡니다. 재사용 원격 모듈은 `declare` 블록만 사용해야 하며 전역 Alloy 구성 블록을 포함하지 않습니다.
- 엔드포인트 자격증명, Git 토큰, 클라이언트 인증서, SSH 키, WinRM 비밀번호, 복호화된 설정을 인벤토리·values 파일·Alloy 모듈에 쓰지 않습니다. AWX/Kubernetes/OS Secret 참조를 사용합니다.
- Linux 변경은 systemd를, Windows 변경은 Windows 서비스와 WinRM을 고려합니다. Kubernetes 변경은 다른 Alloy 배포와 수집이 중복되지 않도록 합니다.
- 커밋 전 영향받는 인벤토리 문법, Ansible 플레이북/role, Alloy 구성을 검증합니다.
