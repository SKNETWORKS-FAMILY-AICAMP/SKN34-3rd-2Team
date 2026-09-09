"""SQLite 저장소가 JSON 저장소(`reconcile`)와 같은 판정을 내리는지 대조한다.

두 구현을 같은 입력으로 돌려 리포트와 상태를 비교한다. 규칙을 한쪽만 고치면
여기서 깨진다.
"""

from __future__ import annotations

import tempfile
import unittest
from dataclasses import asdict, replace
from datetime import timedelta
from pathlib import Path

from job_matching_bot.config import AS_OF
from job_matching_bot.ingestion.job_store import JobStore, reconcile
from job_matching_bot.ingestion.mock_source import mock_jobs
from job_matching_bot.ingestion.sqlite_store import SqliteJobStore, is_sqlite_path
from job_matching_bot.schemas.job_record import STATUS_EXPIRED, STATUS_OPEN, STATUS_REMOVED


def _report_view(report):
    return {
        "new": sorted(report.new), "updated": sorted(report.updated), "unchanged": sorted(report.unchanged),
        "expired": sorted(report.expired), "removed": sorted(report.removed),
        "still_missing": sorted(report.still_missing), "observed": sorted(report.observed),
    }


def _status_view(records):
    return {r.job.job_id: (r.status, r.missing_runs, r.revisions) for r in records}


class SqliteVersusJsonTest(unittest.TestCase):
    """같은 시나리오를 두 저장소에 돌리고 결과가 같은지 본다."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = SqliteJobStore(Path(self.temp.name) / "store.sqlite")
        self.jobs = mock_jobs()

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def _both(self, steps):
        """steps: [(collected, kwargs)] 를 두 구현에 순서대로 적용하고 (리포트들, 상태) 쌍을 돌려준다."""
        json_records = {}
        json_reports, sqlite_reports = [], []
        for collected, kwargs in steps:
            json_records, report = reconcile(json_records, collected, **kwargs)
            json_reports.append(_report_view(report))
            sqlite_reports.append(_report_view(self.store.upsert(collected, **kwargs)))
        return (json_reports, _status_view(json_records.values())), (sqlite_reports, _status_view(self.store.all_records()))

    def test_first_collection_matches(self):
        a, b = self._both([(self.jobs, dict(source="MOCK"))])
        self.assertEqual(a, b)
        self.assertEqual(len(self.jobs), self.store.count())

    def test_recollect_unchanged_and_changed(self):
        changed = [replace(self.jobs[0], description=self.jobs[0].description + " 수정", content_hash="sha256:changed")]
        a, b = self._both([
            (self.jobs, dict(source="MOCK")),
            (changed + self.jobs[1:], dict(source="MOCK", as_of=AS_OF + timedelta(days=1))),
        ])
        self.assertEqual(a, b)
        self.assertEqual(1, self.store.get(self.jobs[0].job_id).revisions)

    def test_missing_then_removed_after_limit(self):
        later = AS_OF + timedelta(days=1)
        a, b = self._both([
            (self.jobs, dict(source="MOCK")),
            (self.jobs[1:], dict(source="MOCK", as_of=later)),
            (self.jobs[1:], dict(source="MOCK", as_of=later + timedelta(days=1))),
        ])
        self.assertEqual(a, b)
        self.assertEqual(STATUS_REMOVED, self.store.get(self.jobs[0].job_id).status)

    def test_observed_in_listing_keeps_and_revives(self):
        later = AS_OF + timedelta(days=1)
        gone = self.jobs[0]
        a, b = self._both([
            (self.jobs, dict(source="MOCK")),
            ([], dict(source="MOCK", as_of=later, missing_run_limit=1)),                       # 전부 REMOVED
            ([], dict(source="MOCK", as_of=later, observed_ids={gone.source_job_id})),         # 하나만 목록에서 봄 → 부활
        ])
        self.assertEqual(a, b)
        self.assertEqual(STATUS_OPEN, self.store.get(gone.job_id).status)

    def test_expired_by_deadline(self):
        expiring = replace(self.jobs[0], deadline=(AS_OF - timedelta(days=1)).isoformat())
        a, b = self._both([
            ([expiring] + self.jobs[1:], dict(source="MOCK")),
            (self.jobs[1:], dict(source="MOCK", as_of=AS_OF + timedelta(days=1))),
        ])
        self.assertEqual(a, b)
        self.assertEqual(STATUS_EXPIRED, self.store.get(expiring.job_id).status)

    def test_other_source_is_not_touched(self):
        other = [replace(j, source="OTHER", job_id=f"OTHER:{j.source_job_id}") for j in self.jobs[:2]]
        a, b = self._both([
            (self.jobs + other, dict(source="MOCK")),
            ([], dict(source="MOCK", as_of=AS_OF + timedelta(days=1), missing_run_limit=1)),
        ])
        self.assertEqual(a, b)
        for job in other:
            self.assertEqual(STATUS_OPEN, self.store.get(job.job_id).status)


class RoundTripTest(unittest.TestCase):
    def test_every_field_survives(self):
        # Windows는 열린 SQLite 파일을 못 지운다. 실패해도 연결을 닫도록 with로 감싼다.
        with tempfile.TemporaryDirectory() as temp, SqliteJobStore(Path(temp) / "s.sqlite") as store:
            job = replace(
                mock_jobs()[0],
                tech_stack=["Python", "FastAPI"], keywords=["백엔드/서버개발"],
                required_majors=["컴퓨터·소프트웨어"], required_major_terms=["컴퓨터"],
                # True와 False를 하나씩 둔다. 둘 다 True면 '0'이 True로 읽히는 버그를 못 잡는다.
                required_certifications=["정보처리기사"], military_required=True, body_is_image=False,
                min_career_years=3, field_provenance={"career": {"method": "detail_dl", "evidence": "경력 3년"}},
            )
            store.upsert([job], source="MOCK")
            back = store.get(job.job_id).job
            self.assertEqual(asdict(replace(job, status=STATUS_OPEN)), asdict(back))
            tags = {(r["kind"], r["value"]) for r in store.conn.execute("SELECT kind, value FROM job_tags")}
            self.assertIn(("tech_stack", "FastAPI"), tags)
            self.assertIn(("keywords", "백엔드/서버개발"), tags)
            self.assertEqual(1, store.stats()["by_status"][STATUS_OPEN])
            self.assertEqual([job.job_id], [j.job_id for j in store.active_jobs()])

    def test_legacy_image_flag_with_requirement_text_is_repaired_on_read(self):
        """구 수집본의 잘못된 이미지 플래그가 추천 카드까지 전파되지 않는다."""
        with tempfile.TemporaryDirectory() as temp, SqliteJobStore(Path(temp) / "s.sqlite") as store:
            job = replace(
                mock_jobs()[0],
                description="주요업무 " + "Python 기반 데이터 분석과 API 개발을 수행합니다. " * 12,
                body_is_image=True,
            )
            store.upsert([job], source="MOCK")
            self.assertFalse(store.get(job.job_id).job.body_is_image)

    def test_json_store_still_used_for_json_paths(self):
        self.assertTrue(is_sqlite_path(Path("x/store.sqlite")))
        self.assertFalse(is_sqlite_path(Path("x/store.json")))
        with tempfile.TemporaryDirectory() as temp:
            store = JobStore(Path(temp) / "store.json")
            store.upsert(mock_jobs(), source="MOCK")
            store.save()
            self.assertEqual(len(mock_jobs()), len(JobStore(Path(temp) / "store.json").load().records))


if __name__ == "__main__":
    unittest.main()
