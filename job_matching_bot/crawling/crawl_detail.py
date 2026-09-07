"""사람인 채용공고 상세 POC 크롤러 (requests + BeautifulSoup).

`crawl_saramin.py`가 만든 목록 JSON을 입력으로 받아, 각 공고의 상세 페이지에서
모집조건과 상세요강을 추가로 수집한다.

## 확인한 제약

1. **상세 페이지 경로** — 목록의 링크(`/zf_user/jobs/relay/view`)는 껍데기라
   본문이 없다. 실제 본문은 `/zf_user/jobs/view?rec_idx=N`에 있다.
   robots.txt의 `User-agent: *`에 이 경로는 Disallow가 없다.

2. **헤드헌팅 공고는 제외한다.** robots.txt가 아래를 명시적으로 막는다.
       Disallow: /zf_user/jobs/view/etc
       Disallow: /zf_user/jobs/view*innerCampaign=headhuntingView
   `SKIP_URL_MARKERS`로 걸러낸다.

3. **상세요강 이미지는 받지 않는다.** 본문이 이미지인 공고가 표본의 약 42%인데,
   이미지 호스트(`saraminimage.co.kr`)의 robots.txt는 `Disallow: /`에 화이트리스트
   방식이고 공고 이미지 경로(`/recruit/os_hk_26/` 등)는 허용 목록에 없다.
   그래서 이미지는 **URL과 URL 해시만 기록**하고 `needs_human_review`로 표시한다.
   OCR은 하지 않는다.

4. 차단/캡차/429는 우회하지 않는다. 감지되면 즉시 멈춘다.

5. 요청 간격을 둔다(기본 3~5초). 병렬로 돌리지 않는다.

## 규모 수집을 위한 동작

수천 건을 몇 시간에 걸쳐 받으므로 **끊겨도 잃지 않고, 다시 시작하면 이어서** 간다.

- 한 건 받을 때마다 `.jsonl`에 바로 붙여 쓴다.
- `--resume`(기본): 출력 파일에 이미 있는 공고는 건너뛴다.
- `--raw-root`: 저장소 원본(`job_raw/SARAMIN_POC/`)에 `--refresh-days` 안에 받은
  공고도 건너뛴다. 매일 증분으로 돌릴 때 새 공고만 받게 된다.
- `--max-minutes`: 시간이 다 되면 깨끗이 멈춘다. 다음에 이어서 돌리면 된다.
- 5xx·연결 오류는 한 번 더 시도한다. 429는 재시도하지 않고 멈춘다.

사용:
    python crawl_saramin.py --it --all
    python crawl_saramin_detail.py --max-minutes 180
    python crawl_saramin_detail.py --max-minutes 180        # 끊겼으면 그대로 다시
    python -m job_matching_bot.ingest --source SARAMIN_POC --observed job_matching_bot/artifacts/raw/saramin_raw.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import requests
from bs4 import BeautifulSoup

from job_matching_bot.crawling.http_session import (
    LIST_PAGE_URL,
    BlockedByTargetSiteError,
    check_response,
    navigation_headers,
    new_session,
    polite_delay,
)
from job_matching_bot.ingestion.record_files import (
    append_record,
    latest_by_id,
    read_records,
)

BASE_URL = "https://www.saramin.co.kr"
DETAIL_URL = f"{BASE_URL}/zf_user/jobs/view"
ALLOWED_PATH = "/zf_user/jobs/view"
SOURCE = "SARAMIN_POC"

# robots.txt가 막는 상세 페이지 변형. 하나라도 걸리면 요청하지 않는다.
SKIP_URL_MARKERS = ("innerCampaign=headhuntingView", "/zf_user/jobs/view/etc")



# 상세요강 텍스트가 이 길이 미만이면 본문이 이미지에 있다고 본다.
# 표본에서 텍스트만 있는 공고는 중앙값 1,391자, 이미지형은 400~700자대였다.
TEXT_BODY_MIN_CHARS = 800

# 일시 오류(5xx, 연결 끊김)는 이만큼 쉬고 한 번 더 시도한다.
RETRY_DELAY_RANGE = (15.0, 30.0)

KST = timezone(timedelta(hours=9))




def _guard_allowed(url: str) -> None:
    if not urlparse(url).path.startswith(ALLOWED_PATH):
        raise ValueError(f"허용 경로가 아닙니다: {url}")
    if any(marker in url for marker in SKIP_URL_MARKERS):
        raise ValueError(f"robots.txt가 막는 경로입니다: {url}")




def _section_name(section: Any) -> str:
    heading = section.select_one("h2")
    return heading.get_text(" ", strip=True) if heading else ""


def _dl_pairs(section: Any) -> dict[str, str]:
    """섹션 안의 dt/dd 쌍을 뽑는다. 사이트가 항목을 늘려도 그대로 담긴다."""
    pairs: dict[str, str] = {}
    for dl in section.select("dl"):
        key = dl.select_one("dt")
        value = dl.select_one("dd")
        if key and value:
            name = key.get_text(" ", strip=True)
            if name:
                pairs[name] = value.get_text(" ", strip=True)
    return pairs


def parse_detail(html: str, rec_idx: str, url: str) -> dict[str, Any]:
    soup = BeautifulSoup(html, "html.parser")
    sections: dict[str, dict[str, str]] = {}
    body_text = ""
    body_images: list[str] = []

    for section in soup.select(".jv_cont"):
        name = _section_name(section)
        if not name:
            continue
        pairs = _dl_pairs(section)
        if pairs:
            sections[name] = pairs
        if "상세" in name:
            body_text = section.get_text("\n", strip=True)
            body_images = [
                img.get("src", "")
                for img in section.find_all("img")
                if (img.get("src") or "").startswith("http")
            ]

    # 이미지는 받지 않으므로 내용 해시는 만들 수 없다. URL 해시만 남겨서
    # 나중에 이미지가 교체됐는지 비교할 수 있게 한다.
    image_records = [
        {
            "url": src,
            "url_sha256": hashlib.sha256(src.encode("utf-8")).hexdigest(),
            "fetched": False,
            "reason": "이미지 호스트 robots.txt 비허용 경로",
        }
        for src in dict.fromkeys(body_images)
    ]
    has_text_body = len(body_text) >= TEXT_BODY_MIN_CHARS

    # 페이지 하단의 해시태그 블록. 기업이 등록 때 고른 직무·전문분야·기술스택·지역
    # 분류가 전부 들어 있고 모든 공고에 있다. 3,100건 실측에서 숨김 분류 블록은
    # 2%에만 있었지만 이 블록은 표준 UI라, 기술스택의 실제 출처는 여기다.
    tags: list[str] = []
    for block in soup.select("div.tags"):
        for token in block.get_text(" ", strip=True).split():
            if token.startswith("#") and len(token) > 1 and token[1:] not in tags:
                tags.append(token[1:])

    return {
        "source": SOURCE,
        "source_job_id": rec_idx,
        "source_url": url,
        "fetched_at": datetime.now(KST).isoformat(timespec="seconds"),
        "sections": sections,
        "conditions": sections.get("핵심 정보", {}),
        "benefits": sections.get("복리후생", {}),
        "apply": sections.get("접수기간 및 방법", {}),
        "company_info": sections.get("기업정보", {}),
        "description": body_text,
        "description_images": image_records,
        "tags": tags,
        # 본문이 이미지에만 있으면 요구역량을 텍스트로 확보하지 못한 상태다.
        "needs_human_review": bool(image_records) and not has_text_body,
        "parser_version": "saramin-detail-poc-0.3.0",
    }


def fetch_detail(session: requests.Session, rec_idx: str, timeout: int = 30) -> dict[str, Any]:
    url = f"{DETAIL_URL}?rec_idx={rec_idx}"
    _guard_allowed(url)
    # 목록에서 공고를 클릭해 들어가는 문서 이동이다. Referer는 목록 페이지.
    response = session.get(url, headers=navigation_headers(LIST_PAGE_URL), timeout=timeout)
    check_response(response)
    return parse_detail(response.text, rec_idx, url)


def fresh_raw_ids(raw_root: Path | None, refresh_days: int, now: datetime | None = None) -> set[str]:
    """저장소 원본 중 최근에 받은 공고의 ID. 이건 다시 받지 않는다."""
    if raw_root is None:
        return set()
    base = Path(raw_root) / SOURCE
    if not base.exists():
        return set()
    now = now or datetime.now(KST)
    cutoff = now - timedelta(days=refresh_days)
    fresh: set[str] = set()
    for path in base.glob("*.json"):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            fetched = datetime.fromisoformat(payload["fetched_at"])
        except (ValueError, KeyError, json.JSONDecodeError):
            continue
        if fetched.tzinfo is None:
            fetched = fetched.replace(tzinfo=KST)
        if fetched >= cutoff:
            fresh.add(str(payload.get("source_job_id") or path.stem))
    return fresh


def done_record_ids(records: list[dict[str, Any]], require_field: str | None = None) -> set[str]:
    """이미 받은 것으로 칠 공고 ID. 같은 공고가 여러 번 있으면 마지막 것을 기준으로 본다.

    `require_field`를 주면 그 필드가 없는 레코드는 "덜 받은 것"으로 보고 제외한다.
    파서에 필드가 추가됐을 때 예전 레코드만 골라 다시 받기 위해서다.
    """
    latest = latest_by_id(records)
    if require_field is None:
        return set(latest)
    return {job_id for job_id, record in latest.items() if require_field in record}


def plan_targets(
    listings: list[dict[str, Any]],
    *,
    done_ids: set[str],
    fresh_ids: set[str],
    limit: int | None,
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    """이번 실행에서 받을 공고를 고른다. (대상, 건너뛴 이유별 건수)를 돌려준다.

    순수 함수라 네트워크 없이 검증할 수 있다.
    """
    targets: list[dict[str, Any]] = []
    skipped = {"no_id": 0, "already_in_output": 0, "fresh_in_raw": 0, "robots": 0}
    seen: set[str] = set()
    for item in listings:
        rec_idx = str(item.get("source_job_id") or "")
        if not rec_idx or rec_idx in seen:
            skipped["no_id"] += 1 if not rec_idx else 0
            continue
        seen.add(rec_idx)
        if rec_idx in done_ids:
            skipped["already_in_output"] += 1
            continue
        if rec_idx in fresh_ids:
            skipped["fresh_in_raw"] += 1
            continue
        if any(marker in str(item.get("source_url") or "") for marker in SKIP_URL_MARKERS):
            skipped["robots"] += 1
            continue
        targets.append(item)
    if limit is not None:
        targets = targets[:limit]
    return targets, skipped


def _fetch_with_retry(session: requests.Session, rec_idx: str) -> dict[str, Any]:
    """일시 오류는 한 번 더. 차단·429·허용 경로 위반은 그대로 올린다."""
    try:
        return fetch_detail(session, rec_idx)
    except requests.HTTPError as error:
        status = error.response.status_code if error.response is not None else 0
        if status < 500:
            raise
    except (requests.ConnectionError, requests.Timeout):
        pass
    polite_delay(*RETRY_DELAY_RANGE)
    return fetch_detail(session, rec_idx)


def crawl_details(
    targets: list[dict[str, Any]],
    output: Path,
    min_delay: float,
    max_delay: float,
    max_minutes: float | None = None,
) -> dict[str, int]:
    """대상을 순서대로 받아 `output`(.jsonl)에 한 건씩 붙인다."""
    counts = {"saved": 0, "failed": 0, "skipped": 0, "image_body": 0}
    if not targets:
        return counts
    # 사람처럼 목록 페이지를 먼저 열어 쿠키를 받은 세션으로 시작한다.
    try:
        session = new_session(min_delay=min_delay, max_delay=max_delay)
    except (BlockedByTargetSiteError, requests.RequestException) as error:
        print(f"[중단] 목록 페이지를 열지 못했습니다: {error}")
        return counts
    started = time.monotonic()
    deadline = started + max_minutes * 60 if max_minutes else None
    total = len(targets)

    for index, item in enumerate(targets, start=1):
        if deadline is not None and time.monotonic() >= deadline:
            print(f"[시간 종료] {max_minutes}분이 지나 멈춥니다. 남은 {total - index + 1}건은 다음에 이어서.")
            break
        rec_idx = str(item["source_job_id"])
        try:
            detail = _fetch_with_retry(session, rec_idx)
        except BlockedByTargetSiteError as error:
            print(f"[중단] {error}")
            break
        except ValueError as error:
            counts["skipped"] += 1
            print(f"  [{index}/{total}] 건너뜀 — {error}")
            continue
        except requests.RequestException as error:
            counts["failed"] += 1
            print(f"  [{index}/{total}] 실패 {rec_idx}: {error}")
            polite_delay(min_delay, max_delay)
            continue

        # 목록에서 이미 받은 값을 합쳐 하나의 레코드로 만든다.
        detail["list_item"] = item
        append_record(output, detail)
        counts["saved"] += 1
        if detail["needs_human_review"]:
            counts["image_body"] += 1

        elapsed = time.monotonic() - started
        per_item = elapsed / index
        remaining = per_item * (total - index)
        flag = " [본문 이미지]" if detail["needs_human_review"] else ""
        print(
            f"  [{index}/{total}] {rec_idx} 조건 {len(detail['conditions'])}개 / "
            f"본문 {len(detail['description'])}자{flag}  "
            f"(경과 {elapsed / 60:.0f}분, 남은 예상 {remaining / 60:.0f}분)"
        )
        if index < total:
            polite_delay(min_delay, max_delay)

    return counts


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="사람인 상세 POC 크롤러 (requests + bs4)")
    parser.add_argument("--input", type=Path, default=Path("output/saramin_raw.json"))
    parser.add_argument("--output", type=Path, default=Path("output/saramin_detail.jsonl"))
    parser.add_argument("--limit", type=int, default=None, help="이번 실행에서 받을 최대 건수")
    parser.add_argument("--max-minutes", type=float, default=None, help="이 시간이 지나면 멈춘다")
    parser.add_argument(
        "--no-resume", action="store_true", help="출력 파일에 이미 있는 공고도 다시 받는다"
    )
    parser.add_argument(
        "--refetch-without",
        metavar="FIELD",
        default=None,
        help="출력에 있어도 이 필드가 없는(예전 파서로 받은) 공고는 다시 받는다. 예: tags",
    )
    parser.add_argument(
        "--raw-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "job_matching_bot" / "artifacts" / "job_raw",
        help="저장소 원본 경로. 최근에 받은 공고는 건너뛴다",
    )
    parser.add_argument(
        "--refresh-days", type=int, default=7, help="원본이 이 일수 안이면 다시 받지 않는다"
    )
    parser.add_argument("--min-delay", type=float, default=3.0)
    parser.add_argument("--max-delay", type=float, default=5.0)
    args = parser.parse_args()

    if args.output.suffix != ".jsonl":
        print("출력은 .jsonl 이어야 합니다 (한 건씩 이어 쓰기 위해).")
        return 2

    listings = read_records(args.input)
    done_ids = set() if args.no_resume else done_record_ids(
        read_records(args.output), require_field=args.refetch_without
    )
    fresh_ids = fresh_raw_ids(args.raw_root, args.refresh_days)
    targets, skipped = plan_targets(
        listings, done_ids=done_ids, fresh_ids=fresh_ids, limit=args.limit
    )

    print(f"목록 {len(listings)}건 → 이번에 받을 상세 {len(targets)}건")
    print(
        f"  건너뜀: 출력에 이미 있음 {skipped['already_in_output']} / "
        f"원본 {args.refresh_days}일 내 {skipped['fresh_in_raw']} / "
        f"robots 제외 {skipped['robots']} / ID 없음 {skipped['no_id']}"
    )
    if targets:
        avg = (args.min_delay + args.max_delay) / 2 + 1.0
        print(f"  예상 소요 약 {len(targets) * avg / 60:.0f}분 (요청 간격 {args.min_delay}~{args.max_delay}초)")

    counts = crawl_details(targets, args.output, args.min_delay, args.max_delay, args.max_minutes)

    total_in_output = len(latest_by_id(read_records(args.output)))
    print(
        f"\n이번 실행: 저장 {counts['saved']} / 실패 {counts['failed']} / 건너뜀 {counts['skipped']} "
        f"(이미지 본문 {counts['image_body']})"
    )
    print(f"출력 누적 {total_in_output}건(고유): {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
