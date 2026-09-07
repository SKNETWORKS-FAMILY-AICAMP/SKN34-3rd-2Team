"""레이어별 동작과 전체 Vertical Slice를 함께 검증한다.

경로는 `config`에서 가져오므로 어느 디렉터리에서 실행해도 동작한다.
"""

import json
import tempfile
import unittest
from pathlib import Path

from job_matching_bot.coach.skill_gap import analyze_skill_evidence
from job_matching_bot.config import AS_OF, DEFAULT_INPUT
from job_matching_bot.ingestion.collection import deduplicate, to_collection_record
from job_matching_bot.ingestion.it_filter import classify_it_job, filter_it_jobs
from job_matching_bot.ingestion.jobkorea import normalize_jobkorea
from job_matching_bot.ingestion.mock_source import mock_jobs
from job_matching_bot.matching.hard_filter import hard_filter
from job_matching_bot.ingestion.job_store import JobStore
from job_matching_bot.ingestion.saramin import normalize_saramin
from job_matching_bot.pipeline import analyze, collect_jobs, run_pipeline
from job_matching_bot.schemas.resume import sample_resume
from job_matching_bot.text_match import compile_terms, matched_terms


class JobKoreaNormalizationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.records = json.loads(DEFAULT_INPUT.read_text(encoding="utf-8"))

    def test_records_normalize_with_traceable_hash(self):
        jobs = [normalize_jobkorea(record) for record in self.records]
        self.assertEqual(len(self.records), len(jobs))
        self.assertTrue(all(job.source_job_id for job in jobs))
        self.assertTrue(all(job.content_hash.startswith("sha256:") for job in jobs))

    def test_deduplicate_keeps_one_per_source_id(self):
        jobs = [normalize_jobkorea(record) for record in self.records]
        merged = deduplicate(jobs + jobs)
        self.assertEqual(len(jobs), len(merged))


class TextMatchTest(unittest.TestCase):
    def test_english_term_does_not_match_inside_longer_word(self):
        patterns = compile_terms(["ai", "api"])
        self.assertEqual([], matched_terms("maintain the detail email", patterns))

    def test_english_term_matches_next_to_korean(self):
        patterns = compile_terms(["api"])
        self.assertEqual(["api"], matched_terms("rest api와 db 연동", patterns))

    def test_korean_term_matches_as_substring(self):
        patterns = compile_terms(["백엔드"])
        self.assertEqual(["백엔드"], matched_terms("주니어 백엔드 개발자", patterns))


class HardFilterTest(unittest.TestCase):
    def test_explicit_conditions_split_three_ways(self):
        resume = sample_resume()
        backend_job, frontend_job, senior_job = mock_jobs()
        self.assertEqual("PASS", hard_filter(backend_job, resume)["status"])
        self.assertEqual("CHECK_REQUIRED", hard_filter(frontend_job, resume)["status"])
        self.assertEqual("FAIL", hard_filter(senior_job, resume)["status"])

    def test_unknown_condition_is_not_treated_as_failure(self):
        resume = sample_resume()
        _, frontend_job, _ = mock_jobs()
        result = hard_filter(frontend_job, resume)
        self.assertEqual([], result["failed"])
        self.assertIn("고용형태 미기재", result["unknown"])


class ItFilterTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.records = json.loads(DEFAULT_INPUT.read_text(encoding="utf-8"))

    def test_only_it_jobs_enter_matching_pipeline(self):
        normalized = [normalize_jobkorea(record) for record in self.records]
        jobs = filter_it_jobs(normalized + mock_jobs())
        self.assertTrue(jobs)
        self.assertTrue(all(classify_it_job(job)["status"] == "INCLUDE" for job in jobs))

    def test_non_it_role_in_title_is_excluded(self):
        normalized = [normalize_jobkorea(record) for record in self.records]
        jobs = filter_it_jobs(normalized + mock_jobs())
        self.assertNotIn("JOBKOREA-49902097", {job.job_id for job in jobs})


class SkillGapTest(unittest.TestCase):
    def test_evidence_states_do_not_infer_missing(self):
        resume = sample_resume()
        backend_job = mock_jobs()[0]
        analysis = analyze_skill_evidence(backend_job, resume)
        states = {item["criterion"]: item["judgement"] for item in analysis["judgements"]}
        self.assertEqual("EVIDENCED", states["Python"])
        self.assertEqual("CONFIRMED_MISSING", states["Kubernetes"])
        self.assertEqual("NOT_EVIDENCED", states["Redis"])

    def test_learning_is_only_recommended_after_user_confirmation(self):
        resume = sample_resume()
        analysis = analyze_skill_evidence(mock_jobs()[0], resume)
        confirmed = {
            item["criterion"]
            for item in analysis["judgements"]
            if item["judgement"] == "CONFIRMED_MISSING"
        }
        recommended = {item["skill"] for item in analysis["learning_recommendations"]}
        # Redis는 Catalog에 있지만 사용자 확인이 없으므로 추천되지 않아야 한다.
        self.assertEqual({"Kubernetes"}, recommended)
        self.assertTrue(recommended <= confirmed)

    def test_evidenced_skill_without_project_gets_feedback(self):
        resume = sample_resume()
        analysis = analyze_skill_evidence(mock_jobs()[0], resume)
        feedback = " ".join(analysis["resume_feedback"])
        # Docker는 기술스택에만 있고 프로젝트 근거가 없다.
        self.assertIn("Docker", feedback)


