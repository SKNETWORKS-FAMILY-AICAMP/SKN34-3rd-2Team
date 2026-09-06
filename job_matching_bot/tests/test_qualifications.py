"""자격요건 구간의 전공·자격증·병역 추출과 하드 필터 판정."""

from __future__ import annotations

import dataclasses
import unittest

from job_matching_bot.ingestion.qualifications import extract_qualifications, normalize_term
from job_matching_bot.ingestion.requirement_sections import split_sections
from job_matching_bot.matching.hard_filter import hard_filter
from job_matching_bot.schemas.resume import mock_resumes
from job_matching_bot.tests.test_resumes import _saramin_job

BODY = """
📋 자격요건
- 컴퓨터공학, 소프트웨어 관련 학과 졸업자
- 정보처리기사 자격증 소지자
- 병역필 또는 면제자
- SQLD 소지자 우대
🏠 근무조건
- 정규직
"""


class ExtractQualificationsTest(unittest.TestCase):
    def test_extracts_major_certification_and_military(self):
        q = extract_qualifications(split_sections(BODY).required)
        self.assertEqual(["컴퓨터·소프트웨어"], q.majors)
        self.assertIn("컴퓨터", q.major_terms)
        self.assertIn("소프트웨어", q.major_terms)
        self.assertEqual(["정보처리기사"], q.certifications)  # SQLD는 우대 줄이라 제외
        self.assertTrue(q.military_required)
        self.assertEqual(1, len(q.evidence["majors"]))

    def test_major_any_and_military_any_are_ignored(self):
        q = extract_qualifications(["전공 무관", "병역 무관", "학력무관"])
        self.assertEqual([], q.majors)
        self.assertFalse(q.military_required)

    def test_generic_gisa_and_normalization(self):
        q = extract_qualifications(["- 전기기사 또는 산업안전기사 자격 보유자"])
        self.assertIn("전기기사", q.certifications)
        self.assertIn("산업안전기사", q.certifications)
        self.assertEqual("정보처리기사", normalize_term("정보 처리 기사"))


class HardFilterQualificationTest(unittest.TestCase):
    def _job(self):
        job = _saramin_job("q1", region="전국")
        job.required_majors = ["컴퓨터·소프트웨어"]
        job.required_major_terms = ["컴퓨터", "소프트웨어", "전산"]
        job.required_certifications = ["정보처리기사"]
        job.military_required = True
        return job

    def test_matching_resume_passes_major_and_certification(self):
        resume = dataclasses.replace(
            mock_resumes()["backend_entry"],
            majors=["컴퓨터소프트웨어공학과"],
            certifications=["정보처리기사"],
        )
        result = hard_filter(self._job(), resume)
        self.assertIn("전공 요건 충족: 컴퓨터소프트웨어공학과", result["passed"])
        self.assertIn("자격증 요건 충족: 정보처리기사", result["passed"])
        self.assertIn("병역 조건 확인 필요 (병역필 또는 면제)", result["unknown"])
        self.assertEqual([], result["failed"])

    def test_non_matching_resume_is_check_required_not_fail(self):
        resume = dataclasses.replace(
            mock_resumes()["backend_entry"], majors=["경영학과"], certifications=["SQLD"]
        )
        result = hard_filter(self._job(), resume)
        self.assertEqual([], result["failed"])
        self.assertTrue(any(text.startswith("전공 요건 미확인") for text in result["unknown"]))
        self.assertIn("자격증 확인 필요: 정보처리기사", result["unknown"])

    def test_missing_resume_info_is_check_required(self):
        result = hard_filter(self._job(), mock_resumes()["backend_entry"])
        self.assertIn("전공 확인 필요: 컴퓨터·소프트웨어", result["unknown"])
        self.assertIn("자격증 확인 필요: 정보처리기사", result["unknown"])


if __name__ == "__main__":
    unittest.main()
