"""조건으로 공고를 찾는 부분. 챗봇이 쓴다.

핵심 약속: **사용자가 말하지 않은 조건으로 거르지 않는다.** 그리고 마감된 공고는
살아 있는 것처럼 보여주지 않는다.
"""

from __future__ import annotations

import tempfile
import unittest
from dataclasses import replace
from datetime import datetime
from pathlib import Path

from job_matching_bot.ingestion.mock_source import mock_jobs
from job_matching_bot.ingestion.sqlite_store import SqliteJobStore
from job_matching_bot.retrieval.store_search import KST, JobFilters, search

NOW = datetime(2026, 9, 7, 12, tzinfo=KST)


class StoreSearchTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "store.sqlite"
        base = mock_jobs()[0]
        self.jobs = [
            replace(
                base,
                job_id="A",
                source_job_id="A",
                company="가회사",
                title="백엔드 개발자",
                description="Python으로 API를 만듭니다",
                tech_stack=["Python", "FastAPI"],
                keywords=["IT개발·데이터"],
                region="서울 강남구",
                career_type="ENTRY",
                min_career_years=None,
                employment_type="정규직",
                deadline="2026-09-30",
                status="OPEN",
            ),
            replace(
                base,
                job_id="B",
                source_job_id="B",
                company="나회사",
                title="프론트엔드 개발자",
                description="React로 화면을 만듭니다",
                tech_stack=["React"],
                keywords=["IT개발·데이터"],
                region="경기 성남시",
                career_type="EXPERIENCED",
                min_career_years=3,
                employment_type="정규직",
                deadline=None,
                status="OPEN",
            ),
            replace(
                base,
                job_id="C",
                source_job_id="C",
                company="다회사",
                title="생산관리 담당자",
                description="공정을 관리합니다",
                tech_stack=[],
                keywords=["생산"],
                region="서울 금천구",
                career_type="ENTRY",
                min_career_years=None,
                employment_type="계약직",
                deadline="2026-09-08",
                status="OPEN",
            ),
            replace(
                base,
                job_id="D",
                source_job_id="D",
                company="라회사",
                title="백엔드 개발자 (마감)",
                description="Python 서버",
                tech_stack=["Python"],
                keywords=["IT개발·데이터"],
                region="서울 마포구",
                career_type="ENTRY",
                min_career_years=None,
                employment_type="정규직",
                deadline="2026-09-01",
                status="OPEN",
            ),
        ]
        with SqliteJobStore(self.path) as store:
            store.upsert(self.jobs, source="MOCK")

    def tearDown(self):
        self.temp.cleanup()

    def find(self, **kwargs):
        return search(self.path, JobFilters(**kwargs), limit=10, as_of=NOW)

    def test_no_conditions_returns_every_live_posting(self):
        result = self.find()
        self.assertEqual({"A", "B", "C"}, {job.job_id for job in result.jobs})

    def test_expired_postings_never_surface(self):
        """마감일이 지난 공고는 status가 OPEN이어도 보여주지 않는다."""
        result = self.find(roles=["백엔드"])
        self.assertEqual(["A"], [job.job_id for job in result.jobs])

    def test_role_matches_title_tags_or_body(self):
        self.assertEqual(["B"], [job.job_id for job in self.find(roles=["프론트엔드"]).jobs])
        self.assertEqual(["A"], [job.job_id for job in self.find(skills=["FastAPI"]).jobs])
        # 본문에만 있는 말도 찾는다.
        self.assertEqual(["C"], [job.job_id for job in self.find(keywords=["공정"]).jobs])

    def test_several_terms_match_any_of_them(self):
        """'백엔드 React'는 둘 다인 공고가 아니라 하나라도 걸리는 공고를 찾는다."""
        result = self.find(roles=["백엔드", "프론트엔드"])
        self.assertEqual({"A", "B"}, {job.job_id for job in result.jobs})

    def test_region_narrows(self):
        self.assertEqual({"A", "C"}, {job.job_id for job in self.find(regions=["서울"]).jobs})

    def test_entry_level_includes_open_to_all(self):
        """신입을 찾을 때 '경력무관'도 포함한다. 지원할 수 있는 자리다."""
        with SqliteJobStore(self.path) as store:
            store.upsert([replace(self.jobs[1], job_id="E", source_job_id="E", career_type="ANY")], source="MOCK")
        result = self.find(career="신입")
        self.assertIn("E", {job.job_id for job in result.jobs})
        self.assertNotIn("B", {job.job_id for job in result.jobs})

    def test_experienced_excludes_entry_only(self):
        result = self.find(career="경력")
        self.assertEqual(["B"], [job.job_id for job in result.jobs])

    def test_employment_type_narrows(self):
        self.assertEqual(["C"], [job.job_id for job in self.find(employment_types=["계약직"]).jobs])

    def test_deadline_soon_keeps_only_dated_and_near(self):
        """마감 임박은 날짜가 없는 상시 공고를 빼야 한다. 급한 것만 보려는 요청이다."""
        result = self.find(deadline_within_days=3)
        self.assertEqual(["C"], [job.job_id for job in result.jobs])

    def test_conditions_combine_with_and(self):
        result = self.find(regions=["서울"], career="신입", employment_types=["정규직"])
        self.assertEqual(["A"], [job.job_id for job in result.jobs])

    def test_total_counts_beyond_the_shown_page(self):
        result = search(self.path, JobFilters(), limit=1, as_of=NOW)
        self.assertEqual(1, len(result.jobs))
        self.assertEqual(3, result.total)

    def test_career_label_is_readable(self):
        by_id = {job.job_id: job for job in self.find().jobs}
        self.assertEqual("신입", by_id["A"].career_label)
        self.assertEqual("경력 3년 이상", by_id["B"].career_label)

    def test_title_match_outranks_a_body_mention(self):
        """본문에 말이 스친 범용 공고가 그 일을 뽑는 공고를 밀어내면 안 된다.

        "신입/경력 공개채용" 같은 공고는 본문에 온갖 직무를 다 적어 둔다. 정렬을 안 하면
        무엇을 물어도 그런 공고만 올라온다.
        """
        with SqliteJobStore(self.path) as store:
            store.upsert(
                [
                    replace(
                        self.jobs[0],
                        job_id="Z",
                        source_job_id="Z",
                        company="마회사",
                        title="2026 공개채용",
                        description="백엔드, 프론트엔드, 기획 등 전 직군을 뽑습니다",
                        tech_stack=[],
                        keywords=["총무·법무·사무"],
                    )
                ],
                source="MOCK",
            )
        jobs = self.find(roles=["백엔드"]).jobs
        self.assertEqual("A", jobs[0].job_id, "제목에 있는 공고가 먼저")
        self.assertEqual(3, jobs[0].relevance)
        self.assertEqual("Z", jobs[1].job_id)
        self.assertEqual(1, jobs[1].relevance, "본문에만 있으면 낮게")

    def test_strong_counts_only_title_and_tag_matches(self):
        with SqliteJobStore(self.path) as store:
            store.upsert(
                [
                    replace(
                        self.jobs[0],
                        job_id="Z",
                        source_job_id="Z",
                        title="2026 공개채용",
                        description="백엔드 등 전 직군",
                        tech_stack=[],
                        keywords=["총무·법무·사무"],
                    )
                ],
                source="MOCK",
            )
        result = self.find(roles=["백엔드"])
        self.assertEqual(2, result.total)
        self.assertEqual(1, result.strong, "본문에만 스친 것은 빼고 센다")

    def test_tag_match_ranks_between_title_and_body(self):
        jobs = self.find(skills=["Python"]).jobs
        self.assertEqual("A", jobs[0].job_id)
        self.assertEqual(2, jobs[0].relevance, "기술 태그에 있으면 2")

    def test_summary_shows_what_was_used(self):
        filters = JobFilters(roles=["백엔드"], regions=["서울"], career="신입")
        self.assertEqual("백엔드 · 서울 · 신입", filters.summary())
        self.assertEqual("조건 없음", JobFilters().summary())
        self.assertTrue(JobFilters().is_empty)


if __name__ == "__main__":
    unittest.main()
