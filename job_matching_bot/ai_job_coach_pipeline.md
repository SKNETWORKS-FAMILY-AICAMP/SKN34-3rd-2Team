# AI 취업 코치 봇 구조 및 개발 파이프라인

## 1. 프로젝트 방향

기존 Flutter Web + Firebase 기반 웹앱의 **이력서 작성 화면**에  
`AI 취업 코치` 버튼을 추가하고, 버튼을 누르면 우측에 봇 탭이 열리는 구조로 구현한다.

AI 취업 코치는 단순 이력서 첨삭 봇이 아니라 다음 기능을 담당한다.

- 이력서 분석
- 채용공고 검색
- 이력서 기반 맞춤 채용공고 추천
- 채용공고 ↔ 이력서 역량 매칭
- Skill Gap 분석
- 부족 역량 학습 추천
- 이력서 표현 개선 피드백
- 자유 채팅 기반 채용공고 탐색

중요한 원칙은 **AI가 사용자의 이력서를 임의로 직접 수정하지 않는 것**이다.

AI는 다음과 같이 동작한다.

- 경험은 있으나 표현이 부족함 → **이력서 개선 피드백**
- 이력서에서 경험 근거를 찾지 못함 → **사용자 확인 요청**
- 사용자가 실제 경험이 없다고 확인함 → **학습 추천**
- 사용자가 직접 수정 → **재분석 가능**

AI는 이력서에 어떤 기술이 적혀 있지 않다는 이유만으로 실제 경험이 없다고 단정하지 않는다.
모든 분석 결과에는 판단 근거가 된 이력서 문장과 채용공고 문장을 함께 보관한다.

---

## 2. 사용자 화면 구조

### 2.1 이력서 작성 화면

```text
┌─────────────────────────────────────────────────────┐
│                    이력서 작성                       │
│                                                     │
│ 기본정보                                             │
│ 기술스택                                             │
│ 프로젝트                                             │
│ 경력                                                 │
│ 자기소개                                             │
│                                                     │
│                              [✨ AI 취업 코치]       │
└─────────────────────────────────────────────────────┘
```

`AI 취업 코치` 버튼 클릭 시 우측 패널을 연다.

```text
┌─────────────────────────────┬───────────────────────┐
│         이력서 작성          │     AI 취업 코치      │
│                             │                       │
│ 기본정보                    │ 무엇을 도와드릴까요?   │
│ 프로젝트                    │                       │
│ 기술스택                    │ [📄 이력서 분석]       │
│ 경력                        │ [🎯 맞춤 공고 추천]    │
│ 자기소개                    │ [🔎 채용공고 찾기]     │
│                             │                       │
│                             │ 자유 채팅              │
│                             │ [메시지 입력...]       │
└─────────────────────────────┴───────────────────────┘
```

---

## 3. AI 취업 코치 주요 기능

### 3.1 이력서 분석

특정 채용공고와 비교하기 전에 현재 작성된 이력서 자체를 분석한다.

#### 분석 항목

- 프로젝트 설명의 구체성
- 본인의 역할
- 사용 기술
- 문제 해결 과정
- 프로젝트 성과
- 직무 관련성
- 기술스택과 프로젝트 경험의 연결성
- 중복되거나 불필요한 표현

#### 결과 예시

```text
📄 이력서 분석

강점
✓ Python / FastAPI 프로젝트 경험이 잘 드러남
✓ SQL 활용 경험 확인
✓ AI 프로젝트 경험 존재

보완 필요
⚠ 프로젝트 내 담당 역할이 모호함
⚠ 기술을 사용한 이유가 부족함
⚠ 결과 및 성과가 구체적이지 않음

추천 개선 순서
1. 담당 기능 구체화
2. 문제 해결 과정 추가
3. 결과 또는 성과 추가
```

이 단계에서는 AI가 문장을 자동으로 바꾸지 않고 **어디를 어떻게 개선하면 좋은지 피드백**한다.

---

### 3.2 채용공고 찾기

사용자가 자연어로 원하는 직무를 질문할 수 있다.

예:

```text
"백엔드 개발자로 취업하고 싶은데 무슨 공고가 있어?"
```

또는

```text
"AI 엔지니어 신입 채용공고 찾아줘"
```

봇은 질문에서 검색 조건을 추출한다.

```text
Intent: JOB_SEARCH

직무: Backend Developer
경력: 신입
지역: 미지정
기술: 미지정
```

이후 채용공고 DB에서 조건에 맞는 공고를 검색한다.

#### 결과 예시

```text
백엔드 개발자 관련 공고를 찾았습니다.

1. A기업 Backend Developer
   Python / FastAPI / SQL

2. B기업 Python Backend Engineer
   Python / Django / Docker

3. C기업 Junior Backend Developer
   Java / Spring / MySQL

[공고 보기]
[내 이력서와 비교]
```

