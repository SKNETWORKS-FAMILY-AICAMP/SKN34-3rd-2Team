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
from job_matching_bot.retrieval import store_search
from job_matching_bot.ingestion.mock_source import mock_jobs
from job_matching_bot.ingestion.sqlite_store import SqliteJobStore


def turn(**kwargs) -> schemas.ChatTurnOut:
    understood = kwargs.pop("understood", "찾아볼게요.")
    intent = kwargs.pop("intent", "검색")
    counts_jobs = kwargs.pop("counts_jobs", True)
    requirement_query = kwargs.pop("requirement_query", "")
    unavailable = kwargs.pop("unavailable", "")
    job_refs = kwargs.pop("job_refs", [])
    return schemas.ChatTurnOut(
        intent=intent,
        counts_jobs=counts_jobs,
        requirement_query=requirement_query,
        unavailable=unavailable,
        job_refs=job_refs,
        filters=schemas.ChatFilters(**kwargs),
        understood=understood,
    )


def answer(text="이렇습니다.", followups=None) -> schemas.ChatAnswerOut:
    return schemas.ChatAnswerOut(answer=text, followups=followups or [])


class FakeHit:
    """벡터 검색이 돌려주는 것 중 우리가 쓰는 것은 job_id뿐이다."""

    def __init__(self, job_id: str):
        self.job_id = job_id


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
        self.compared = {}
        self.found = {}
        self.calls = 0
        self.by_meaning = getattr(self, "by_meaning", [])

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

        def comparer(values):
            self.compared.update(values)
            return answered or answer()

        def finder(query, top_k, filter=None):
            self.found.update({"query": query, "top_k": top_k, "filter": filter})
            return [FakeHit(job_id) for job_id in self.by_meaning]

        return ChatService(
            generator=generator, store_path=self.path, adviser=adviser,
            job_asker=job_asker, finder=finder, comparer=comparer,
        )

    def ask(self, out, message="백엔드 찾아줘", filters=None, top_k=5,
            job_id=None, answered=None, resume_text=None, last_job_ids=None):
        request = schemas.JobChatRequest(
            message=message, filters=filters, top_k=top_k, job_id=job_id,
            resume_text=resume_text, last_job_ids=last_job_ids or [],
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

    def test_condition_hits_do_not_call_the_index(self):
        """조건으로 찾았으면 벡터를 부르지 않는다. 평소 경로가 느려지면 안 된다."""
        self.by_meaning = ["J1"]
        response = self.ask(turn(roles=["백엔드"]))
        self.assertEqual(8, response.total)
        self.assertEqual({}, self.found, "인덱스를 부르지 않는다")

    def test_job_fields_are_ready_to_show(self):
        response = self.ask(turn(roles=["백엔드"]), top_k=1)
        job = response.jobs[0]
        self.assertTrue(job.job_id and job.company and job.title)
        self.assertEqual("신입", job.career)
        self.assertEqual("정규직", job.employment_type)


class ConfusableTermTest(unittest.TestCase):
    """Java 로 찾을 때 JavaScript 가 걸리면 안 된다. 그렇다고 Spring 이 SpringBoot 를
    놓쳐서도 안 된다.

    `LIKE '%Java%'` 는 부분 문자열이라 실측에서 "Java" 검색 2,004건 중 198건(15%)이
    Java 태그 없이 Javascript 만 있는 공고였다. 그렇다고 단어 경계로 일괄 차단하면
    기술 태그 220종의 접두사 쌍 11개 중 10개가 같은 계열이라 열 곳이 나빠진다.
    """

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "store.sqlite"
        base = mock_jobs()[0]
        jobs = [
            replace(
                base, job_id=job_id, source_job_id=job_id, company=f"{job_id}회사",
                title=title, description=description, tech_stack=list(tech),
                keywords=["IT개발·데이터"], region="서울 강남구", career_type="ANY",
                min_career_years=None, employment_type="정규직", deadline=None, status="OPEN",
            )
            for job_id, title, description, tech in [
                ("J-JAVA", "백엔드 개발자", "Java와 Spring으로 서버를 만듭니다", ["Java", "Spring"]),
                ("J-JS", "프론트 개발자", "Javascript로 화면을 만듭니다", ["Javascript"]),
                ("J-BOTH", "풀스택 개발자", "Java와 Javascript를 씁니다", ["Java", "Javascript"]),
                ("J-BOOT", "서버 개발자", "SpringBoot로 API를 만듭니다", ["SpringBoot"]),
                ("J-KOR", "웹 개발자", "자바 기반 서비스를 운영합니다", []),
                ("J-KORJS", "화면 개발자", "자바스크립트로 UI를 만듭니다", []),
                ("J-GO", "서버 개발자", "Go로 API를 만듭니다", ["Go"]),
                ("J-GOLANG", "백엔드 개발자", "GoLang 기반 서비스", ["GoLang"]),
                ("J-MONGO", "데이터 개발자", "MongoDB와 Django를 씁니다", ["MongoDB", "Django"]),
                ("J-GOOGLE", "클라우드 엔지니어", "Google Cloud를 운영합니다", ["GCP"]),
            ]
        ]
        with SqliteJobStore(self.path) as store:
            store.upsert(jobs, source="MOCK")

    def tearDown(self):
        self.temp.cleanup()

    def found(self, term):
        result = store_search.search(
            self.path, store_search.JobFilters(skills=[term]), limit=50
        )
        return {job.job_id for job in result.jobs}

    def test_java_does_not_match_javascript(self):
        self.assertNotIn("J-JS", self.found("Java"))

    def test_java_still_matches_java(self):
        self.assertIn("J-JAVA", self.found("Java"))

    def test_a_job_with_both_is_found_by_java(self):
        """한 공고에 둘 다 있으면 Java 쪽이 걸린다. 빼면 진짜 Java 공고를 잃는다."""
        self.assertIn("J-BOTH", self.found("Java"))

    def test_javascript_still_finds_javascript(self):
        self.assertIn("J-JS", self.found("Javascript"))

    def test_korean_follows_the_same_rule(self):
        found = self.found("자바")
        self.assertIn("J-KOR", found)
        self.assertNotIn("J-KORJS", found)

    def test_go_does_not_match_mongodb_django_google(self):
        """두 글자짜리는 앞뒤를 다 봐야 한다. "Go" 는 Django 안에도 Google 안에도 있다."""
        found = self.found("Go")
        self.assertIn("J-GO", found)
        self.assertIn("J-GOLANG", found, "GoLang 은 Go 가 맞다")
        self.assertNotIn("J-MONGO", found)
        self.assertNotIn("J-GOOGLE", found)

    def test_spring_still_matches_springboot(self):
        """접두사 쌍 11개 중 10개는 같은 계열이라 막으면 손해다."""
        self.assertIn("J-BOOT", self.found("Spring"))


class MeaningSearchTest(ChatTestCase):
    """조건으로 못 찾으면 뜻으로 찾는다.

    "돈 다루는 일"은 공고에 그렇게 적히지 않는다. 글자로 훑으면 0건이고, 요건 말투로
    고쳐 쓴 문장으로 인덱스를 찾으면 회계 공고가 나온다. 실측으로 확인한 차이다
    (유사도 0.377 → 0.773).
    """

    def setUp(self):
        super().setUp()
        self.by_meaning = ["J3", "J5"]

    def test_no_condition_match_falls_back_to_meaning(self):
        response = self.ask(
            turn(keywords=["돈 다루는 일"], requirement_query="[주요업무] 전표 처리, 결산"),
            message="돈 다루는 일 찾아줘",
        )
        self.assertEqual(["J3", "J5"], [job.job_id for job in response.jobs])
        self.assertIn("뜻이 가까운", response.reply, "어떻게 찾았는지 밝힌다")
        self.assertIn("전표 처리", self.found["query"], "요건 말투 문장으로 찾는다")

    def test_weak_body_only_matches_also_fall_back(self):
        """건수는 많은데 제목·태그에 하나도 안 걸렸으면 물어본 일과 상관없는 공고들이다."""
        self.by_meaning = ["J2"]
        response = self.ask(
            turn(roles=["서버"], requirement_query="[주요업무] 서버 운영"),
            message="서버 관련 일 찾아줘",
        )
        # 목록의 공고는 제목이 "백엔드 개발자"라 "서버"는 본문에만 있다(relevance 1).
        self.assertEqual(["J2"], [job.job_id for job in response.jobs])

    def test_conditions_are_carried_into_the_index_query(self):
        """지역·고용형태는 인덱스에도 걸어야 뜻만 맞고 조건은 틀린 공고가 안 나온다."""
        self.ask(
            turn(keywords=["돈 다루는 일"], regions=["서울"], career="신입",
                 requirement_query="[주요업무] 전표 처리"),
            message="서울에서 돈 다루는 일",
        )
        self.assertIsNotNone(self.found["filter"])

    def test_closed_jobs_from_the_index_are_dropped(self):
        """인덱스는 밤에 한 번 갱신된다. 낮에 마감된 공고가 남아 있을 수 있다."""
        self.by_meaning = ["J1", "없는공고", "J2"]
        response = self.ask(
            turn(keywords=["돈 다루는 일"], requirement_query="[주요업무] 전표 처리")
        )
        self.assertEqual(["J1", "J2"], [job.job_id for job in response.jobs])

    def test_index_failure_does_not_break_the_conversation(self):
        """인덱스가 안 붙었다고 챗봇이 멈출 이유가 없다."""

        def broken(query, top_k, filter=None):
            raise RuntimeError("Pinecone 연결 실패")

        service = self.service(
            turn(keywords=["돈 다루는 일"], requirement_query="[주요업무] 전표 처리")
        )
        service._finder = broken
        response = service.chat(schemas.JobChatRequest(message="돈 다루는 일"))
        self.assertEqual(0, response.total)
        self.assertIn("찾지 못했", response.reply)

    def test_no_conditions_at_all_still_searches_by_meaning(self):
        """"돈 다루는 일"은 조건으로 옮길 말이 없다. 그렇다고 되물으면 안 된다.

        조건이 비었다는 이유로 검색 전에 되묻는 바람에 의미 검색이 아예 실행되지
        않았다. 되묻는 것은 뜻으로 찾을 문장마저 없을 때다.
        """
        response = self.ask(
            turn(requirement_query="[주요업무] 전표 처리, 결산"),
            message="돈 다루는 일 찾아줘",
        )
        self.assertEqual("검색", response.mode)
        self.assertEqual(["J3", "J5"], [job.job_id for job in response.jobs])
        self.assertIn("뜻이 가까운", response.reply)

    def test_no_requirement_query_means_no_fallback(self):
        """LLM이 문장을 안 줬으면 부를 것이 없다."""
        self.ask(turn(keywords=["돈 다루는 일"], requirement_query=""))
        self.assertEqual({}, self.found)

    def test_region_only_search_does_not_use_meaning(self):
        """찾을 말이 없으면 조건 조회가 정확하다. "서울만"에 벡터를 부르면 낭비다."""
        self.ask(turn(regions=["제주"], requirement_query="[주요업무] 무엇이든"))
        self.assertEqual({}, self.found)


class UnavailableTest(ChatTestCase):
    """모으지 않는 것으로 찾아 달라고 하면 없다고 말한다.

    실측: 오늘 받은 공고 696건 중 631건(90%)이 급여를 "면접 후 결정"으로 적었다.
    숫자가 있는 65건도 대부분 최저임금 안내다. 급여로 정렬하면 정작 많이 주는 곳이
    빠지고 순서가 거꾸로 나온다.
    """

    def test_pay_is_not_something_we_can_sort_by(self):
        response = self.ask(turn(unavailable="급여"), message="급여 제일 높은공고")
        self.assertEqual("안내", response.mode)
        self.assertEqual([], response.jobs)
        self.assertIn("면접 후 결정", response.reply, "왜 못 하는지 밝힌다")
        self.assertNotIn(
            "조건을 하나 빼거나", response.reply, "빼면 찾을 수 있다는 뜻이 되면 안 된다"
        )
        self.assertTrue(response.suggestions, "할 수 있는 것을 권한다")

    def test_it_does_not_search_with_a_condition_we_cannot_meet(self):
        """조건으로 넣으면 0건이 나오고 "지역을 넓혀 보라"는 엉뚱한 안내가 나간다."""
        self.ask(turn(unavailable="급여", keywords=["급여 높은"]))
        self.assertEqual({}, self.found, "인덱스도 부르지 않는다")

    def test_chance_of_passing_is_unknowable(self):
        response = self.ask(turn(unavailable="합격 가능성"), message="붙을 만한 데 있어?")
        self.assertEqual("안내", response.mode)
        self.assertIn("알 수 없어요", response.reply)


class RecommendHandoffTest(ChatTestCase):
    """이력서로 골라 달라는 말은 추천이 맡는다. 챗봇은 이력서를 받지 않는다."""

    def test_resume_based_ask_hands_off_instead_of_searching(self):
        """앞 대화에 조건이 남아 있어도 그걸로 목록을 내면 안 된다.

        실제로 "Python · 신입" 조건이 남은 상태에서 "내 이력서 보면 제일 잘 어울리는
        공고가 뭐예요?"를 물었더니, 이력서가 화면 왼쪽에 멀쩡히 있는데도 "이력서를
        먼저 올려 주세요"라고 답하면서 그 조건으로 486건을 검색해 보여 줬다.
        """
        previous = schemas.ChatFilters(skills=["Python"], career="신입")
        response = self.ask(
            turn(intent="추천", skills=["Python"], career="신입"),
            message="지금 내 이력서 보면 제일 잘 어울리는 공고가 뭐예요?",
            filters=previous,
        )
        self.assertEqual("추천", response.mode)
        self.assertEqual([], response.jobs, "챗봇이 목록을 내지 않는다")
        self.assertEqual(0, response.total)
        self.assertNotIn("올려", response.reply, "이력서가 없다고 하지 않는다")

    def test_previous_conditions_survive_the_handoff(self):
        """추천을 보고 와서 "그럼 서울만"으로 이어갈 수 있어야 한다."""
        previous = schemas.ChatFilters(roles=["백엔드"], regions=["서울"])
        response = self.ask(turn(intent="추천"), message="나한테 맞는 공고", filters=previous)
        self.assertEqual(["백엔드"], response.filters.roles)
        self.assertEqual(["서울"], response.filters.regions)


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


class AdviceEvidenceTest(ChatTestCase):
    """질문 답에 붙는 근거 공고. 여기도 내려간 공고는 빼야 한다.

    검색 답에서는 빼면서 질문 답의 근거에서는 빼지 않아, 저장소가 아직 OPEN으로
    아는 접수마감 공고가 그대로 화면에 붙어 나갔다.
    """

    class _Liveness:
        """맨 앞 공고 하나만 내려간 것으로 본다."""

        def __init__(self) -> None:
            self.asked: list[str] = []

        def alive(self, job_ids: list[str]) -> list[str]:
            self.asked = list(job_ids)
            return list(job_ids[1:])

    def test_closed_jobs_do_not_become_evidence(self):
        service = self.service(turn(intent="질문", roles=["백엔드"]))
        liveness = self._Liveness()
        service._liveness = liveness

        response = service.chat(
            schemas.JobChatRequest(message="요즘 뭘 많이 뽑아?", top_k=5)
        )

        self.assertTrue(liveness.asked, "근거로 붙일 공고도 열어 본다")
        shown = [job.job_id for job in response.jobs]
        self.assertNotIn(liveness.asked[0], shown, "내려간 공고는 근거가 될 수 없다")
        self.assertEqual(3, len(shown), "빠진 자리는 다음 공고가 채운다")


class JobQuestionTest(ChatTestCase):
    """공고 하나를 놓고 묻기. **그 공고 원문만** 근거로 쓴다."""

    def test_asking_about_a_job_skips_the_filter_step(self):
        """공고를 골라 물었으면 무슨 말이든 그 공고 이야기다. 조건을 다시 뽑지 않는다."""
        response = self.ask(
            turn(roles=["엉뚱한직무"]), message="신입도 지원할 수 있어?", job_id="J1"
        )
        self.assertEqual("공고", response.mode)
        self.assertEqual(0, self.calls, "조건 추출 LLM은 부르지 않는다")

    def test_the_resume_goes_with_the_question(self):
        """이력서 화면에서 물었으면 이력서를 함께 넘긴다.

        안 넘기던 때에는 "이 공고 나한테 맞아?"에 "현재 이력서 내용을 볼 수 없어
        판단하기는 어렵다"고 답했다. 이력서는 바로 옆 화면에 열려 있었다.
        """
        self.ask(
            turn(), message="나한테 맞는 공고야?", job_id="J1",
            resume_text="Python으로 FastAPI 추천 API를 만들었습니다.",
        )
        self.assertIn("FastAPI", self.asked["resume"])

    def test_without_a_resume_the_model_is_told_so(self):
        """안 받았으면 없다고 분명히 알린다. 빈 칸을 주면 지어내 채운다."""
        self.ask(turn(), message="뭘 요구해?", job_id="J1")
        self.assertEqual("(없음)", self.asked["resume"])

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


class JobReferenceTest(ChatTestCase):
    """"2번 자세히 봐줘" — 직전 목록에서 자리를 가리킨 말.

    서버는 대화를 저장하지 않는다. 직전에 무엇을 보여 줬는지는 앱이 `last_job_ids`로
    되돌려 줘야 안다. 이게 없던 때는 사용자가 공고 카드를 눌러 `job_id`를 보내야만
    그 공고를 놓고 물을 수 있었다.
    """

    def test_the_second_one_becomes_that_job(self):
        result = self.ask(
            turn(intent="질문", job_refs=[2]),
            message="2번 자세히 봐줘",
            last_job_ids=["J1", "J2", "J3"],
        )
        self.assertEqual("공고", result.mode)
        self.assertIn("2회사", self.asked["job"])

    def test_the_first_one_too(self):
        self.ask(
            turn(intent="질문", job_refs=[1]),
            message="첫 번째 거 자격요건 알려줘",
            last_job_ids=["J1", "J2", "J3"],
        )
        self.assertIn("1회사", self.asked["job"])

    def test_a_number_past_the_end_is_not_guessed(self):
        """세 건을 보여 줬는데 "5번"이라고 하면 엉뚱한 공고를 집지 않는다."""
        result = self.ask(
            turn(intent="질문", job_refs=[5]),
            message="5번 알려줘",
            last_job_ids=["J1", "J2", "J3"],
        )
        self.assertNotEqual("공고", result.mode)
        self.assertEqual({}, self.asked)

    def test_without_a_previous_list_it_says_so(self):
        """앞에 보여 준 것이 없으면 조건 검색으로 내려보내지 않고 그렇다고 말한다."""
        result = self.ask(
            turn(intent="질문", job_refs=[2]), message="2번 알려줘", last_job_ids=[]
        )
        self.assertEqual("안내", result.mode)
        self.assertIn("앞에 보여 드린 공고가 없어요", result.reply)

    def test_no_reference_still_searches(self):
        """번호를 안 가리킨 말은 예전 그대로 흐른다."""
        result = self.ask(turn(roles=["백엔드"]), last_job_ids=["J1", "J2"])
        self.assertEqual("검색", result.mode)
        self.assertEqual({}, self.asked)

    def test_the_tapped_card_still_wins(self):
        """카드를 눌러 물으면 그 공고다. 말 속의 번호를 따지지 않는다."""
        self.ask(
            turn(intent="질문", job_refs=[2]),
            message="여기 2번 항목이 뭐야?",
            job_id="J7",
            last_job_ids=["J1", "J2", "J3"],
        )
        self.assertIn("7회사", self.asked["job"])


class JobCompareTest(ChatTestCase):
    """"1번하고 3번 비교해줘" — 자리를 둘 가리키면 비교다.

    따로 의도를 두지 않는다. 개수가 곧 신호이고, LLM이 한 번 더 가를 일을 만들지
    않는 편이 틀릴 여지가 적다.
    """

    def test_two_references_compare_both(self):
        result = self.ask(
            turn(intent="질문", job_refs=[1, 3]),
            message="1번하고 3번 비교해줘",
            last_job_ids=["J1", "J2", "J3"],
        )
        self.assertEqual("비교", result.mode)
        self.assertIn("1회사", self.compared["job_a"])
        self.assertIn("3회사", self.compared["job_b"])
        self.assertEqual({}, self.asked, "하나 묻기로 새면 안 된다")

    def test_the_spoken_order_is_kept(self):
        self.ask(
            turn(intent="질문", job_refs=[3, 1]),
            message="3번이랑 1번 중 뭐가 나아?",
            last_job_ids=["J1", "J2", "J3"],
        )
        self.assertIn("3회사", self.compared["job_a"])
        self.assertIn("1회사", self.compared["job_b"])

    def test_both_jobs_come_back_for_the_screen(self):
        result = self.ask(
            turn(intent="질문", job_refs=[1, 2]), last_job_ids=["J1", "J2", "J3"]
        )
        self.assertEqual(["J1", "J2"], [job.job_id for job in result.jobs])
        self.assertEqual(2, result.total)

    def test_the_same_number_twice_is_not_a_comparison(self):
        """"1번하고 1번"은 비교가 아니다. 하나 묻기로 내려간다."""
        result = self.ask(
            turn(intent="질문", job_refs=[1, 1]), last_job_ids=["J1", "J2"]
        )
        self.assertEqual("공고", result.mode)
        self.assertEqual({}, self.compared)

    def test_a_number_past_the_end_is_dropped(self):
        """세 건을 보여 줬는데 "2번하고 9번"이면 남는 것이 하나뿐이라 비교가 아니다."""
        result = self.ask(
            turn(intent="질문", job_refs=[2, 9]), last_job_ids=["J1", "J2", "J3"]
        )
        self.assertEqual("공고", result.mode)
        self.assertIn("2회사", self.asked["job"])

    def test_the_resume_is_passed_through(self):
        self.ask(
            turn(intent="질문", job_refs=[1, 2]),
            message="둘 중 나한테 맞는 건?",
            last_job_ids=["J1", "J2"],
            resume_text="FastAPI로 추천 API를 개발했습니다.",
        )
        self.assertIn("FastAPI", self.compared["resume"])

    def test_without_a_resume_it_says_none(self):
        self.ask(turn(intent="질문", job_refs=[1, 2]), last_job_ids=["J1", "J2"])
        self.assertEqual("(없음)", self.compared["resume"])

    def test_a_closed_job_is_not_compared(self):
        """비교하는 사이에 한쪽이 마감됐을 수 있다. 없는 공고를 상대로 견주지 않는다."""
        service = self.service(turn(intent="질문", job_refs=[1, 2]))
        service.drop_dead = lambda ids: {i for i in ids if i != "J2"}
        result = service.chat(
            schemas.JobChatRequest(
                message="1번하고 2번 비교해줘", last_job_ids=["J1", "J2"]
            )
        )
        self.assertEqual("공고", result.mode)
        self.assertIn("1회사", self.asked["job"])
        self.assertEqual({}, self.compared)

    def test_both_closed_says_so(self):
        service = self.service(turn(intent="질문", job_refs=[1, 2]))
        service.drop_dead = lambda ids: set()
        result = service.chat(
            schemas.JobChatRequest(
                message="1번하고 2번 비교해줘", last_job_ids=["J1", "J2"]
            )
        )
        self.assertEqual("안내", result.mode)
        self.assertIn("비교할 공고를 찾지 못했어요", result.reply)


if __name__ == "__main__":
    unittest.main()
