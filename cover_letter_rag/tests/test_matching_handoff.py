import sqlite3
from copy import deepcopy

import pytest
from fastapi.testclient import TestClient

from app.config import Settings, get_settings
from app.main import app, get_context_gateway, get_resume_review_service
from app.matching_handoff import load_selected_job, JobStoreUnavailable
from app.models import FirestoreResumeReviewRequest, ResumeReviewGeneration, ReviewQuestion
from app.resume_review import ResumeReviewService
from app.review_workflow import ReviewConflict, ReviewInputError, apply_selected_job_identity_revisions, digest, job_role_title
from test_resume_review import FakeFirebase, SAMPLE_CONTENT


@pytest.fixture
def store(tmp_path):
    path = tmp_path / 'jobs.sqlite'
    with sqlite3.connect(path) as db:
        db.execute('CREATE TABLE jobs (job_id TEXT PRIMARY KEY, status TEXT, description TEXT, company TEXT, title TEXT, deadline TEXT, body_is_image INTEGER, content_hash TEXT, source_url TEXT)')
        db.execute('INSERT INTO jobs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                   ('saramin:1', 'OPEN', 'Python API 개발 경험\n' + '공고 원문 전체 ' * 250,
                    '테스트 회사', '백엔드', None, 0, 'hash1', 'https://example.com/job'))
    return path


def test_reads_full_text_and_does_not_create_missing_store(store, tmp_path):
    assert len(load_selected_job(store, 'saramin:1')['text']) > 1200
    missing = tmp_path / 'missing.sqlite'
    with pytest.raises(JobStoreUnavailable): load_selected_job(missing, 'id')
    assert not missing.exists()
    with pytest.raises(ReviewInputError): load_selected_job(store, "' OR 1=1 --")


@pytest.mark.parametrize('field,value,error', [
    ('status', 'CLOSED', ReviewConflict), ('deadline', '2020-01-01', ReviewConflict),
    ('deadline', '알 수 없음', ReviewInputError), ('description', '', ReviewInputError),
])
def test_unusable_jobs_fail_closed(store, field, value, error):
    with sqlite3.connect(store) as db: db.execute(f'UPDATE jobs SET {field} = ?', (value,))
    with pytest.raises(error): load_selected_job(store, 'saramin:1')


def test_legacy_image_flag_with_text_detail_is_reviewable(store):
    """본문이 충분히 저장된 구 레코드는 이미지 플래그를 보정한다."""
    with sqlite3.connect(store) as db:
        db.execute('UPDATE jobs SET body_is_image = 1')
    assert 'Python API 개발 경험' in load_selected_job(store, 'saramin:1')['text']


def test_image_only_detail_still_fails_closed(store):
    with sqlite3.connect(store) as db:
        db.execute('UPDATE jobs SET description = ?, body_is_image = 1', ('상세요강 자격요건',))
    with pytest.raises(ReviewInputError):
        load_selected_job(store, 'saramin:1')


def test_handoff_auth_versions_and_full_source(store):
    db, calls = FakeFirebase(), []
    def generate(data):
        calls.append(data)
        return ResumeReviewGeneration(summary='검토', section_reviews=[])
    service = ResumeReviewService(Settings(openai_api_key='test', matching_job_store_path=store), db, generate)
    request = FirestoreResumeReviewRequest(cohort_id='cohort-1', resume_id='resume-1', selected_job_id='saramin:1',
        expected_input_hash=digest(SAMPLE_CONTENT), expected_job_hash=load_selected_job(store, 'saramin:1')['source']['snapshot_hash'])
    result = service.review('valid-token', request)
    assert len(calls[0]['job_posting_text']) > 1200
    assert '[선택 공고 식별 정보' in calls[0]['job_posting_text']
    assert '회사명: 테스트 회사' in calls[0]['job_posting_text']
    assert '직무명: 백엔드' in calls[0]['job_posting_text']
    assert result.job_source['job_id'] == 'saramin:1'
    assert db.saved['job_source'] == result.job_source
    assert service.review('valid-token', request) == result
    assert len(calls) == 1
    with pytest.raises(ReviewConflict):
        service.review('valid-token', request.model_copy(update={'expected_input_hash': 'stale'}))
    with pytest.raises(ReviewInputError):
        service.review('valid-token', request.model_copy(update={'job_posting_text': 'client fake'}))
    with sqlite3.connect(store) as connection:
        connection.execute("UPDATE jobs SET description = '수정된 공고'")
    with pytest.raises(ReviewConflict):
        service.review('valid-token', request)
    assert len(calls) == 1