---

### 3.3 내 이력서 맞춤 공고 추천

현재 작성된 이력서를 기반으로 지원 적합도가 높은 공고를 우선 추천한다.

```text
Resume
   ↓
Resume Parsing
   ↓
User Skill Profile
   ↓
Job DB
   ↓
Matching Engine
   ↓
추천 채용공고 Ranking
```

초기 POC에서는 필수조건 판정과 추천 순위를 분리한다.

#### 1단계 — Hard Filter

지원이 불가능하거나 공고가 유효하지 않은 경우를 먼저 걸러낸다.

```text
공고 마감 여부
경력 최소/최대 조건
필수 학력
필수 자격증
근무 가능 지역
고용형태
근무 자격/비자 조건
```

필수조건을 확인할 수 없으면 탈락으로 단정하지 않고 `확인 필요` 상태로 둔다.

#### 2단계 — Ranking

Hard Filter를 통과했거나 확인이 필요한 공고를 다음 기준으로 정렬한다.

```text
직무 유사도
+
필수 기술 일치
+
우대 기술 일치
+
경력 조건
+
프로젝트 경험
```

예시 Ranking Score:

```text
직무 유사도        35%
필수 기술 일치     35%
우대 기술 일치     10%
프로젝트 유사도    10%
명시 조건 충족     10%
------------------------
최종 Ranking Score 100점
```

이 가중치는 Python 파이프라인과 Functions 양쪽에서 같은 값을 써야 한다.
값이 갈라지면 같은 이력서로 서로 다른 점수가 나온다. 실제 정의 위치는
`job_matching_bot/matching/ranking.py`의 `WEIGHT_*`와
`functions/src/jobCoachScoring.ts`의 `WEIGHTS`이며, 서로를 가리키는 주석을 둔다.

`경력 조건`은 별도 점수 항목이 아니라 Hard Filter에서 처리하고, 그 결과를
`명시 조건 충족` 점수(PASS 1.0, CHECK_REQUIRED 0.5)로 반영한다.

초기 점수는 채용 합격 확률이 아니다. UI에는 `적합도 87%` 대신 `추천 점수 87점` 또는
`적합도 높음/보통/낮음`으로 표시하고, 점수 옆에 추천 이유와 미확인 조건을 함께 제공한다.

#### 추천 결과 예시

```text
🎯 현재 이력서 기준 추천 공고

1. A기업 Backend Developer
   추천 점수 87점 · 적합도 높음

2. B기업 AI Backend Engineer
   추천 점수 82점 · 적합도 높음

3. C기업 Data Engineer
   추천 점수 76점 · 적합도 보통
```

---

## 4. 맞춤 공고 분석 + 학습 추천

학습 추천은 별도의 메인 기능으로 분리하지 않는다.

**맞춤 채용공고 분석 과정 안에 Skill Gap 분석과 학습 추천을 포함한다.**

```text
추천 채용공고
      ↓
사용자 공고 선택
      ↓
채용공고 요구역량 추출
      ↓
이력서 보유역량 추출
      ↓
Resume ↔ Job Matching
      ↓
Skill Gap Analysis
      ↓
Gap 원인 분류
```

Gap은 이력서에 적힌 내용만으로 실제 경험 유무를 단정하지 않도록 근거 상태를 먼저 분류한다.

```text
                         Skill Evidence
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
       근거 확인됨          근거 불충분         경험 없음 확인
          │                    │                    │
          ↓                    ↓                    ↓
   이력서 개선 피드백      사용자에게 질문        학습 추천
```

판정 상태는 다음과 같이 저장한다.

```text
EVIDENCED          이력서에서 관련 경험 근거 확인
NOT_EVIDENCED      이력서에서 근거를 찾지 못함
CONFIRMED_MISSING  사용자가 실제 경험이 없다고 확인
```

`NOT_EVIDENCED`는 역량 부족을 의미하지 않는다. 이 상태에서는 다음과 같이 확인 질문을 한다.

```text
이력서에서는 Docker 경험을 확인하지 못했습니다.
실제로 사용한 경험이 있나요?
```

---

### 4.1 경험은 있으나 표현이 부족한 경우

예:

채용공고 요구사항:

```text
REST API 설계 및 개발 경험
```

현재 이력서:

```text
FastAPI를 이용한 프로젝트 진행
```

AI 피드백:

```text
FastAPI 활용 경험은 확인되지만
REST API 개발 경험이 충분히 드러나지 않습니다.

다음 내용을 추가하는 것을 권장합니다.

- 어떤 API를 개발했는지
- 본인의 담당 기능
- 요청/응답 데이터
- DB 연동 여부
- 개발 결과
```

