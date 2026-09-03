# AI 취업 코치 POC

Flutter 이력서 화면과 연결하기 전에 채용공고 정규화, Hard Filter, Ranking,
Skill Evidence 분기를 재현 가능한 데이터로 검증하는 Phase 1 Vertical Slice다.

이 서비스의 검색·추천 대상은 **IT 직무 채용공고로 한정**한다. 원본 수집 데이터에서
IT 직무 근거가 없는 공고와 IT 기업의 비IT 직무를 사전 필터로 제외한다.

## 모듈 구조

레이어는 한 방향으로만 의존한다. 매칭 엔진은 이미 정규화된 `Job`만 받고,
수집·정규화는 매칭을 알지 못한다.

```text
schemas/     공통 Job / ResumeProfile 스키마
    ↑
ingestion/   수집·정규화 (잡코리아, Mock, IT 직무 필터, 중복 제거)
    ↑
matching/    Hard Filter, Ranking
    ↑
coach/       Skill Gap, 이력서 피드백, 학습 추천
    ↑
reporting/   Markdown 보고서
exporters/   Functions가 읽는 TypeScript 공고 모듈
    ↑
pipeline.py  위 단계의 실행 순서만 담당
```

`text_match.py`는 한글·영문이 섞인 문장에서 키워드를 찾는 규칙을 모아둔 곳이다.
`config.py`는 기준 시각과 기본 경로를, `validation.py`는 파이프라인 자체 검증을 담당한다.

## 실행

Python 3.10 이상이 필요하다. 외부 의존성은 없다.

```powershell
python -m unittest discover -s job_matching_bot/tests -t .
python -m job_matching_bot           # 분석 파이프라인 (한 번 계산)
python -m job_matching_bot.ingest    # 수집 실행 (반복하며 저장소를 쌓음)
```

수집과 분석은 주기가 달라 진입점이 분리돼 있다. 수집은 여러 번 돌리며
저장소를 갱신하고, 분석은 그 결과를 읽어 한 번 계산한다.

## 반복 수집과 상태 관리

같은 공고를 다시 수집했을 때 신규인지 갱신인지 구분하지 못하면 두 번째
수집부터 데이터가 망가진다. `ingestion/job_store.py`가 `source + source_job_id`를
키로 대조해 판정한다.

```text
처음 본 공고        → 신규 등록, first_seen_at 기록
content_hash 같음   → 내용 그대로, last_seen_at만 갱신
content_hash 다름   → 내용 갱신, revisions 증가
이번에 안 보임       → 즉시 삭제하지 않고 상태로 남김
```

상태는 네 가지다.

| 상태 | 의미 |
|---|---|
| `OPEN` | 진행 중 |
| `EXPIRED` | 마감일이 지남 (관측 여부와 무관하게 확정) |
| `CLOSED` | 소스가 마감이라고 명시 |
| `REMOVED` | 마감 전인데 소스에서 계속 사라짐 |

수집이 한 번 실패했다고 저장된 공고 전체가 삭제 처리되면 안 되므로, 연속으로
관측되지 않은 횟수가 `DEFAULT_MISSING_RUN_LIMIT`(기본 2회)를 넘을 때만
`REMOVED`로 넘긴다. 다시 나타나면 `OPEN`으로 돌아온다.

수집 범위(`source`)를 벗어난 공고는 이번에 안 보였다고 사라진 것으로 보지
않는다. 백엔드 공고만 수집한 날 프론트엔드 공고가 안 보이는 것은 삭제가 아니다.

### 원본 보존과 재처리

정규화 전 응답은 `artifacts/job_raw/{source}/{source_job_id}.json`에 파싱 성공
여부와 함께 남는다. 선택자가 틀렸을 때 재수집 없이 고친 파서로 다시 돌릴 수 있다.

```python
from job_matching_bot.ingestion import raw_store
from job_matching_bot.ingestion.jobkorea import normalize_jobkorea

parsed, failures = raw_store.reparse(
    "job_matching_bot/artifacts/job_raw", normalize_jobkorea, only_failed=True
)
```

수집 리포트(`artifacts/collection_report.json`)에는 신규·갱신·만료·삭제 건수와
함께 **필수 필드 누락 목록**과 **파서 버전별 건수**가 남는다. 필수 필드 누락이
갑자기 늘면 선택자가 깨진 신호다.

입력은 `fixtures/jobkorea_detail_first_page.json`의 잡코리아 상세 10건과
통제된 Mock 공고 3건이다.

실행하면 다음 산출물이 생성된다. `artifacts/`는 재생성되는 파일이라 커밋하지 않는다.

| 경로 | 내용 |
|---|---|
| `artifacts/job_coach_pipeline_test.json` | 전체 실행 결과 |
| `artifacts/job_coach_pipeline_test.md` | 사람이 읽는 보고서 |
| `artifacts/collected_it_jobs.json` | IT 공고 수집 레코드 |
| `functions/src/generated/collectedJobs.ts` | Functions가 import하는 공고 데이터 |

## 채용공고 데이터의 단일 출처

공고 데이터를 Functions에 다시 하드코딩하면 Python POC와 값이 갈라진다.
그래서 수집 결과는 이 파이프라인만 만들고, Functions는 생성된
`functions/src/generated/collectedJobs.ts`를 읽기만 한다.

```text
fixtures + Mock
      ↓
job_matching_bot (정규화 → IT 필터 → 수집 레코드)
      ↓
functions/src/generated/collectedJobs.ts   ← 자동 생성, 직접 수정 금지
      ↓
analyzeResumeAndMatch (Callable Function)
```

공고를 추가하거나 fixture를 바꾼 뒤에는 `python -m job_matching_bot`을 다시 실행해
생성 파일을 갱신한다.

점수 가중치처럼 양쪽이 같아야 하는 값은 `matching/ranking.py`와
`functions/src/jobCoachScoring.ts`에 서로를 가리키는 주석과 함께 둔다.

`career_type`은 신입·경력 조건(`ENTRY`, `EXPERIENCED`, `ANY`, `UNKNOWN`),
`employment_type`은 정규직·계약직 같은 고용형태를 의미하므로 서로 섞지 않는다.

## Flutter에서 확인

이력서 편집 화면 상단의 `AI 취업 코치` 버튼을 누르면 우측 패널이 열린다.
이 브랜치는 기본적으로 로컬 fixture 모드이므로 Functions를 배포하지 않아도
현재 편집 중인 기술스택과 프로젝트 내용을 이용해 결과를 표시한다.

실제 Callable Function을 사용하려면 다음처럼 실행한다.

```powershell
flutter run -d chrome --dart-define=AI_COACH_LOCAL_FIXTURE=false
```

이 경우 `analyzeResumeAndMatch` Functions가 배포되어 있거나 Emulator에 연결되어야 한다.
Callable Function은 Firebase 인증, 이력서 소유권을 확인한 뒤 결과를
`cohorts/{cohortId}/resumes/{resumeId}/aiAnalyses/{analysisId}`에 저장한다.

## 판정 원칙

- `EVIDENCED`: 이력서 기술스택 또는 프로젝트에서 근거 확인
- `NOT_EVIDENCED`: 근거를 찾지 못했으며 사용자에게 확인 필요
- `CONFIRMED_MISSING`: 사용자가 실제 경험이 없다고 확인
- 학습 추천은 `CONFIRMED_MISSING`이면서 Catalog에 있는 항목만 생성
- 추천 점수는 합격 확률이 아니라 공고 정렬용 POC 점수
