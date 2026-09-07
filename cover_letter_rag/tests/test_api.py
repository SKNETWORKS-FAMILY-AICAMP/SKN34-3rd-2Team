from fastapi.testclient import TestClient

from app.main import app, get_service
from app.models import (
    DraftImprovement,
    JobComparisonResponse,
    JobRecommendationResponse,
    JobRecommendationResult,
    JobRecommendationResponse,
    JobRecommendationResult,
    JobSearchResponse,
    JobSearchResult,
    RequirementComparison,
    RequirementStatus,
    ResumeProfileResponse,
    ResumeProfileResponse,
    ReviewResponse,
    SourceReference,
)


class FakeService:
    def search_jobs(self, resume_text: str, top_k: int) -> JobSearchResponse:
        return JobSearchResponse(
            results=[
                JobSearchResult(
                    rank=1,
                    job_id="sample-1",
                    company="샘플 회사",
                    title="백엔드 개발자",
                    location="서울",
                    employment_type="정규직",
                    summary="Python API 개발",
                    source="data/jobs/sample.json",
                )
            ]
        )

    def review(self, request) -> ReviewResponse:
        return ReviewResponse(
            question_intent="직무 강점과 기여 방안 확인",
            requirements=[
                RequirementComparison(
                    requirement="Python 경험",
                    requirement_type="필수",
                    source_id="provided_job_posting",
                    status=RequirementStatus.MET,
                    resume_evidence=[
                        {
                            "resume_quote": "Python으로 API를 개발했습니다.",
                            "explanation": "직접 개발 근거",
                        }
                    ],
                )
            ],
            improvements=[DraftImprovement(issue="추상적 표현", suggestion="구체 행동으로 교체")],
            confirmation_questions=[],
            revised_draft="Python으로 API를 개발했습니다.",
            sources=[
                SourceReference(
                    source_id="resume",
                    source_type="resume",
                    title="사용자 제공 이력서",
                    excerpt=request.resume_text,
                )
            ],
        )

    def analyze_profile(self, request) -> ResumeProfileResponse:
        return ResumeProfileResponse(
            target_roles=["백엔드 개발자"],
            skills=[{"name": "Python", "resume_quote": "Python으로 API를 개발했습니다."}],
            experiences=[],
            search_terms=["Python", "백엔드 개발자"],
        )

    def recommend_jobs(self, request) -> JobRecommendationResponse:
        return JobRecommendationResponse(
            analyzed_profile=self.analyze_profile(request),
            results=[
                JobRecommendationResult(
                    rank=1,
                    job_id="sample-1",
                    company="샘플 회사",
                    title="백엔드 개발자",
                    location="서울",
                    employment_type="정규직",
                    summary="Python API 개발",
                    source="data/jobs/sample.json",
                    matched_resume_skills=["Python"],
                    resume_evidence=["Python으로 API를 개발했습니다."],
                    recommendation_reasons=["이력서 기술과 공고 키워드가 일치합니다."],
                )
            ],
        )

    def compare_job(self, request) -> JobComparisonResponse:
        return JobComparisonResponse(
            job=JobSearchResult(
                rank=1, job_id=request.job_id, company="샘플 회사", title="백엔드 개발자",
                summary="Python API 개발", source="data/jobs/sample.json",
            ),
            requirements=[
                RequirementComparison(
                    requirement="Python 경험", requirement_type="필수",
                    source_id=f"indexed_job:{request.job_id}", status=RequirementStatus.MET,
                    resume_evidence=[{
                        "resume_quote": "Python으로 API를 개발했습니다.",
                        "explanation": "직접 개발 근거",
                    }],
                )
            ],
            confirmation_questions=[], sources=[],
        )

    def analyze_profile(self, request) -> ResumeProfileResponse:
        return ResumeProfileResponse(
            target_roles=["백엔드 개발자"],
            skills=[{"name": "Python", "resume_quote": "Python으로 API를 개발했습니다."}],
            experiences=[],
            search_terms=["Python", "백엔드 개발자"],
        )

    def recommend_jobs(self, request) -> JobRecommendationResponse:
        profile = self.analyze_profile(request)
        return JobRecommendationResponse(
            analyzed_profile=profile,
            results=[
                JobRecommendationResult(
                    rank=1,
                    job_id="sample-1",
                    company="샘플 회사",
                    title="백엔드 개발자",
                    location="서울",
                    employment_type="정규직",
                    summary="Python API 개발",
                    source="data/jobs/sample.json",
                    matched_resume_skills=["Python"],
                    resume_evidence=["Python으로 API를 개발했습니다."],
                    recommendation_reasons=["이력서 기술과 공고 키워드가 일치합니다."],
                )
            ],
        )


app.dependency_overrides[get_service] = lambda: FakeService()
client = TestClient(app)


def test_health_does_not_require_api_key() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["model"] == "gpt-5.6-luna"


def test_search_endpoint_contract() -> None:
    response = client.post(
        "/api/v1/jobs/search",
        json={"resume_text": "Python으로 교육용 REST API를 개발한 프로젝트 경험이 있습니다.", "top_k": 3},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["results"][0]["job_id"] == "sample-1"
    assert "지원자 점수" in body["notice"]


def test_review_endpoint_contract() -> None:
    response = client.post(
        "/api/v1/reviews",
        json={
            "resume_text": "Python으로 API를 개발했습니다. 팀 프로젝트에서 테스트도 작성했습니다.",
            "job_posting_text": "Python API 개발 경험과 테스트 작성 경험이 필요합니다.",
            "cover_letter_question": "직무 강점을 작성해 주세요.",
            "draft_text": "Python 개발 경험을 바탕으로 기여하겠습니다.",
            "top_k": 2,
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["requirements"][0]["status"] == "충족"
    assert "합격 가능성" in body["notice"]


def test_recommend_endpoint_uses_resume_without_registered_skill_tags() -> None:
    response = client.post(
        "/api/v1/jobs/recommend",
        json={
            "resume_text": "Python으로 API를 개발했습니다. 팀 프로젝트에서 테스트도 작성했습니다.",
            "base_cover_letter_text": "교육 플랫폼 백엔드 개발에 기여하고 싶습니다.",
            "preferred_roles": ["백엔드 개발자"],
            "top_k": 3,
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["analyzed_profile"]["skills"][0]["name"] == "Python"
    assert body["results"][0]["matched_resume_skills"] == ["Python"]
    assert "registered_skills" not in body


def test_compare_selected_job_endpoint_contract() -> None:
    response = client.post(
        "/api/v1/jobs/compare",
        json={
            "job_id": "sample-1",
            "resume_text": "Python으로 API를 개발했습니다. 팀 프로젝트에서 테스트도 작성했습니다.",
        },
    )
    assert response.status_code == 200
    assert response.json()["requirements"][0]["status"] == "충족"


def test_recommend_endpoint_uses_resume_without_registered_skill_tags() -> None:
    response = client.post(
        "/api/v1/jobs/recommend",
        json={
            "resume_text": "Python으로 API를 개발했습니다. 팀 프로젝트에서 테스트도 작성했습니다.",
            "base_cover_letter_text": "교육 플랫폼 백엔드 개발에 기여하고 싶습니다.",
            "preferred_roles": ["백엔드 개발자"],
            "top_k": 3,
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["analyzed_profile"]["skills"][0]["name"] == "Python"
    assert body["results"][0]["matched_resume_skills"] == ["Python"]
    assert "registered_skills" not in body


def test_validation_rejects_blank_payload() -> None:
    response = client.post("/api/v1/jobs/search", json={"resume_text": "   "})
    assert response.status_code == 422