AI가 직접 경험을 만들어내거나 임의로 이력서를 수정하지 않는다.

---

### 4.2 사용자가 실제 경험이 없다고 확인한 경우

예:

채용공고 요구사항:

```text
Docker 경험 우대
```

현재 이력서:

```text
Docker 관련 경험 없음
```

사용자 확인:

```text
Docker를 실제 프로젝트에서 사용한 경험이 없습니다.
```

AI 결과:

```text
사용자 확인에 따라 Docker를 학습이 필요한 역량으로 분류했습니다.

이 부분은 이력서 문구를 수정하는 것보다
실제 프로젝트 경험을 추가하는 것을 추천합니다.

추천 학습

1. Docker 기본 개념
2. Image / Container 이해
3. Dockerfile 작성
4. FastAPI 프로젝트 Dockerizing
5. Docker Compose
6. 실제 서버 배포
```

즉,

```text
표현 문제 → Resume Feedback

근거 불충분 → 사용자 확인 질문

경험 없음 확인 → Learning Recommendation
```

으로 처리한다.

---

## 5. 전체 사용자 서비스 Flow

```text
이력서 작성
    ↓
[✨ AI 취업 코치]
    ↓
봇 패널 Open
    ↓
┌────────────────────────────────────┐
│                                    │
├─ 📄 이력서 분석                    │
│                                    │
├─ 🔎 채용공고 찾기                  │
│      ↓                             │
│   자연어 검색                      │
│      ↓                             │
│   채용공고 목록                    │
│                                    │
├─ 🎯 내 이력서 맞춤 공고 추천       │
│      ↓                             │
│   Resume ↔ Job Matching            │
│      ↓                             │
│   추천 Ranking                     │
│      ↓                             │
│   공고 선택                        │
│      ↓                             │
│   Skill Gap                        │
│      ↓                             │
│   ┌───────────┬───────────┬───────────┐ │
│   │ 표현 개선  │ 근거 불충분 │ 없음 확인  │ │
│   │ Resume    │ 사용자 질문 │ Learning  │ │
│   │ Feedback  │           │ Recommend │ │
│   └───────────┴───────────┴───────────┘ │
│                                    │
└─ 💬 자유 채팅                      │
```

---

## 6. 전체 기술 구조

```text
                     Flutter Web
                         │
             ┌───────────┴───────────┐
             │                       │
        Resume Editor          AI Coach Panel
             │                       │
             └───────────┬───────────┘
                         ↓
                  Firebase Auth
                         ↓
              Firebase / Backend API
                         │
        ┌────────────────┼─────────────────┐
        │                │                 │
   Firestore         Storage          FastAPI
        │                │                 │
   사용자 데이터      이력서 파일      AI / Matching
   채용공고 DB                           Engine
                                          │
                              ┌───────────┼───────────┐
                              │           │           │
                         Resume Parser  Job Parser  LLM
                              │           │
                              └─────┬─────┘
                                    ↓
                               Matching
                                    ↓
                               Skill Gap
                                    ↓
                      ┌─────────────┴─────────────┐
                      ↓                           ↓
                Resume Feedback             Learning
                                          Recommendation
```

### 6.1 인증 및 데이터 접근 경계

```text
Flutter Web
    ↓ Firebase Auth 로그인
Firebase ID Token 발급
    ↓ Authorization: Bearer <token>
FastAPI
    ↓ 토큰 검증 + UID 확인 + 권한 검사
Firestore / Storage / AI 서비스
```

- Flutter는 사용자의 이력서 초안과 화면 표시용 데이터만 직접 다룬다.
- FastAPI는 모든 요청에서 Firebase ID Token을 검증하고 `uid`를 서버에서 확정한다. 클라이언트가 보낸 `user_id`는 신뢰하지 않는다.
- `jobs`, `recommendations`, `analyses`의 생성·수정은 원칙적으로 Backend/Admin SDK만 수행한다.
- 운영자 기능은 Firebase Custom Claims 등 명시적인 역할 정보로 제한한다.
- Storage의 원본 이력서는 소유자와 허가된 백엔드만 읽을 수 있게 한다.
- 애플리케이션 로그에는 이력서 원문, 이메일, 전화번호, 토큰을 남기지 않는다.

---

## 7. Firebase 역할

### Firebase Auth

- 로그인
- 회원가입
- 사용자 UID 관리

### Firebase Storage

- 이력서 PDF / DOCX 저장
- 업로드 파일 관리

### Firestore

예시 Collection:

```text
users
resumes
jobs
job_raw
recommendations
analyses
analysis_runs
chat_sessions
chat_messages
```

