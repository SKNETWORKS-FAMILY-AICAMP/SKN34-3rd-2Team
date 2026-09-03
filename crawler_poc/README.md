# 잡코리아 POC 크롤러 (별도 폴더)

`job_matching_bot/` 패키지와는 완전히 분리된 실험용 폴더다. 기존 `job_matching_bot` 코드는
전혀 건드리지 않는다. 결과물만 이후 `job_matching_bot/fixtures/`에 새 파일로 옮겨 사용한다.

## 왜 별도 폴더인가

`job_matching_bot/crawlers/skill_extractor.py`는 텍스트에서 기술 키워드를 뽑아내는
"추출기"일 뿐, 실제로 잡코리아 사이트에 접속해서 페이지를 가져오는 "크롤러"는
프로젝트에 아직 없었다. 이 폴더가 그 크롤러 POC다.

## 실행 전 확인한 제약 사항

1. **robots.txt (jobkorea.co.kr, 2026-04-01 기준)** — `ClaudeBot` 등 AI 에이전트 그룹을 포함해
   아래 두 경로만 명시적으로 허용한다.
   - `Allow: /recruit/joblist` (공고 목록)
   - `Allow: /Recruit/GI_Read` (공고 상세)
   이 스크립트는 이 두 경로만 요청하도록 코드로 강제한다(`ALLOWED_PATH_PREFIXES`).
   그 외 경로(`/Search/`, `/login/`, `/RecrtMng/` 등)는 절대 요청하지 않는다.

2. **서버 측 봇 차단(WAF/캡차)** — 실제로 확인해보니, robots.txt 허용 여부와 별개로
   일반 HTTP 요청(브라우저가 아닌 요청)에는 목록·상세 페이지 모두 "보안정책에 의하여
   이용이 일시적으로 중지되었습니다" 캡차 차단 페이지가 떴다. 그래서 `requests` 기반이
   아니라 **실제 Chromium 브라우저를 띄우는 Playwright**로 구현했다.

3. **캡차는 우회하지 않는다.** 차단 페이지 문구(`BLOCK_PAGE_MARKERS`)가 감지되면
   스크립트는 즉시 멈춘다. 자동으로 풀거나 우회하지 않고, 화면에 뜬 브라우저 창을
   사람이 직접 보고 판단하도록 한다.

4. **반드시 로컬 PC에서 실행할 것.** 클라우드/데이터센터 IP로는 이미 접속 시점부터
   차단 페이지가 뜨는 것을 확인했다. 이 스크립트는 사용자 PC의 Playwright로 실행해야
   정상적인 페이지를 받을 가능성이 있다.

5. **요청 간격을 둔다.** 상세 페이지를 열 때마다 3~8초 랜덤 대기를 넣는다
   (`_human_delay`). 한 번 실행에 수집하는 공고 수도 `--limit` 기본값 10건으로
   POC 규모로 제한했다.

## 알려진 한계 (실제 DOM 미검증)

이 세션에서는 잡코리아 페이지가 계속 차단 응답만 반환해서, **실제 렌더링된 HTML
구조를 눈으로 확인하지 못한 채로 작성했다.** 그래서:

- `json_ld` (schema.org `JobPosting`) 추출은 `<script type="application/ld+json">`을
  그대로 파싱하는 표준 방식이라 비교적 안정적이다. `title`, `description`,
  `datePosted`, `validThrough`, `employmentType`, `experienceRequirements`,
  `educationRequirements`, `hiringOrganization.name`, `jobLocation.address` 등
  대부분의 필드가 여기서 나온다.
- `list_item.conditions`(경력/학력/지역/고용형태 조건 chip), `list_item.company`,
  `query_data.CORP_INFO.info.companyTypeName`(기업형태)은 이 스크립트가 채우지 않고
  빈 값으로 둔다. 실제 DOM class명을 모르기 때문이다.
  다행히 `job_matching_bot.matching.pipeline.normalize_jobkorea()`는 conditions가
  비어 있으면 `json_ld` 값으로 자동 대체(fallback)하도록 이미 설계되어 있어서,
  정규화 자체는 깨지지 않는다. 다만 `company_type`은 "미기재"로 남는다.
- `description_blocks`는 몇 가지 후보 selector(`CANDIDATE_DESCRIPTION_SELECTORS`)를
  순서대로 시도한다. 실제 페이지를 열어보고 정확한 selector로 바꿔야 `required_skills`
  키워드 추출 정확도가 fixture 데이터 수준으로 올라온다.

**즉, 이 스크립트를 한 번 실행해서 나온 JSON을 열어보고, 위 필드들이 비어 있거나
이상하면 selector를 실제 DOM에 맞게 고쳐야 완성된다.** 브라우저 창이 뜬 채로
실행되므로(`--headless` 안 주면 기본이 창 띄우기), 실행 중 개발자 도구(F12)로
실제 class명을 확인해서 `CANDIDATE_DESCRIPTION_SELECTORS`와 conditions 추출 부분에
반영하면 된다.

## 설치 및 실행

```powershell
cd crawler_poc
pip install -r requirements.txt
playwright install chromium

python crawl_jobkorea.py --limit 5
```

기본 목록 URL은 `dutyStcd=1`(백엔드 개발 직무 코드 예시)로 되어 있다. 실제 잡코리아
직무 코드 체계에 맞게 `--list-url`로 바꿔서 실행한다.

```powershell
python crawl_jobkorea.py --list-url "https://www.jobkorea.co.kr/recruit/joblist?menucode=duty&dutyStcd=1" --limit 10
```

결과는 기본적으로 `crawler_poc/output/jobkorea_raw.json`에 저장된다. 이 파일은
`job_matching_bot/fixtures/jobkorea_detail_first_page.json`과 동일한 레코드 구조이므로,
검증 후 `job_matching_bot/fixtures/` 아래에 새 이름(예: `jobkorea_poc_batch2.json`)으로
복사해서 기존 파이프라인에 바로 넣어볼 수 있다.

```python
from job_matching_bot.matching.pipeline import normalize_jobkorea
import json

records = json.loads(open("job_matching_bot/fixtures/jobkorea_poc_batch2.json", encoding="utf-8").read())
jobs = [normalize_jobkorea(r) for r in records]
```

## 다음에 할 일

1. 브라우저 창을 띄운 채로 한 번 실행해서 실제 목록/상세 페이지가 정상적으로
   렌더링되는지 눈으로 확인한다 (차단 문구가 뜨면 즉시 멈추고 사람이 판단).
2. F12 개발자 도구로 조건 chip, 회사명, 기업형태가 있는 실제 selector를 확인하고
   `crawl_jobkorea.py`의 해당 부분을 채운다.
3. `output/jobkorea_raw.json`을 `job_matching_bot/fixtures/`로 옮기고
   `normalize_jobkorea()`로 정상 정규화되는지 확인한다.
4. 운영 전환 시에는 `job_matching_bot/ai_job_coach_pipeline.md` 10.3절의 수집 운영
   규칙(재시도/백오프, `source_job_id` 기준 upsert, 상태 전이 기록 등)을 추가로
   반영한다.
