"""공고 저장소: content_hash 기반 upsert와 상태 전이.

매 수집마다 전량을 새로 만들면 두 번째 수집부터 무엇이 새 공고이고 무엇이
사라진 공고인지 알 수 없다. 이 모듈은 `source + source_job_id`를 키로
기존 레코드와 대조해 다음을 판정한다.

    처음 본 공고            → 신규 등록, first_seen_at 기록
    content_hash 같음       → 내용 그대로, last_seen_at만 갱신
    content_hash 다름       → 내용 갱신, revisions 증가
    이번에 안 보임           → 즉시 삭제하지 않고 상태로 남김

마감일이 지나면 EXPIRED, 마감 전인데 소스에서 계속 사라져 있으면 REMOVED다.
수집이 한 번 실패했다고 전체가 REMOVED가 되면 안 되므로, 연속으로 관측되지
않은 횟수가 기준을 넘을 때만 REMOVED로 넘긴다.
"""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from job_matching_bot.config import AS_OF
from job_matching_bot.schemas.job_posting import Job
from job_matching_bot.schemas.job_record import (
    DEFAULT_MISSING_RUN_LIMIT,
    STATUS_CLOSED,
    STATUS_EXPIRED,
    STATUS_OPEN,
    STATUS_REMOVED,
    CollectionReport,
    JobRecord,
)

# 이 필드가 비어 있으면 선택자 오류나 파싱 실패를 의심해야 한다.
REQUIRED_FIELDS = ("company", "title", "source_url")


def _is_expired(job: Job, as_of: datetime) -> bool:
    if not job.deadline:
        return False
    try:
        parsed = datetime.fromisoformat(job.deadline)
    except ValueError:
        return False
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=as_of.tzinfo)
    return parsed < as_of


def resolve_status(job: Job, as_of: datetime) -> str:
    """관측된 공고의 상태. 소스가 마감이라고 하면 그 말을 따른다."""
    if job.status == STATUS_CLOSED:
        return STATUS_CLOSED
    return STATUS_EXPIRED if _is_expired(job, as_of) else STATUS_OPEN


def _missing_field_names(job: Job) -> list[str]:
    return [name for name in REQUIRED_FIELDS if not getattr(job, name, None)]


def reconcile(
    existing: dict[tuple[str, str], JobRecord],
    collected: Iterable[Job],
    *,
    source: str,
    as_of: datetime = AS_OF,
    missing_run_limit: int = DEFAULT_MISSING_RUN_LIMIT,
    observed_ids: set[str] | None = None,
) -> tuple[dict[tuple[str, str], JobRecord], CollectionReport]:
    """수집 결과를 기존 저장 내용과 대조해 새 저장 상태와 리포트를 만든다.

    `source`는 이번 수집이 책임지는 범위다. 다른 소스의 공고는 이번에 안 보였다고
    사라진 것으로 보지 않는다. 백엔드 공고만 수집한 날 프론트엔드 공고가 안
    보이는 것은 삭제가 아니기 때문이다.

    `observed_ids`는 **목록 페이지에서 본** source_job_id 집합이다. 증분 수집은
    새 공고의 상세만 받으므로 `collected`에는 기존 공고가 없다. 이때 목록에서
    보인 공고를 "안 보였다"고 세면 두 번 만에 전부 REMOVED가 된다. 목록에 있었으면
    살아 있는 것이고, 내용은 마지막으로 받은 것을 유지한다. None이면 전량 수집으로
    보고 `collected`만으로 판단한다.
    """
    merged = dict(existing)
    report = CollectionReport(source=source, collected_at=as_of.isoformat())
    seen: set[tuple[str, str]] = set()
    timestamp = as_of.isoformat()

    for job in collected:
        key = (job.source, job.source_job_id)
        seen.add(key)
        status = resolve_status(job, as_of)
        job_id = job.job_id

        missing = _missing_field_names(job)
        if missing:
            report.missing_fields[job_id] = missing
        report.parser_versions[job.parser_version] = (
            report.parser_versions.get(job.parser_version, 0) + 1
        )

        previous = merged.get(key)
        if previous is None:
            merged[key] = JobRecord(
                job=job,
                first_seen_at=timestamp,
                last_seen_at=timestamp,
                status=status,
            )
            report.new.append(job_id)
            continue

        changed = previous.job.content_hash != job.content_hash
        merged[key] = JobRecord(
            job=job,
            first_seen_at=previous.first_seen_at,
            last_seen_at=timestamp,
            status=status,
            # 다시 보였으므로 미관측 카운터를 되돌린다. 삭제 처리됐던 공고가
            # 재게시되면 그대로 다시 열린 상태가 된다.
            missing_runs=0,
            revisions=previous.revisions + (1 if changed else 0),
        )
        (report.updated if changed else report.unchanged).append(job_id)

    for key, record in merged.items():
        if key in seen or record.job.source != source:
            continue
        # 마감일은 관측 여부와 무관하게 확정적으로 판정할 수 있다.
        if _is_expired(record.job, as_of):
            record.status = STATUS_EXPIRED
            report.expired.append(record.job.job_id)
            continue
        if observed_ids is not None and record.job.source_job_id in observed_ids:
            # 목록에서 봤다. 상세를 다시 받지 않았을 뿐 사라진 게 아니다.
            record.last_seen_at = timestamp
            record.missing_runs = 0
            if record.status == STATUS_REMOVED:
                # 삭제 처리했던 공고가 목록에 다시 보이면 되살린다.
                record.status = STATUS_OPEN
            report.observed.append(record.job.job_id)
            continue
        record.missing_runs += 1
        if record.missing_runs >= missing_run_limit:
            record.status = STATUS_REMOVED
            report.removed.append(record.job.job_id)
        else:
            report.still_missing.append(record.job.job_id)

    return merged, report


