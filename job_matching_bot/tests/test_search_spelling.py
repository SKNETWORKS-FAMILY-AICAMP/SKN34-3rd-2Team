"""사람이 치는 표기와 사람인이 붙인 태그 표기가 다르다.

`Spring Boot`라고 치면 태그에 걸린 공고가 0건이었다. 사람인은 `SpringBoot`로 붙인다.
띄어쓰기 하나에 354건이 사라졌고, 챗봇은 "200건 중 직무가 맞는 건 8건"이라고 답했다.
숫자도 틀렸고 "직무"라는 말도 틀렸다 — Spring Boot는 기술이다.
"""

from __future__ import annotations

import unittest

from job_matching_bot.api.service import _matched_what
from job_matching_bot.retrieval.store_search import JobFilters, spellings_of


class SpellingTest(unittest.TestCase):
    def test_a_spaced_name_finds_the_joined_tag(self):
        self.assertIn("SpringBoot", spellings_of("Spring Boot"))

    def test_an_abbreviation_finds_the_full_name(self):
        self.assertIn("Kubernetes", spellings_of("K8s"))

    def test_the_typed_word_comes_first(self):
        # 사용자가 친 말을 빼면 태그에 없는 말(제목·본문에만 있는 말)을 못 찾는다.
        self.assertEqual(spellings_of("REST API")[0], "REST API")

    def test_an_unknown_word_is_left_alone(self):
        self.assertEqual(spellings_of("우주비행"), ["우주비행"])

    def test_the_same_spelling_is_not_repeated(self):
        found = spellings_of("SpringBoot")
        self.assertEqual(len(found), len(set(s.lower() for s in found)))


class MatchedWhatTest(unittest.TestCase):
    def test_a_role_search_says_role(self):
        self.assertEqual(_matched_what(JobFilters(roles=["백엔드"])), "직무가")

    def test_a_skill_search_does_not_say_role(self):
        self.assertEqual(_matched_what(JobFilters(skills=["Spring Boot"])), "기술이")

    def test_both_together_name_neither(self):
        filters = JobFilters(roles=["백엔드"], skills=["Spring Boot"])
        self.assertEqual(_matched_what(filters), "제목·태그에")

    def test_a_free_keyword_names_neither(self):
        self.assertEqual(_matched_what(JobFilters(keywords=["핀테크"])), "제목·태그에")


if __name__ == "__main__":
    unittest.main()
