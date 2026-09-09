"""Offline guardrail regressions; these do not measure live LLM quality."""
import pytest

from app.models import ConfirmationAnswer, ResumeReviewGeneration, SentenceReview
from app.resume_review import ground_sentences, require_answer_reflection


def review(original, replacement, **kwargs):
    item = SentenceReview(field_path='projects[0].description', original_quote=original,
                          suggested_revision=replacement, reason='테스트', **kwargs)
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[item])
    ground_sentences({item.field_path: original}, [], result)
    return result.sentence_reviews[0]


def test_followup_revision_must_reflect_the_newly_confirmed_fact():
    item = SentenceReview(
        field_path='projects[0].description',
        original_quote='서비스를 구현했습니다.',
        suggested_revision='서비스를 안정적으로 구현했습니다.',
        reason='표현 정리',
        evidence_quotes=['서비스를 구현했습니다.'],
        status='improved',
    )
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[item])
    warnings = require_answer_reflection(
        result,
        [ConfirmationAnswer(
            question_id='q1',
            field_path='projects[0].description',
            question='무엇을 구현했나요?',
            answer='Pinecone 검색 결과를 원문 DB와 대조하는 API를 구현했습니다.',
        )],
    )
    assert item.suggested_revision is None
    assert 'answer_not_reflected' in item.validation_issues
    assert warnings


def test_role_answer_keeps_only_the_candidates_confirmed_scope():
    original = '채용공고 매칭과 이력서 첨삭 기능을 구현했습니다.'
    answer = ConfirmationAnswer(
        question_id='q1',
        field_path='projects[0].description',
        question='본인과 팀원의 담당 범위를 구분해 주세요.',
        answer='저는 공고 원문 비교와 확인 질문 기반 첨삭 API를 구현했고, 팀원은 공고 수집을 담당했습니다.',
    )
    item = SentenceReview(
        field_path=answer.field_path,
        original_quote=original,
        suggested_revision='공고 원문 비교와 확인 질문 기반 첨삭 API를 구현했습니다.',
        reason='본인 담당 범위 명확화',
        evidence_quotes=[answer.answer],
        status='improved',
        edit_type='content',
    )
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[item])
    ground_sentences({answer.field_path: original}, [answer], result)
    assert require_answer_reflection(result, [answer]) == []
    assert item.suggested_revision is not None
    assert '팀원' not in item.suggested_revision


@pytest.mark.parametrize('original,replacement,kind', [
    ('개발을 진행 하였습니다.', '개발을 진행했습니다.', 'tone'),
    ('개발 하였습니다.', '개발하였습니다.', 'spelling'),
    ('기능을 만들었어요.', '기능을 만들었습니다.', 'tone'),
    ('오류가 발생됬습니다.', '오류가 발생했습니다.', 'spelling'),
])
def test_language_edits_are_separate_from_content(original, replacement, kind):
    result = review(original, replacement, edit_type=kind)
    assert result.status == 'formatting'
    assert result.suggested_revision == replacement
    assert not result.validation_issues
    assert result.evidence_sources == ['projects[0].description']


@pytest.mark.parametrize('replacement', [None, '개발했습니다.'])
def test_no_edit_does_not_manufacture_question(replacement):
    result = review('개발했습니다.', replacement)
    assert result.status == 'unchanged'
    assert result.edit_type == 'none'
    assert result.confirmation_question is None


@pytest.mark.parametrize('original,replacement,issue', [
    ('개발했습니다.', '   ', 'empty_revision'),
    ('구현하지 못했습니다.', '구현했습니다.', 'negation_changed'),
    ('개발 중입니다.', '개발을 완료했습니다.', 'work_status_changed'),
    ('팀원이 구현했습니다.', '제가 구현했습니다.', 'ownership_changed'),
    ('개발에 참여했습니다.', '개발을 주도했습니다.', 'unsupported_role'),
    ('성능을 개선했습니다.', '성능을 30% 개선했습니다.', 'unsupported_number'),
    ('API 개발', 'Docker API 개발', 'unsupported_term'),
    ('문의 [연락처 삭제]', '문의하세요.', 'redacted_content'),
])
def test_risky_edits_are_withheld(original, replacement, issue):
    result = review(original, replacement)
    assert result.suggested_revision is None
    assert result.status == 'needs_confirmation'
    assert issue in result.validation_issues
    assert result.confirmation_question


