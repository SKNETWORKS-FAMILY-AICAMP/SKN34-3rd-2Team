# 이력서 첨삭 서버

선택한 채용공고와 학생 이력서를 대조해 문장별 수정안과 확인 질문을 주고, 답을 받아 다시 첨삭하는 FastAPI 서버입니다.
맞춤 이력서(공고별 사본) 만들기·적용·되돌리기도 이 서버가 맡습니다. 공고 추천은 `job_matching_bot`이 맡고, 둘은
통합 서버 하나(`app.integrated`, 8000번)로 함께 뜹니다.

- 요청·응답 계약: [v2 계약](docs/resume-review-v2.md) → [v3 공고 요건 대조](docs/resume-review-v3.md)(검증 결과·남은 한계 포함)
- 수정안 적용·되돌리기: [적용 API](docs/resume-apply.md)
- 추천 봇과 연결: [매칭 봇 ↔ 첨삭 통합](docs/matching-integration.md)

## 구조

```text
cover_letter_rag/
├── app/
│   ├── integrated.py        # 통합 서버: 공고 추천(/), 첨삭(/resume-review), 학생 챗봇, 공부방 노트
│   ├── main.py              # 첨삭·맞춤 이력서 라우트와 예외 변환
│   ├── config.py            # 루트 .env 기반 설정
│   ├── models.py            # 요청·응답·모델 구조화 출력 스키마
│   ├── prompts.py           # 첨삭 지시문
│   ├── resume_review.py     # 첨삭 서비스, 수정안 근거 검증(숫자·기술어·부정·칸 사이 중복)
│   ├── review_workflow.py   # 첨삭 한 턴의 흐름: 답 정리 → 모델 → 검증 → 사실 검사 → 저장
│   ├── review_rules.py      # 여러 검증이 함께 쓰는 칸 이름·낱말 목록
│   ├── fact_check.py        # 후속 수정안을 뜻으로 대조하고 틀린 곳만 다시 쓰게 하는 검사
│   ├── job_requirements.py  # 공고 요건 정리(공고당 한 번, Firestore에 저장)
│   ├── star_checks.py       # 경험 칸 STAR 판정 검증
│   ├── technology.py        # 기술 이름 정규화
│   ├── matching_handoff.py  # 추천 봇 공고 저장소에서 선택 공고 읽기
│   ├── tailored_resumes.py  # 맞춤 이력서 만들기·목록·승격
│   ├── resume_apply.py      # 수정안 적용·되돌리기 API
│   └── firebase_gateway.py  # Firebase 인증·Firestore 읽기/쓰기와 소유권 검사
├── evaluation/
│   ├── review_eval.py       # 목업 이력서로 첨삭 대화를 끝까지 돌려 보는 평가 도구
│   └── fixtures/            # 평가 케이스(dev·heldout·unseen 등)
├── docs/
├── tests/                   # 외부 API 키 없이 도는 시험
└── .env.example
```

## 실행

설정은 저장소 루트 `.env` 하나를 씁니다(`copy .env.example .env` 후 값 채우기). 첨삭에 필요한 값은
`OPENAI_API_KEY`, `FIREBASE_PROJECT_ID`, 그리고 셸의 `GOOGLE_APPLICATION_CREDENTIALS`(저장소 밖 서비스 계정 JSON 경로)입니다.
키와 서비스 계정 JSON은 Git이나 Flutter에 넣지 않습니다.

저장소 루트에서:

```powershell
.\playdata_venv\Scripts\python.exe -m uvicorn app.integrated:app --app-dir cover_letter_rag --host 127.0.0.1 --port 8000
```

- `GET /resume-review/health`: 모델 이름과 Firebase 설정 여부
- `GET /resume-review/api/v1/resumes/review-context`: 첨삭 창에 보여 줄 이력서·선택 공고
- `POST /resume-review/api/v1/resumes/reviews`: 첫 첨삭, 답변 뒤 재첨삭, 누락 점검
- `/resume-review/api/v1/resumes/{resume_id}/tailored…`: 맞춤 이력서 만들기·조회·세션 저장·삭제·승격
- 수정안 적용·되돌리기는 [적용 API](docs/resume-apply.md)

## 시험과 평가

```powershell
cd cover_letter_rag
$env:PYTHONPATH=".."; python -m pytest -q tests
python -m evaluation.review_eval --cases dev --label 이름 --apply-polish
```

평가 도구는 실제 모델을 부르고 결과를 `evaluation/runs/`(Git 제외)에 남깁니다. 고칠 때 본 케이스로 고친 결과를 확인하지 않습니다.

## 안전 규칙

- 서버는 ID 토큰의 `uid`가 `cohorts/{cohortId}/resumes/{resumeId}.userId`와 같을 때만 이력서를 읽습니다. Firebase Admin SDK는
  보안 규칙을 우회하므로 이 소유권 검사를 없애면 안 됩니다.
- 이름·전화·이메일·생년월일·내부 ID/URL은 모델 입력에서 뺍니다.
- 수정안의 인용·숫자·기술어·역할 과장·부정 표현·확신 없는 답을 원문과 확인된 답에 대조하고, 근거가 없으면 보류합니다.
  의미 변화 전체를 막지는 못하므로 사용자가 적용 전에 확인합니다.
- 결과는 원본 이력서를 덮어쓰지 않고 `cohorts/{cohortId}/resumes/{resumeId}/aiReviews/{reviewId}`에 따로 저장합니다.
- 합격 가능성을 단정하거나 지원자를 점수화하지 않습니다.
