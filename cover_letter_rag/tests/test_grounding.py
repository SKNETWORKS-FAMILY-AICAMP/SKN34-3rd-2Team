from app.models import (
    RequirementComparison,
    RequirementStatus,
    ResumeEvidence,
    ReviewGeneration,
    ReviewRequest,
)
from app.service import enforce_grounding


def _request() -> ReviewRequest:
    return ReviewRequest(
        resume_text="Python으로 REST API를 개발했습니다. 팀 프로젝트에서 코드 리뷰를 진행했습니다.",
        job_posting_text="Python과 AWS 경험이 필요합니다.",
        cover_letter_question="직무 역량을 작성해 주세요.",
        draft_text="Python API 개발 경험으로 기여하겠습니다.",
        top_k=2,
    )


def test_unverified_resume_quote_is_removed_and_status_is_changed() -> None:
    generation = ReviewGeneration(
        question_intent="직무 역량",
        requirements=[
            RequirementComparison(
                requirement="AWS 운영 경험",
                requirement_type="필수",
                source_id="provided_job_posting",
                status=RequirementStatus.MET,
                resume_evidence=[
                    ResumeEvidence(
                        resume_quote="AWS에서 대규모 서비스를 운영했습니다.",
                        explanation="운영 경험",
                    )
                ],
            )
        ],
        improvements=[],
        confirmation_questions=[],
        revised_draft="Python API 개발 경험으로 기여하겠습니다.",
    )

    response = enforce_grounding(_request(), generation, [])

    assert response.requirements[0].status == RequirementStatus.NEEDS_CONFIRMATION
    assert response.requirements[0].resume_evidence == []
    assert response.confirmation_questions
    assert response.grounding_warnings


def test_invented_number_falls_back_to_original_draft() -> None:
    request = _request()
    generation = ReviewGeneration(
        question_intent="직무 역량",
        requirements=[],
        improvements=[],
        confirmation_questions=[],
        revised_draft="API 응답 시간을 50% 개선했습니다.",
    )

    response = enforce_grounding(request, generation, [])

    assert response.revised_draft == request.draft_text
    assert any("50%" in warning for warning in response.grounding_warnings)


def test_exact_resume_quote_is_preserved() -> None:
    quote = "Python으로 REST API를 개발했습니다."
    generation = ReviewGeneration(
        question_intent="직무 역량",
        requirements=[
            RequirementComparison(
                requirement="Python API 개발 경험",
                requirement_type="필수",
                source_id="provided_job_posting",
                status=RequirementStatus.MET,
                resume_evidence=[ResumeEvidence(resume_quote=quote, explanation="직접 근거")],
            )
        ],
        improvements=[],
        confirmation_questions=[],
        revised_draft="Python API 개발 경험으로 기여하겠습니다.",
    )

    response = enforce_grounding(_request(), generation, [])

    assert response.requirements[0].status == RequirementStatus.MET
    assert response.requirements[0].resume_evidence[0].resume_quote == quote