class CollectionRecordTest(unittest.TestCase):
    def test_separates_career_and_employment_type(self):
        record = to_collection_record(mock_jobs()[0])
        self.assertEqual("ENTRY", record["career_type"])
        self.assertEqual("정규직", record["employment_type"])
        self.assertEqual("주니어 백엔드·AI 서비스 개발자", record["position"])
        self.assertEqual("2026-09-30", record["deadline"])
        self.assertEqual("2026-09-02", record["collected_at"])


class StoreIntegrationTest(unittest.TestCase):
    """수집 저장소의 공고가 분석·내보내기에 합류한다."""

    def _saramin_job(self, job_id: str, title: str):
        return normalize_saramin(
            {
                "source_job_id": job_id,
                "source_url": f"https://www.saramin.co.kr/zf_user/jobs/view?rec_idx={job_id}",
                "conditions": {"경력": "신입", "학력": "학력무관", "근무형태": "정규직", "근무지역": "서울"},
                "company_info": {},
                "description": "상세요강\n선택 : IT개발·데이터 > 기술스택 > Python\n",
                "needs_human_review": False,
                "list_item": {"company": "테스트", "title": title, "job_sectors": [], "support_text": "상시채용"},
            },
            as_of=AS_OF,
        )

    def test_without_store_path_only_fixtures_are_used(self):
        records = json.loads(DEFAULT_INPUT.read_text(encoding="utf-8"))
        _, all_jobs, _ = collect_jobs(records, as_of=AS_OF)
        self.assertFalse(any(job.source == "SARAMIN_POC" for job in all_jobs))

    def test_open_store_jobs_join_and_expired_ones_do_not(self):
        records = json.loads(DEFAULT_INPUT.read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as temp_dir:
            store_path = Path(temp_dir) / "store.json"
            store = JobStore(store_path).load()
            store.upsert(
                [self._saramin_job("1", "백엔드 개발자 신입"), self._saramin_job("2", "데이터 엔지니어 신입")],
                source="SARAMIN_POC",
                as_of=AS_OF,
            )
            # 하나를 만료시킨다.
            for record in store.records.values():
                if record.job.source_job_id == "2":
                    record.status = "EXPIRED"
            store.save()

            _, all_jobs, it_jobs = collect_jobs(records, as_of=AS_OF, store_path=store_path)
            ids = {job.job_id for job in all_jobs}
            self.assertIn("SARAMIN-1", ids)
            self.assertNotIn("SARAMIN-2", ids)
            # 기술스택이 앱 쪽 레코드까지 살아 나간다.
            self.assertIn("SARAMIN-1", {job.job_id for job in it_jobs})
            result = analyze(records, as_of=AS_OF, store_path=store_path)
            record = next(r for r in result["collected_jobs"] if r["id"] == "SARAMIN-1")
            self.assertEqual(["Python"], record["tech_stack"])
            self.assertEqual(1, result["input_summary"]["store"])
            # 기준 검증(1순위 등)은 저장소가 붙어도 유지된다.
            self.assertEqual("PASS", result["test_status"])


class VerticalSliceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.records = json.loads(DEFAULT_INPUT.read_text(encoding="utf-8"))

    def test_analyze_runs_without_file_io(self):
        result = analyze(self.records, as_of=AS_OF)
        self.assertEqual("PASS", result["test_status"])
        self.assertEqual("MOCK-BE-001", result["selected_job"]["job_id"])

    def test_full_run_writes_all_artifacts(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            result = run_pipeline(
                DEFAULT_INPUT,
                root / "result.json",
                root / "report.md",
                as_of=AS_OF,
                collection_output=root / "collected_jobs.json",
            )
            self.assertEqual("PASS", result["test_status"])
            self.assertTrue((root / "result.json").exists())
            self.assertTrue((root / "report.md").exists())
            collected = json.loads((root / "collected_jobs.json").read_text(encoding="utf-8"))
            self.assertEqual(len(result["collected_jobs"]), len(collected))
            self.assertTrue(all(item["id"] for item in collected))


if __name__ == "__main__":
    unittest.main()
