from fastapi.testclient import TestClient

from app.config import Settings
from app.firebase_gateway import FirebaseAuthenticationError, ResumeNotFoundError
from app.main import app, get_resume_review_service
from app.models import (
    FirestoreResumeReviewRequest,
    ResumeReviewGeneration,
    ResumeSectionReview,
)
from app.resume_review import (
    ResumeReviewService,
    enforce_resume_review_grounding,
    render_resume_content,
)


SAMPLE_CONTENT = {
    "basicInfo": {
        "name": "홍길동",
        "phone": "010-1234-5678",
        "email": "private@example.com",
        "birthDate": "2000-01-01",
        "githubUrl": "https://github.com/private",
    },
    "coreCompetencies": {"text": "Python REST API 개발"},
    "techStack": [{"id": "skill-1", "name": "Python", "level": "중"}],
    "projects": [
        {
            "id": "project-1",
            "name": "LMS 프로젝트",
            "role": "백엔드 개발",
            "techStack": "FastAPI",
            "description": "API 응답 시간을 20% 개선했습니다.",
            "url": "https://private.example.com",
        }
    ],
}


class FakeFirebase:
    def __init__(self) -> None:
        self.saved: dict | None = None
        self.states = {}

    def claim_review(self, cohort_id, resume_id, uid, request_id, fingerprint):
        from app.review_workflow import ReviewConflict
        if request_id in self.states:
            state = self.states[request_id]
            if state['fingerprint'] != fingerprint or not state.get('response'):
                raise ReviewConflict('duplicate')
            return state
        self.states[request_id] = {'fingerprint': fingerprint}
        return {}

    def complete_review(self, cohort_id, resume_id, uid, request_id, response):
        self.saved = response
        self.states[request_id]['response'] = response

    def fail_review(self, *args):
        pass

    def get_ai_review(self, cohort_id, resume_id, uid, review_id):
        self.get_owned_resume(cohort_id, resume_id, uid)
        return self.states[review_id]['response']

    def verify_id_token(self, id_token: str) -> str:
        if id_token != "valid-token":
            raise FirebaseAuthenticationError()
        return "user-1"

    def get_owned_resume(self, cohort_id: str, resume_id: str, uid: str) -> dict:
        if (cohort_id, resume_id, uid) != ("cohort-1", "resume-1", "user-1"):
            raise ResumeNotFoundError()
        return {"userId": "user-1", "content": SAMPLE_CONTENT}

    def save_ai_review(self, cohort_id: str, resume_id: str, uid: str, payload: dict) -> str:
        self.saved = payload
        return "review-1"


def _generation(_: dict[str, str]) -> ResumeReviewGeneration:
    return ResumeReviewGeneration(
        summary="프로젝트 성과 근거가 명확하며 역할을 더 구체화할 수 있습니다.",
        section_reviews=[
            ResumeSectionReview(
                section_key="projects",
                strengths=["성과 수치가 있습니다."],
                issues=["구체 행동이 부족합니다."],
                resume_quotes=["API 응답 시간을 20% 개선했습니다."],
                suggested_revision="API 응답 시간을 20% 개선했습니다.",
                confirmation_questions=["어떤 방법으로 개선했나요?"],
            )
        ],
    )


def test_renderer_excludes_personal_information_and_internal_fields() -> None:
    rendered = render_resume_content(SAMPLE_CONTENT)

    assert "홍길동" not in rendered
    assert "010-1234-5678" not in rendered
    assert "private@example.com" not in rendered
    assert "project-1" not in rendered
    assert "private.example.com" not in rendered
    assert "Python REST API 개발" in rendered
    assert "API 응답 시간을 20% 개선했습니다." in rendered


def test_review_reads_owned_resume_and_saves_separate_review() -> None:
    firebase = FakeFirebase()
    service = ResumeReviewService(Settings(openai_api_key="test"), firebase, generator=_generation)

    response = service.review(
        "valid-token",
        FirestoreResumeReviewRequest(cohort_id="cohort-1", resume_id="resume-1"),
    )

    assert response.review_id
    assert response.section_reviews[0].suggested_revision is None
    assert response.input_fields['projects[0].description'] == SAMPLE_CONTENT['projects'][0]['description']
    assert 'basicInfo' in response.excluded_fields
    assert firebase.saved is not None
    assert firebase.saved['telemetry']['prompt_version'] == 'resume-v3-quality'
    assert "content" not in firebase.saved


