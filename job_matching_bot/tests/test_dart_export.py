"""Dart 생성 파일이 컴파일 가능한 리터럴을 만드는지 확인한다."""

from __future__ import annotations

import unittest

from job_matching_bot.exporters.dart import build_dart_module


def _record(**overrides):
    base = {
        "id": "T-1",
        "company": "테스트",
        "position": "개발자",
        "description": "예산 $10M USD 규모 프로젝트, 100% 달성",
        "required_skills": ["Python"],
        "preferred_skills": [],
        "tech_stack": [],
        "career_type": "ANY",
        "min_career_years": None,
        "education": "학력무관",
        "location": "서울",
        "employment_type": "정규직",
        "deadline": None,
        "source": "TEST",
        "source_url": "https://example.test/1",
        "status": "OPEN",
    }
    base.update(overrides)
    return base


class DartStringEscapeTest(unittest.TestCase):
    def test_dollar_sign_is_escaped_so_dart_does_not_interpolate(self):
        # Dart는 "$10M"을 문자열 보간으로 읽어 컴파일이 깨진다.
        module = build_dart_module([_record()])
        self.assertIn(r"\$10M USD", module)
        self.assertNotIn('"예산 $10M', module)

    def test_dollar_in_company_and_skills_is_escaped(self):
        module = build_dart_module([
            _record(company="A$B", required_skills=["C$#"], position="$100 챌린지")
        ])
        self.assertNotIn('"A$B"', module)
        self.assertIn(r"A\$B", module)
        self.assertIn(r"C\$#", module)
        self.assertIn(r"\$100", module)

    def test_quotes_and_backslashes_still_escaped(self):
        module = build_dart_module([_record(description='큰따옴표 " 와 역슬래시 \\ 포함')])
        self.assertIn(r"\"", module)
        self.assertIn(r"\\", module)


if __name__ == "__main__":
    unittest.main()
