"""JSON 저장소를 SQLite로 옮긴다. 한 번 쓰고 마는 이관 도구.

    python -m job_matching_bot.ingestion.migrate_store            # artifacts/job_store.json → .sqlite
    python -m job_matching_bot.ingestion.migrate_store --verify   # 옮기지 않고 대조만

옮긴 뒤 건수·job_id 집합·content_hash·생애주기 필드·목록 필드가 원본과 1:1로 같은지
대조한다. 하나라도 다르면 종료 코드 1이고, SQLite 파일은 그대로 두니 열어서 확인할 수 있다.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from dataclasses import asdict
from pathlib import Path

from job_matching_bot.config import ARTIFACTS_DIR
from job_matching_bot.ingestion.sqlite_store import SqliteJobStore
from job_matching_bot.schemas.job_record import JobRecord

DEFAULT_JSON = ARTIFACTS_DIR / "job_store.json"
DEFAULT_SQLITE = ARTIFACTS_DIR / "job_store.sqlite"


def load_json(path: Path) -> list[JobRecord]:
    return [JobRecord.from_dict(p) for p in json.loads(path.read_text(encoding="utf-8"))]


def migrate(json_path: Path, sqlite_path: Path) -> int:
    records = load_json(json_path)
    store = SqliteJobStore(sqlite_path)
    with store.conn:
        for i, record in enumerate(records, 1):
            store.put(record)
            if i % 2000 == 0:
                print(f"  {i:,}/{len(records):,}", flush=True)
    store.close()
    return len(records)


def verify(json_path: Path, sqlite_path: Path) -> list[str]:
    """원본과 SQLite를 레코드 단위로 대조한다. 불일치 설명 목록을 돌려준다(비어 있으면 통과)."""
    problems: list[str] = []
    originals = {r.job.job_id: r for r in load_json(json_path)}
    store = SqliteJobStore(sqlite_path)
    restored = {r.job.job_id: r for r in store.all_records()}
    store.close()

    if len(originals) != len(restored):
        problems.append(f"건수 불일치: json {len(originals):,} / sqlite {len(restored):,}")
    missing = set(originals) - set(restored)
    extra = set(restored) - set(originals)
    if missing:
        problems.append(f"sqlite에 없는 job_id {len(missing)}개 (예: {sorted(missing)[:3]})")
    if extra:
        problems.append(f"json에 없는 job_id {len(extra)}개 (예: {sorted(extra)[:3]})")

    mismatched = 0
    for job_id, original in originals.items():
        copy = restored.get(job_id)
        if copy is None:
            continue
        if asdict(original.job) != asdict(copy.job) or (
            original.status, original.first_seen_at, original.last_seen_at, original.missing_runs, original.revisions
        ) != (copy.status, copy.first_seen_at, copy.last_seen_at, copy.missing_runs, copy.revisions):
            mismatched += 1
            if mismatched <= 3:
                diff = [k for k in asdict(original.job) if asdict(original.job)[k] != asdict(copy.job)[k]]
                problems.append(f"필드 불일치 {job_id}: {diff or '생애주기'}")
    if mismatched > 3:
        problems.append(f"... 필드 불일치 총 {mismatched}건")
    return problems


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="JSON 저장소 → SQLite 이관")
    parser.add_argument("--json", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--sqlite", type=Path, default=DEFAULT_SQLITE)
    parser.add_argument("--verify", action="store_true", help="옮기지 않고 대조만 한다")
    args = parser.parse_args()

    if not args.verify:
        if args.sqlite.exists():
            print(f"이미 있습니다: {args.sqlite} — 지우고 다시 하거나 --verify 로 대조하세요")
            return 1
        started = time.time()
        n = migrate(args.json, args.sqlite)
        size = args.sqlite.stat().st_size / 1_048_576
        print(f"이관 {n:,}건 · {time.time() - started:.1f}초 · {size:.1f}MB → {args.sqlite}")

    problems = verify(args.json, args.sqlite)
    if problems:
        print("대조 실패:")
        for p in problems:
            print("  -", p)
        return 1
    print("대조 통과: 건수·job_id·모든 필드·생애주기 일치")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