데이터 소유권은 경로와 보안 규칙에서 명확히 분리한다.

```text
users/{uid}
users/{uid}/resumes/{resume_id}
users/{uid}/recommendations/{recommendation_id}
users/{uid}/analyses/{analysis_id}
jobs/{job_id}                         # 공용 읽기, 서버 쓰기
job_raw/{source}/{source_job_id}      # 서버 전용
```

#### resumes

```json
{
  "resume_id": "resume_001",
  "user_id": "user_001",
  "skills": [
    "Python",
    "FastAPI",
    "SQL"
  ],
  "projects": [],
  "experience": [],
  "parsed_text": "...",
  "parser_version": "resume-parser-0.1.0",
  "consent_version": "2026-09",
  "created_at": "2026-09-02T09:00:00+09:00",
  "updated_at": "2026-09-02T09:00:00+09:00"
}
```

#### jobs

```json
{
  "job_id": "job_001",
  "company": "A기업",
  "title": "Backend Developer",
  "description": "...",
  "responsibilities": [
    "백엔드 API 개발"
  ],
  "required_skills": [
    "Python",
    "FastAPI",
    "SQL"
  ],
  "preferred_skills": [
    "Docker",
    "AWS"
  ],
  "education": "학력무관",
  "experience": {
    "type": "경력",
    "min_years": 2,
    "max_years": null
  },
  "employment_type": "정규직",
  "country": "대한민국",
  "region": "서울",
  "address": "서울특별시 ...",
  "source": "JOBKOREA_POC",
  "source_job_id": "12345678",
  "source_url": "https://www.jobkorea.co.kr/...",
  "raw_text": "...",
  "status": "OPEN",
  "posted_at": "2026-09-01T00:00:00+09:00",
  "deadline": "2026-09-30T23:59:59+09:00",
  "first_seen_at": "2026-09-02T09:00:00+09:00",
  "last_seen_at": "2026-09-02T09:00:00+09:00",
  "content_hash": "sha256:...",
  "parser_version": "job-parser-0.1.0",
  "field_provenance": {
    "experience": {
      "method": "html_selector",
      "evidence": "경력 2년 이상",
      "confidence": 1.0
    },
    "required_skills": {
      "method": "llm_extraction",
      "evidence": "Python 및 FastAPI 기반 API 개발",
      "confidence": 0.92
    }
  }
}
```

`raw_text`와 `field_provenance`는 파싱 오류를 추적하고 AI 판단의 근거를 보여주기 위한 필드다. 검색·매칭에는 정규화 필드를 사용하되, 원문 근거를 함께 보존한다.

### 개인정보 보관 정책

- 원본 이력서와 파싱 결과의 보관 기간을 서비스 정책에 명시한다.
- 사용자가 계정을 삭제하면 이력서 원본, 파싱 결과, 분석 결과, 대화 기록을 함께 삭제하는 작업을 제공한다.
- 모델 호출에는 기능 수행에 필요한 최소 정보만 전달하며, 민감정보를 가능하면 마스킹한다.
- 운영 로그와 분석 데이터에는 사용자 원문 대신 익명화된 식별자와 상태 코드만 남긴다.

---

## 8. 채용공고 API 승인 여부에 따른 개발 방향

채용공고 수집부와 서비스 로직을 분리한다.

핵심 원칙:

> API 승인 여부에 관계없이 Flutter와 AI 봇은 같은 Job Schema를 사용한다.

```text
                 Job Data Source
                       │
             ┌─────────┴─────────┐
             │                   │
         API 승인 O           API 승인 X
             │                   │
        Official API       Mock / POC Crawling
             │                   │
             └─────────┬─────────┘
                       ↓
               Job Normalization
                       ↓
                  Common Schema
                       ↓
                     jobs
                       ↓
                Recommendation
                       ↓
                   AI Coach
```

이 구조를 사용하면 API 승인 후에도 프론트엔드와 추천 로직을 크게 수정할 필요가 없다.

---

## 9. Case A — 채용공고 API가 승인된 경우

### Pipeline

```text
채용공고 API
    ↓
API 요청
    ↓
Raw Job Data
    ↓
필드 Mapping
    ↓
Job Normalization
    ↓
중복 제거
    ↓
LLM / Rule 기반
요구역량 추출
    ↓
Firestore jobs
    ↓
Matching Engine
    ↓
AI 취업 코치
```

### 처리 항목

API에서 받은 데이터를 공통 Schema로 변환한다.

공통 Schema의 기준은 7장의 `jobs` 문서다. 각 수집기는 원본 응답을 `job_raw`에 먼저 보존한 뒤 정규화·검증을 거쳐 `jobs`에 upsert한다.

