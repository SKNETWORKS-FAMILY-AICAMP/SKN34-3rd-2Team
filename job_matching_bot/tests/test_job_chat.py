"""공고 찾아보기 챗봇. 말을 조건으로 바꾸고 저장소에서 찾는다.

핵심 약속: **건수는 실제 결과에서 온다.** 답 문장을 LLM이 통째로 쓰면 없는 공고를
있다고 말하게 된다. 그래서 조건 해석만 LLM에 맡기고 문장은 결과로 조립한다.
"""

from __future__ import annotations

import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from job_matching_bot.api import schemas
from job_matching_bot.api.service import ChatService, StoreUnavailable
from job_matching_bot.ingestion.mock_source import mock_jobs
from job_matching_bot.ingestion.sqlite_store import SqliteJobStore


def turn(**kwargs) -> schemas.ChatTurnOut:
    understood = kwargs.pop("understood", "찾아볼게요.")
    off_topic = kwargs.pop("off_topic", False)
    return schemas.ChatTurnOut(
        filters=schemas.ChatFilters(**kwargs), understood=understood, off_topic=off_topic
    )


class ChatServiceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "store.sqlite"
        base = mock_jobs()[0]
        jobs = [
            replace(
                base,
                job_id=f"J{i}",
                source_job_id=f"J{i}",
                company=f"{i}회사",
                title="백엔드 개발자",
                description="Python으로 서버를 만듭니다",
                tech_stack=["Python"],
                keywords=["IT개발·데이터"],
                region="서울 강남구" if i % 2 else "부산 해운대구",
                career_type="ENTRY",
                min_career_years=None,
                employment_type="정규직",
                deadline=None,
                status="OPEN",
            )
            for i in range(1, 9)
        ]
        with SqliteJobStore(self.path) as store:
            store.upsert(jobs, source="MOCK")

    def tearDown(self):
        self.temp.cleanup()

    def service(self, out) -> ChatService:
        self.seen = {}

        def generator(values):
            self.seen.update(values)
            return out

        return ChatService(generator=generator, store_path=self.path)

    def ask(self, out, message="백엔드 찾아줘", filters=None, top_k=5):
        request = schemas.JobChatRequest(message=message, filters=filters, top_k=top_k)
        return self.service(out).chat(request)

    def test_finds_jobs_and_counts_them_from_the_store(self):
        response = self.ask(turn(roles=["백엔드"]))
        self.assertEqual(8, response.total)
        self.assertEqual(5, len(response.jobs), "top_k만큼만 보여준다")
        self.assertIn("8건", response.reply)

    def test_previous_filters_are_handed_to_the_model(self):
        """대화를 잇는 값은 서버가 아니라 요청에 실려 온다. 서버는 대화를 저장하지 않는다."""
        previous = schemas.ChatFilters(roles=["백엔드"])
        self.ask(turn(roles=["백엔드"], regions=["서울"]), message="서울만", filters=previous)
        self.assertIn("백엔드", self.seen["previous"])
        self.assertEqual("서울만", self.seen["message"])

    def test_narrowed_filters_come_back_for_the_next_turn(self):
        response = self.ask(turn(roles=["백엔드"], regions=["서울"]), message="서울만")
        self.assertEqual(["서울"], response.filters.regions)
        self.assertEqual(4, response.total, "서울 공고만 남는다")

    def test_no_result_says_so_and_offers_to_widen(self):
        response = self.ask(turn(roles=["용접"], regions=["제주"]))
        self.assertEqual(0, response.total)
        self.assertEqual([], response.jobs)
        self.assertIn("찾지 못했", response.reply)
        self.assertIn("지역 상관없이", response.suggestions)

    def test_suggestions_do_not_repeat_conditions_already_set(self):
        response = self.ask(turn(roles=["백엔드"], regions=["서울"], career="신입"))
        self.assertNotIn("서울만", response.suggestions)
        self.assertNotIn("신입만", response.suggestions)

    def test_empty_conditions_ask_back_instead_of_listing_everything(self):
        """조건이 없는데 공고를 쏟아내면 대화가 아니라 목록이 된다."""
        response = self.ask(turn(understood="어떤 일을 찾으시나요?"), message="공고")
        self.assertEqual(0, response.total)
        self.assertEqual([], response.jobs)
        self.assertIn("어떤 일", response.reply)

    def test_off_topic_keeps_previous_filters(self):
        previous = schemas.ChatFilters(roles=["백엔드"])
        response = self.ask(turn(off_topic=True), message="안녕", filters=previous)
        self.assertEqual(["백엔드"], response.filters.roles)
        self.assertEqual([], response.jobs)

    def test_missing_store_is_a_clear_error(self):
        service = ChatService(generator=lambda v: turn(roles=["백엔드"]), store_path=Path("없는파일.sqlite"))
        with self.assertRaises(StoreUnavailable):
            service.chat(schemas.JobChatRequest(message="백엔드"))

    def test_job_fields_are_ready_to_show(self):
        response = self.ask(turn(roles=["백엔드"]), top_k=1)
        job = response.jobs[0]
        self.assertTrue(job.job_id and job.company and job.title)
        self.assertEqual("신입", job.career)
        self.assertEqual("정규직", job.employment_type)


if __name__ == "__main__":
    unittest.main()
