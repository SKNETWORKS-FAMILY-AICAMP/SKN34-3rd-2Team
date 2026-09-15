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


@pytest.mark.parametrize('original,replacement,edit_type', [
    # 2026-09-15 자세한 이력서 목업에서 나온 수정안. 뜻이 같은 단어나 조사만 바꿔 뜻이 흔들린다.
    ('실제로 얼마나 빠르게 동작하는지 재 보는 습관이 있습니다.', '실제로 얼마나 빠르게 동작하는지 다시 보는 습관이 있습니다.', 'tone'),
    ('알림 서비스로 참가해 백엔드를 맡았습니다.', '알림 서비스에 참가해 백엔드를 맡았습니다.', 'spelling'),
    ('동기화 로직에는 단위 테스트 35개를 붙였습니다.', '동기화 로직에는 단위 테스트 35개를 추가했습니다.', 'clarity'),
    ('조건별로 쪼개서 원인을 찾고 재현한 뒤 고칩니다.', '조건별로 쪼개 원인을 찾고 재현한 뒤 고쳤습니다.', 'tone'),
])
def test_minor_rewording_is_not_offered(original, replacement, edit_type):
    result = review(original, replacement, edit_type=edit_type)
    assert result.suggested_revision is None
    assert result.status == 'unchanged'
    assert not result.confirmation_question
    assert not result.validation_issues


def test_purpose_negation_rewording_is_kept_with_a_notice():
    # 목적을 말하는 부정 표현("재발하지 않도록")을 뜻이 같은 말로 바꾸면 막지 않고 안내만 붙인다.
    revision = '크래시 재발을 막으려고 원인을 정리한 문서를 팀에 공유했습니다.'
    result = review('크래시가 재발하지 않도록 원인 정리 문서를 팀에 공유 하였습니다.', revision, edit_type='clarity')
    assert result.suggested_revision == revision
    assert not result.validation_issues
    assert "'재발하지 않도록'" in result.meaning_notice


@pytest.mark.parametrize('original,replacement', [
    ('저는 백엔드 개발자 입니다.', '저는 백엔드 개발자입니다.'),                       # 띄어쓰기
    ('팀원과 개발 중이에요.', '팀원과 개발 중입니다.'),                               # 합니다체
    ('사내 기술 개선 우수상 수상.', '사내 기술 개선 우수상을 수상했습니다.'),              # 명사형 문장 잇기
    ('API 개발을 진행 하였습니다.', 'API 개발을 진행했습니다.'),                        # 군더더기
    ('프론트엔드 역활을 맡았습니다.', '프론트엔드 역할을 맡았습니다.'),                   # 맞춤법
    ('구조를 다시 짜고 문의가 줄었고 테스트도 붙였습니다.', '구조를 다시 짰습니다. 문의가 줄었고 테스트도 붙였습니다.'),  # 문장 나누기
])
def test_small_but_useful_surface_edits_are_kept(original, replacement):
    result = review(original, replacement, edit_type='clarity')
    assert result.suggested_revision == replacement
    assert result.status == 'formatting'


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


def test_rewording_units_and_joined_names_is_not_a_fact_change():
    # "1.2s→0.5s"를 "1.2초에서 0.5초로", "ECS+GitHub"를 "ECS와 GitHub"로 풀어 쓰는 것은 사실 변경이 아니다.
    from app.resume_review import ground_sentences
    cases = [
        ('N+1 제거와 커버링 인덱스, Redis 캐시 도입으로 주문 목록 API p95 1.2s→0.5s.',
         'N+1 제거와 커버링 인덱스, Redis 캐시를 도입해 주문 목록 API p95를 1.2초에서 0.5초로 줄였습니다.'),
        ('EC2 수동 배포를 ECS+GitHub Actions로 전환, 배포 시간 40분→8분.',
         'EC2 수동 배포를 ECS와 GitHub Actions로 전환해 배포 시간을 40분에서 8분으로 줄였습니다.'),
    ]
    for original, revision in cases:
        result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
            field_path='projects[0].description', original_quote=original, reason='문장으로 정리',
            suggested_revision=revision, edit_type='clarity')])
        ground_sentences({'projects[0].description': original}, [], result)
        assert result.sentence_reviews[0].validation_issues == [], original
        assert result.sentence_reviews[0].suggested_revision == revision


