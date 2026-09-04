from app.config import Settings
from app.models import JobRecommendationRequest, ResumeProfileGeneration, ReviewGeneration
from app.service import CoverLetterService
from app.vector_store import RetrievedJob


class FakeRepository:
    def search(self, query: str, top_k: int) -> list[RetrievedJob]:
        assert "Python" in query
        assert "교육 플랫폼" in query
        return [
            RetrievedJob(
                job_id="SARAMIN-101", company="테스트 회사", title="Python 백엔드 개발자",
                industry_code=None, industry_name=None, job_mid_code=None, job_mid_name=None,
                job_code=None, job_name=None, location_code=None, location="서울",
                employment_type_code=None, employment_type="정규직", career="신입",
                education=None, job_sectors=("백엔드/서버개발",),
                tech_tags=("Python", "FastAPI"), detail_quality="DETAILED",
                source="https://example.test/101", chunks=("Python FastAPI 기반 API 개발",),
            )
        ]


def test_recommendation_removes_ungrounded_skills_and_returns_resume_evidence() -> None:
    def profile_generator(_: dict[str, str]) -> ResumeProfileGeneration:
        return ResumeProfileGeneration(
            target_roles=["백엔드 개발자"],
            skills=[
                {"name": "Python", "resume_quote": "Python으로 API를 개발했습니다."},
                {"name": "Kubernetes", "resume_quote": "Kubernetes 운영 경험 3년"},
            ],
            experiences=[], search_terms=["Python", "Kubernetes"],
            cover_letter_intents=["교육 플랫폼"],
        )

    service = CoverLetterService(
        Settings(openai_api_key="test"), FakeRepository(),
        generator=lambda _: ReviewGeneration(
            question_intent="", requirements=[], improvements=[],
            confirmation_questions=[], revised_draft=""
        ),
        profile_generator=profile_generator,
    )
    response = service.recommend_jobs(
        JobRecommendationRequest(
            resume_text="Python으로 API를 개발했습니다. 팀 프로젝트에서 테스트도 작성했습니다.",
            base_cover_letter_text="교육 플랫폼 백엔드 개발에 기여하고 싶습니다.",
            preferred_roles=["백엔드 개발자"],
        )
    )

    assert [skill.name for skill in response.analyzed_profile.skills] == ["Python"]
    assert response.results[0].matched_resume_skills == ["Python"]
    assert response.results[0].resume_evidence == ["Python으로 API를 개발했습니다."]
    assert any("Kubernetes" in item for item in response.analyzed_profile.grounding_warnings)
