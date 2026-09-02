# Git 브랜치 전략

## 목적

이 저장소는 Git 변경이 Argo CD와 AWX의 배포 입력이므로, 브랜치는 코드 작업 단위이면서 환경별 승인 상태를 나타낸다. 복잡한 Git-flow 대신 **짧은 작업 브랜치 + 환경 승격 브랜치**를 사용한다.

## 영구 브랜치

| 브랜치 | 역할 | 연결 환경 | 변경 방법 |
| --- | --- | --- | --- |
| `dev` | 개발 통합 기준선 | `dev` | 작업 브랜치 pull request를 병합 |
| `stg` | 스테이징 승인 상태 | `stg` | `dev`에서 승격 pull request를 병합 |
| `main` | 운영 승인 상태 및 기본 브랜치 | `prd` | `stg`에서 승격 pull request를 병합 |

Argo CD Application은 환경에 따라 `targetRevision`을 각각 `dev`, `stg`, `main`으로 설정한다. 환경별 경로는 계속 `server/env/<환경>` 및 `agents/env/<환경>`를 사용한다. 즉, 브랜치는 **어느 변경 집합을 배포할지**, 디렉터리는 **환경별 설정값**을 담당한다.

## 작업 브랜치와 pull request

작업은 항상 최신 `dev`에서 만들고, 완료 후 `dev`로 pull request를 생성한다.

```text
feature/<간단한-설명>  # 기능 추가
fix/<간단한-설명>      # 버그 수정
chore/<간단한-설명>    # 문서·도구·정리 작업
```

- 작업 브랜치는 수명이 짧아야 하며, 병합 뒤 삭제한다.
- pull request는 최소 한 명의 승인과 CI 성공 후 squash merge한다.
- Helm 차트·이미지·Alloy·Ansible 컬렉션의 고정 버전 변경, CRD, 저장소, retention, 인증 설정 변경은 영향과 롤백 방법을 pull request에 기록한다.
- 평문 비밀값, 개인키, 토큰, kubeconfig는 어떤 브랜치에도 커밋하지 않는다.

## 승격 흐름

```text
feature/fix/chore ──PR──► dev (dev) ──승격 PR──► stg (stg) ──승격 PR──► main (prd)
```

1. `dev` 병합 후 개발 환경에 수동 Sync하고, CI와 관측성 smoke test를 통과시킨다.
2. 검증한 정확한 `dev` 커밋만 `stg`로 pull request를 만들어 승격한다. 스테이징 배포와 테스트를 완료한다.
3. 승인한 `stg` 커밋만 `main`으로 pull request를 만들어 운영에 승격한다. 모든 환경은 변경 창과 승인 절차에 따라 수동 Sync한다.
4. 각 prd 배포 성공 시 `main`의 해당 커밋에 주석 태그 `v<주.부.수>`를 생성한다.

환경 승격 pull request에서는 대상 환경의 `values.yaml`만 필요할 때 수정할 수 있다. 기능 변경을 승격 PR에서 추가하지 않으며, 대상 브랜치에만 존재하는 환경 설정은 다음 승격 시 충돌 여부를 반드시 확인한다.

## 긴급 수정과 롤백

긴급 수정은 최신 `main`에서 `hotfix/<간단한-설명>` 브랜치를 만들어 `main`으로 먼저 pull request를 병합한다. 이후 같은 커밋을 `stg`, `dev`로 역병합하여 브랜치가 다시 수렴하게 한다.

배포 실패 시 우선 Argo CD에서 이전의 검증된 Git revision으로 되돌리거나, 해당 승격 pull request의 revert pull request를 만든다. 보호 브랜치에는 force push와 히스토리 재작성을 하지 않는다.

## GitHub 보호 규칙

`dev`, `stg`, `main`에 다음 규칙을 적용한다.

- 직접 push 금지 및 pull request 필수
- 최신 기준 브랜치 반영 요구
- CI 필수 통과: YAML/Helm, Ansible, Alloy, 비밀값 검사
- 승인 1명 이상 요구 (`main`은 CODEOWNERS 또는 운영 승인자 지정 권장)
- force push와 브랜치 삭제 금지
- 병합 후 작업 브랜치 자동 삭제

## 초기 적용 순서

1. `main`을 기본 브랜치로 유지한다.
2. 현재 `main` 커밋에서 `dev`, `stg`를 생성한다.
3. GitHub에서 세 영구 브랜치의 보호 규칙을 적용한다.
4. Argo CD Application의 환경별 `targetRevision`을 이 문서의 매핑대로 구현한다.
