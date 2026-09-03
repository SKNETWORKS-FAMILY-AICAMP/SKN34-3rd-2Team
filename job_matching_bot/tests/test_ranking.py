"""Ranking 규칙 검증.

가중치 값 자체는 평가 세트로 조정할 대상이라 여기서 고정하지 않는다.
검증하는 것은 "무엇을 채점 대상으로 삼는가"다.
"""

import unittest
from dataclasses import replace

from job_matching_bot.matching.ranking import (
    WEIGHT_CONDITIONS,
    WEIGHT_PROJECT,
    WEIGHT_ROLE,
    WEIGHT_SKILLS,
    declared_skills,
    rank_jobs,
)
from job_matching_bot.schemas.job_posting import Job
from job_matching_bot.schemas.resume import sample_resume


def _job(**overrides) -> Job:
    base = Job(
        job_id="T-1",
        source="TEST",
        source_job_id="1",
        source_url="test://1",
        company="테스트",
        company_type="미기재",
        title="백엔드 개발자",
        description="",
        required_skills=[],
        preferred_skills=[],
        career_type="ANY",
        min_career_years=None,
        education="학력무관",
        region="서울",
        employment_type="정규직",
        posted_at=None,
        deadline=None,
        status="OPEN",
        content_hash="sha256:test",
        parser_version="test",
        field_provenance={},
    )
    return replace(base, **overrides)


class WeightTest(unittest.TestCase):
    def test_weights_sum_to_one(self):
        self.assertAlmostEqual(
            1.0, WEIGHT_ROLE + WEIGHT_SKILLS + WEIGHT_PROJECT + WEIGHT_CONDITIONS
        )


class DeclaredSkillsTest(unittest.TestCase):
    def test_all_sources_merge_into_one_pool(self):
        job = _job(
            required_skills=["Python"],
            preferred_skills=["Docker"],
            tech_stack=["Python", "Kotlin"],
        )
        pool, sources = declared_skills(job)
        self.assertEqual({"python", "docker", "kotlin"}, set(pool))
        self.assertEqual(["required_skills", "preferred_skills", "tech_stack"], sources)

    def test_spelling_variants_count_once(self):
        # "Spring Boot"와 "SpringBoot"는 하나의 기술이다.
        pool, _ = declared_skills(_job(required_skills=["Spring Boot"], tech_stack=["SpringBoot"]))
        self.assertEqual(1, len(pool))
        # 표시용 원문은 먼저 나온 출처의 것을 쓴다.
        self.assertEqual("Spring Boot", pool["springboot"])

    def test_tech_stack_only_job_reports_its_source(self):
        _, sources = declared_skills(_job(tech_stack=["Java"]))
        self.assertEqual(["tech_stack"], sources)


class SkillScoreTest(unittest.TestCase):
    def test_tech_stack_alone_scores(self):
        # 이미지 본문 공고는 LLM 추출이 안 돼 required_skills가 빈다. 그래도
        # 기업이 고른 기술스택으로 채점돼야 한다.
        job = _job(tech_stack=["Python", "Docker", "Kotlin"])
        [result] = rank_jobs([job], sample_resume())
        self.assertEqual(["tech_stack"], result["score_detail"]["skills_source"])
        self.assertEqual(["Docker", "Python"], result["evidence"]["matched_skills"])
        # 태그 3개는 분모 하한(4)에 걸린다: 2/4
        self.assertAlmostEqual(2 / 4, result["score_detail"]["skills"], places=3)

    def test_single_tag_posting_cannot_outscore_a_richer_match(self):
        # 태그 1개가 우연히 맞은 공고(1/1)가 7개 중 5개 맞은 공고를 이기면 안 된다.
        sparse = _job(job_id="sparse", tech_stack=["Python"])
        rich = _job(
            job_id="rich",
            tech_stack=["Python", "Django", "FastAPI", "PostgreSQL", "Docker", "Kotlin", "Go"],
        )
        results = {r["job_id"]: r for r in rank_jobs([sparse, rich], sample_resume())}
        self.assertLess(
            results["sparse"]["score_detail"]["skills"],
            results["rich"]["score_detail"]["skills"],
        )

    def test_required_and_tech_stack_are_not_double_counted(self):
        job = _job(required_skills=["Python"], tech_stack=["Python", "Kotlin"])
        [result] = rank_jobs([job], sample_resume())
        # Python 1개 일치 / 전체 2개(Python, Kotlin) → 분모 하한 4 적용: 1/4.
        # Python이 두 번 세이지 않는다는 것은 skills_total 로 확인한다.
        self.assertAlmostEqual(0.25, result["score_detail"]["skills"], places=3)
        self.assertEqual(2, result["score_detail"]["skills_total"])

    def test_resume_spelling_variant_matches_tag(self):
        # 이력서에 "Postgres"라고 적어도 태그 "PostgreSQL"에 맞아야 한다.
        resume = replace(sample_resume(), skills=["Postgres"], project_skills=[])
        [result] = rank_jobs([_job(tech_stack=["PostgreSQL"])], resume)
        self.assertEqual(["PostgreSQL"], result["evidence"]["matched_skills"])

    def test_no_skill_information_scores_zero_with_empty_source(self):
        [result] = rank_jobs([_job()], sample_resume())
        self.assertEqual([], result["score_detail"]["skills_source"])
        self.assertEqual(0.0, result["score_detail"]["skills"])

    def test_broad_tech_stack_is_diluted_not_rewarded(self):
        # 태그를 54개 고른 공고는 아무에게나 높은 점수를 주면 안 된다.
        # 분모가 커져 자연히 희석된다.
        narrow = _job(job_id="narrow", tech_stack=["Python", "Django"])
        broad = _job(
            job_id="broad",
            tech_stack=["Python", "Django"] + [f"Tech{i}" for i in range(50)],
        )
        results = {r["job_id"]: r for r in rank_jobs([narrow, broad], sample_resume())}
        self.assertGreater(
            results["narrow"]["score_detail"]["skills"],
            results["broad"]["score_detail"]["skills"],
        )

    def test_project_experience_matches_tech_stack_too(self):
        job = _job(tech_stack=["PostgreSQL"])
        [result] = rank_jobs([job], sample_resume())
        self.assertEqual(["PostgreSQL"], result["evidence"]["matched_project_skills"])


if __name__ == "__main__":
    unittest.main()
