"""목록 한 줄의 조건 글을 네 토막으로 가른다.

상세를 받아야만 저장소에 들어가서, IT 밖 10개 대분류가 **영영 0건**이다. "서울 영업직
있어?"에 없어서가 아니라 우리가 안 갖고 있어서 답을 못 한다. 조건은 목록에 이미
있는데 한 줄에 붙어 있을 뿐이다.

챗봇 검색은 `region LIKE '%서울%'` 처럼 이 값들로만 거른다. 안 가르면 전부 미기재가
되어 어떤 지역 검색에도 안 걸린다.

실측: 목록 42,902건 중 98.3%가 넷 다 갈린다. 상세까지 있는 27,786건과 대조하면
지역(시·도) 99.6% · 학력 99.5% · 경력 96.6% · 고용형태 94.9%가 같은 값이 나온다.
"""

from __future__ import annotations

import unittest

from job_matching_bot.ingestion.listing_conditions import (
    conditions_from_listing,
    split_condition_text,
)


class SplitTest(unittest.TestCase):
    def check(self, text, region, career, employment, education):
        got = split_condition_text(text)
        self.assertEqual(region, got.region, f"지역: {text}")
        self.assertEqual(career, got.career, f"경력: {text}")
        self.assertEqual(employment, got.employment, f"고용형태: {text}")
        self.assertEqual(education, got.education, f"학력: {text}")

    def test_a_year_range(self):
        self.check("서울 강남구 3 ~ 11년 · 정규직 대학(2,3년)↑",
                   "서울 강남구", "3 ~ 11년", "정규직", "대학(2,3년)↑")

    def test_entry_level(self):
        self.check("충북 음성군 신입 · 정규직 대학교(4년)↑",
                   "충북 음성군", "신입", "정규직", "대학교(4년)↑")

    def test_the_middle_dot_can_appear_inside_the_career(self):
        """`신입 · 경력`은 한 덩어리다. 가운뎃점으로 무턱대고 가르면 안 된다."""
        self.check("서울 영등포구 신입 · 경력 · 정규직 대학(2,3년)↑",
                   "서울 영등포구", "신입·경력", "정규직", "대학(2,3년)↑")

    def test_the_word_bakk_is_part_of_the_value(self):
        """`외`가 지역에도 고용형태에도 붙는다."""
        self.check("경기 평택시 외 신입 · 경력 · 정규직 외 고졸↑",
                   "경기 평택시 외", "신입·경력", "정규직 외", "고졸↑")

    def test_a_minimum_year(self):
        self.check("경북 김천시 경력 2년↑ · 정규직 학력무관",
                   "경북 김천시", "경력 2년↑", "정규직", "학력무관")

    def test_no_degree_requirement(self):
        self.check("서울 강남구 외 4 ~ 10년 · 정규직 학력무관",
                   "서울 강남구 외", "4 ~ 10년", "정규직", "학력무관")

    def test_an_empty_line_gives_empty_parts(self):
        got = split_condition_text("")
        self.assertEqual(0, got.parsed_count)

    def test_one_part_failing_does_not_lose_the_rest(self):
        """통째로 실패하지 않는다. 지역만 걸려도 지역 검색에는 쓸 수 있다."""
        got = split_condition_text("서울 강남구 알 수 없는 조건")
        self.assertEqual("서울 강남구", got.region)
        self.assertGreaterEqual(got.parsed_count, 1)


class InterpretTest(unittest.TestCase):
    """해석은 상세와 **같은 파서**를 쓴다. 두 종류가 섞여도 결과가 어긋나면 안 된다."""

    def test_it_produces_the_fields_the_search_filters_on(self):
        got = conditions_from_listing("서울 강남구 3 ~ 11년 · 정규직 대학(2,3년)↑")
        self.assertEqual("서울 강남구", got["region"])
        self.assertEqual("EXPERIENCED", got["career_type"])
        self.assertEqual(3, got["min_career_years"], "구간은 앞 숫자가 최소 연차다")
        self.assertEqual("초대졸", got["education"])
        self.assertEqual("정규직", got["employment_type"])

    def test_entry_and_experienced_together_is_open_to_both(self):
        got = conditions_from_listing("서울 영등포구 신입 · 경력 · 정규직 대학(2,3년)↑")
        self.assertEqual("ANY", got["career_type"])

    def test_entry_only(self):
        got = conditions_from_listing("충북 음성군 신입 · 정규직 대학교(4년)↑")
        self.assertEqual("ENTRY", got["career_type"])
        self.assertEqual("대졸", got["education"])

    def test_an_unreadable_line_is_marked_unstated_not_guessed(self):
        got = conditions_from_listing("")
        self.assertEqual("미기재", got["region"])
        self.assertEqual("UNKNOWN", got["career_type"])
        self.assertEqual("미기재", got["education"])


if __name__ == "__main__":
    unittest.main()