```text
job_id
source_job_id
company
title
career
education
country
region
address
employment_type
description
responsibilities
required_skills
preferred_skills
source
source_url
posted_at
deadline
status
first_seen_at
last_seen_at
content_hash
parser_version
field_provenance
```

API가 제공하지 않는 `required_skills`, `preferred_skills` 등은 공고 설명에서 별도로 추출할 수 있다.

```text
Job Description
      ↓
Job Parser
      ↓
Required Skill
Preferred Skill
Career
Education
Responsibilities
```

#### 장점

- 데이터 수집 안정성 증가
- 크롤링 유지보수 감소
- 정기적인 데이터 업데이트 가능
- 수집 파이프라인 자동화 용이

---

## 10. Case B — 채용공고 API가 승인되지 않은 경우

API 승인 전에도 서비스 개발을 멈추지 않는다.

초기 개발은 **Mock Data + 제한적인 POC 수집 데이터**로 진행한다.

### Pipeline

```text
Mock Job Data
      +
POC Crawling Data
      ↓
Job Normalization
      ↓
Common Job Schema
      ↓
Firestore jobs
      ↓
Matching Engine
      ↓
AI 취업 코치
```

### 10.1 Mock Data

초기에는 JSON / CSV 형태의 테스트 데이터를 사용한다.

```json
{
  "job_id": "test_001",
  "company": "테스트기업",
  "title": "Backend Developer",
  "required_skills": [
    "Python",
    "FastAPI",
    "SQL"
  ],
  "preferred_skills": [
    "Docker",
    "AWS"
  ]
}
```

Mock Data를 이용해 먼저 다음 기능을 완성한다.

```text
채용공고 검색
↓
맞춤 공고 추천
↓
공고 상세
↓
Resume Matching
↓
Skill Gap
↓
Resume Feedback
↓
Learning Recommendation
```

---

### 10.2 POC Crawling

API가 아직 없을 때 실제 채용공고 구조 검증을 위해 제한적인 POC 크롤링을 사용할 수 있다.

```text
채용 사이트
    ↓
HTTP Request
    ↓
HTML
    ↓
Parsing
    ↓
Job Raw Data
    ↓
Normalization
```

크롤링은 서비스 핵심 로직과 분리한다.

```text
crawler/
    ↓
jobs.json

또는

crawler/
    ↓
Firestore jobs
```

즉 추천 봇이 직접 채용 사이트를 크롤링하지 않는다.

```text
잘못된 구조

AI Bot
   ↓
실시간 크롤링
   ↓
결과 반환
```

대신 다음 구조를 사용한다.

```text
Crawler / API
      ↓
Job Database
      ↓
AI Bot
```

이렇게 해야 데이터 수집 실패가 챗봇 자체 장애로 연결되지 않는다.

### 10.3 수집 운영 규칙

```text
HTTP 응답 / API 응답
        ↓
job_raw 원본 보존
        ↓
Normalization + Schema Validation
        ↓
source + source_job_id 중복 제거
        ↓
content_hash 비교 후 jobs upsert
        ↓
검색 인덱스 / 추천 대상 반영
```

- 비로그인 상태에서 공개된 정보만 수집하며, 사이트 이용약관과 `robots.txt`를 사전에 확인한다.
- 브라우저와 유사한 `User-Agent`, `Accept-Language` 등 일반 요청 헤더는 사용할 수 있지만 로그인 우회, CAPTCHA 우회, 차단 회피는 하지 않는다.
- 요청 간격, 동시 요청 수, 일일 수집량을 제한하고 `429`·`5xx`에는 지수 백오프와 최대 재시도 횟수를 적용한다.
- 목록 URL과 상세 URL을 모두 보존하고, 같은 공고는 `source + source_job_id`를 기준으로 upsert한다.
- 공고가 더 이상 확인되지 않으면 즉시 삭제하지 않고 `OPEN → CLOSED/EXPIRED/REMOVED` 상태와 마지막 확인 시간을 기록한다.
- 상세 내용이 이미지로 제공되면 이미지 URL과 해시를 보존하고 OCR 결과, OCR 신뢰도, 사람이 확인할 필요가 있는지를 함께 기록한다.
- 선택자 오류, 필수 필드 누락, 파서 버전별 성공률을 모니터링하며 실패 원본은 재처리할 수 있게 둔다.

---

## 11. API 승인 전후 전환 전략

가장 중요한 부분은 `Job Repository` 추상화이다.

```text
Flutter / AI Coach
        ↓
Job Service
        ↓
Job Repository
        ↓
┌──────────────┬───────────────┐
│              │               │
Mock        Crawler         Official API
```

개발 초기:

```text
JobRepository
      ↓
Mock / Crawling
```

API 승인 이후:

```text
JobRepository
      ↓
Official API
```

