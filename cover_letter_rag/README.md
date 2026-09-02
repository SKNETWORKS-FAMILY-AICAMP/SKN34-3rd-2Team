# Cover Letter RAG

Flutter/Firebase LMS와 분리해 먼저 검증하는 FastAPI 기반 백엔드입니다. 정적 채용공고는 별도 인덱싱 명령에서 로드·청킹·임베딩·Chroma 저장을 완료하고, 서비스 요청에서는 검색과 생성만 수행합니다.

## 구조

```text
cover_letter_rag/
├── app/
│   ├── main.py          # FastAPI 라우트와 예외 변환
│   ├── config.py        # .env 기반 서버 설정
│   ├── models.py        # 요청·응답 및 구조화 출력 스키마
│   ├── prompts.py       # 사실성·안전 가드레일 프롬프트
│   ├── vector_store.py  # Chroma 검색 어댑터
│   └── service.py       # Retrieve + Generate와 사후 근거 검증
├── scripts/
│   └── index_jobs.py    # 로딩·청킹·임베딩·저장 전용 CLI
├── data/
│   ├── jobs/            # 직접 준비한 정적 공고 JSON
│   └── sample_review_request.json
├── tests/               # 외부 API 키 없이 실행되는 API/가드레일 테스트
├── .env.example
└── pyproject.toml
```

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

인덱서는 `data/jobs/*.json`을 읽고, 공고 단위 문서를 재귀 청킹한 뒤 `text-embedding-3-small`로 임베딩하여 `chroma_db`에 저장합니다. 서버 시작이나 API 요청 중에는 인덱싱하지 않습니다.

## 2. API 실행

```powershell
uvicorn app.main:app --reload --port 8001
```

- `GET /health`: 프로세스 상태와 인덱스 준비 여부
- `POST /api/v1/jobs/search`: 이력서 기반 정적 공고 Top-k 검색
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

