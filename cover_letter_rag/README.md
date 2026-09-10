# Cover Letter RAG

선택한 문장의 원본 적용과 복원: [적용 API 명세](docs/resume-apply.md).

이력서 첨삭 최신 요청/저장 규격은 [v2 계약](docs/resume-review-v2.md)을 확인하세요.
아래 초기 예시의 answers만 보내는 방식은 더 이상 허용되지 않습니다.

Flutter/Firebase LMS와 분리해 먼저 검증하는 FastAPI 기반 백엔드입니다. 채용공고는 별도 인덱싱 명령에서 로드·중복 제거·청킹·임베딩·VectorDB 저장을 완료하고, 서비스 요청에서는 이력서 분석·검색·생성만 수행합니다. 운영 기본 VectorDB는 Pinecone이며 Chroma는 로컬 개발·테스트 대체 수단으로 유지합니다.

현재 추천 기준은 사용자가 별도로 등록한 기술 태그가 아니라 이력서 원문입니다. 선택적으로 받은 기존 자기소개서는 희망 직무나 도메인 의도만 보강하며, 이력서에 없는 기술·경험의 근거로 사용하지 않습니다.

## 구조

```text
cover_letter_rag/
├── app/
│   ├── main.py          # FastAPI 라우트와 예외 변환
│   ├── config.py        # .env 기반 서버 설정
│   ├── models.py        # 요청·응답 및 구조화 출력 스키마
│   ├── prompts.py       # 사실성·안전 가드레일 프롬프트
│   ├── crawled_jobs.py  # 크롤링 JSONL 중복 제거·정규화·품질 분류
│   ├── vector_store.py  # Pinecone/Chroma 검색 어댑터
│   └── service.py       # Retrieve + Generate와 사후 근거 검증
├── scripts/
│   ├── index_jobs.py    # 정적 샘플 로딩·청킹·임베딩·저장 CLI
│   └── index_saramin_jsonl.py # 실제 크롤링 JSONL 인덱싱 CLI
├── data/
│   ├── jobs/            # 사람인 job-search 응답 형식의 정적 공고 JSON
│   ├── job_enrichments/ # 사람인 응답에 없는 RAG용 상세 공고 내용
│   └── sample_review_request.json
├── tests/               # 외부 API 키 없이 실행되는 API/가드레일 테스트
├── .env.example
└── pyproject.toml
```

`local_data/`는 크롤링 원본처럼 용량이 크고 재생성 가능한 로컬 데이터 전용이며 Git에서 제외됩니다.

## 실행 준비

