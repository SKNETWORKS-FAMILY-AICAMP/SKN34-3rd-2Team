# AI 취업 코치 프로젝트 통합 테스트 보고서

- 실행일: 2026-09-02
- 브랜치: `feature/job-matching-bot`
- 최종 결과: **PASS**

## 구현 범위

- 잡코리아 상세 수집본 10건 + Mock 3건 공통 스키마 정규화
- IT 직무 사전 필터로 비IT 공고 8건 제외
- 명시 조건 기반 `PASS / CHECK_REQUIRED / FAIL` Hard Filter
- 직무·필수기술·우대기술·프로젝트 근거 기반 Ranking
- `EVIDENCED / NOT_EVIDENCED / CONFIRMED_MISSING` Skill Evidence
- 사용자 확인 이후에만 학습 추천 생성
- Firebase Callable Function의 인증·이력서 소유권 검증
- 이력서 편집 화면의 별도 `AI 취업 코치` 패널
- 배포 전 UI 확인을 위한 로컬 fixture 모드

## 구조 정리 (2026-09-02)

초기 구현은 수집·정규화·매칭·코치·보고서가 한 파일(850줄)에 모여 있었고,
채용공고 데이터와 점수 가중치가 Python·TypeScript·Dart에 각각 하드코딩되어
서로 다른 값을 갖고 있었다. 다음과 같이 정리했다.

| 항목 | 이전 | 이후 |
|---|---|---|
| Python 파이프라인 | `matching/pipeline.py` 단일 파일 | `ingestion / matching / coach / reporting / exporters` 레이어 분리 |
| 공고 데이터 | Python·TS에 각각 하드코딩 | 파이프라인이 `functions/src/generated/collectedJobs.ts` 생성, Functions는 읽기만 |
| 점수 가중치 | Python 35/35/10/10/10, Dart 70/10/20, 문서 30/35/10/15/10 | 세 곳 모두 35/35/10/10/10 |
| 학습 Catalog | Python은 Kubernetes만, TS·Dart는 Kubernetes+Redis | 세 곳 모두 Kubernetes+Redis |
| 학력 판정 | TS는 `대졸`만 특수 처리 | Python과 같은 `EDUCATION_RANK` 비교 |
| 키워드 매칭 | 단순 부분 문자열 | ASCII 경계 규칙 (`text_match.py` ↔ `jobCoachScoring.ts`) |
| 실행 경로 | 레포 루트에서만 동작 | `config.py`가 패키지 기준으로 계산 |
| 자체 검증 | fixture 개수 하드코딩 (13/5/8) | 개수 대신 관계를 검증 |

## 검증 결과

| 검증 | 결과 | 내용 |
|---|---|---|
| Python unittest | PASS | 15/15 통과 |
| Python Vertical Slice | PASS | 13건 정규화 → IT 5건 → 추천 4건, Mock 백엔드 공고 1순위 |
| 파이프라인 자체 검증 | PASS | 9개 항목 전부 통과 |
| Python ↔ TypeScript 점수 일치 | PASS | IT 공고 5건 전부 직무·기술 점수 동일 |
| Firebase Functions 빌드 | PASS | TypeScript strict 빌드 성공 |
| 새 Flutter 모듈 정적 분석 | PASS | AI 코치 모듈 이슈 없음 |
| Flutter test | PASS | 4/4 통과 |

## 실제 POC 결과 요약

- IT 직무 필터: 전체 13건 중 IT 5건 포함 / 비IT 8건 제외
- IT 공고 Hard Filter: PASS 3건 / CHECK_REQUIRED 1건 / FAIL 1건
- 선택 공고: `MOCK-BE-001` 주니어 백엔드·AI 서비스 개발자
- 추천 점수: 87.6점 — 합격 확률이 아닌 정렬 점수
- `EVIDENCED`: Python, FastAPI, PostgreSQL, Docker, AWS
- `CONFIRMED_MISSING`: Kubernetes
- `NOT_EVIDENCED`: Redis
- 학습 추천: 사용자가 경험 없음으로 확인한 Kubernetes만 생성
  (Redis도 Catalog에 있지만 사용자 확인이 없어 추천하지 않음)

## 추천 Ranking

| 순위 | 공고 | 점수 | 등급 | 조건 |
|---:|---|---:|---|---|
| 1 | MOCK-BE-001 | 87.6점 | 높음 | PASS |
| 2 | JOBKOREA-49902818 | 33.3점 | 낮음 | PASS |
| 3 | JOBKOREA-49902323 | 33.3점 | 낮음 | PASS |
| 4 | MOCK-FE-002 | 5.0점 | 낮음 | CHECK_REQUIRED |

`MOCK-BE-003`은 최소 경력 5년 조건으로 Hard Filter에서 FAIL 처리되어 추천에서 제외됐다.

## 남은 작업

- `resume_parser`(PDF/DOCX 업로드) — Phase 2
- `job_repository` 추상화와 공식 API Adapter — Phase 3
- Intent 분류와 자유 채팅 — Phase 5
- 잡코리아 공고 중 요구기술이 이미지·첨부파일에만 있는 건의 OCR 처리
- 추천 가중치는 별도 평가 세트로 조정 필요 (현재 값은 제품 품질 수치가 아님)