def test_changed_quantity_or_unit_is_still_held():
    from app.resume_review import ground_sentences
    original = '조회 시간을 1.2초에서 0.5초로 줄였습니다.'
    for revision in ('조회 시간을 1.2분에서 0.5분으로 줄였습니다.', '조회 시간을 1.2초에서 0.3초로 줄였습니다.'):
        result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
            field_path='projects[0].description', original_quote=original, reason='정리',
            suggested_revision=revision, edit_type='clarity')])
        ground_sentences({'projects[0].description': original}, [], result)
        assert 'unsupported_number' in result.sentence_reviews[0].validation_issues, revision


def _grounded(field_path, original, revision, answers, edit_type='content', job_text=''):
    from app.models import ConfirmationAnswer
    from app.resume_review import ground_sentences
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
        field_path=field_path, original_quote=original, reason='답변 반영', suggested_revision=revision,
        edit_type=edit_type)])
    confirmed = [ConfirmationAnswer(question_id=f'q{i}', field_path=field_path, question='질문', answer=a)
                 for i, a in enumerate(answers)]
    ground_sentences({field_path: original}, confirmed, result, job_text)
    return result.sentence_reviews[0]


def test_answer_that_clarifies_own_scope_can_replace_team_wording():
    item = _grounded(
        'selfIntroduction.challenge.body',
        '챗봇이 엉뚱한 답을 하는 문제가 있었는데, 팀원들과 함께 여러 방법을 시도해서 개선했습니다.',
        '챗봇이 엉뚱한 답을 하는 문제가 있어, 제가 맡은 PDF 파싱과 청킹 방식을 조항 단위로 바꿔 개선했습니다.',
        ['사내 규정 챗봇에서 PDF 파싱, 청킹, 검색을 제가 맡았고 청크를 조항 단위로 바꿨습니다. 화면은 팀원이 만들었습니다.'],
    )
    assert 'ownership_changed' not in item.validation_issues
    assert item.suggested_revision


def test_team_wording_cannot_disappear_without_an_answer():
    item = _grounded(
        'projects[0].description', '팀원들과 함께 로그인 기능을 구현했습니다.', '로그인 기능을 구현했습니다.', [],
        edit_type='clarity')
    assert 'ownership_changed' in item.validation_issues


def test_motivation_may_name_posting_work_as_company_context():
    item = _grounded(
        'selfIntroduction.motivation.body',
        '평소 생성형 AI 기술에 관심이 많았고 귀사에서 성장하고 싶어 지원했습니다.',
        '스텔라에이아이의 주요 업무인 RAG 기반 문서 질의응답은 제 경험과 맞닿아 있습니다. 사내 규정 챗봇에서 청크를 조항 단위로 바꿔 정답률을 62%에서 81%로 높인 경험으로 검색 품질 개선에 기여하고 싶습니다.',
        ['사내 규정 챗봇에서 청크를 조항 단위로 바꾸고 질문 50개로 채점해 정답률을 62%에서 81%로 높였습니다.'],
        job_text='RAG 기반 기업용 문서 질의응답 서비스 개발',
    )
    assert item.validation_issues == []


def test_answer_rebuild_must_keep_facts_of_untouched_sentences():
    # 답변으로 문단을 새로 쓸 때 답과 무관한 문장의 사실(FastAPI·Docker)이 사라지면 안 된다(2026-09-15 새 케이스).
    original = ('부품 표면 사진 4천 장으로 불량 여부를 분류했습니다. 불량 사진이 8%뿐이라 증강과 클래스 가중치로 보완해 '
                'F1을 0.78에서 0.91로 높였습니다. 학습한 모델은 FastAPI로 감싸 Docker 이미지로 만들었습니다.')
    answer = ConfirmationAnswer(question_id='q', field_path='projects[0].description', question='전처리 방법은?',
                                answer='불량 이미지가 8%인 클래스 불균형을 확인하고 불량 이미지 증강과 클래스 가중치를 적용했습니다.')
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
        field_path='projects[0].description', original_quote=original, edit_type='content', reason='답변 반영',
        suggested_revision='부품 표면 사진 4천 장 중 불량 이미지가 8%인 클래스 불균형을 확인하고 증강과 클래스 가중치를 적용해 F1을 0.78에서 0.91로 높였습니다.',
        evidence_quotes=[answer.answer])])
    ground_sentences({'projects[0].description': original}, [answer], result)
    assert 'missing_fact_anchor' in result.sentence_reviews[0].validation_issues
    assert result.sentence_reviews[0].suggested_revision is None


