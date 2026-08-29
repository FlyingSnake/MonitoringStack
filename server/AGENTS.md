# 서버 영역 지침

- 장기 운영 서버 워크로드 변경은 Argo CD 리소스로 렌더링·동기화해야 합니다. 직접 `helm install`은 문서화된 최초 Argo CD 부트스트랩에만 허용됩니다.
- `Application` 동기화 순서를 명시합니다. 순서는 기반 리소스 → 인증/저장소 → 관측성 → AWX 자동화입니다.
- 독립 운영 서비스마다 별도 namespace, release 이름, Argo CD Application을 사용합니다.
- 소스 차트 버전을 고정하고 `targetRevision`에는 불변 버전을 설정합니다. 차트의 `main` 또는 `latest`를 추적하지 않습니다.
- 환경 차이는 `server/env/<environment>/values.yaml`로 처리합니다. 공통 기본값은 복제된 매니페스트가 아닌 `server/values/`에 둡니다.
- TLS, 인증/프록시 정책, NetworkPolicy 검토 없이 Loki, Tempo, Mimir, Pyroscope 수집 엔드포인트를 노출하지 않습니다.
- 스토리지 bucket 이름, 보존 기간, 복제, CRD, Secret 참조는 운영 영향 변경으로 취급합니다. 이러한 변경에는 백업·마이그레이션·롤백 근거를 포함합니다.
- 커밋 전 영향받는 모든 환경에 맞는 YAML 검증과 Helm 렌더링을 실행합니다.
