from copy import deepcopy
from types import SimpleNamespace

import pytest

from app.resume_apply import ApplyRequest, UndoRequest, build_application, mutate
from app.review_workflow import digest, ReviewConflict, ReviewInputError
from app.firebase_gateway import ResumeAccessError, ResumeNotFoundError

CONTENT = {'projects': [{'id': 'a', 'description': 'API 개발. 테스트 작성.', 'techStack': 'Python'}]}


def review():
    return {'input_hash': digest(CONTENT), 'sentence_reviews': [
        {'field_path': 'projects[0].description', 'original_quote': 'API 개발.', 'suggested_revision': 'Python API 개발.', 'status': 'improved'},
        {'field_path': 'projects[0].description', 'original_quote': '테스트 작성.', 'suggested_revision': '테스트를 작성했습니다.', 'status': 'improved'}]}


def request(**kwargs):
    return ApplyRequest(cohort_id='c', resume_id='r', request_id='apply1', review_id='review1', expected_input_hash=digest(CONTENT), selected_indices=[0, 1], **kwargs)


def test_multiple_edits_preserve_unselected_fields():
    result, fields = build_application(CONTENT, review(), request())
    assert result['projects'][0]['description'] == 'Python API 개발. 테스트를 작성했습니다.'
    assert result['projects'][0]['techStack'] == 'Python'
    assert CONTENT['projects'][0]['description'] == 'API 개발. 테스트 작성.'
    assert fields == ['projects[0].description']


@pytest.mark.parametrize('mode', ['version', 'overlap', 'ambiguous', 'blocked', 'duplicate', 'quality_blocked'])
def test_invalid_edits_rejected(mode):
    data, req = review(), request()
    if mode == 'version': req.expected_input_hash = '0' * 64
    if mode == 'overlap': data['sentence_reviews'][1] = deepcopy(data['sentence_reviews'][0])
    if mode == 'ambiguous': data['sentence_reviews'][0]['original_quote'] = '.'
    if mode == 'blocked': data['sentence_reviews'][0]['status'] = 'needs_confirmation'
    if mode == 'duplicate': req.selected_indices = [0, 0]
    if mode == 'quality_blocked': data['sentence_reviews'][0]['validation_issues'] = ['unsupported_role']
    with pytest.raises((ReviewConflict, ReviewInputError)):
        build_application(CONTENT, data, req)


@pytest.fixture
def gateway(monkeypatch):
    from app import resume_apply
    store = {'users/u': {'isActive': True, 'cohortId': 'c'},
             'resume': {'userId': 'u', 'status': 'writing', 'content': deepcopy(CONTENT)},
             'review': {'userId': 'u', 'response': review()}}
    class Ref:
        def __init__(self, path): self.path = path
        def collection(self, name): return Ref(self.path + '/' + name)
        def document(self, name): return Ref(self.path + '/' + name)
        def get(self, **kwargs): return SimpleNamespace(to_dict=lambda: deepcopy(store.get(self.path)))
    class Tx:
        def __init__(self): self.writes = []
        def create(self, ref, value): self.writes.append((ref.path, value, False))
        def update(self, ref, value): self.writes.append((ref.path, value, True))
    def transactional(fn):
        def run(tx):
            result = fn(tx)
            for path, value, update in tx.writes:
                store[path] = {**(store.get(path, {}) if update else {}), **value}
            return result
        return run
    monkeypatch.setattr(resume_apply.firestore, 'transactional', transactional)
    db = SimpleNamespace(collection=lambda name: Ref(name), transaction=Tx)
    return SimpleNamespace(_db=db, _resume_ref=lambda *args: Ref('resume'), _review_ref=lambda *args: Ref('review'), store=store)


def test_apply_retry_and_undo_are_atomic(gateway):
    first = mutate(gateway, 'u', request())
    assert mutate(gateway, 'u', request()) == first
    undo = UndoRequest(cohort_id='c', resume_id='r', request_id='undo1', application_id='apply1', expected_input_hash=first.input_hash)
    restored = mutate(gateway, 'u', undo, True)
    assert gateway.store['resume']['content'] == CONTENT
    assert mutate(gateway, 'u', undo, True) == restored
    assert gateway.store['resume/aiApplications/apply1']['before'] == CONTENT


@pytest.mark.parametrize('failure', ['approved', 'inactive', 'owner', 'review_owner'])
def test_denied_operations_write_nothing(gateway, failure):
    if failure == 'approved': gateway.store['resume']['status'] = 'approved'
    if failure == 'inactive': gateway.store['users/u']['isActive'] = False
    if failure == 'owner': gateway.store['resume']['userId'] = 'other'
    if failure == 'review_owner': gateway.store['review']['userId'] = 'other'
    before = deepcopy(gateway.store)
    with pytest.raises((ReviewConflict, ResumeAccessError, ResumeNotFoundError)):
        mutate(gateway, 'u', request())
    assert gateway.store == before


def test_undo_does_not_overwrite_later_user_edit(gateway):
    applied = mutate(gateway, 'u', request())
    gateway.store['resume']['content']['projects'][0]['description'] = '사용자 수정'
    with pytest.raises(ReviewConflict):
        mutate(gateway, 'u', UndoRequest(cohort_id='c', resume_id='r', request_id='undo1', application_id='apply1', expected_input_hash=applied.input_hash), True)
    assert gateway.store['resume']['content']['projects'][0]['description'] == '사용자 수정'


def test_api_apply_and_missing_auth(gateway):
    from fastapi.testclient import TestClient
    from app.main import app
    from app.resume_apply import gateway_dependency
    gateway.verify_id_token = lambda token: 'u'
    app.dependency_overrides[gateway_dependency] = lambda: gateway
    try:
        client = TestClient(app)
        assert client.post('/api/v1/resumes/reviews/apply', json=request().model_dump()).status_code == 401
        response = client.post('/api/v1/resumes/reviews/apply', json=request().model_dump(), headers={'Authorization': 'Bearer test'})
        assert response.status_code == 200
        assert response.json()['operation_id'] == 'apply1'
    finally:
        app.dependency_overrides.pop(gateway_dependency, None)
