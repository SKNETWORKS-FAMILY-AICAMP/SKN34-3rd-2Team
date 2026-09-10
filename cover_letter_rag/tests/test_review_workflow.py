from copy import deepcopy
import pytest

from app.models import ConfirmationAnswer, FirestoreResumeReviewRequest, ResumeReviewGeneration, SentenceReview, ReviewQuestion
from app.config import Settings
from app.resume_review import ResumeReviewService, ground_sentences
from app.review_workflow import (ReviewConflict, ReviewInputError, redact, prepare_answers,
                                 normalize_diagnostics, normalize_questions, item_references, digest,
                                 focused_followup_context, focused_time_context,
                                 add_short_self_introduction_questions)
from test_resume_review import FakeFirebase, SAMPLE_CONTENT


def generation(_):
    return ResumeReviewGeneration(summary='검토', section_reviews=[], questions=[
        ReviewQuestion(field_path='projects[0].description', topic='action', question='어떤 행동을 했나요?', reason='행동 부족', priority=1)])


def test_duplicate_request_returns_one_generation():
    db = FakeFirebase()
    calls = []
    def generate(data):
        calls.append(data)
        return generation(data)
    service = ResumeReviewService(Settings(openai_api_key='test'), db, generate)
    request = FirestoreResumeReviewRequest(cohort_id='cohort-1', resume_id='resume-1', request_id='once')
    first = service.review('valid-token', request)
    assert service.review('valid-token', request) == first
    assert len(calls) == 1
    assert first.telemetry['input_tokens'] is None
    with pytest.raises(ReviewConflict):
        service.review('valid-token', request.model_copy(update={'review_focus': '다른 요청'}))


def test_followup_is_bound_to_question_and_version():
    db = FakeFirebase()
    service = ResumeReviewService(Settings(openai_api_key='test'), db, generation)
    first = service.review('valid-token', FirestoreResumeReviewRequest(cohort_id='cohort-1', resume_id='resume-1'))
    q = first.questions[0]
    answer = ConfirmationAnswer(question_id=q.question_id, field_path=q.field_path, question=q.question, answer='캐싱을 적용했습니다.')
    request = FirestoreResumeReviewRequest(cohort_id='cohort-1', resume_id='resume-1', previous_review_id=first.review_id, expected_input_hash=first.input_hash, answers=[answer])
    result = service.review('valid-token', request)
    assert result.confirmed_answers[0].answer == answer.answer
    assert not result.questions
    with pytest.raises(ReviewConflict):
        service.review('valid-token', request.model_copy(update={'expected_input_hash': 'old'}))
    with pytest.raises(ReviewInputError):
        prepare_answers(request.model_copy(update={'answers': [answer.model_copy(update={'question_id': 'fake'})]}), first.model_dump(), first.input_hash, first.item_refs)


def test_followup_prompt_is_limited_to_the_answered_resume_item():
    fields = {
        'projects[0].description': '첫 번째 프로젝트 설명',
        'projects[0].techStack': 'Python',
        'projects[1].description': '두 번째 프로젝트 설명',
        'selfIntroduction.aspiration.body': '지원 동기',
    }
    current = ConfirmationAnswer(
        question_id='q1', field_path='projects[0].description', question='무엇을 했나요?', answer='API를 구현했습니다.',
    )
    prior_other_item = ConfirmationAnswer(
        question_id='q2', field_path='projects[1].description', question='무엇을 했나요?', answer='다른 답변',
    )
    scoped_fields, scoped_answers, focused = focused_followup_context(
        fields, [prior_other_item, current], [current],
    )
    assert focused
    assert set(scoped_fields) == {'projects[0].description', 'projects[0].techStack'}
    assert scoped_answers == [current]
    assert focused_time_context(
        'projects[0] 첫 프로젝트: 2025.01 ~ 2025.02 (이력서 기록값)\n'
        'projects[1] 둘째 프로젝트: 2025.03 ~ 2025.04 (이력서 기록값)',
        [current],
    ) == 'projects[0] 첫 프로젝트: 2025.01 ~ 2025.02 (이력서 기록값)'


def test_legacy_ids_block_answers_and_reordering_changes_version():
    content = deepcopy(SAMPLE_CONTENT)
    del content['projects'][0]['id']
    refs = item_references(content, {'projects[0].description': '내용'})
    assert refs['projects[0].description'].startswith('legacy:')
    original = {'projects': [{'id': 'one'}, {'id': 'two'}]}
    assert digest(original) != digest({'projects': list(reversed(original['projects']))})


def test_same_experience_technology_is_grounded():
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
        field_path='projects[0].description', original_quote='API 개발', reason='기술 연결',
        suggested_revision='Python API 개발', evidence_quotes=['API 개발', '파이썬'])])
    assert not ground_sentences({'projects[0].description': 'API 개발', 'projects[0].techStack': '파이썬'}, [], result)
    assert result.sentence_reviews[0].status == 'improved'
    assert 'projects[0].techStack' in result.sentence_reviews[0].evidence_sources


def test_identical_revision_and_privacy():
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
        field_path='projects[0].description', original_quote='개발했습니다.', reason='정리',
        suggested_revision='개발했습니다.', evidence_quotes=['개발했습니다.'])])
    ground_sentences({'projects[0].description': '개발했습니다.'}, [], result)
    assert result.sentence_reviews[0].status == 'unchanged'
    assert result.sentence_reviews[0].suggested_revision is None
    assert redact('연락 a@example.com 010-1234-5678') == '연락 [연락처 삭제] [연락처 삭제]'