def test_single_sentence_original_may_be_rebuilt_from_answer():
    original = '생성형 AI에 관심이 많아 지원했습니다.'
    answer = ConfirmationAnswer(question_id='q', field_path='selfIntroduction.motivation.body', question='어떤 업무?',
                                answer='사내 규정 챗봇에서 PDF 파싱과 검색을 맡았습니다.')
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
        field_path='selfIntroduction.motivation.body', original_quote=original, edit_type='content', reason='답변 반영',
        suggested_revision='사내 규정 챗봇에서 PDF 파싱과 검색을 맡은 경험을 바탕으로 지원했습니다.',
        evidence_quotes=[answer.answer])])
    ground_sentences({'selfIntroduction.motivation.body': original}, [answer], result)
    assert result.sentence_reviews[0].validation_issues == []


def test_nominal_fields_reject_sentence_rewrites():
    answer = ConfirmationAnswer(question_id='q', field_path='techStack[4].name', question='배포 자동화?',
                                answer='Fastlane으로 TestFlight 배포를 자동화해 40분에서 10분으로 줄였습니다.')
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
        field_path='techStack[4].name', original_quote='Fastlane', edit_type='content', reason='답변 반영',
        suggested_revision='Fastlane — 오프라인 다운로드 프로젝트 TestFlight 배포 자동화, 배포 작업 시간 40분 → 10분',
        evidence_quotes=[answer.answer])])
    ground_sentences({'techStack[4].name': 'Fastlane'}, [answer], result)
    assert 'nominal_field_rewritten' in result.sentence_reviews[0].validation_issues


def test_tech_stack_name_cannot_gain_another_technology():
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
        field_path='techStack[3].name', original_quote='Jest', edit_type='content', reason='답변 반영',
        suggested_revision='Jest, supertest', evidence_quotes=['Jest와 supertest로 API 테스트를 작성했습니다.'])])
    answer = ConfirmationAnswer(question_id='q', field_path='techStack[3].name', question='테스트?',
                                answer='Jest와 supertest로 API 테스트를 작성했습니다.')
    ground_sentences({'techStack[3].name': 'Jest'}, [answer], result)
    assert 'nominal_field_rewritten' in result.sentence_reviews[0].validation_issues


def test_negation_shift_is_withheld_but_not_asked():
    # 부정 표현 뒤집기는 보류하되 묻지 않는다. 예전 문구는 항목도 표현도 없어 답할 수 없었고 같은 칸을 3턴 연속 물었다.
    result = review('구현하지 못했습니다.', '구현했습니다.')
    assert result.suggested_revision is None and 'negation_changed' in result.validation_issues
    assert result.confirmation_question is None and result.status == 'unchanged'


def test_negation_shift_in_content_edit_drops_silently_without_question():
    original = '오류가 나지 않도록 입력값을 검증했습니다.'
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
        field_path='projects[0].description', original_quote=original, edit_type='content', reason='정리',
        suggested_revision='오류가 나도록 입력값을 검증했습니다.', evidence_quotes=[original])])
    ground_sentences({'projects[0].description': original}, [], result)
    item = result.sentence_reviews[0]
    assert item.suggested_revision is None and item.confirmation_question is None


def test_nominal_field_rewrite_is_withheld_without_a_question():
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
        field_path='techStack[4].name', original_quote='Fastlane', edit_type='content', reason='답변 반영',
        suggested_revision='Fastlane으로 TestFlight 배포를 자동화했습니다.', evidence_quotes=['Fastlane'])])
    ground_sentences({'techStack[4].name': 'Fastlane'}, [], result)
    item = result.sentence_reviews[0]
    assert item.suggested_revision is None and item.confirmation_question is None


