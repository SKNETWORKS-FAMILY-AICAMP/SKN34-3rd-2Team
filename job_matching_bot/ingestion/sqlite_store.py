"""SQLite로 동작하는 공고 저장소.

JSON 파일 저장소(`job_store.JobStore`)는 전량을 메모리에 올렸다 통째로 다시 쓴다.
11,493건에 68MB일 땐 문제가 없었지만, 전 카테고리 활성 공고 약 176,000건이면
1GB짜리 JSON을 매번 읽고 쓰게 되어 감당이 안 된다. 여기서는 바뀐 행만 갱신하고
`job_id` 하나만 꺼내 읽을 수 있다. 첨삭이 공고 원문을 조회할 때도 이 경로를 쓴다.

판정 규칙은 `job_store.reconcile`과 **같아야 한다.** 이 클래스는 그 규칙을 SQL 위에서
다시 구현한 것이라, 규칙을 고칠 때는 두 곳을 함께 고친다(`tests/test_sqlite_store.py`가
두 구현의 결과가 같은지 대조한다).

스키마
    jobs      공고 한 건 = 한 행. Job 필드 + 생애주기(status, first/last_seen, missing_runs,
              revisions) + 인덱스 추적(embed_hash, indexed_embed_hash, indexed_at)
    job_tags  목록형 값(기술 태그·카테고리 등)을 (job_id, kind, value)로 풀어 둔 것. 조회용
    runs      배치 실행 기록

목록·딕셔너리 필드는 JSON 문자열로 넣는다. SQLite는 타입이 느슨해 읽을 때
`_JSON_FIELDS` / `_BOOL_FIELDS` / `_INT_FIELDS`로 되돌린다.
"""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable, Iterator

from job_matching_bot.config import AS_OF
from job_matching_bot.ingestion.job_store import REQUIRED_FIELDS, _is_expired, resolve_status
from job_matching_bot.schemas.job_posting import Job
from job_matching_bot.schemas.job_record import (
    DEFAULT_MISSING_RUN_LIMIT,
    STATUS_OPEN,
    STATUS_REMOVED,
    CollectionReport,
    JobRecord,
)

JOB_FIELDS: tuple[str, ...] = tuple(Job.__dataclass_fields__)
_JSON_FIELDS = frozenset(
    {
        "required_skills", "preferred_skills", "tech_stack", "keywords",
        "required_majors", "required_major_terms", "required_certifications",
        "field_provenance",
    }
)
_BOOL_FIELDS = frozenset({"body_is_image", "military_required"})
_INT_FIELDS = frozenset({"min_career_years"})
LIFECYCLE_FIELDS: tuple[str, ...] = ("first_seen_at", "last_seen_at", "missing_runs", "revisions")
# status는 Job에도 있고 생애주기에도 있다. 저장소가 관리하므로 한 컬럼만 둔다.
_COLUMNS: tuple[str, ...] = JOB_FIELDS + LIFECYCLE_FIELDS
# job_tags로 풀어 두는 목록 필드. kind 이름은 필드명과 같다.
TAG_FIELDS: tuple[str, ...] = ("tech_stack", "required_skills", "preferred_skills", "keywords")

_SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs (
    job_id TEXT PRIMARY KEY,
    {job_columns},
    first_seen_at TEXT NOT NULL,
    last_seen_at TEXT NOT NULL,
    missing_runs INTEGER NOT NULL DEFAULT 0,
    revisions INTEGER NOT NULL DEFAULT 0,
    embed_hash TEXT,
    indexed_embed_hash TEXT,
    indexed_at TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS jobs_source_key ON jobs(source, source_job_id);
CREATE INDEX IF NOT EXISTS jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS jobs_deadline ON jobs(deadline);
CREATE INDEX IF NOT EXISTS jobs_content_hash ON jobs(content_hash);
CREATE TABLE IF NOT EXISTS job_tags (
    job_id TEXT NOT NULL REFERENCES jobs(job_id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    value TEXT NOT NULL,
    PRIMARY KEY (job_id, kind, value)
);
CREATE INDEX IF NOT EXISTS job_tags_kind_value ON job_tags(kind, value);
CREATE TABLE IF NOT EXISTS runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    source TEXT,
    new INTEGER, updated INTEGER, unchanged INTEGER,
    expired INTEGER, removed INTEGER, observed INTEGER, still_missing INTEGER,
    vectors INTEGER,
    error TEXT
);
"""


def _encode(field: str, value: Any) -> Any:
    if field in _JSON_FIELDS:
        return json.dumps(value if value is not None else ([] if field != "field_provenance" else {}), ensure_ascii=False)
    if field in _BOOL_FIELDS:
        return 1 if value else 0
    return value


def _decode(field: str, value: Any) -> Any:
    if field in _JSON_FIELDS:
        if value is None:
            return {} if field == "field_provenance" else []
        return json.loads(value)
    if field in _BOOL_FIELDS:
        # 컬럼은 INTEGER지만, 혹시 문자열 '0'이 오더라도 True로 읽히면 안 된다.
        return bool(int(value)) if value is not None else False
    if field in _INT_FIELDS:
        return None if value is None else int(value)
    return value


def _column_type(field: str) -> str:
    if field in _BOOL_FIELDS or field in _INT_FIELDS:
        return "INTEGER"
    return "TEXT"


def _chunks(items: list[Any], size: int) -> Iterator[list[Any]]:
    for start in range(0, len(items), size):
        yield items[start : start + size]


class SqliteJobStore:
    """`JobStore`와 같은 겉모습(`load` / `save` / `upsert` / `active_jobs` / `stats`)을 가진 SQLite 저장소."""

    # SQLite 변수 한도(999) 안에서 IN 절을 쪼개는 크기.
    _IN_CHUNK = 400

    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(str(self.path))
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("PRAGMA synchronous=NORMAL")
        self.conn.execute("PRAGMA foreign_keys=ON")
        job_columns = ",\n    ".join(f"{name} {_column_type(name)}" for name in JOB_FIELDS if name != "job_id")
        self.conn.executescript(_SCHEMA.format(job_columns=job_columns))

    # ── JobStore 호환 ──────────────────────────────────────────
    def load(self) -> "SqliteJobStore":
        return self

    def save(self) -> None:
        self.conn.commit()

    def close(self) -> None:
        self.conn.close()

    # ── 읽기 ──────────────────────────────────────────────────
    def _row_to_record(self, row: sqlite3.Row) -> JobRecord:
        job_fields = {name: _decode(name, row[name]) for name in JOB_FIELDS}
        return JobRecord(
            job=Job(**job_fields),
            first_seen_at=row["first_seen_at"],
            last_seen_at=row["last_seen_at"],
            status=row["status"],
            missing_runs=row["missing_runs"],
            revisions=row["revisions"],
        )

    def get(self, job_id: str) -> JobRecord | None:
        row = self.conn.execute("SELECT * FROM jobs WHERE job_id = ?", (job_id,)).fetchone()
        return self._row_to_record(row) if row else None

    def iter_records(self, status: str | None = None) -> Iterator[JobRecord]:
        sql, params = "SELECT * FROM jobs", ()
        if status:
            sql, params = sql + " WHERE status = ?", (status,)
        for row in self.conn.execute(sql + " ORDER BY job_id", params):
            yield self._row_to_record(row)

    def __enter__(self) -> "SqliteJobStore":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def active_jobs(self) -> list[Job]:
        """추천 대상에 넣을 수 있는 공고. 만료·삭제된 공고는 뺀다."""
        return [record.job for record in self.iter_records(STATUS_OPEN)]

    def all_records(self) -> list[JobRecord]:
        return list(self.iter_records())

    def count(self) -> int:
        return int(self.conn.execute("SELECT COUNT(*) FROM jobs").fetchone()[0])

    def stats(self) -> dict[str, Any]:
        by_status = {
            row["status"]: row["n"]
            for row in self.conn.execute("SELECT status, COUNT(*) AS n FROM jobs GROUP BY status")
        }
        return {"total": self.count(), "by_status": by_status}

    # ── 쓰기 ──────────────────────────────────────────────────
    def _write_record(self, record: JobRecord) -> None:
        job = record.job
        values = {name: _encode(name, getattr(job, name)) for name in JOB_FIELDS}
        values["status"] = record.status
        values.update(
            first_seen_at=record.first_seen_at,
            last_seen_at=record.last_seen_at,
            missing_runs=record.missing_runs,
            revisions=record.revisions,
        )
        columns = ", ".join(values)
        placeholders = ", ".join(f":{name}" for name in values)
        updates = ", ".join(f"{name} = excluded.{name}" for name in values if name != "job_id")
        self.conn.execute(
            f"INSERT INTO jobs ({columns}) VALUES ({placeholders}) "
            f"ON CONFLICT(job_id) DO UPDATE SET {updates}",
            values,
        )
        self.conn.execute("DELETE FROM job_tags WHERE job_id = ?", (job.job_id,))
        rows = [
            (job.job_id, kind, str(value))
            for kind in TAG_FIELDS
            for value in (getattr(job, kind) or [])
            if str(value).strip()
        ]
        if rows:
            self.conn.executemany("INSERT OR IGNORE INTO job_tags (job_id, kind, value) VALUES (?, ?, ?)", rows)

    def put(self, record: JobRecord) -> None:
        """레코드 하나를 그대로 넣는다. 이관과 테스트용. 판정 없이 덮어쓴다."""
        self._write_record(record)

    def _existing_light(self, keys: list[tuple[str, str]]) -> dict[tuple[str, str], sqlite3.Row]:
        """collected 공고의 기존 행 중 판정에 필요한 컬럼만."""
        found: dict[tuple[str, str], sqlite3.Row] = {}
        for chunk in _chunks(keys, self._IN_CHUNK):
            marks = ", ".join("(?, ?)" for _ in chunk)
            params = [v for key in chunk for v in key]
            rows = self.conn.execute(
                "SELECT source, source_job_id, content_hash, first_seen_at, revisions "
                f"FROM jobs WHERE (source, source_job_id) IN (VALUES {marks})",
                params,
            )
            for row in rows:
                found[(row["source"], row["source_job_id"])] = row
        return found

    def upsert(
        self,
        collected: Iterable[Job],
        *,
        source: str,
        as_of: datetime = AS_OF,
        missing_run_limit: int = DEFAULT_MISSING_RUN_LIMIT,
        observed_ids: set[str] | None = None,
    ) -> CollectionReport:
        """`job_store.reconcile`과 같은 판정을 SQL 위에서 한다. 결과 리포트도 같은 모양."""
        collected = list(collected)
        report = CollectionReport(source=source, collected_at=as_of.isoformat())
        timestamp = as_of.isoformat()
        seen: set[tuple[str, str]] = set()

        # ① 이번에 받은 공고: 신규 / 갱신 / 변경 없음
        keys = [(job.source, job.source_job_id) for job in collected]
        existing = self._existing_light(list(dict.fromkeys(keys)))
        with self.conn:
            for job in collected:
                key = (job.source, job.source_job_id)
                seen.add(key)
                status = resolve_status(job, as_of)
                missing = [name for name in REQUIRED_FIELDS if not getattr(job, name, None)]
                if missing:
                    report.missing_fields[job.job_id] = missing
                report.parser_versions[job.parser_version] = report.parser_versions.get(job.parser_version, 0) + 1

                previous = existing.get(key)
                if previous is None:
                    record = JobRecord(job=job, first_seen_at=timestamp, last_seen_at=timestamp, status=status)
                    report.new.append(job.job_id)
                else:
                    changed = previous["content_hash"] != job.content_hash
                    record = JobRecord(
                        job=job,
                        first_seen_at=previous["first_seen_at"],
                        last_seen_at=timestamp,
                        status=status,
                        missing_runs=0,
                        revisions=int(previous["revisions"]) + (1 if changed else 0),
                    )
                    (report.updated if changed else report.unchanged).append(job.job_id)
                self._write_record(record)
                # 같은 공고가 collected에 두 번 오면 두 번째는 '기존'으로 보이게 한다 (reconcile과 동일).
                existing[key] = {
                    "content_hash": job.content_hash,
                    "first_seen_at": record.first_seen_at,
                    "revisions": record.revisions,
                }

            # ② 이번에 안 보인 같은 소스의 공고: 만료 / 목록에서 봄 / 미관측 누적 / 삭제
            rows = self.conn.execute(
                "SELECT job_id, source_job_id, deadline, status, missing_runs FROM jobs WHERE source = ?",
                (source,),
            ).fetchall()
            seen_ids = {sid for (_, sid) in seen}
            expire: list[str] = []
            touch: list[tuple[str, str]] = []      # (status, job_id)
            bump: list[tuple[int, str, str]] = []   # (missing_runs, status, job_id)
            for row in rows:
                if row["source_job_id"] in seen_ids:
                    continue
                probe = Job.__new__(Job)
                probe.deadline = row["deadline"]
                if _is_expired(probe, as_of):
                    expire.append(row["job_id"])
                    report.expired.append(row["job_id"])
                    continue
                if observed_ids is not None and row["source_job_id"] in observed_ids:
                    new_status = STATUS_OPEN if row["status"] == STATUS_REMOVED else row["status"]
                    touch.append((new_status, row["job_id"]))
                    report.observed.append(row["job_id"])
                    continue
                runs = int(row["missing_runs"]) + 1
                if runs >= missing_run_limit:
                    bump.append((runs, STATUS_REMOVED, row["job_id"]))
                    report.removed.append(row["job_id"])
                else:
                    bump.append((runs, row["status"], row["job_id"]))
                    report.still_missing.append(row["job_id"])

            self.conn.executemany("UPDATE jobs SET status = 'EXPIRED' WHERE job_id = ?", [(j,) for j in expire])
            self.conn.executemany(
                "UPDATE jobs SET status = ?, last_seen_at = ?, missing_runs = 0 WHERE job_id = ?",
                [(s, timestamp, j) for (s, j) in touch],
            )
            self.conn.executemany(
                "UPDATE jobs SET missing_runs = ?, status = ? WHERE job_id = ?", bump
            )
        return report

    # ── 인덱스 추적 (적재 단계가 쓴다) ─────────────────────────
    def mark_indexed(self, job_id: str, embed_hash: str, at: datetime) -> None:
        self.conn.execute(
            "UPDATE jobs SET indexed_embed_hash = ?, indexed_at = ? WHERE job_id = ?",
            (embed_hash, at.isoformat(), job_id),
        )

    def clear_indexed(self, job_ids: Iterable[str]) -> None:
        self.conn.executemany(
            "UPDATE jobs SET indexed_embed_hash = NULL, indexed_at = NULL WHERE job_id = ?",
            [(j,) for j in job_ids],
        )

    # ── 실행 기록 ─────────────────────────────────────────────
    def record_run(self, report: CollectionReport, *, started_at: datetime, finished_at: datetime,
                   vectors: int | None = None, error: str | None = None) -> None:
        self.conn.execute(
            "INSERT INTO runs (started_at, finished_at, source, new, updated, unchanged, expired, removed, "
            "observed, still_missing, vectors, error) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                started_at.isoformat(), finished_at.isoformat(), report.source,
                len(report.new), len(report.updated), len(report.unchanged), len(report.expired),
                len(report.removed), len(report.observed), len(report.still_missing), vectors, error,
            ),
        )
        self.conn.commit()


def is_sqlite_path(path: Path) -> bool:
    return Path(path).suffix.lower() in (".sqlite", ".sqlite3", ".db")
