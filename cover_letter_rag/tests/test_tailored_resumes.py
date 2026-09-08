from app.models import TailoredResumeCreateRequest
from app.tailored_resumes import TailoredResumeService


class Gateway:
    def __init__(self):
        self.items = {}

    def create_tailored_resume(self, cohort_id, resume_id, uid, source):
        key = (cohort_id, resume_id, source['job_id'], source['snapshot_hash'])
        if key not in self.items:
            self.items[key] = {
                'tailored_resume_id': 'tailored-1', 'baseResumeId': resume_id,
                'jobId': source['job_id'], 'companyName': source['company'], 'jobTitle': source['title'],
                'sourceResumeHash': 'resume-hash', 'jobSnapshotHash': source['snapshot_hash'],
                'status': 'draft', 'content': {'projects': [{'description': '원본 경험'}]},
            }
        return self.items[key]

    def list_tailored_resumes(self, cohort_id, resume_id, uid):
        return list(self.items.values())


def test_creates_idempotent_job_specific_resume_draft():
    calls = []
    def load(job_id):
        calls.append(job_id)
        return {'source': {'job_id': job_id, 'company': 'A사', 'title': '백엔드 개발자', 'snapshot_hash': 'job-hash'}}

    service = TailoredResumeService(Gateway(), load)
    request = TailoredResumeCreateRequest(cohort_id='cohort-1', resume_id='resume-1', selected_job_id='job-1')
    first, second = service.create('user-1', request), service.create('user-1', request)

    assert first.tailored_resume_id == second.tailored_resume_id
    assert first.base_resume_id == 'resume-1'
    assert first.company_name == 'A사'
    assert first.content['projects'][0]['description'] == '원본 경험'
    assert calls == ['job-1', 'job-1']


def test_lists_only_saved_tailored_resume_metadata():
    service = TailoredResumeService(Gateway(), lambda job_id: {'source': {'job_id': job_id, 'company': 'A사', 'title': '개발자', 'snapshot_hash': 'job-hash'}})
    service.create('user-1', TailoredResumeCreateRequest(cohort_id='c', resume_id='r', selected_job_id='job'))
    item = service.list('user-1', 'c', 'r')[0]
    assert item.job_id == 'job'
    assert item.status == 'draft'
