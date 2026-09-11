"""챗봇 채점 도구가 재야 할 것을 재는지.

가장 중요한 것은 마지막 시험이다. **케이스에 적어 둔 기대값을 아무도 안 보는 일**이
실제로 있었다. `intent`, `counts_jobs`, `job_refs`를 적어 두었는데 응답에 그 칸이
없어 전부 건너뛰었고, 그래도 22/22 통과라고 나왔다. 재는 줄 알았던 것을 안 재는
쪽이 아예 안 재는 쪽보다 나쁘다.
"""

from __future__ import annotations

import json
import unittest
from types import SimpleNamespace

from job_matching_bot.evaluation import chat_eval
from job_matching_bot.evaluation.chat_grader_page import build_page


def _turn(**kwargs) -> SimpleNamespace:
    base = dict(intent="검색", topic="채용", counts_jobs=False, job_refs=[],
                unavailable="", requirement_query="")
    return SimpleNamespace(**{**base, **kwargs})


class CaseFileTest(unittest.TestCase):
    def test_every_expected_field_is_actually_checked(self):
        cases = json.loads(chat_eval.CASES.read_text(encoding="utf-8"))["cases"]
        self.assertEqual(chat_eval.unknown_keys(cases), set())

    def test_the_two_layers_do_not_overlap(self):
        self.assertEqual(chat_eval.HTTP_KEYS & chat_eval.ROUTER_KEYS, frozenset())


class RouterCheckTest(unittest.TestCase):
    def test_intent_is_compared(self):
        checks = chat_eval.check_router({"intent": "질문"}, _turn(intent="검색"))
        self.assertEqual([ok for _, ok, _ in checks], [False])

    def test_counts_jobs_false_is_compared_not_skipped(self):
        # `if expect.get("counts_jobs")`로 썼다면 False 기대가 통째로 빠진다.
        checks = chat_eval.check_router({"counts_jobs": False}, _turn(counts_jobs=True))
        self.assertEqual([ok for _, ok, _ in checks], [False])

    def test_job_refs_order_matters(self):
        checks = chat_eval.check_router({"job_refs": [1, 3]}, _turn(job_refs=[3, 1]))
        self.assertEqual([ok for _, ok, _ in checks], [False])

    def test_empty_job_refs_is_compared(self):
        ok = chat_eval.check_router({"job_refs": []}, _turn(job_refs=[3]))
        self.assertEqual([o for _, o, _ in ok], [False])

    def test_nothing_expected_means_nothing_checked(self):
        self.assertEqual(chat_eval.check_router({}, _turn()), [])


class HttpCheckTest(unittest.TestCase):
    def test_resume_scope_is_compared(self):
        checks = chat_eval.check(
            {"resume_scope": "프로젝트"}, {}, {"resume_scope": "전체"}, 1.0)
        self.assertIn(("이력서 범위", False, "프로젝트 ↔ 전체"), checks)

    def test_extra_filter_values_are_forgiven(self):
        checks = chat_eval.check(
            {"filters": {"roles": ["백엔드"]}}, {},
            {"filters": {"roles": ["백엔드", "서버"]}}, 1.0)
        self.assertTrue(all(ok for _, ok, _ in checks))


class GraderPageTest(unittest.TestCase):
    RESULTS = [{
        "id": "ref-single",
        "note": "직전 목록에서 2번",
        "turns": [{
            "message": "2번 자세히 봐줘",
            "got": {"mode": "공고", "reply": "신입 지원이 가능한 자리입니다.",
                    "jobs": [{"company": "카카오", "title": "백엔드 개발자"}]},
            "elapsed": 3.2,
        }],
    }]

    def test_the_reply_and_its_evidence_are_both_on_the_page(self):
        page = build_page(self.RESULTS, "20260911-000000")
        self.assertIn("신입 지원이 가능한 자리입니다.", page)
        self.assertIn("카카오", page)

    def test_a_reply_cannot_close_the_data_block_early(self):
        results = [{**self.RESULTS[0], "turns": [
            {**self.RESULTS[0]["turns"][0], "got": {
                "mode": "공고", "reply": "</script><script>alert(1)</script>", "jobs": []}}
        ]}]
        page = build_page(results, "x")
        self.assertNotIn("</script><script>alert(1)", page)

    def test_a_missing_reply_does_not_break_the_page(self):
        results = [{"id": "x", "note": "", "turns": [
            {"message": "안녕", "got": {"mode": "안내"}, "elapsed": 0.4}]}]
        self.assertIn("안녕", build_page(results, "x"))


if __name__ == "__main__":
    unittest.main()
