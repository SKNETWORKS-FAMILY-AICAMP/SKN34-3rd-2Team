# 채용공고 추천봇

이력서를 받아 맞는 채용공고를 골라 주고, **왜 맞는지를 양쪽 원문 인용으로** 보여 준다.
공고는 채용 사이트에서 수집해 Pinecone에 임베딩으로 담아 두고, 추천할 때마다
이력서로 그 인덱스를 검색한다. 이력서는 저장하지 않는다 — 요청마다 질의로만 쓴다.

이력서 첨삭은 이 모듈이 하지 않는다. 사용자가 추천 목록에서 공고를 고르면 그때
이력서 첨삭은 팀원의 첨삭 모듈(S32-17)이 그 공고 기준으로 맡는다. 두 모듈은 코드가 분리돼 있고,
나중에 한 프로세스로 합친다.

## 어떻게 추천하는가

한 번의 요청이 다섯 단계를 지난다. 어느 단계가 실패하면 추천을 내보내지 않는다 —
검색이 죽었는데 아무 공고나 내보내는 것보다 503이 낫다.

```
① 이력서 → 검색 질의문           LLM. 이력서를 "공고 자격요건처럼" 고쳐 쓴다
② 벡터 검색 (상위 25)            Pinecone. 지역·고용형태·연차를 메타데이터로 거른다
③ 하드 필터                      규칙. 연차·학력·지역·고용형태·전공·자격증
④ LLM 재정렬 (상위 6)            적합도(높음/보통/낮음) + 근거 + 우려
⑤ 근거 검증                      인용이 원문에 실제로 있는지 대조. 없으면 버린다
```

①을 LLM에 맡기는 이유: 이력서는 "FastAPI로 API를 개발했습니다"처럼 **경험**으로
쓰이고, 공고는 "Python 개발 경험 2년 이상"처럼 **요구**로 쓰인다. 표현을 공고 쪽으로
맞춰야 벡터 검색이 걸린다.

③이 ④보다 앞에 있는 이유: 임베딩만으로 순위를 매기면 신입 이력서에 경력 7년 공고가
3위로 올라온다(실측으로 확인). 조건은 규칙으로
먼저 자르고, LLM은 조건이 맞는 것들 사이에서만 고른다.

⑤가 있는 이유: 모델은 근거를 지어낸다. 인용이 이력서와 공고 양쪽 원문에 **글자 그대로**
있어야 살아남는다(공백 차이만 무시한다). 근거가 하나도 안 남으면 적합도를 "낮음"으로
내린다.

## 판정 원칙

- **근거는 인용이다.** "백엔드 경험이 있습니다"가 아니라
  `"FastAPI로 추천 API를 개발하고"` ↔ `"Python 기반 백엔드(FastAPI) API 서버 개발"`.
- **적혀 있지 않은 것과 못 갖춘 것은 다르다.** 공고에 학력이 없으면 탈락이 아니라
  `CHECK_REQUIRED`다. 하드 필터는 PASS / CHECK_REQUIRED / FAIL 셋으로 답한다.
- **조건 충족은 근거가 아니다.** 연차·학력·지역은 `conditions`로 따로 보여 준다.
  근거 칸에는 무엇을 할 줄 아는지만 넣는다.
- **우대사항은 가산만 한다.** 충족하면 근거에 들어가고, 못 채웠어도 우려에 넣지 않는다.
  우대사항이 없어도 지원에 지장이 없다.
- **이력서로 확인할 수 없는 것은 우려가 아니다.** "커뮤니케이션 능력", "졸업 예정" 같은
  항목을 우려로 세면 이력서를 아무리 잘 써도 감점된다.
- **적합도는 개수가 아니라 주력이 겹치는가다.** 근거 3개면 높음, 같은 식으로 세지 않는다.
  Flutter 공고에 Flutter로 앱 둘을 만든 이력서면 높음이고, Kotlin 공고면 보통이다.
- **합격 가능성을 말하지 않는다.** 점수화·서열화도 하지 않는다.

## 모듈 구조

```text
crawling/     목록·상세 수집. 수집 규칙은 crawling/README.md
    ↓
ingestion/    원본 → Job 정규화. 요건 구간 분리, 전공·자격증 추출, 제외 직무
    ↓
retrieval/    Pinecone 적재·검색. 중복 제거, 만료 판정, 증분 적재
    ↓
matching/     하드 필터
    ↓
api/          FastAPI. 위 단계를 한 요청으로 잇는다

schemas/      Job / ResumeProfile / 원본 레코드
sync.py       수집 원본 → 인덱스까지 한 번에 (증분)
```

`coach/`는 공고 본문에서 요구역량을 뽑는 수집 단계의 도구다. `exporters/`에는
이력서 목업을 앱용 Dart로 내보내는 것만 남아 있다.

벡터 검색 이전의 규칙 기반 추천 경로(파이프라인·랭킹·Skill Gap·공고 Dart 내보내기)는
없앴다. 추천은 `api/`만 담당한다. 앱이 아직 들고 있는 공고 생성 파일
(`collected_jobs.g.dart`)은 챗봇 공고 검색을 서버로 옮길 때 함께 지운다.

## 준비

API 키와 로컬 서버 설정은 레포 루트 `.env` 한 곳에 둔다. Firebase Functions 배포 전에는
`powershell -ExecutionPolicy Bypass -File scripts/sync-functions-env.ps1`로 생성본
`functions/.env`를 동기화한다. 키를 코드나 문서에 적지 않는다.

