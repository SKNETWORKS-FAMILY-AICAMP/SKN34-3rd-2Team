"""채용 챗봇. 검색 / 채용 질문 / 공고 하나 묻기 세 갈래.

핵심 약속 둘.

1. **건수는 실제 결과에서 온다.** 답 문장을 LLM이 통째로 쓰면 없는 공고를 있다고
   말하게 된다. 그래서 조건 해석만 LLM에 맡기고 검색 답은 결과로 조립한다.
2. **답에는 근거가 붙는다.** 질문에는 공고를 센 표를, 공고 물음에는 그 공고 원문을
   준다. 근거 없이 쓰게 하면 우리 데이터와 상관없는 일반론이 나온다.
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
    intent = kwargs.pop("intent", "검색")
    counts_jobs = kwargs.pop("counts_jobs", True)
    return schemas.ChatTurnOut(
        intent=intent,
        counts_jobs=counts_jobs,
        filters=schemas.ChatFilters(**kwargs),
        understood=understood,
    )


def answer(text="이렇습니다.", followups=None) -> schemas.ChatAnswerOut:
    return schemas.ChatAnswerOut(answer=text, followups=followups or [])


class ChatTestCase(unittest.TestCase):
    """공고 8건이 든 임시 저장소. LLM은 부르지 않는다."""

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

    def service(self, out, answered=None) -> ChatService:
        """LLM을 부르지 않는 서비스. `seen`에 무엇이 넘어갔는지 남긴다."""
        self.seen = {}
        self.advised = {}
        self.asked = {}
        self.calls = 0

        def generator(values):
            self.calls += 1
            self.seen.update(values)
            return out

        def adviser(values):
            self.advised.update(values)
            return answered or answer()

        def job_asker(values):
            self.asked.update(values)
            return answered or answer()

        return ChatService(
            generator=generator, store_path=self.path, adviser=adviser, job_asker=job_asker
        )

    def ask(self, out, message="백엔드 찾아줘", filters=None, top_k=5,
            job_id=None, answered=None):
        request = schemas.JobChatRequest(
            message=message, filters=filters, top_k=top_k, job_id=job_id
        )
        return self.service(out, answered=answered).chat(request)


class SearchTest(ChatTestCase):
    """말을 조건으로 바꿔 저장소에서 찾는다."""

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

    def test_small_talk_keeps_previous_filters(self):
        previous = schemas.ChatFilters(roles=["백엔드"])
        response = self.ask(turn(intent="잡담"), message="안녕", filters=previous)
        self.assertEqual("안내", response.mode)
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


class AdviceTest(ChatTestCase):
    """채용 질문. 답은 LLM이 쓰지만 **숫자는 우리가 세어 건네준다.**"""

    def test_question_is_answered_with_counted_jobs(self):
        response = self.ask(
            turn(intent="질문", roles=["백엔드"]),
            message="백엔드 신입은 뭘 준비해야 해?",
            answered=answer("Python을 적은 공고가 많아요."),
        )
        self.assertEqual("질문", response.mode)
        self.assertEqual("Python을 적은 공고가 많아요.", response.reply)
        self.assertIn("8건", self.advised["stats"], "센 결과가 근거로 넘어가야 한다")
        self.assertIn("Python", self.advised["stats"])
        self.assertEqual("백엔드 신입은 뭘 준비해야 해?", self.advised["question"])

    def test_answer_carries_the_jobs_it_counted(self):
        """숫자만 주면 확인할 길이 없다. 근거가 된 공고를 몇 건 붙인다."""
        response = self.ask(turn(intent="질문", roles=["백엔드"]), message="뭐가 필요해?")
        self.assertTrue(response.jobs)
        self.assertLessEqual(len(response.jobs), 3)
        self.assertEqual(8, response.total)

    def test_a_countable_question_with_no_conditions_counts_everything(self):
        """"요즘 많이 요구하는 기술이 뭐야?"에는 조건이 없다. 그래도 전체를 세면 답이 된다.

        조건이 없다고 세지 않았더니, 세어 달라는 질문에 "저희가 모은 공고로는 알 수
        없어요"라고 답했다. 조건 유무는 셀지 말지의 기준이 아니다.
        """
        response = self.ask(
            turn(intent="질문"), message="요즘 많이 요구하는 기술이 뭐야?"
        )
        self.assertEqual("질문", response.mode)
        self.assertIn("전체", self.advised["stats"])
        self.assertIn("Python", self.advised["stats"])
        self.assertEqual(8, response.total)
        self.assertTrue(response.jobs)

    def test_the_table_says_what_it_counted(self):
        """모수를 밝히지 않으면 모델이 표를 믿지 못해 "알 수 없다"고 물러선다.

        실제로 "신입 공고의 기술"을 물었을 때 표에 그 분포가 들어 있는데도 "전체 공고
        기준이라 신입 공고에서의 비율은 알 수 없다"고 답했다.
        """
        self.ask(turn(intent="질문", career="신입"), message="신입 공고에 자주 나오는 기술은?")
        stats = self.advised["stats"]
        self.assertIn("센 것:", stats)
        self.assertIn("신입이 지원할 수 있는", stats)
        self.assertIn("경력무관", stats, "무엇이 함께 들어갔는지 밝힌다")

    def test_advice_questions_do_not_count(self):
        """세어서 답할 물음이 아니면 조건이 남아 있어도 숫자를 대지 않는다.

        "서울 백엔드 신입"을 찾아본 뒤 "자소서 어떻게 써?"라고 물으면 조건은 그대로
        남아 있다. 그걸로 표를 만들면 상관없는 숫자가 답의 첫 문단을 차지한다.
        """
        response = self.ask(
            turn(intent="질문", counts_jobs=False, roles=["백엔드"], regions=["서울"]),
            message="자소서 어떻게 써?",
        )
        self.assertIn("세어 답할 것이 아니다", self.advised["stats"])
        self.assertEqual([], response.jobs)
        self.assertEqual(0, response.total)

    def test_followups_become_suggestions(self):
        response = self.ask(
            turn(intent="질문", roles=["백엔드"]),
            answered=answer(followups=["서울은 몇 건이야?", "이 조건으로 공고 보여줘", "가", "나"]),
        )
        self.assertEqual(3, len(response.suggestions), "세 개까지만")
        self.assertIn("서울은 몇 건이야?", response.suggestions)


class JobQuestionTest(ChatTestCase):
    """공고 하나를 놓고 묻기. **그 공고 원문만** 근거로 쓴다."""

    def test_asking_about_a_job_skips_the_filter_step(self):
        """공고를 골라 물었으면 무슨 말이든 그 공고 이야기다. 조건을 다시 뽑지 않는다."""
        response = self.ask(
            turn(roles=["엉뚱한직무"]), message="신입도 지원할 수 있어?", job_id="J1"
        )
        self.assertEqual("공고", response.mode)
        self.assertEqual(0, self.calls, "조건 추출 LLM은 부르지 않는다")

    def test_the_posting_text_is_handed_to_the_model(self):
        self.ask(turn(), message="뭘 요구해?", job_id="J1")
        job = self.asked["job"]
        self.assertIn("1회사", job)
        self.assertIn("백엔드 개발자", job)
        self.assertIn("Python으로 서버를 만듭니다", job, "본문이 통째로 들어가야 한다")
        self.assertIn("신입", job)
        self.assertEqual("뭘 요구해?", self.asked["question"])

    def test_previous_filters_survive_a_job_question(self):
        """공고를 물어본 뒤 "다른 것도 보여줘"로 돌아갈 수 있어야 한다."""
        previous = schemas.ChatFilters(roles=["백엔드"], regions=["서울"])
        response = self.ask(turn(), message="이거 어때?", job_id="J1", filters=previous)
        self.assertEqual(["백엔드"], response.filters.roles)
        self.assertEqual(["서울"], response.filters.regions)

    def test_missing_job_says_so_instead_of_guessing(self):
        response = self.ask(turn(), message="이거 어때?", job_id="없는공고")
        self.assertEqual("안내", response.mode)
        self.assertIn("찾지 못했", response.reply)
        self.assertEqual({}, self.asked, "없는 공고로 LLM을 부르지 않는다")


if __name__ == "__main__":
    unittest.main()
