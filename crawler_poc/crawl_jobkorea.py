"""잡코리아 채용공고 POC 크롤러 (Playwright 기반, 로컬 PC 전용 실행).

⚠️ 반드시 사용자 로컬 PC에서 실행할 것. 클라우드/데이터센터 IP에서는
   jobkorea.co.kr이 즉시 보안 차단 페이지를 띄우는 것을 확인했다.
⚠️ 이 스크립트는 CAPTCHA/차단을 우회하지 않는다. 차단이 감지되면 즉시 중단하고
   사람이 브라우저 창에서 직접 확인하도록 안내한다. 로그인 우회, 헤더 위조를 통한
   차단 회피 등은 구현하지 않는다.

robots.txt (jobkorea.co.kr, 2026-04-01 기준) 에서 명시적으로 허용된 경로만 접근한다.
    Allow: /recruit/joblist   (공고 목록)
    Allow: /Recruit/GI_Read   (공고 상세)
그 외 경로(/Search/, /login/, /RecrtMng/ 등)는 절대 접근하지 않는다.

수집 결과는 job_matching_bot/fixtures/jobkorea_detail_first_page.json 과 동일한
레코드 스키마(job_id / source_url / list_item / json_ld / query_data / description_blocks)로
저장하므로, job_matching_bot.matching.pipeline.normalize_jobkorea() 를 그대로 재사용할 수 있다.

단, list_item.conditions / company_type 등 일부 필드는 실제 페이지 DOM 검증 전이라
비어 있을 수 있다 (자세한 내용은 README.md 참고). json_ld(schema.org JobPosting)는
표준 포맷이라 상대적으로 안정적으로 추출된다.

사전 준비:
    pip install -r requirements.txt
    playwright install chromium

실행 예시:
    python crawl_jobkorea.py --limit 10
    python crawl_jobkorea.py --list-url "https://www.jobkorea.co.kr/recruit/joblist?menucode=duty&dutyStcd=1" --limit 5
"""

from __future__ import annotations

import argparse
import json
import random
import re
import time
from pathlib import Path
from urllib.parse import urljoin, urlparse

from playwright.sync_api import Page, sync_playwright

BASE_URL = "https://www.jobkorea.co.kr"

# robots.txt에서 명시적으로 허용된 경로만 접근한다. 이 목록 밖의 경로는 요청하지 않는다.
ALLOWED_PATH_PREFIXES = ("/recruit/joblist", "/Recruit/GI_Read")

# 차단/캡차 페이지에서 흔히 보이는 문구. 하나라도 감지되면 즉시 중단한다.
BLOCK_PAGE_MARKERS = (
    "보안정책에 의하여",
    "일시적으로 중지",
    "자동입력 방지",
    "비정상적인 접근",
    "이용이 제한",
)

DETAIL_URL_RE = re.compile(r"/Recruit/GI_Read/(\d+)")

# 상세 페이지 본문 후보 selector. 실제 DOM을 열어보고 필요하면 조정할 것.
CANDIDATE_DESCRIPTION_SELECTORS = (
    ".tbCol .cont",
    ".recruit-detail",
    "#container",
)


class BlockedByTargetSiteError(RuntimeError):
    """차단/캡차 페이지가 감지되어 자동화를 중단해야 할 때 발생시킨다."""


def _is_allowed_path(url: str) -> bool:
    path = urlparse(url).path
    return any(path.startswith(prefix) for prefix in ALLOWED_PATH_PREFIXES)


def _guard_allowed(url: str) -> None:
    if not _is_allowed_path(url):
        raise ValueError(
            f"robots.txt 허용 경로가 아닙니다: {url}\n허용 경로: {ALLOWED_PATH_PREFIXES}"
        )


def _human_delay(min_s: float = 3.0, max_s: float = 8.0) -> None:
    time.sleep(random.uniform(min_s, max_s))


def _check_blocked(page: Page) -> None:
    try:
        text = page.inner_text("body")
    except Exception:
        return
    if any(marker in text for marker in BLOCK_PAGE_MARKERS):
        raise BlockedByTargetSiteError(
            "잡코리아가 이 세션을 차단/캡차 요구 중입니다. 자동화를 중단합니다. "
            "브라우저 창에서 직접 확인하고, 필요하면 사람이 캡차를 푼 뒤 다시 실행하세요."
        )


def collect_detail_urls_from_list(page: Page, list_url: str, limit: int) -> list[str]:
    _guard_allowed(list_url)
    page.goto(list_url, wait_until="domcontentloaded")
    _check_blocked(page)

    hrefs = page.eval_on_selector_all("a[href]", "els => els.map(e => e.getAttribute('href'))")
    detail_urls: list[str] = []
    seen: set[str] = set()
    for href in hrefs:
        if not href:
            continue
        match = DETAIL_URL_RE.search(href)
        if not match:
            continue
        job_id = match.group(1)
        if job_id in seen:
            continue
        seen.add(job_id)
        detail_urls.append(urljoin(BASE_URL, f"/Recruit/GI_Read/{job_id}"))
        if len(detail_urls) >= limit:
            break
    return detail_urls