```
OPENAI_API_KEY=
PINECONE_API_KEY1=                # 채용공고 인덱스 키. 공지·정책 쪽은 PINECONE_API_KEY다
PINECONE_INDEX=job-posting        # 생략하면 job-posting
PINECONE_NAMESPACE=               # 생략하면 기본 namespace
OPENAI_MODEL=                     # 생략하면 코드 기본값
OPENAI_EMBEDDING_MODEL=           # 생략하면 text-embedding-3-small
CORS_ALLOW_ORIGINS=               # API 서버용. 쉼표로 구분
```

```powershell
py -3.12 -m venv playdata_venv
playdata_venv\Scripts\activate
pip install -r requirements.txt                       # 수집·정제
pip install fastapi "uvicorn[standard]" langchain langchain-openai pinecone   # 적재·API
```

설치하는 패키지가 아니라 레포 루트에서 `python -m job_matching_bot.<모듈>`로 실행한다.
의존성 목록은 `pyproject.toml`에 있다.

## 실행

**테스트** — 외부 접속 없이 돈다.

```powershell
python -m unittest discover -s job_matching_bot/tests -t .
```

**수집** — 규칙과 인자는 [crawling/README.md](crawling/README.md).

```powershell
python -m job_matching_bot.crawling.crawl_list --all-categories --sort AD --page-count 100
python -m job_matching_bot.crawling.detail_queue
python -m job_matching_bot.crawling.crawl_detail --limit 1000
```

**적재** — 수집 원본을 정제해 인덱스에 넣는다. 내용이 그대로인 공고는 다시 임베딩하지
않으므로 여러 번 돌려도 비용은 바뀐 것에만 든다.

```powershell
python -m job_matching_bot.sync                   # 증분 적재
python -m job_matching_bot.sync --dry-run         # 뭘 할지만 본다
python -m job_matching_bot.sync --skip-index      # 정제까지만, 인덱스는 안 건드림
python -m job_matching_bot.retrieval.refresh_metadata   # 메타데이터만 갱신. 임베딩 안 함
python -m job_matching_bot.retrieval.index_state        # 저장소가 기억하는 인덱스 상태. --adopt 로 기존 벡터 등록
python -m job_matching_bot.exporters.resume_mocks_dart  # 이력서 목업 → 앱 생성 파일
```

```
원본 JSONL → 유효성 검사 → 중복 제거 → 최신 레코드 선택 → 필드 정규화
→ 본문 정제 → 상태·품질 판정 → 변경 여부 확인 → 임베딩 → Pinecone 적재
```

**API 서버**

```powershell
python -m uvicorn job_matching_bot.api.main:app --host 127.0.0.1 --port 8000
```

```
GET  /health                     인덱스 이름, 벡터 수, LLM 설정 여부
POST /api/v1/jobs/recommend      추천
```

요청은 이력서 원문과 조건이다. 앱이 이력서 화면의 값을 그대로 보낸다.

```json
{
  "resume_text": "[프로젝트 경험] ...",
  "preferred_regions": ["서울", "경기"],
  "preferred_employment_types": ["정규직"],
  "education_level": "대졸",
  "career_years": 0,
  "majors": [],
  "certifications": [],
  "top_k": 10
}
```

응답의 공고 하나는 이렇게 생겼다.

```json
{
  "company": "...", "title": "...", "source_url": "...",
  "fit": "높음",
  "reasons": [
    {"claim": "Spring Boot 기반 API를 만든 경험이 있습니다",
     "resume_quote": "주문·결제 REST API를 설계하고 구현했습니다.",
     "job_quote": "Spring Boot 기반 백엔드 서비스 설계 및 개발"}
  ],
  "concerns": ["Kafka 기반 이벤트 처리 경험이 이력서에서 확인되지 않는다"],
  "conditions": {"region": "서울 강남구", "career": "경력무관", "education": "학력무관"},
  "filter_status": "PASS",
  "unknown_conditions": []
}
```

한 회사는 두 건까지만 올린다. 검색·필터가 실패하면 503이다.

## 인덱스와 비용

- 인덱스 `job-posting`, 1536차원, cosine, serverless(aws us-east-1)
- 임베딩은 `text-embedding-3-small`. 모델을 바꾸면 차원이 달라져 인덱스를 새로 만들어야 한다
- **임베딩 대상은 요건 구간만**(주요업무·자격요건·우대사항). 본문 앞의 분류 경로 줄은
  모든 공고를 서로 비슷하게 만들어 유사도가 0.37~0.50에 뭉치게 하므로 뺀다
- 메타데이터에 요건 원문 1,200자를 같이 담는다. LLM 재정렬이 이걸 읽는다.
  300자로 자르면 자격요건이 잘려 적합도가 전부 "보통"으로 나온다

비용은 두 군데서 난다.

| 어디 | 언제 | 얼마나 |
|---|---|---|
| OpenAI 임베딩 | 적재 때, 바뀐 공고만 | 공고 1건에 요건 ~1,200자 |
| OpenAI 채팅 | 추천 요청마다 2회 (질의문 생성, 재정렬) | 재정렬이 후보 6건 × 1,200자를 읽는다 |
| Pinecone | 검색·적재 | serverless 무료 구간 안 |

429가 오면 기다렸다 다시 시도한다(OpenAI 5→60초, Pinecone 2→30초). 적재는
100건 단위로 나눠 보내고 청크마다 upsert해서, 중간에 끊겨도 진척이 남는다.

## 알려진 한계

- 응답이 20~35초 걸린다. 대부분 LLM 재정렬이다
- 사이트 메타는 `경력무관`인데 본문에 "경력자"라고 적힌 공고를 하드 필터가 못 읽는다.
  재정렬이 본문을 보고 잡을 때도 있지만 보장은 아니다
- 상세가 이미지뿐인 공고(`body_is_image`)는 기업이 고른 기술 태그로만 판단한다
- 수집은 아직 수동이다. 스케줄링과 마감 공고 재확인은 만들지 않았다
