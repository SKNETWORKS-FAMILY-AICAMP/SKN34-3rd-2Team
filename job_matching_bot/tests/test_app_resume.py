"""평가가 앱과 같은 이력서를 보내는가.

평가는 오래 `fixtures/eval_resumes.json`에 손으로 쓴 이력서를 썼다. 그 글에는
**자격사항·학력사항·기술스택·핵심역량이 없었다.** 요청의 `certifications`와 `majors`도
비어 있었다. 그 상태로 잰 추천 품질은 사용자가 실제로 받는 추천의 품질이 아니다.

이제 원본은 앱과 같은 `scripts/resume_mocks.json` 하나다. 여기서는 파이썬 판이
`resume_text_builder.dart`와 **한 글자도 다르지 않은지** 본다.

Dart 정답지는 `test/dump_mock_resume_text_test.dart`가 만든다. 그 파일이 없으면
대조 테스트는 건너뛴다 — Flutter 없이도 나머지는 돌아야 한다. 앱 쪽 직렬화를
고쳤다면 이렇게 다시 만든다.

    flutter test test/dump_mock_resume_text_test.dart
"""

from __future__ import annotations

import json
import unittest
from datetime import date
from pathlib import Path

from job_matching_bot.evaluation.app_resume import (
    MOCKS,
    build_resume_text,
    estimate_career_years,
    load_personas,
    profile_from_content,
)

DART_DUMP = MOCKS.parent.parent / "test" / "tmp_dump" / "dart_resume_text.json"


class SerializationTest(unittest.TestCase):
    """구간 순서와 줄 모양. Dart 정답지가 없을 때도 최소한은 지켜야 한다."""

    def setUp(self):
        self.content = json.loads(MOCKS.read_text(encoding="utf-8"))["personas"][
            "backend_experienced_3y"
        ]["content"]

    def test_every_section_the_app_writes_is_present(self):
        text = build_resume_text(self.content)
        for label in (
            "핵심역량",
            "기술스택",
            "프로젝트 경험",
            "경력사항",
            "학력사항",
            "자격사항",
            "수상내역",
            "교육경험",
            "기타활동",
            "자기소개서",
        ):
            self.assertIn(f"[{label}]", text, f"{label} 구간이 빠졌다")

    def test_the_section_order_matches_the_app(self):
        """서버가 앞부분을 더 무겁게 보지는 않지만, 순서가 다르면 같은 글이 아니다."""
        text = build_resume_text(self.content)
        order = [line[1:-1] for line in text.splitlines() if line.startswith("[") and line.endswith("]")]
        self.assertEqual(
            ["핵심역량", "기술스택", "프로젝트 경험", "경력사항", "학력사항",
             "자격사항", "수상내역", "교육경험", "기타활동", "자기소개서"],
            order,
        )

    def test_a_certification_carries_its_issuer_and_date(self):
        self.assertIn("- SQLD / 한국데이터산업진흥원 (2022-06)", build_resume_text(self.content))

    def test_continuation_lines_are_not_indented(self):
        """Dart 쪽 `section`이 줄마다 trim을 건다. `  역할:` 의 들여쓰기는 안 남는다."""
        text = build_resume_text(self.content)
        self.assertIn("\n역할: 백엔드 개발(단독)", text)
        self.assertNotIn("\n  역할:", text)

    def test_an_empty_section_is_left_out_entirely(self):
        self.assertNotIn("[자격사항]", build_resume_text({"certifications": []}))

    def test_a_current_job_reads_as_still_working(self):
        content = {"experience": [{"company": "(주)어딘가", "startDate": "2024-01", "isCurrent": True}]}
        self.assertIn("(2024-01 ~ 재직 중)", build_resume_text(content))


class ProfileTest(unittest.TestCase):
    def test_certifications_and_majors_are_sent(self):
        """이 둘이 비어 있어서 자격증·전공 조건을 보는지 평가에 안 잡혔다."""
        persona = load_personas()["백엔드 경력 3년 — Java/Spring Boot"]
        self.assertEqual(["SQLD"], persona["certifications"])
        self.assertEqual(["정보컴퓨터공학부"], persona["majors"])

    def test_career_years_add_up_the_months(self):
        experience = [
            {"company": "가", "startDate": "2023-03", "endDate": "2026-03"},
            {"company": "나", "startDate": "2022-01", "endDate": "2022-07"},
        ]
        self.assertEqual(3.5, estimate_career_years(experience))

    def test_a_current_job_counts_up_to_today(self):
        years = estimate_career_years(
            [{"company": "가", "startDate": "2024-09", "isCurrent": True}],
            today=date(2026, 9, 10),
        )
        self.assertEqual(2.0, years)

    def test_a_broken_date_is_skipped_not_guessed(self):
        self.assertEqual(0, estimate_career_years([{"company": "가", "startDate": "언젠가"}]))

    def test_no_education_reads_as_unstated(self):
        self.assertEqual("미기재", profile_from_content({})["education_level"])


class LoadPersonasTest(unittest.TestCase):
    def test_every_persona_can_be_sent_as_is(self):
        """`recommend()` 가 이 딕셔너리를 그대로 본문으로 만든다. 필드가 다 있어야 한다."""
        personas = load_personas()
        self.assertEqual(5, len(personas))
        for name, persona in personas.items():
            with self.subTest(name):
                self.assertGreater(len(persona["resume_text"]), 20, "서버가 20자 미만을 거절한다")
                for field in (
                    "preferred_regions",
                    "preferred_employment_types",
                    "education_level",
                    "career_years",
                    "majors",
                    "certifications",
                ):
                    self.assertIn(field, persona)

    def test_the_mock_prefix_is_dropped_from_the_name(self):
        self.assertTrue(all(not n.startswith("[목업]") for n in load_personas()))


@unittest.skipUnless(DART_DUMP.exists(), "Dart 정답지 없음 — flutter test 로 만드세요")
class MatchesTheAppTest(unittest.TestCase):
    """앱이 실제로 보내는 글과 글자 단위로 같은가."""

    def setUp(self):
        self.dart = json.loads(DART_DUMP.read_text(encoding="utf-8"))
        self.mocks = json.loads(MOCKS.read_text(encoding="utf-8"))["personas"]

    def test_the_resume_text_is_identical(self):
        for key, want in self.dart.items():
            with self.subTest(key):
                self.assertEqual(want["resume_text"], build_resume_text(self.mocks[key]["content"]))

    def test_the_conditions_are_identical(self):
        for key, want in self.dart.items():
            got = profile_from_content(self.mocks[key]["content"])
            for field in ("education_level", "career_years", "majors", "certifications"):
                with self.subTest(key=key, field=field):
                    self.assertEqual(want[field], got[field])


if __name__ == "__main__":
    unittest.main()