def test_other_project_is_not_evidence():
    item = SentenceReview(field_path='projects[0].description', original_quote='API 개발',
                          suggested_revision='Docker API 개발', evidence_quotes=['Docker'], reason='기술 연결')
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[item])
    ground_sentences({'projects[0].description': 'API 개발', 'projects[1].techStack': 'Docker'}, [], result)
    assert result.sentence_reviews[0].suggested_revision is None
    assert 'Docker' not in result.sentence_reviews[0].evidence_quotes


@pytest.mark.parametrize('quotes,text', [
    (['개발', '개발'], '개발'),
    (['API 개발', '개발'], 'API 개발'),
    (['개발'], '개발 후 개발'),
])
def test_duplicate_overlapping_and_ambiguous_locations(quotes, text):
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[
        SentenceReview(field_path='projects[0].description', original_quote=q,
                       suggested_revision=q + '했습니다.', reason='표현', edit_type='tone') for q in quotes])
    warnings = ground_sentences({'projects[0].description': text}, [], result)
    assert warnings
    assert len(result.sentence_reviews) == (0 if text == '개발 후 개발' else 1)


def test_identical_revision_preserves_real_question():
    result = review('성능을 개선했습니다.', '성능을 개선했습니다.', confirmation_question='무엇을 변경했나요?')
    assert result.status == 'needs_confirmation'
    assert result.suggested_revision is None


def test_project_state_preserved_during_tone_change():
    result = review('팀원과 개발 중이에요.', '팀원과 개발 중입니다.', edit_type='tone')
    assert result.status == 'formatting'


def test_existing_numbers_do_not_become_negative_via_formatting():
    result = review('10% 개선', '-10% 개선')
    # Hyphens are no longer stripped to label a semantic change as formatting.
    assert result.status == 'needs_confirmation'
    assert 'quantity_sign_changed' in result.validation_issues


def test_factual_technology_anchors_are_returned_for_a_safe_revision():
    result = review('Python API 개발을 진행했습니다.', 'Python으로 API를 개발했습니다.', edit_type='clarity')
    assert result.suggested_revision == 'Python으로 API를 개발했습니다.'
    assert {'Python', 'api'} <= set(result.fact_anchors)
    assert result.change_rate is not None


def test_removing_a_technology_anchor_requires_confirmation():
    result = review('Python API 개발을 진행했습니다.', '기능을 개발했습니다.', edit_type='clarity')
    assert result.suggested_revision is None
    assert result.status == 'needs_confirmation'
    assert 'missing_fact_anchor' in result.validation_issues


def test_large_safe_rewrite_has_a_change_rate_notice():
    result = review(
        'Python API 개발을 진행했습니다.',
        'Python을 활용해 사용자 요청을 처리하는 API를 구현하고 예외 상황을 점검했습니다.',
        edit_type='content',
    )
    assert result.suggested_revision is not None
    assert result.change_rate is not None and result.change_rate > 0.3
    assert result.change_rate_notice


def test_quality_result_passes_through_review_service():
    from app.config import Settings
    from app.models import FirestoreResumeReviewRequest
    from app.resume_review import ResumeReviewService
    from test_resume_review import FakeFirebase, SAMPLE_CONTENT
    original = SAMPLE_CONTENT['projects'][0]['description']

    def generate(_):
        return ResumeReviewGeneration(summary='검토', section_reviews=[], sentence_reviews=[
            SentenceReview(field_path='projects[0].description', original_quote=original,
                           suggested_revision=None, reason='유지', edit_type='none')])

    db = FakeFirebase()
    result = ResumeReviewService(Settings(openai_api_key='test'), db, generate).review(
        'valid-token', FirestoreResumeReviewRequest(cohort_id='cohort-1', resume_id='resume-1'))
    assert result.sentence_reviews[0].status == 'unchanged'
    assert not result.questions
    assert db.saved['sentence_reviews'][0]['edit_type'] == 'none'
