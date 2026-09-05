# 에이전트 영역 지침

- 인벤토리, 플레이북, role, AWX 객체 선언, Alloy 모듈을 Git에서 관리합니다. 필수 AWX UI 전용 변경을 만들지 않습니다.
- 모든 Ansible role은 멱등적으로 작성하고, 기반 패키지/서비스 모듈이 허용하면 check mode를 지원합니다.
- 대상별 동작은 `linux`, `windows`, `k8s` role/모듈에 두고, 공통 엔드포인트와 레이블 로직은 공통 코드에 둡니다.
- Grafana Alloy 버전을 고정하고, 환경별 values 파일에서 고정 설정 리비전 또는 승인된 브랜치 전략을 참조합니다.
- 로컬 Alloy bootstrap 파일에는 시작 수준 설정과 `import.git` 연결만 둡니다. 재사용 원격 모듈은 `declare` 블록만 사용해야 하며 전역 Alloy 구성 블록을 포함하지 않습니다.
- 엔드포인트 자격증명, Git 토큰, 클라이언트 인증서, SSH 키, WinRM 비밀번호, 복호화된 설정을 인벤토리·values 파일·Alloy 모듈에 쓰지 않습니다. AWX/Kubernetes/OS Secret 참조를 사용합니다.
- Linux 변경은 systemd를, Windows 변경은 Windows 서비스와 WinRM을 고려합니다. Kubernetes 변경은 다른 Alloy 배포와 수집이 중복되지 않도록 합니다.
- 커밋 전 영향받는 인벤토리 문법, Ansible 플레이북/role, Alloy 구성을 검증합니다.

## 미검증 대상 운영 계약

- Windows 인벤토리는 의도적으로 비어 있으며, 실제 WinRM 호스트가 준비될 때까지 플레이북을 실행하지 않습니다. 대상별 주소·인증 방식·서버 인증서 검증은 Inventory와 AWX Machine Credential ExternalSecret으로 주입하고, 사용자명·비밀번호·개인키는 Git에 기록하지 않습니다.
- 기본 WinRM 연결 계약은 HTTPS(5986)·서버 인증서 검증이다. 도메인 Kerberos 등으로 transport를 바꿔야 하면 승인된 host_vars/환경 overlay에서만 변경하며, `ansible_winrm_server_cert_validation: ignore`를 사용하지 않습니다.
- Windows AWX Credential은 `awx.windowsCredential.enabled`를 활성화하고 `platform-secrets.additionalExternalSecrets`로 Vault KV의 WinRM `username`·`password`를 `monitoring-windows-winrm` Secret에 동기화한 경우에만 Job Template에 연결됩니다. 실제 적용 전에는 Alloy 설치 파일의 공식 SHA-256을 `alloy_installer_checksum`으로 주입합니다.
- Windows에서 수행할 후속 검증은 설치/업그레이드 롤백, Alloy Windows Service 재시작, ACL·Registry 환경변수 보호, Windows Event Log·Windows exporter·OTLP 및 mTLS+Basic Auth 수집입니다.
- Linux Docker fixture 검증은 실제 호스트 검증을 대체하지 않습니다. 실제 Linux 대상에서는 배포판, systemd, 권한, 프록시/DNS, eBPF·프로파일링 지원 여부를 확인합니다.
- .NET ARM64 프로파일러는 지원 wrapper/artifact가 준비될 때까지 graceful fallback만 허용하며, 실제 profile 수집 검증 대상에서 제외합니다.