def test_sentence_copied_from_another_field_is_withheld_but_similar_one_is_only_flagged():
    from app.resume_review import _cross_field_overlap
    fields = {
        'projects[0].description': '목록 화면 렌더링을 메모이제이션으로 줄여 첫 화면 시간을 3.2초에서 1.1초로 단축했습니다.',
        'selfIntroduction.intro.body': '사용자가 멈칫하는 순간을 관찰하는 습관이 있습니다.',
    }
    original = fields['selfIntroduction.intro.body']
    copied = original + ' 목록 화면 렌더링을 메모이제이션으로 줄여 첫 화면 시간을 3.2초에서 1.1초로 단축했습니다.'
    verbatim, notice = _cross_field_overlap('selfIntroduction.intro.body', original, copied, fields)
    assert verbatim and notice is None
    similar = original + ' 대시보드 목록 렌더링을 메모이제이션으로 줄여 첫 화면 시간을 3.2초에서 1.1초로 개선한 경험이 있습니다.'
    verbatim, notice = _cross_field_overlap('selfIntroduction.intro.body', original, similar, fields)
    assert not verbatim and notice and '프로젝트' in notice
    different = original + ' 좁은 화면과 느린 네트워크에서 직접 눌러 보며 확인합니다.'
    assert _cross_field_overlap('selfIntroduction.intro.body', original, different, fields) == (False, None)


def test_wish_negation_dropped_by_answer_rewrite_keeps_the_answer_facts():
    # 2026-09-15 새 케이스 Node 자기소개: 답변 사실을 넣어 다시 쓰다 "불편을 겪지 않는"이 빠져 수정안이 세 번 모두 버려졌다.
    path = 'selfIntroduction.intro.body'
    original = '저는 백엔드 개발자입니다. 사용자가 불편을 겪지 않는 API를 만들고 싶습니다.'
    revision = ('저는 백엔드 개발자입니다. 여행 일정 공유 앱에서 인덱스를 추가해 일정 목록 조회 API 응답 시간을 '
                '1.8초에서 0.4초로 줄였습니다.')
    answer = ConfirmationAnswer(question_id='q1', field_path=path, question='직접 한 일을 알려 주세요.',
                                answer='여행 일정 공유 앱에서 인덱스를 추가해 일정 목록 조회 응답 시간을 1.8초에서 0.4초로 줄였습니다.')
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
        field_path=path, original_quote=original, suggested_revision=revision, reason='답변 반영', edit_type='content',
        evidence_quotes=[original])])
    ground_sentences({path: original}, [answer], result)
    item = result.sentence_reviews[0]
    assert item.suggested_revision == revision and not item.validation_issues
    assert "'겪지 않는'" in item.meaning_notice


@pytest.mark.parametrize('original, revision', [
    ('로그인 화면은 구현하지 못했습니다.', '로그인 화면을 구현했습니다.'),        # 한 일을 뒤집음
    ('배포 경험은 없습니다.', '배포를 맡았습니다.'),                               # 경험 없음을 뒤집음
    ('오류가 나지 않도록 입력값을 검증했습니다.', '오류가 나도록 입력값을 검증했습니다.'),  # 같은 말을 긍정으로
])
def test_work_negation_or_inversion_is_still_withheld(original, revision):
    result = review(original, revision, edit_type='content')
    assert result.suggested_revision is None and 'negation_changed' in result.validation_issues
    assert result.meaning_notice is None


