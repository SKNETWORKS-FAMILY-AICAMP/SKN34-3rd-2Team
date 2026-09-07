"""공고 지역이 '전국'이면 희망 지역과 무관하게 통과하는지 확인한다."""

from __future__ import annotations

import unittest

from job_matching_bot.matching.hard_filter import hard_filter, is_nationwide
from job_matching_bot.schemas.resume import mock_resumes
from job_matching_bot.tests.test_resumes import _saramin_job


class NationwideRegionTest(unittest.TestCase):
    def test_nationwide_job_passes_any_preferred_region(self):
        resume = mock_resumes()["embedded_entry_regional"]  # 대전 희망
        job = _saramin_job("n1", region="대구 동구, 서울전체, 전국")
        result = hard_filter(job, resume)
        self.assertEqual([], result["failed"])
        self.assertIn("전국 근무 가능 — 지역 조건 충족", result["passed"])

    def test_non_nationwide_job_still_fails_on_mismatch(self):
        resume = mock_resumes()["embedded_entry_regional"]
        job = _saramin_job("n2", region="서울 강남구")
        self.assertEqual("FAIL", hard_filter(job, resume)["status"])

    def test_helper(self):
        self.assertTrue(is_nationwide("전국"))
        self.assertTrue(is_nationwide("서울 강남구, 전국"))
        self.assertFalse(is_nationwide("전남광주 나주시"))


if __name__ == "__main__":
    unittest.main()