def _extract_json_ld(page: Page) -> list[dict]:
    raw_scripts = page.eval_on_selector_all(
        "script[type='application/ld+json']", "els => els.map(e => e.textContent)"
    )
    parsed: list[dict] = []
    for raw in raw_scripts:
        if not raw:
            continue
        try:
            value = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if isinstance(value, list):
            parsed.extend(v for v in value if isinstance(v, dict))
        elif isinstance(value, dict):
            parsed.append(value)
    return parsed


def _extract_description_blocks(page: Page) -> list[dict]:
    """본문 텍스트를 보수적으로 추출한다.

    ⚠️ 실제 상세 페이지 DOM 클래스명은 검증 전이므로 후보 selector를 순서대로
    시도한다. 전부 실패하면 빈 리스트를 반환한다 (파이프라인은 description이
    비어 있어도 동작하지만, required_skills 추출 정확도는 떨어진다).
    """
    for selector in CANDIDATE_DESCRIPTION_SELECTORS:
        try:
            text = page.inner_text(selector)
        except Exception:
            continue
        text = text.strip()
        if text:
            return [{"description_type": "DESCRIPTION", "status": 200, "text": text}]
    return []


def collect_detail_record(page: Page, detail_url: str) -> dict:
    _guard_allowed(detail_url)
    page.goto(detail_url, wait_until="domcontentloaded")
    _check_blocked(page)

    match = DETAIL_URL_RE.search(detail_url)
    job_id = match.group(1) if match else ""

    json_ld = _extract_json_ld(page)
    description_blocks = _extract_description_blocks(page)
    title = json_ld[0].get("title", "") if json_ld else ""

    return {
        "job_id": job_id,
        "source_url": detail_url,
        "list_item": {
            # 목록 페이지 조건 chip(conditions)은 이 스크립트에서 채우지 않는다.
            # job_matching_bot.matching.pipeline.normalize_jobkorea()는 conditions가
            # 비어 있으면 json_ld 값(experienceRequirements/educationRequirements/
            # jobLocation/employmentType)으로 자동 대체하므로 정규화 자체는 깨지지 않는다.
            "company": "",
            "title": title,
            "conditions": [],
            "keywords": "",
            "posted_at": "",
            "deadline": "",
            "url": detail_url,
        },
        "json_ld": json_ld,
        # 기업형태(companyTypeName)는 잡코리아가 별도 API로 불러오는 값이라
        # 이 스크립트에서는 채우지 못한다. normalize_jobkorea()는 없으면 "미기재"로 채운다.
        "query_data": {"CORP_INFO": {"info": {}}},
        "description_blocks": description_blocks,
    }


def run(list_url: str, limit: int, output_path: Path, headless: bool) -> None:
    results: list[dict] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=headless)
        context = browser.new_context(locale="ko-KR")
        page = context.new_page()

        try:
            detail_urls = collect_detail_urls_from_list(page, list_url, limit)
        except BlockedByTargetSiteError as exc:
            print(f"[중단] {exc}")
            browser.close()
            return

        print(f"목록에서 상세 URL {len(detail_urls)}건 발견")

        for index, detail_url in enumerate(detail_urls, start=1):
            print(f"[{index}/{len(detail_urls)}] {detail_url}")
            try:
                record = collect_detail_record(page, detail_url)
            except BlockedByTargetSiteError as exc:
                print(f"[중단] {exc}")
                break
            results.append(record)
            if index < len(detail_urls):
                _human_delay()

        browser.close()

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{len(results)}건 저장 완료: {output_path.resolve()}")


def main() -> int:
    parser = argparse.ArgumentParser(description="잡코리아 POC 크롤러 (Playwright, 로컬 실행 전용)")
    parser.add_argument(
        "--list-url",
        default=f"{BASE_URL}/recruit/joblist?menucode=duty&dutyStcd=1",
        help="robots.txt에서 허용하는 /recruit/joblist 경로의 목록 URL",
    )
    parser.add_argument(
        "--limit", type=int, default=10, help="이번 실행에서 수집할 최대 공고 수 (POC 기본값 10)"
    )
    parser.add_argument("--output", type=Path, default=Path("output/jobkorea_raw.json"))
    parser.add_argument(
        "--headless",
        action="store_true",
        help="헤드리스로 실행한다 (기본값은 창을 띄워서 실행 - 차단/캡차를 사람이 바로 확인하기 위함).",
    )
    args = parser.parse_args()

    run(args.list_url, args.limit, args.output, headless=args.headless)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