```powershell
cd ..
py -3.12 -m venv playdata_venv
.\playdata_venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

루트 `.env`의 `OPENAI_API_KEY`, `PINECONE_API_KEY1`에 실제 키를 넣습니다. 채용공고 인덱스는 공지·정책 인덱스와 계정이 달라 키 이름을 나눴습니다 — 공지용은 `PINECONE_API_KEY`입니다. 키는 Flutter 앱이나 요청 본문에 넣지 않습니다. 공지 검색과 채용공고 추천은 데이터와 검색 목적이 다르므로, 이 서비스는 공지용 `student` 인덱스와 분리된 채용공고 전용 `job-postings` 인덱스를 사용합니다.

## 1. 정적 공고 인덱싱

```powershell
python -m scripts.index_jobs
```

인덱서는 `data/jobs/*.json`의 사람인 `job-search` 응답과 공고 ID가 같은
`data/job_enrichments/*.json`을 결합합니다. 이후 공고 단위 문서를 재귀 청킹한 뒤
`text-embedding-3-small`로 임베딩하여 Pinecone에 저장합니다. 서버 시작이나 API
요청 중에는 인덱싱하지 않습니다.

기본 설정은 `job-postings` 인덱스, `saramin` namespace, cosine metric, 1536차원입니다. 기존 `job-postings` 인덱스가 이미 있으면 dimension과 metric이 일치해야 하며, 다르면 인덱싱을 중단합니다. 같은 공고를 다시 넣을 때는 `job_id`가 같은 기존 벡터를 삭제한 뒤 배치 업서트하므로 오래된 청크가 섞이지 않습니다. 향후 다른 공고 출처를 함께 검색해야 한다면 출처별 namespace 분리 여부를 검색 요구사항에 맞춰 다시 결정합니다.

샘플 공고는 실제 채용공고가 아닌 형식 검증용 데이터입니다. `jobs.job[]`의 필드와
하이픈이 포함된 키 이름은 [사람인 채용정보 API 가이드](https://oapi.saramin.co.kr/guide/job-search)를 따릅니다.
사람인 응답에는 자격요건 전문이 없으므로 이를 API 필드인 것처럼 추가하지 않고,
RAG 비교에 필요한 직접 작성한 내용만 `job_enrichments`에 분리해 둡니다.

사람인 응답의 지역·산업·직무·근무형태는 `code`와 `name`을 함께 보존합니다.
향후 검색 조건은 사용자에게 이름을 보여 주고 `loc_cd`, `ind_cd`, `job_mid_cd`,
`job_cd`, `job_type`에는 해당 코드를 전달합니다. VectorDB 메타데이터에도 코드와
이름을 모두 저장하고, 의미 검색 문서에는 사람이 읽을 수 있는 이름을 포함합니다.

### 크롤링 JSONL 검증 및 인덱싱

팀원이 수집한 원본을 `local_data/saramin_detail.jsonl`에 둔 뒤 먼저 비용 없는 검증을 실행합니다.

```powershell
python -m scripts.index_saramin_jsonl --validate-only
```

검증 명령은 `source_job_id`별 마지막 레코드를 남겨 중복을 제거하고, IT 공고 필터링과 상세본문 품질 분류, 청킹까지만 수행합니다. 실제 OpenAI 임베딩 API를 호출해 Pinecone에 저장하려면 별도로 다음 명령을 실행합니다.

```powershell
python -m scripts.index_saramin_jsonl
```

`needs_human_review=true`인 공고는 `NEEDS_CONFIRMATION`, 상세본문이 짧은 공고는 `LIMITED`로 보존합니다. 해당 공고를 선택해 상세 비교할 때는 사용자에게 최신 공고 원문 확인을 요청해야 합니다.

비용 없이 로컬 Chroma로만 시험하려면 `.env`에서 `VECTOR_STORE_PROVIDER=chroma`로 바꿉니다. 이 경우 같은 명령이 `chroma_db`에 저장합니다.

## 2. API 실행

```powershell
uvicorn app.main:app --reload --port 8001
```

- `GET /health`: 프로세스 상태와 인덱스 준비 여부
- `POST /api/v1/jobs/search`: 이력서 기반 정적 공고 Top-k 검색
- `POST /api/v1/profiles/analyze`: 이력서 직접 인용 근거가 있는 기술·경험과 검색 신호 추출
- `POST /api/v1/jobs/recommend`: 이력서 분석 → VectorDB 공고 검색 → 근거 포함 추천
- `POST /api/v1/jobs/compare`: 추천 공고 ID 선택 → 공고 요구사항과 이력서 근거·부족 정보 비교
- `POST /api/v1/reviews`: 이력서·공고·문항·초안 기반 비교 및 첨삭
- `POST /api/v1/resumes/reviews`: Firebase 인증 후 Firestore의 본인 이력서를 읽어 섹션별 첨삭

Swagger UI는 `http://127.0.0.1:8001/docs`에서 확인할 수 있습니다.

## 안전 규칙

- 이력서의 직접 인용문만 요구사항 충족 근거로 인정합니다.
- 모델이 반환한 인용문이 이력서 원문에 없으면 서버가 해당 근거를 제거하고 상태를 `확인 필요`로 바꿉니다.
- 첨삭안에 입력 원문 어디에도 없는 숫자가 생기면 첨삭안을 반환하지 않고 원본 초안을 유지합니다.
- 부족한 경험·기술·자격·성과·수치는 생성하지 않고 확인 질문으로 전환합니다.
- 합격 가능성을 단정하거나 지원자를 점수화하지 않습니다. 검색 순위는 공고 검색 결과에만 적용합니다.

## Firebase 이력서 첨삭

### 문장별 첨삭과 추가 답변

응답 `input_fields`는 요약하지 않은 실제 모델 입력값이며 `excluded_fields`는 제외한 필드,
`input_hash`는 해당 입력의 SHA-256입니다. 개인정보가 자유 서술문에 들어 있다면 자동 익명화를 보장하지 않습니다.
`sentence_reviews`는 `field_path`, `original_quote`, `reason`, `suggested_revision`,
`evidence_quotes`, `confirmation_question`으로 원문과 수정안을 비교합니다.
기존 섹션별 진단은 유지하지만 `section_reviews[].suggested_revision`은 null이며 문장별 수정안을 사용합니다.

같은 POST 요청에 아래 `answers`를 추가하면 현재 저장된 이력서와 추가 사실로 재첨삭합니다.
배열 위치는 현재 입력 기준입니다. 이력서를 수정했다면 새 결과의 경로를 사용하세요.

```json
{
  "cohort_id": "cohort-id",
  "resume_id": "resume-id",
  "answers": [{
    "field_path": "projects[0].description",
    "question": "어떤 변화가 있었나요?",
    "answer": "컴포넌트를 독립적으로 확인하는 환경을 구축했습니다."
  }]
}
```

답변은 사용자가 확인한 진술이며 외부 검증된 사실을 의미하지 않습니다. 수정안의 인용·수치·영문 기술명·일부 역할 과장을 해당 필드 근거와 비교합니다.
의미적 환각 전체를 차단하는 검증은 아니며 사용자 검토가 필요합니다.
매 호출은 새로운 결과를 저장하며 원본 적용/Flutter 비교 화면/선택 공고 ID 조회는 아직 구현하지 않았습니다.
선택 공고 본문은 기존 `job_posting_text`로 전달할 수 있습니다.

이력서 첨삭 API는 Flutter가 이력서 원문을 다시 보내는 대신 아래 값만 받습니다.

- `Authorization: Bearer <Firebase ID token>`
- `cohort_id`, `resume_id`
- 선택 입력: `job_posting_text`, `review_focus`

서버는 ID 토큰을 검증해 얻은 `uid`가
`cohorts/{cohortId}/resumes/{resumeId}.userId`와 일치할 때만 `content`를 읽습니다.
Firebase Admin SDK는 Firestore Security Rules를 우회하므로 이 서버 소유권 검사를 제거하면 안 됩니다.
이름·전화·이메일·생년월일과 내부 ID/URL은 LLM 입력에서 제외합니다.

결과는 원본 이력서를 덮어쓰지 않고 다음 경로에 별도 저장됩니다.

```text
cohorts/{cohortId}/resumes/{resumeId}/aiReviews/{reviewId}
```

현재 Firestore 규칙에는 `aiReviews` 클라이언트 직접 읽기 규칙이 없습니다. Flutter 연동 시에는
백엔드 조회 API를 사용하거나, 팀 합의 후 본인 문서만 읽도록 규칙을 별도로 추가해야 합니다.

로컬에서는 서비스 계정 JSON을 저장소 밖에 두고 현재 셸의
`GOOGLE_APPLICATION_CREDENTIALS`에 경로를 지정한 뒤 `.env`의 `FIREBASE_PROJECT_ID`를 설정합니다.
서비스 계정 JSON, Firebase/Pinecone/OpenAI 키는 Git 또는 Flutter에 넣지 않습니다.

요청 예시:

```bash
curl -X POST http://127.0.0.1:8001/api/v1/resumes/reviews \
  -H "Authorization: Bearer FIREBASE_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"cohort_id":"cohort-id","resume_id":"resume-id","review_focus":"프로젝트 경험"}'
```
