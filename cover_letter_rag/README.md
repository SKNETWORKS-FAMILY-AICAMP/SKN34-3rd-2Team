# Cover Letter RAG

Flutter/Firebase LMS와 분리해 먼저 검증하는 FastAPI 기반 백엔드입니다. 채용공고는 별도 인덱싱 명령에서 로드·중복 제거·청킹·임베딩·Chroma 저장을 완료하고, 서비스 요청에서는 이력서 분석·검색·생성만 수행합니다.

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
│   ├── vector_store.py  # Chroma 검색 어댑터
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
cd cover_letter_rag
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".[dev]"
Copy-Item .env.example .env
```

`.env`의 `OPENAI_API_KEY`에 실제 키를 넣습니다. 키는 Flutter 앱이나 요청 본문에 넣지 않습니다.

## 1. 정적 공고 인덱싱

```powershell
python -m scripts.index_jobs
```

인덱서는 `data/jobs/*.json`의 사람인 `job-search` 응답과 공고 ID가 같은
`data/job_enrichments/*.json`을 결합합니다. 이후 공고 단위 문서를 재귀 청킹한 뒤
`text-embedding-3-small`로 임베딩하여 `chroma_db`에 저장합니다. 서버 시작이나 API
요청 중에는 인덱싱하지 않습니다.

샘플 공고는 실제 채용공고가 아닌 형식 검증용 데이터입니다. `jobs.job[]`의 필드와
하이픈이 포함된 키 이름은 [사람인 채용정보 API 가이드](https://oapi.saramin.co.kr/guide/job-search)를 따릅니다.
사람인 응답에는 자격요건 전문이 없으므로 이를 API 필드인 것처럼 추가하지 않고,
RAG 비교에 필요한 직접 작성한 내용만 `job_enrichments`에 분리해 둡니다.

사람인 응답의 지역·산업·직무·근무형태는 `code`와 `name`을 함께 보존합니다.
향후 검색 조건은 사용자에게 이름을 보여 주고 `loc_cd`, `ind_cd`, `job_mid_cd`,
`job_cd`, `job_type`에는 해당 코드를 전달합니다. Chroma 메타데이터에도 코드와
이름을 모두 저장하고, 의미 검색 문서에는 사람이 읽을 수 있는 이름을 포함합니다.

### 크롤링 JSONL 검증 및 인덱싱

팀원이 수집한 원본을 `local_data/saramin_detail.jsonl`에 둔 뒤 먼저 비용 없는 검증을 실행합니다.

```powershell
python -m scripts.index_saramin_jsonl --validate-only
```

검증 명령은 `source_job_id`별 마지막 레코드를 남겨 중복을 제거하고, IT 공고 필터링과 상세본문 품질 분류, 청킹까지만 수행합니다. 실제 OpenAI 임베딩 API를 호출해 Chroma에 저장하려면 별도로 다음 명령을 실행합니다.

```powershell
python -m scripts.index_saramin_jsonl
```

`needs_human_review=true`인 공고는 `NEEDS_CONFIRMATION`, 상세본문이 짧은 공고는 `LIMITED`로 보존합니다. 해당 공고를 선택해 상세 비교할 때는 사용자에게 최신 공고 원문 확인을 요청해야 합니다.

## 2. API 실행

```powershell
uvicorn app.main:app --reload --port 8001
```

- `GET /health`: 프로세스 상태와 인덱스 준비 여부
- `POST /api/v1/jobs/search`: 이력서 기반 정적 공고 Top-k 검색
- `POST /api/v1/profiles/analyze`: 이력서 직접 인용 근거가 있는 기술·경험과 검색 신호 추출
- `POST /api/v1/jobs/recommend`: 이력서 분석 → Chroma 공고 검색 → 근거 포함 추천
- `POST /api/v1/jobs/compare`: 추천 공고 ID 선택 → 공고 요구사항과 이력서 근거·부족 정보 비교
- `POST /api/v1/reviews`: 이력서·공고·문항·초안 기반 비교 및 첨삭

Swagger UI는 `http://127.0.0.1:8001/docs`에서 확인할 수 있습니다.

## 안전 규칙

- 이력서의 직접 인용문만 요구사항 충족 근거로 인정합니다.
- 모델이 반환한 인용문이 이력서 원문에 없으면 서버가 해당 근거를 제거하고 상태를 `확인 필요`로 바꿉니다.
- 첨삭안에 입력 원문 어디에도 없는 숫자가 생기면 첨삭안을 반환하지 않고 원본 초안을 유지합니다.
- 부족한 경험·기술·자격·성과·수치는 생성하지 않고 확인 질문으로 전환합니다.
- 합격 가능성을 단정하거나 지원자를 점수화하지 않습니다. 검색 순위는 공고 검색 결과에만 적용합니다.

## Firebase 연동 경계

현재 입력은 API 요청으로 직접 받습니다. 다음 단계에서는 서버에서 Firebase ID 토큰을 검증하고, 검증된 `uid`를 기준으로 Firestore 보안 규칙과 서버 조회 조건을 함께 적용해 로그인 사용자의 이력서만 불러와야 합니다. Flutter에는 OpenAI API 키를 두지 않습니다.