def test_selected_job_identity_replaces_resume_placeholders_without_question():
    generated = ResumeReviewGeneration(
        summary='',
        section_reviews=[],
        questions=[ReviewQuestion(
            field_path='selfIntroduction.aspiration.body',
            topic='other',
            question='지원 회사명과 직무명을 실제 값으로 확정해 주세요.',
            reason='자리표시자',
        )],
    )
    fields = {
        'selfIntroduction.aspiration.body': '[회사명]의 [직무명]으로 성장하고 싶습니다.',
    }
    apply_selected_job_identity_revisions(
        generated,
        fields,
        {'company': '테스트 회사', 'title': '백엔드 개발자'},
    )
    assert generated.questions == []
    assert generated.sentence_reviews[0].suggested_revision == '테스트 회사의 백엔드 개발자로 성장하고 싶습니다.'


def test_posting_title_is_reduced_to_resume_role_title():
    assert job_role_title(
        '(주)토마토에이아이',
        '(주)토마토에이아이와 함께할 AI엔지니어를 찾고 있어요',
    ) == 'AI 엔지니어'
    assert job_role_title(
        '(주)디더블유아이',
        '(주)디더블유아이에서 AI 분석 서비스 개발자 모십니다',
    ) == 'AI 분석 서비스 개발자'


def test_identity_placeholder_uses_role_title_not_full_posting_title():
    generated = ResumeReviewGeneration(summary='', section_reviews=[])
    apply_selected_job_identity_revisions(
        generated,
        {'selfIntroduction.aspiration.body': '[회사명]의 [직무명]으로 성장하고 싶습니다.'},
        {
            'company': '(주)토마토에이아이',
            'title': '(주)토마토에이아이와 함께할 AI엔지니어를 찾고 있어요',
        },
    )
    assert generated.sentence_reviews[0].suggested_revision == (
        '(주)토마토에이아이의 AI 엔지니어로 성장하고 싶습니다.'
    )


def test_job_subject_placeholder_uses_natural_role_particle():
    generated = ResumeReviewGeneration(summary='', section_reviews=[])
    apply_selected_job_identity_revisions(
        generated,
        {'selfIntroduction.motivation.body': '[회사명]의 [직무명]은 제가 학습해 온 방향과 맞닿아 있습니다.'},
        {'company': '(주)토마토에이아이', 'title': '(주)토마토에이아이와 함께할 AI엔지니어를 찾고 있어요'},
    )
    assert generated.sentence_reviews[0].suggested_revision == (
        '(주)토마토에이아이의 AI 엔지니어 직무는 제가 학습해 온 방향과 맞닿아 있습니다.'
    )


def test_previously_applied_full_posting_title_is_repaired():
    generated = ResumeReviewGeneration(summary='', section_reviews=[])
    apply_selected_job_identity_revisions(
        generated,
        {
            'selfIntroduction.aspiration.body': (
                '(주)토마토에이아이의 (주)토마토에이아이와 함께할 '
                'AI엔지니어를 찾고 있어요로 성장하고 싶습니다.'
            ),
        },
        {
            'company': '(주)토마토에이아이',
            'title': '(주)토마토에이아이와 함께할 AI엔지니어를 찾고 있어요',
        },
    )
    assert generated.sentence_reviews[0].suggested_revision == (
        '(주)토마토에이아이의 AI 엔지니어로 성장하고 싶습니다.'
    )


def test_context_requires_owner_and_disables_cache(store):
    app.dependency_overrides[get_context_gateway] = lambda: FakeFirebase()
    app.dependency_overrides[get_settings] = lambda: Settings(matching_job_store_path=store)
    client = TestClient(app)
    params = {'cohort_id': 'cohort-1', 'resume_id': 'resume-1'}
    try:
        assert client.get('/api/v1/resumes/review-context', params=params).status_code == 401
        ok = client.get('/api/v1/resumes/review-context', params=params, headers={'Authorization': 'Bearer valid-token'})
        assert ok.status_code == 200
        assert ok.headers['cache-control'] == 'no-store'
        assert ok.json()['input_hash'] == digest(SAMPLE_CONTENT)
        selected = client.get('/api/v1/resumes/review-context', params={**params, 'job_id': 'saramin:1'}, headers={'Authorization': 'Bearer valid-token'})
        assert selected.status_code == 200
        assert selected.json()['job_source']['job_id'] == 'saramin:1'
        foreign = client.get('/api/v1/resumes/review-context', params={**params, 'resume_id': 'another'}, headers={'Authorization': 'Bearer valid-token'})
        assert foreign.status_code == 404
    finally: app.dependency_overrides.clear()


def test_integrated_routes_preserve_matching_contract():
    from app.integrated import app as integrated
    client = TestClient(integrated)
    matching = client.get('/openapi.json').json()
    review = client.get('/resume-review/openapi.json').json()
    assert '/api/v1/jobs/recommend' in matching['paths']
    assert 'RecommendRequest' in matching['components']['schemas']
    assert '/api/v1/resumes/reviews' in review['paths']
    assert '/api/v1/resumes/reviews/apply' in review['paths']
    assert client.post('/api/v1/jobs/recommend', json={}).status_code == 422