위쪽 서비스 로직은 그대로 유지한다.

```text
Chat
Recommendation
Matching
Skill Gap
Resume Feedback
Learning Recommendation
```

서비스 계층에서는 **데이터 입력부만 교체**하는 형태를 유지한다. 다만 실제 전환 시에는 API 제공 범위, 호출 제한, 라이선스, 필드 의미 차이를 확인하고 Adapter 내부 매핑과 회귀 테스트를 수행해야 한다.

---

## 12. 백엔드 모듈 구조

### 12.1 목표 구조

```text
backend/
│
├─ job/
│   ├─ job_service
│   ├─ job_repository
│   ├─ job_normalizer
│   └─ job_parser
│
├─ resume/
│   ├─ resume_parser
│   ├─ resume_analyzer
│   └─ resume_service
│
├─ recommendation/
│   ├─ matching_engine
│   ├─ ranking
│   └─ skill_gap
│
├─ coach/
│   ├─ intent_classifier
│   ├─ chat_service
│   ├─ resume_feedback
│   └─ learning_recommendation
│
└─ api/
    ├─ resume
    ├─ jobs
    ├─ recommendation
    └─ chat
```

### 12.2 현재 Phase 1 구현

Phase 1에서는 위 구조를 `job_matching_bot` 패키지 안에 다음처럼 대응시켰다.
레이어는 한 방향으로만 의존한다.

```text
job_matching_bot/
│
├─ schemas/      Job, ResumeProfile 공통 스키마
├─ ingestion/    job_normalizer + job_parser에 해당
│   ├─ jobkorea.py        잡코리아 상세 → 공통 스키마
│   ├─ mock_source.py     통제된 Mock 공고
│   ├─ skill_extractor.py 텍스트 기반 기술 키워드 추출
│   ├─ it_filter.py       IT 직무 사전 필터
│   └─ collection.py      중복 제거, 수집 레코드 직렬화
├─ matching/     matching_engine + ranking
│   ├─ hard_filter.py
│   └─ ranking.py
├─ coach/        skill_gap + learning_recommendation
│   ├─ skill_gap.py
│   └─ learning_catalog.py
├─ reporting/    Markdown 보고서
├─ exporters/    Functions가 읽는 공고 데이터 생성
├─ pipeline.py   실행 순서만 담당
└─ validation.py 파이프라인 자체 검증
```

아직 구현하지 않은 것은 `resume_parser`(Phase 2), `job_repository` 추상화와
`intent_classifier`, `chat_service`(Phase 5)다.

### 12.3 API 계층의 현재 형태

이 문서 6장은 FastAPI를 전제로 그렸지만, Phase 1은 기존 웹앱이 이미 쓰고 있는
**Firebase Callable Function**으로 구현했다. 인증·소유권 검증 위치와 책임은 같다.

```text
Flutter Web
    ↓ Firebase Auth
analyzeResumeAndMatch (Callable Function, asia-northeast3)
    ↓ uid 확인 + 이력서 소유권 검사
Firestore
```

Callable Function은 클라이언트가 보낸 `userId`를 신뢰하지 않고 `request.auth.uid`로
소유권을 확인한다. 분석 결과는 다음 경로에 저장한다.

```text
cohorts/{cohortId}/resumes/{resumeId}/aiAnalyses/{analysisId}
```

7장의 `users/{uid}/...` 경로는 이 서비스가 기수(cohort) 단위 LMS 위에 올라가면서
`cohorts/{cohortId}/resumes/{resumeId}` 형태로 바뀌었다. 소유권을 경로가 아니라
문서의 `userId` 필드와 보안 규칙으로 확인한다는 원칙은 그대로다.

FastAPI로 옮기는 경우에도 위 모듈 구조와 판정 규칙은 그대로 두고 진입점만 바꾼다.

---

## 13. 챗봇 Intent 구조

사용자의 자연어 입력을 기능과 연결한다.

```text
사용자 메시지
      ↓
Intent Classification
      ↓
┌─────────────────────────┐
│ JOB_SEARCH              │
│ JOB_RECOMMEND           │
│ JOB_ANALYSIS            │
│ RESUME_ANALYSIS         │
│ RESUME_FEEDBACK         │
│ SKILL_GAP               │
│ LEARNING_RECOMMENDATION │
│ GENERAL_CHAT            │
└─────────────────────────┘
```

예:

```text
"백엔드로 취업하고 싶은데 공고 있어?"

→ JOB_SEARCH
```

```text
"내 이력서에 제일 잘 맞는 공고 추천해줘"

→ JOB_RECOMMEND
```

```text
"이 공고 나한테 맞아?"

→ JOB_ANALYSIS
```