def test_self_intro_repeating_several_facts_of_a_project_gets_a_notice():
    from app.resume_review import _repeated_facts_notice
    fields = {
        'projects[0].name': '매물 검색 서비스',
        'projects[0].description': '목록을 처음 열 때 매물 500건을 한 번에 받던 것을 20건씩 나눠 받도록 바꿔 첫 화면 표시 시간을 '
                                   '3.2초에서 1.1초로 줄였습니다.',
        'selfIntroduction.intro.body': '매물 검색 서비스에서 첫 화면 표시 시간을 3.2초에서 1.1초로 줄였습니다.',
    }
    path, original = 'selfIntroduction.intro.body', fields['selfIntroduction.intro.body']
    repeated = ('매물 검색 서비스에서 500건을 한 번에 받던 목록을 20건씩 불러오는 무한 스크롤로 개선해 첫 화면 표시 시간을 '
                '3.2초에서 1.1초로 줄였습니다.')
    notice = _repeated_facts_notice(path, original, repeated, fields)
    assert notice and "'매물 검색 서비스' 프로젝트 칸" in notice and '500건·20건' in notice
    # 이미 그 칸에 있던 수치, 전후 한 쌍만 가리키는 구절, 경험 칸이 아닌 칸은 알리지 않는다.
    assert _repeated_facts_notice(path, original, original + ' 사용자 입장에서 생각합니다.', fields) is None
    fields2 = {**fields, 'selfIntroduction.intro.body': '사용자 입장에서 생각합니다.'}
    assert _repeated_facts_notice(path, fields2[path], '첫 화면 표시 시간을 3.2초에서 1.1초로 줄였습니다.', fields2) is None
    assert _repeated_facts_notice('projects[1].description', '', repeated, fields) is None


def test_adverbs_containing_negation_syllables_are_not_negation():
    # "끊임없이"의 "없"을 부정으로 잡아 "원문의 '싶습니다. 끊임없이' 표현이 빠졌어요"가 붙었다(2026-09-15 새 케이스 v16m).
    from app.resume_review import _meaning_risks, _negation_notice
    original = '입사 후 꼭 필요한 개발자가 되고 싶습니다. 끊임없이 배우고 성장하겠습니다.'
    revision = '입사 후 먼저 매물 검색 화면의 로딩 속도를 점검하며 팀에 필요한 개발자가 되겠습니다. 꾸준히 배우며 성장하겠습니다.'
    assert _negation_notice(original, revision) is None
    assert 'negation_changed' not in _meaning_risks(original, revision)
    assert _negation_notice('틀림없이 동작하도록 테스트했습니다.', '확실히 동작하도록 테스트했습니다.') is None
    # 진짜 부정은 그대로 본다.
    assert 'negation_changed' in _meaning_risks('끊임없이 시도했지만 배포는 못했습니다.', '끊임없이 시도해 배포했습니다.')


def test_dropping_a_number_from_the_original_is_a_missing_fact():
    # 답을 넣어 다시 쓰다 "매물 500건을 한 번에 받던 것을"의 500건이 빠졌는데 통과했다(2026-09-15 새 케이스 v16m).
    path = 'projects[0].description'
    original = ('원룸 매물을 조건으로 검색하는 웹 서비스입니다. 저는 검색 필터와 매물 목록 화면을 맡았습니다. 목록을 처음 열 때 '
                '매물 500건을 한 번에 받던 것을 20건씩 나눠 받고 스크롤에 맞춰 이어 받도록 바꿔 첫 화면 표시 시간을 3.2초에서 1.1초로 줄였습니다.')
    answer = ConfirmationAnswer(question_id='q1', field_path=path, question='REST API로 연동했나요?',
                                answer='React Query로 백엔드 REST API의 매물 조회와 필터 조건 조회를 연동했습니다.')

    def ground(revision):
        result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
            field_path=path, original_quote=original, suggested_revision=revision, reason='답변 반영', edit_type='content',
            evidence_quotes=[original])])
        ground_sentences({path: original}, [answer], result)
        return result.sentence_reviews[0]

    dropped = ground('원룸 매물을 조건으로 검색하는 웹 서비스로, 검색 필터와 매물 목록 화면을 맡았습니다. React Query로 백엔드 REST API의 '
                     '매물 조회와 필터 조건 조회를 연동하고, 매물 목록을 20건씩 나눠 받는 무한 스크롤 방식으로 첫 화면 표시 시간을 3.2초에서 1.1초로 줄였습니다.')
    assert dropped.suggested_revision is None and 'missing_fact_anchor' in dropped.validation_issues
    kept = ground('원룸 매물을 조건으로 검색하는 웹 서비스로, 검색 필터와 매물 목록 화면을 맡았습니다. React Query로 백엔드 REST API의 '
                  '매물 조회와 필터 조건 조회를 연동했습니다. 매물 500건을 한 번에 받던 목록을 20건씩 나눠 받도록 바꿔 첫 화면 표시 시간을 '
                  '3.2s에서 1.1s로 줄였습니다.')
    assert kept.suggested_revision and not kept.validation_issues


