"""cover_letter_rag 인덱서용 정적 공고 JSON 내보내기 테스트."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from job_matching_bot.config import DEFAULT_INPUT
from job_matching_bot.exporters.cover_letter_rag_jobs import to_rag_job, write_rag_jobs
from job_matching_bot.pipeline import AS_OF, run_pipeline

# cover_letter_rag/scripts/index_jobs.py `_validate_job`이 요구하는 필드.
# 서버 코드를 import하지 않고 계약만 복제한다. 그쪽이 바뀌면 여기도 맞춘다.
INDEXER_REQUIRED_FIELDS = {"job_id", "company", "title", "summary", "responsibilities", "requirements"}


def _record(**overrides):
    base = {
        "id": "SARAMIN-1",
        "company": "샘플",
        "position": "백엔드 개발자",
        "career_type": "ANY",
        "min_career_years": None,
        "education": "학력무관",
        "status": "OPEN",
        "employment_type": "정규직",
        "location": "서울",
        "deadline": "2026-12-31",
        "required_skills": ["Python", "FastAPI"],
        "preferred_skills": ["Docker"],
        "tech_stack": ["Python", "FastAPI", "Docker"],
        "description": "학습 플랫폼 API 개발\n\n운영 자동화\n",
        "source": "SARAMIN_POC",
        "source_url": "https://example.test/1",
        "collected_at": "2026-09-02T12:00:00+09:00",
    }
    base.update(overrides)
    return base


class ToRagJobTest(unittest.TestCase):
    def test_maps_skills_to_required_and_preferred(self):
        job = to_rag_job(_record())
        self.assertTrue(INDEXER_REQUIRED_FIELDS <= job.keys())
        self.assertEqual("SARAMIN-1", job["job_id"])
        self.assertEqual(
            [{"type": "필수", "text": "Python"}, {"type": "필수", "text": "FastAPI"}],
            job["requirements"],
        )
        self.assertEqual(["Docker"], job["preferred"])
        self.assertEqual(["학습 플랫폼 API 개발", "운영 자동화"], job["responsibilities"])
        self.assertEqual("학습 플랫폼 API 개발 운영 자동화", job["summary"])

    def test_hard_conditions_become_requirement_sentences(self):
        job = to_rag_job(_record(min_career_years=3, education="대졸"))
        texts = [item["text"] for item in job["requirements"]]
        self.assertIn("경력 3년 이상", texts)
        self.assertIn("학력 대졸", texts)

    def test_requirements_never_empty(self):
        tagged = to_rag_job(_record(required_skills=[], tech_stack=["Java"]))
        self.assertEqual([{"type": "기타", "text": "기술스택 태그: Java"}], tagged["requirements"])

        bare = to_rag_job(_record(required_skills=[], tech_stack=[], description=""))
        self.assertEqual(1, len(bare["requirements"]))
        self.assertEqual("기타", bare["requirements"][0]["type"])
        # 설명이 없으면 회사·직무로 요약과 업무를 채운다.
        self.assertEqual("샘플 백엔드 개발자", bare["summary"])
        self.assertEqual(["샘플 백엔드 개발자"], bare["responsibilities"])


class WriteRagJobsTest(unittest.TestCase):
    def test_writes_one_file_per_job_and_removes_stale_files(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out = Path(temp_dir)
            (out / "stale.json").write_text("{}", encoding="utf-8")
            written = write_rag_jobs([_record(), _record(id="JOBKOREA/2")], out)
            self.assertEqual(2, len(written))
            self.assertFalse((out / "stale.json").exists())
            self.assertTrue((out / "JOBKOREA_2.json").exists())
            payload = json.loads((out / "SARAMIN-1.json").read_text(encoding="utf-8"))
            self.assertTrue(INDEXER_REQUIRED_FIELDS <= payload.keys())
            self.assertTrue(payload["requirements"])

    def test_pipeline_writes_rag_jobs_from_same_collection(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            result = run_pipeline(
                DEFAULT_INPUT,
                root / "result.json",
                root / "report.md",
                as_of=AS_OF,
                rag_jobs_output=root / "rag_jobs",
            )
            files = sorted((root / "rag_jobs").glob("*.json"))
            self.assertEqual(len(result["collected_jobs"]), len(files))
            ids = {json.loads(f.read_text(encoding="utf-8"))["job_id"] for f in files}
            self.assertEqual({job["id"] for job in result["collected_jobs"]}, ids)


if __name__ == "__main__":
    unittest.main()