def open_store(path: Path):
    """경로 확장자로 저장소 구현을 고른다. `.sqlite`/`.db`면 SQLite, 아니면 JSON.

    JSON은 전량을 메모리에 올렸다 통째로 쓰는 방식이라 수만 건까지만 맞다.
    테스트와 작은 실험은 JSON을, 실제 수집은 SQLite를 쓴다.
    """
    from job_matching_bot.ingestion.sqlite_store import SqliteJobStore, is_sqlite_path

    path = Path(path)
    return SqliteJobStore(path) if is_sqlite_path(path) else JobStore(path)


class JobStore:
    """JSON 파일 한 개로 동작하는 저장소. 작은 규모와 테스트용.

    수집 운영은 `sqlite_store.SqliteJobStore`가 맡는다(`open_store`가 경로로 고른다).
    upsert 판정 로직은 `reconcile`에 있고 이 클래스는 읽고 쓰는 일만 하므로,
    백엔드를 바꿔도 판정 규칙은 그대로 쓴다.
    """

    def __init__(self, path: Path):
        self.path = Path(path)
        self.records: dict[tuple[str, str], JobRecord] = {}

    def load(self) -> JobStore:
        if self.path.exists():
            payloads = json.loads(self.path.read_text(encoding="utf-8"))
            self.records = {}
            for payload in payloads:
                record = JobRecord.from_dict(payload)
                self.records[record.key] = record
        return self

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = [record.to_dict() for record in self.records.values()]
        self.path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    def upsert(
        self,
        collected: Iterable[Job],
        *,
        source: str,
        as_of: datetime = AS_OF,
        missing_run_limit: int = DEFAULT_MISSING_RUN_LIMIT,
        observed_ids: set[str] | None = None,
    ) -> CollectionReport:
        self.records, report = reconcile(
            self.records,
            collected,
            source=source,
            as_of=as_of,
            missing_run_limit=missing_run_limit,
            observed_ids=observed_ids,
        )
        return report

    def active_jobs(self) -> list[Job]:
        """추천 대상에 넣을 수 있는 공고. 만료·삭제된 공고는 뺀다."""
        return [
            record.job
            for record in self.records.values()
            if record.status == STATUS_OPEN
        ]

    def all_records(self) -> list[JobRecord]:
        return list(self.records.values())

    def stats(self) -> dict[str, Any]:
        by_status: dict[str, int] = {}
        for record in self.records.values():
            by_status[record.status] = by_status.get(record.status, 0) + 1
        return {"total": len(self.records), "by_status": by_status}