def test_experience_field_is_not_flagged_for_resembling_self_introduction():
    # 경험 칸은 사례의 원래 자리다. 자기소개서가 같은 사례를 쓰고 있어도 프로젝트 설명 수정안에 안내를 붙이지 않는다(v16m).
    from app.resume_review import _cross_field_overlap
    fields = {
        'projects[0].description': '불량 분류 모델을 FastAPI로 감싸 Docker 이미지로 만들었습니다.',
        'selfIntroduction.challenge.body': '캡스톤에서 불량 분류 모델을 FastAPI로 감싸 Docker 이미지로 배포했습니다.',
    }
    revision = '캡스톤에서 불량 분류 모델을 FastAPI로 감싸 Docker 이미지로 배포했습니다.'
    assert _cross_field_overlap('projects[0].description', fields['projects[0].description'], revision, fields) == (False, None)
    verbatim, _ = _cross_field_overlap('selfIntroduction.intro.body', '', fields['projects[0].description'], fields)
    assert verbatim, '자기소개서 쪽은 그대로 본다'


def test_answer_restating_the_original_cannot_replace_several_sentences_and_drop_numbers():
    # 사용자가 원문 내용을 되풀이해 답했고, 모델이 원문 두 문장(상황 + 숫자 결과)을 그 답 한 문장으로 바꿨다. "답변 문장을
    # 그대로 옮긴 수정안" 예외로 사실 검사를 건너뛰어 숫자 결과와 상황 문장이 사라졌다(2026-09-15 한 번도 안 본 케이스).
    from app.resume_review import _merge_original_with_confirmed_answer
    path = 'projects[0].description'
    original = '주문 조회 화면이 느리다는 고객 문의가 많았습니다. 인덱스를 추가해 주문 조회 시간을 2.4초에서 0.6초로 줄였습니다.'
    answer_text = '주문 조회 API에 인덱스를 설계하고 적용해 주문 조회 화면이 느린 문제를 줄이는 업무를 맡았습니다.'
    answer = ConfirmationAnswer(question_id='q1', field_path=path, question='인덱스를 어떻게 적용했나요?', answer=answer_text)
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
        field_path=path, original_quote=original, suggested_revision=answer_text, reason='답변 반영', edit_type='content',
        evidence_quotes=[answer_text])])
    ground_sentences({path: original}, [answer], result)
    item = result.sentence_reviews[0]
    assert item.suggested_revision is None and 'missing_fact_anchor' in item.validation_issues
    assert item.confirmation_question is None, '이미 답한 사용자에게 뜻 모를 확인 질문을 붙이지 않는다'

    # 답을 원문에 합치는 대체 수정안도 원문의 숫자 결과 문장을 남긴다.
    merged = _merge_original_with_confirmed_answer(original, answer_text)
    assert '2.4초에서 0.6초로' in merged and answer_text in merged


def test_single_sentence_answer_restatement_is_still_allowed():
    # 한 문장짜리 원문을 답변 문장으로 바꾸는 건 그대로 허용한다. 원문 영단어를 모두 되풀이할 필요는 없다.
    path = 'projects[0].description'
    original = 'REST API 연동 담당.'
    answer_text = 'React Query로 매물 조회와 필터 조건 조회를 백엔드와 연동했습니다.'
    answer = ConfirmationAnswer(question_id='q1', field_path=path, question='무엇을 연동했나요?', answer=answer_text)
    result = ResumeReviewGeneration(summary='', section_reviews=[], sentence_reviews=[SentenceReview(
        field_path=path, original_quote=original, suggested_revision=answer_text, reason='답변 반영', edit_type='content',
        evidence_quotes=[answer_text])])
    ground_sentences({path: original}, [answer], result)
    assert result.sentence_reviews[0].suggested_revision == answer_text
