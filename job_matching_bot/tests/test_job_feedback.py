"""공고 기준 이력서 피드백 — 지어낸 인용을 걸러내는지.

핵심 약속: **공고가 요구하지 않은 것을 요구한다고 말하지 않는다.** 공고 인용이 원문에
없으면 그 항목을 통째로 버린다. 이력서 인용만 틀렸으면 "확인 안 됨"으로 낮춘다 —
요구 자체는 사실이기 때문이다.
"""

from __future__ import annotations

import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from job_matching_bot.api import schemas
from job_matching_bot.api.service import (
    FeedbackService,
    JobNotFound,
    JobTextUnavailable,
    _verify_points,
)
from job_matching_bot.ingestion.mock_source import mock_jobs
from job_matching_bot.ingestion.sqlite_store import SqliteJobStore

JOB_TEXT = """주요업무
- FastAPI 기반 추천 API를 설계하고 운영합니다

자격요건
- Python 백엔드 개발 경험
- 주도적으로 문제를 정의하고 해결하는 분

우대사항
- Docker 배포 경험
"""

RESUME_TEXT = """[프로젝트 경험]
- 추천 서비스 / 백엔드 개발
  FastAPI로 추천 API를 개발하고 응답 속도를 개선했습니다.
"""


def _point(**over) -> schemas.FeedbackPoint:
    base = dict(
        kind="요구역량",
        topic="Python 백엔드 개발",
        job_quote="Python 백엔드 개발 경험",
        status="드러남",
        resume_quote="FastAPI로 추천 API를 개발하고",
        advice="지금처럼 프로젝트에 도구 이름과 함께 적어 두면 좋습니다.",
    )
    return schemas.FeedbackPoint(**{**base, **over})


class VerifyPointsTest(unittest.TestCase):
    def test_keeps_a_point_whose_both_quotes_exist(self):
        kept, warnings = _verify_points([_point()], JOB_TEXT, RESUME_TEXT)
        self.assertEqual([], warnings)
        self.assertEqual("드러남", kept[0].status)
        self.assertEqual("FastAPI로 추천 API를 개발하고", kept[0].resume_quote)

    def test_drops_a_point_whose_job_quote_is_invented(self):
        # 공고가 요구하지 않은 것을 요구한다고 말하는 항목은 남길 수 없다.
        kept, warnings = _verify_points(
            [_point(job_quote="Kubernetes 운영 경험 필수")], JOB_TEXT, RESUME_TEXT
        )
        self.assertEqual([], kept)
        self.assertIn("공고에 없는 인용", warnings[0])

    def test_downgrades_when_only_the_resume_quote_is_invented(self):
        # 요구는 사실이므로 항목은 남기되, 이력서에서 확인됐다고 말하지 않는다.
        kept, warnings = _verify_points(
            [_point(resume_quote="Kafka로 이벤트 처리를 했습니다")], JOB_TEXT, RESUME_TEXT
        )
        self.assertEqual(1, len(kept))
        self.assertEqual("확인 안 됨", kept[0].status)
        self.assertEqual("", kept[0].resume_quote)
        self.assertIn("이력서에 없는 인용", warnings[0])

    def test_unconfirmed_point_never_carries_a_resume_quote(self):
        kept, _ = _verify_points(
            [_point(status="확인 안 됨", resume_quote="FastAPI로 추천 API를 개발하고")],
            JOB_TEXT,
            RESUME_TEXT,
        )
        self.assertEqual("", kept[0].resume_quote)

    def test_whitespace_differences_are_ignored(self):
        kept, warnings = _verify_points(
            [_point(job_quote="Python  백엔드 개발 경험")], JOB_TEXT, RESUME_TEXT
        )
        self.assertEqual([], warnings)
        self.assertEqual(1, len(kept))


class FeedbackServiceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "store.sqlite"
        base = mock_jobs()[0]
        self.job = replace(
            base,
            job_id="MOCK-1",
            source_job_id="MOCK-1",
            description=JOB_TEXT,
            company="테스트컴퍼니",
            title="백엔드 개발자",
        )
        with SqliteJobStore(self.path) as store:
            store.upsert([self.job], source="MOCK")

    def tearDown(self):
        self.temp.cleanup()

    def _service(self, out: schemas.JobFeedbackOut) -> FeedbackService:
        return FeedbackService(generator=lambda values: out, store_path=self.path)

    def _request(self) -> schemas.JobFeedbackRequest:
        return schemas.JobFeedbackRequest(job_id="MOCK-1", resume_text=RESUME_TEXT)

    def test_reads_the_full_posting_from_the_store(self):
        seen = {}

        def generator(values):
            seen.update(values)
            return schemas.JobFeedbackOut(wanted="주도적인 백엔드 개발자", points=[_point()])

        service = FeedbackService(generator=generator, store_path=self.path)
        response = service.feedback(self._request())

        # 앱이 보낸 발췌가 아니라 저장소의 본문 전체로 대조한다.
        self.assertEqual(JOB_TEXT, seen["job_text"])
        self.assertEqual("테스트컴퍼니", seen["company"])
        self.assertEqual("테스트컴퍼니", response.company)
        self.assertEqual("주도적인 백엔드 개발자", response.wanted)
        self.assertEqual(1, len(response.points))
        self.assertEqual([], response.warnings)

    def test_invented_quotes_do_not_reach_the_response(self):
        out = schemas.JobFeedbackOut(
            wanted="x", points=[_point(job_quote="Kubernetes 운영 경험 필수")]
        )
        response = self._service(out).feedback(self._request())
        self.assertEqual([], response.points)
        self.assertEqual(1, len(response.warnings))

    def test_closed_job_is_answered_with_a_warning(self):
        with SqliteJobStore(self.path) as store:
            store.conn.execute("UPDATE jobs SET status = 'EXPIRED' WHERE job_id = 'MOCK-1'")
            store.conn.commit()
        out = schemas.JobFeedbackOut(wanted="x", points=[_point()])
        response = self._service(out).feedback(self._request())
        self.assertTrue(any("진행 중이 아닙니다" in w for w in response.warnings))

    def test_image_only_posting_is_refused(self):
        with SqliteJobStore(self.path) as store:
            store.conn.execute("UPDATE jobs SET body_is_image = 1 WHERE job_id = 'MOCK-1'")
            store.conn.commit()
        out = schemas.JobFeedbackOut(wanted="x", points=[])
        with self.assertRaises(JobTextUnavailable):
            self._service(out).feedback(self._request())

    def test_unknown_job_is_refused(self):
        out = schemas.JobFeedbackOut(wanted="x", points=[])
        request = schemas.JobFeedbackRequest(job_id="없는공고", resume_text=RESUME_TEXT)
        with self.assertRaises(JobNotFound):
            self._service(out).feedback(request)


if __name__ == "__main__":
    unittest.main()