def test_sentence_cannot_borrow_another_projects_number():
    from app.models import SentenceReview
    from app.resume_review import ground_sentences
    fields = {'projects[0].description': 'API 개발', 'projects[1].description': '50% 개선'}
    generated = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[
        SentenceReview(field_path='projects[0].description', original_quote='API 개발',
                       reason='구체화', suggested_revision='API 50% 개선', evidence_quotes=['API 개발', '50% 개선'])
    ])
    assert ground_sentences(fields, [], generated)
    assert generated.sentence_reviews[0].suggested_revision is None


def test_confirmed_answer_allows_grounded_revision():
    from app.models import ConfirmationAnswer, SentenceReview
    from app.resume_review import ground_sentences
    answer = ConfirmationAnswer(field_path='projects[0].description', question='변화는?', answer='독립적으로 확인하는 환경을 구축했습니다.')
    generated = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[
        SentenceReview(field_path=answer.field_path, original_quote='QA 개선', reason='구체화',
                       suggested_revision=answer.answer, evidence_quotes=[answer.answer])
    ])
    assert ground_sentences({answer.field_path: 'QA 개선'}, [answer], generated) == []
    assert generated.sentence_reviews[0].suggested_revision == answer.answer


def test_revision_with_invented_number_is_removed() -> None:
    resume_text = render_resume_content(SAMPLE_CONTENT)
    generated = _generation({})
    generated.section_reviews[0].suggested_revision = "API 응답 시간을 50% 개선했습니다."

    grounded, warnings = enforce_resume_review_grounding(resume_text, generated)

    assert grounded.section_reviews[0].suggested_revision is None
    assert warnings
    assert grounded.confirmation_questions


def test_korean_section_label_is_normalized_and_questions_are_limited() -> None:
    resume_text = render_resume_content(SAMPLE_CONTENT)
    generated = ResumeReviewGeneration(
        summary="요약",
        section_reviews=[
            ResumeSectionReview(
                section_key="프로젝트",
                resume_quotes=["API 응답 시간을 20% 개선했습니다."],
                confirmation_questions=[f"질문 {index}" for index in range(5)],
            )
        ],
        confirmation_questions=[f"전체 질문 {index}" for index in range(12)],
    )

    grounded, warnings = enforce_resume_review_grounding(resume_text, generated)

    assert warnings == []
    assert grounded.section_reviews[0].section_key == "projects"
    assert len(grounded.section_reviews[0].confirmation_questions) == 3
    assert len(grounded.confirmation_questions) == 10


class EndpointService:
    def review(self, id_token: str, request: FirestoreResumeReviewRequest):
        return ResumeReviewService(
            Settings(openai_api_key="test"), FakeFirebase(), generator=_generation
        ).review(id_token, request)


def test_firestore_review_endpoint_requires_bearer_token() -> None:
    app.dependency_overrides[get_resume_review_service] = lambda: EndpointService()
    try:
        response = TestClient(app).post(
            "/api/v1/resumes/reviews",
            json={"cohort_id": "cohort-1", "resume_id": "resume-1"},
        )
    finally:
        app.dependency_overrides.pop(get_resume_review_service, None)

    assert response.status_code == 401


def test_firestore_review_endpoint_contract() -> None:
    app.dependency_overrides[get_resume_review_service] = lambda: EndpointService()
    try:
        response = TestClient(app).post(
            "/api/v1/resumes/reviews",
            headers={"Authorization": "Bearer valid-token"},
            json={"cohort_id": "cohort-1", "resume_id": "resume-1"},
        )
    finally:
        app.dependency_overrides.pop(get_resume_review_service, None)

    assert response.status_code == 200
    body = response.json()
    assert body["review_id"]
    assert body["resume_id"] == "resume-1"
    assert "원본 이력서는 변경하지 않았습니다" in body["notice"]
