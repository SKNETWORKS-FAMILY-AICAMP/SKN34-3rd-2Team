"""추천 근거 필드: 일치 기술 + 프로젝트 근거 + 근거 없는 요구 기술 = 공고 기술 전체."""

from __future__ import annotations

import unittest

from job_matching_bot.matching.ranking import rank_jobs
from job_matching_bot.schemas.resume import mock_resumes
from job_matching_bot.tests.test_resumes import _saramin_job


class UnmatchedSkillsEvidenceTest(unittest.TestCase):
    def test_unmatched_skills_complete_the_declared_pool(self):
        jobs = [
            _saramin_job("e1", region="전국", tech_stack=("Python", "FastAPI", "Kubernetes", "Terraform")),
            _saramin_job("e2", region="전국", tech_stack=("Java", "Spring Boot")),
        ]
        for resume in mock_resumes().values():
            for item in rank_jobs(jobs, resume):
                evidence = item["evidence"]
                matched = set(evidence["matched_skills"])
                project = set(evidence["matched_project_skills"])
                unmatched = set(evidence["unmatched_skills"])
                self.assertEqual(item["score_detail"]["skills_total"], len(matched | project | unmatched))
                self.assertFalse(unmatched & matched)
                self.assertFalse(unmatched & project)
                # 출처별(필수·우대·태그) 목록을 합치면 공고 기술 전체이고 서로 겹치지 않는다.
                buckets = [
                    evidence[key]
                    for key in (
                        "matched_required", "matched_preferred", "matched_tags",
                        "unmatched_required", "unmatched_preferred", "unmatched_tags",
                    )
                ]
                flat = [name for bucket in buckets for name in bucket]
                self.assertEqual(item["score_detail"]["skills_total"], len(flat))
                self.assertEqual(len(flat), len(set(flat)))
                # 공고 조건이 카드에 실린다.
                self.assertIn("region", item)
                self.assertIn("employment_type", item)


if __name__ == "__main__":
    unittest.main()
