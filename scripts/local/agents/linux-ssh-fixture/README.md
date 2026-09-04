# 로컬 Linux Alloy 검증 대상

이 fixture는 AWX가 SSH로 접속해 Linux Alloy를 설치·구성하는 경로를 검증합니다. AWX 실행 Pod는 Vault Kubernetes Auth로 로그인해 수집 Basic Auth와 `monitoring-client` PKI 단기 인증서를 발급받고, 대상의 `/etc/alloy/credentials`에 제한 권한으로 배포합니다. 일회성 SSH 키는 `.state/`와 Kubernetes `awx/monitoring-linux-test-ssh` Secret에만 존재하며 Git에는 저장되지 않습니다. `destroy.sh`는 컨테이너, 전용 프로파일 송신기, Kubernetes Secret, AWX Machine Credential, 로컬 SSH 키를 함께 정리합니다.

```bash
./scripts/local/agents/linux-ssh-fixture/create.sh
# local GitOps Application을 다시 적용·awx-config를 수동 Sync한 뒤
# AWX의 "Install Alloy - local Linux fixture" Job을 실행합니다.
./scripts/local/agents/linux-ssh-fixture/verify.sh
./scripts/local/agents/linux-ssh-fixture/destroy.sh
```

컨테이너는 로컬 호스트 TCP 2222만 사용하며, Gateway 수집 도메인과 local Git daemon은 `host-gateway`로 해석합니다.

`verify.sh`는 Alloy systemd 상태와 credential 파일 권한을 확인합니다. 로그·메트릭·트레이스 전송은 Alloy journal과 backend query로, 프로파일 전송은 전용 `linux-alloy-fixture-profile` 서비스명을 가진 임시 송신기로 확인합니다.