```text
"내 이력서 한번 분석해줘"

→ RESUME_ANALYSIS
```

### 13.1 POC 라우팅 전략

POC에서는 모든 Intent를 한 번에 학습시키지 않는다.

- `채용공고 찾기`, `맞춤 공고 추천`, `이력서 분석` 버튼은 Intent를 명시적으로 고정한다.
- 자유 대화는 우선 `JOB_SEARCH`, `JOB_ANALYSIS`, `GENERAL_CHAT`만 분류한다.
- 선택 중인 `resume_id`, `job_id`는 서버 세션 상태로 관리하고 모델이 추측하지 않게 한다.
- `SKILL_GAP`, `RESUME_FEEDBACK`, `LEARNING_RECOMMENDATION`은 별도 사용자 Intent라기보다 `JOB_ANALYSIS` 이후의 내부 처리 단계로 사용한다.

---

## 14. AI 판단 결과와 안전장치

LLM은 최종 데이터베이스를 직접 수정하지 않는다. 먼저 정해진 JSON Schema로 후보 결과를 만들고, 서버가 검증한 결과만 저장한다.

```json
{
  "criterion": "Docker",
  "judgement": "NOT_EVIDENCED",
  "resume_evidence": [],
  "job_evidence": [
    "Docker 기반 배포 경험 우대"
  ],
  "confidence": 0.91,
  "model_version": "...",
  "prompt_version": "match-v1"
}
```

### 출력 검증 규칙

- 응답은 JSON Schema로 필수 필드, enum, 타입, 길이를 검증한다.
- 이력서와 채용공고 원문은 **분석 대상 데이터**일 뿐 시스템 지시가 아니다. 원문에 포함된 명령문을 실행하거나 따르지 않는다.
- 각 판단은 이력서와 공고의 문장 또는 필드 위치를 근거로 연결한다.
- 근거가 없으면 `NOT_EVIDENCED`로 표시하고, `CONFIRMED_MISSING`은 사용자의 확인 이후에만 저장한다.
- 회사, 경력, 기술, 학력, 수치 등을 원문에 없는 내용으로 생성하지 않는다.
- Schema 검증 실패 시 제한된 횟수만 재시도하고, 계속 실패하면 규칙 기반 결과 또는 사용자에게 확인이 필요한 상태로 전환한다.
- `model_version`, `prompt_version`, `parser_version`, 입력 해시를 저장해 재현과 회귀 테스트가 가능하게 한다.
- 같은 입력과 버전 조합은 캐시해 지연시간과 비용을 관리한다.

### 학습 추천 근거

학습 자료는 검증된 Catalog에서만 선택한다.

```text
provider
title
url
level
estimated_duration
skills
last_checked_at
```

모델이 존재하지 않는 강의나 자격증 URL을 만들어내지 않게 하고, 링크 유효성과 최종 확인 날짜를 화면에 표시한다.

### API 계약 예시

```text
POST /v1/resumes/{resume_id}/analyze
GET  /v1/jobs
POST /v1/recommendations
POST /v1/jobs/{job_id}/match
POST /v1/chat
```

- 모든 보호 API는 Firebase ID Token을 검증하고 리소스 소유권을 확인한다.
- 요청에는 추적용 `request_id`를 부여하고, 중복 분석 요청은 idempotency key로 제어한다.
- 시간이 오래 걸리는 분석은 `QUEUED → RUNNING → SUCCEEDED/FAILED` 상태로 조회할 수 있게 한다.
- 오류 응답은 인증 실패, 입력 검증 실패, 외부 수집 실패, 모델 실패를 구분한다.

---

## 15. 최종 Pipeline

```text
                     Flutter Web App
                           │
                     Resume Editor
                           │
                  [✨ AI 취업 코치]
                           │
                           ↓
                      AI Coach
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
 Resume Analysis       Job Search      Resume-Based
                                       Recommendation
        │                  │                  │
        │                  ↓                  ↓
        │              Job Database      Job Ranking
        │                  │                  │
        │                  └──────────┬───────┘
        │                             ↓
        │                       Job Selection
        │                             ↓
        │                     Resume ↔ Job
        │                         Matching
        │                             ↓
        │                        Skill Gap
        │          ┌─────────────────┼─────────────────┐
        │          │                 │                 │
        │       근거 확인됨        근거 불충분        없음 확인
        │          │                 │                 │
        │   Resume Feedback       사용자 질문          Learning
        │                                           Recommendation
        │          │                 │                 │
        └──────────┴─────────────────┴────────┬────────┘
                                             ↓
                              사용자가 직접 수정
                                             ↓
                                  재분석
```

채용공고 데이터 입력은 별도로 관리한다.

