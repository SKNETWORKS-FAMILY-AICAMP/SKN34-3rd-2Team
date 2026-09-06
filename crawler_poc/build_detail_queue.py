"""목록 수집 결과를 상세 크롤 입력으로 바꾼다. 인기순으로 정렬하고 이미 받은 건 뺀다.

    python build_detail_queue.py \
        --list output/saramin_all_raw.json \
        --detail output/saramin_detail.jsonl \
        --output output/saramin_detail_queue.json

정렬 기준 (앞에 올수록 먼저 받는다):
1. `badge`에 "TOP100"이 있는 공고 — 사이트가 지원자 수로 매긴 인기 표식
2. 같은 등급 안에서는 대분류 내 지원순 순위(`list_rank`)가 앞선 것
3. 그다음 마감이 늦은 것 — 받아 두면 오래 쓸 수 있다

한 공고가 여러 대분류에 걸리면(통합 채용) 가장 앞선 순위 하나만 남긴다.
상세를 이미 태그까지 받은 공고(`tags` 필드 있음)는 큐에서 뺀다. 상세 크롤러의
`--refetch-without tags` 와 같은 기준이라, 예전 파서로 받은 것은 다시 받는다.

이미지 공고는 목록에서 알 수 없어 여기서 못 거른다. 받은 뒤 인덱스에서 제외한다.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from job_matching_bot.ingestion.excluded_roles import is_excluded  # noqa: E402

KST = timezone(timedelta(hours=9))
_DEADLINE_RE = re.compile(r"~\s*(\d{2})\.(\d{2})")


def deadline_key(support_text: str, now: datetime) -> str:
    """'~09.20(일)' 을 'YYYY-MM-DD' 로. 없으면 '9999' — 상시 채용은 뒤로 보내지 않고 앞에 둔다."""
    match = _DEADLINE_RE.search(support_text or "")
    if not match:
        return "9999-12-31"
    month, day = int(match.group(1)), int(match.group(2))
    year = now.year
    # 12월에 1월 마감을 보면 이듬해다.
    if month < now.month - 6:
        year += 1
    return f"{year:04d}-{month:02d}-{day:02d}"


def priority(record: dict[str, Any], now: datetime) -> tuple[int, int, str]:
    top = 0 if "TOP100" in (record.get("badge") or "") else 1
    rank = int(record.get("list_rank") or 10**9)
    # 마감이 늦을수록 앞에: 문자열 역순을 위해 음수 대신 뒤집힌 키를 쓴다.
    deadline = deadline_key(record.get("support_text", ""), now)
    return (top, rank, "".join(chr(0x10FFFF - ord(c)) for c in deadline))


def build_queue(
    list_records: list[dict[str, Any]],
    detailed_ids: set[str],
    now: datetime,
) -> tuple[list[dict[str, Any]], Counter]:
    best: dict[str, dict[str, Any]] = {}
    stats: Counter = Counter()
    for record in list_records:
        job_id = str(record.get("source_job_id") or "")
        if not job_id:
            stats["id 없음"] += 1
            continue
        if job_id in detailed_ids:
            stats["이미 상세 있음"] += 1
            continue
        if is_excluded(record.get("job_sectors") or []):
            stats["제외 직종(배달·배송·운전)"] += 1
            continue
        current = best.get(job_id)
        if current is None or priority(record, now) < priority(current, now):
            if current is not None:
                stats["대분류 중복(앞선 순위로 대체)"] += 1
            best[job_id] = record
        else:
            stats["대분류 중복"] += 1
    queue = sorted(best.values(), key=lambda r: priority(r, now))
    stats["큐에 담김"] = len(queue)
    stats["TOP100"] = sum(1 for r in queue if "TOP100" in (r.get("badge") or ""))
    return queue, stats


def main() -> int:
    parser = argparse.ArgumentParser(description="인기순 상세 크롤 입력 만들기")
    parser.add_argument("--list", type=Path, default=Path("output/saramin_all_raw.json"))
    parser.add_argument("--detail", type=Path, default=Path("output/saramin_detail.jsonl"))
    parser.add_argument("--output", type=Path, default=Path("output/saramin_detail_queue.json"))
    parser.add_argument("--limit", type=int, default=None, help="앞에서부터 이 건수만 담는다")
    args = parser.parse_args()

    list_records = json.loads(args.list.read_text(encoding="utf-8"))
    detailed: set[str] = set()
    if args.detail.exists():
        # str.splitlines()는 U+2028 같은 유니코드 줄바꿈에서도 끊는다. 공고 본문에
        # 그런 문자가 있어 한 건이 둘로 쪼개지므로 개행 문자로만 자른다.
        for line in args.detail.read_text(encoding="utf-8").split("\n"):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue  # 크롤이 중단되며 잘린 마지막 줄
            if "tags" in row:
                detailed.add(str(row.get("source_job_id") or ""))

    now = datetime.now(KST)
    queue, stats = build_queue(list_records, detailed, now)
    if args.limit:
        queue = queue[: args.limit]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(queue, ensure_ascii=False), encoding="utf-8")

    print(f"목록 {len(list_records):,}건 → 큐 {len(queue):,}건 저장: {args.output}")
    for key, value in stats.most_common():
        print(f"  {key}: {value:,}")
    print(f"  예상 소요: {len(queue) * 4 / 3600:.1f}시간 (요청 간격 4초)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