def test_fixed_diagnostics_and_priority_questions():
    result = generation({})
    normalize_diagnostics(result, {'projects[0].description': '설명'}, False, None)
    assert len(result.diagnostics) == 7
    assert all(d.status == 'not_evaluated' for d in result.diagnostics)
    result.questions.append(result.questions[0].model_copy(update={'priority': 3}))
    normalize_questions(result, {'projects[0].description': '설명'}, [], 'r')
    assert len(result.questions) == 1


def test_short_self_introduction_sections_receive_followup_questions():
    result = ResumeReviewGeneration(summary='검토', section_reviews=[])
    fields = {
        'selfIntroduction.intro.body': '데이터를 다루는 일이 좋습니다.',
        'selfIntroduction.motivation.body': 'AI 엔지니어로 성장하고 싶습니다.',
        'selfIntroduction.growth.body': '프로젝트를 통해 배웠습니다.' * 30,
    }

    add_short_self_introduction_questions(result, fields)

    assert [question.field_path for question in result.questions] == [
        'selfIntroduction.intro.body',
        'selfIntroduction.motivation.body',
    ]


def test_general_review_sends_no_job_and_keeps_content_questions():
    seen = []

    def generate(data):
        seen.append(data)
        return ResumeReviewGeneration(
            summary='문장을 검토했습니다.',
            section_reviews=[],
            sentence_reviews=[
                SentenceReview(
                    field_path='coreCompetencies.text',
                    original_quote='Python REST API 개발',
                    suggested_revision='Python REST API를 개발했습니다.',
                    reason='명사형 표현을 서술형으로 정리했습니다.',
                    edit_type='content',
                ),
            ],
            questions=[
                ReviewQuestion(
                    field_path='coreCompetencies.text',
                    topic='other',
                    question='구현한 API의 범위나 검증 방식이 있나요?',
                    reason='일반 첨삭에서도 사실 확인 질문을 반환합니다.',
                ),
            ],
        )

    response = ResumeReviewService(
        Settings(openai_api_key='test'), FakeFirebase(), generate,
    ).review(
        'valid-token',
        FirestoreResumeReviewRequest(
            cohort_id='cohort-1',
            resume_id='resume-1',
            review_mode='general',
        ),
    )

    assert seen[0]['review_mode'].startswith('일반 이력서 첨삭')
    assert response.sentence_reviews[0].suggested_revision == 'Python REST API를 개발했습니다.'
    assert response.questions[0].question == '구현한 API의 범위나 검증 방식이 있나요?'
    assert all(
        diagnostic.criterion not in {'relevance', 'company_fit'} or
        diagnostic.status == 'not_evaluated'
        for diagnostic in response.diagnostics
    )


def test_failed_call_is_not_automatically_rebilled():
    db = FakeFirebase()
    calls = []
    def fail(data):
        calls.append(1)
        raise RuntimeError('model unavailable')
    service = ResumeReviewService(Settings(openai_api_key='test'), db, fail)
    request = FirestoreResumeReviewRequest(cohort_id='cohort-1', resume_id='resume-1', request_id='failed')
    with pytest.raises(RuntimeError):
        service.review('valid-token', request)
    with pytest.raises(ReviewConflict):
        service.review('valid-token', request)
    assert len(calls) == 1


def test_masking_applies_to_model_input_and_saved_fields():
    class PrivateDB(FakeFirebase):
        def get_owned_resume(self, *args):
            data = deepcopy(super().get_owned_resume(*args))
            data['content']['projects'][0]['description'] = '문의 a@example.com 010-1234-5678'
            return data
    seen = []
    def generate(data):
        seen.append(data)
        return generation(data)
    db = PrivateDB()
    response = ResumeReviewService(Settings(openai_api_key='test'), db, generate).review('valid-token',
        FirestoreResumeReviewRequest(cohort_id='cohort-1', resume_id='resume-1', review_focus='b@example.com'))
    assert 'a@example.com' not in seen[0]['resume_text']
    assert 'b@example.com' not in seen[0]['review_focus']
    assert '[연락처 삭제]' in response.input_fields['projects[0].description']


def test_firebase_gateway_denies_inactive_or_foreign_owner():
    from app.firebase_gateway import FirebaseGateway, ResumeAccessError, ResumeNotFoundError
    class Snapshot:
        exists = True
        def __init__(self, data): self.data = data
        def to_dict(self): return self.data
    class Ref:
        def __init__(self, data): self.data = data
        def document(self, _): return self
        def get(self): return Snapshot(self.data)
    class Database:
        user = {'isActive': False, 'cohortId': 'c'}
        def collection(self, _): return Ref(self.user)
    gateway = FirebaseGateway.__new__(FirebaseGateway)
    gateway._db = Database()
    gateway._resume_ref = lambda *args: Ref({'userId': 'another'})
    with pytest.raises(ResumeAccessError):
        gateway.get_owned_resume('c', 'r', 'me')
    gateway._db.user = {'isActive': True, 'cohortId': 'c'}
    with pytest.raises(ResumeNotFoundError):
        gateway.get_owned_resume('c', 'r', 'me')