```text
                     Job Data
                        │
               ┌────────┴────────┐
               │                 │
           API 승인           API 미승인
               │                 │
        Official API       Mock / POC Crawl
               │                 │
               └────────┬────────┘
                        ↓
                Job Normalization
                        ↓
                 Common Job Schema
                        ↓
                    Firestore
                        ↓
                     AI Coach
```

---

## 16. 개발 우선순위

### Phase 0 — 계약·보안·평가 기준

- Resume / Job / Match 공통 Schema와 enum 확정
- Firebase 인증 흐름, 데이터 소유권, Firestore·Storage 보안 규칙 확정
- LLM JSON 출력 Schema와 근거 필드 확정
- 개인정보 동의, 보관 기간, 삭제 절차 정의
- 테스트 이력서와 공고로 평가 세트 및 완료 기준 작성

### Phase 1 — Mock 기반 Vertical Slice

테스트 이력서 1개와 Mock 공고 20개로 다음 한 흐름을 먼저 완주한다.

```text
로그인
→ 이력서 선택
→ 공고 검색/추천
→ 공고 선택
→ Hard Filter + Ranking
→ 근거가 포함된 Skill Gap
→ Resume Feedback 또는 Learning Recommendation
→ 사용자 수정
→ 재분석
```

- AI 취업 코치 버튼과 우측 패널
- 이력서 분석·맞춤 공고 추천·채용공고 찾기 버튼
- 공고 카드, 상세 정보, 추천 근거 표시
- 분석 실패·근거 부족·재시도 상태 표시

### Phase 2 — Resume Pipeline

- PDF / DOCX 업로드와 안전한 파일 검증
- 이력서 데이터 구조화
- Resume Parsing과 Skill Profile 생성
- 원문 근거 위치와 parser version 저장

### Phase 3 — Job Ingestion Pipeline

API 미승인:

- Mock Data
- 비로그인 공개 페이지 대상 제한적 POC Crawling
- Raw 보존, 정규화, 검증, 중복 제거, 만료 처리

API 승인:

- Official API Adapter 연결
- 필드 매핑과 라이선스·호출 제한 확인
- 수집 자동화와 회귀 테스트

### Phase 4 — Matching

- Hard Filter: 마감, 경력, 학력, 지역, 고용형태 등 명시 조건
- Ranking: 직무·필수역량·우대역량·프로젝트 관련성
- 근거와 함께 추천 점수 또는 상·중·하 등급 제공
- `EVIDENCED / NOT_EVIDENCED / CONFIRMED_MISSING` 판정

### Phase 5 — AI Coach

- 제한된 Intent Classification
- 채용공고 자연어 검색과 추천
- Job Analysis와 Skill Gap
- Resume Feedback와 검증된 학습 자료 추천
- 사용자 확인을 통한 미보유 역량 확정

### Phase 6 — 운영 고도화

- Embedding 기반 Semantic Matching과 랭킹 개선
- 사용자 수정 전후 분석 비교
- 채팅 Context 만료·요약·삭제 정책
- 비용, 지연시간, 실패율, 파서 오류 모니터링
- 프롬프트·모델·파서 버전별 회귀 평가

### 완료 기준

- 이력서/공고 필수 필드 파싱 정확도를 평가 세트로 측정한다.
- Hard Filter 조건 누락률과 잘못된 통과율을 별도로 측정한다.
- 추천 품질은 `Precision@5`와 사람의 관련성 평가를 함께 사용한다.
- 사용자에게 표시되는 모든 Skill Gap과 추천 이유는 원문 근거를 포함한다.
- 원문에 없는 경력·기술·회사 정보를 생성하는 비율은 0%를 목표로 한다.
- API별 p95 지연시간, 모델 비용, 실패율의 허용 기준을 정한다.
- 수정 전후 같은 평가 세트를 실행해 품질 하락을 막는다.

---

## 17. 핵심 서비스 정의

최종적으로 이 기능은 단순한 `채용공고 봇` 또는 `이력서 첨삭 봇`이 아니다.

> **사용자가 이력서를 작성하면서 원하는 직무의 채용공고를 탐색하고, 명시 조건과 근거 기반 적합도를 분석한 뒤, 표현이 부족한 부분에는 이력서 피드백을 제공하고 근거가 없는 부분은 사용자에게 확인하며 실제 경험이 없다고 확인된 역량에는 학습 방향을 추천하는 AI 취업 코치**

라는 형태로 정의한다.

핵심 Flow는 다음 한 줄로 정리할 수 있다.

```text
이력서 작성
→ AI 분석
→ 채용공고 탐색/추천
→ 공고 선택
→ Resume Matching
→ Skill Gap
→ 이력서 피드백 또는 학습 추천
→ 사용자 수정
→ 재분석
```
