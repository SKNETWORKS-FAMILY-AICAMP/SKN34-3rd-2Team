"""채점 페이지 — 사람이 한 화면에서 매기고 그대로 채점에 넘긴다.

원래는 `읽기.md`로 판단하고 `채점표.csv`의 같은 번호 줄에 옮겨 적는 방식이었다.
30줄을 매기려면 서른 번 오가야 해서 9월 7일에 두 번 만들어 두고 한 줄도 안 채워졌다.

여기서 지키는 것 셋.

1. **파일 하나로 열린다.** 바깥에서 받아오는 것이 있으면 인터넷 없이는 못 쓴다.
2. **공고 글이 페이지를 깨뜨리지 않는다.** 본문에 `</script>`가 들어 있어도 안전해야 한다.
3. **내려받는 CSV가 `--score`가 읽는 형식과 같다.** 어긋나면 매긴 30줄이 버려진다.
"""

from __future__ import annotations

import json
import re
import unittest

from job_matching_bot.evaluation.grader_page import build_page
from job_matching_bot.evaluation.recommend_eval import SHEET_COLUMNS

ITEM = {
    "번호": 1,
    "이력서": "프론트엔드 수료생",
    "순위": 1,
    "job_id": "SARAMIN-1",
    "회사": "(주)테스트",
    "공고": "프론트엔드 개발자",
    "공고링크": "https://example.com/1",
    "모델_등급": "높음",
    "근거": [{"claim": "React 경험", "resume_quote": "React로 만들었습니다", "job_quote": "React 경험자"}],
    "우려": ["AWS 경험이 확인되지 않는다"],
    "공고_기술": "React, TypeScript",
    "자격요건": ["React 경험 2년 이상"],
    "우대사항": ["Next.js 경험"],
    "조건": "서울 강남구 · 신입 · 대졸 · 정규직",
    "이력서_기술": "React, TypeScript",
}
PERSONAS = {"프론트엔드 수료생": {"resume_text": "React와 TypeScript로 화면을 만들었습니다."}}


def _payload(html: str) -> list[dict]:
    body = re.search(r'<script id="items" type="application/json">(.*?)</script>', html, re.S)
    return json.loads(body.group(1).replace("<\\/", "</"))


class GraderPageTest(unittest.TestCase):
    def test_the_page_is_self_contained(self):
        html = build_page([ITEM], PERSONAS, "20260910-000000")
        outside = re.findall(r'(?:src|href)="https?://[^"]+', html)
        self.assertEqual([], outside, "글꼴·스크립트를 바깥에서 받아오면 안 된다")
        # 공고 원문 링크는 화면을 그릴 때 만들어진다. 정적 HTML이 아니라 데이터에 있다.
        self.assertEqual("https://example.com/1", _payload(html)[0]["공고링크"])

    def test_resume_text_travels_with_the_item(self):
        """옆에 다른 파일을 열어 두지 않아도 이력서를 볼 수 있어야 한다."""
        data = _payload(build_page([ITEM], PERSONAS, "s"))
        self.assertEqual("React와 TypeScript로 화면을 만들었습니다.", data[0]["이력서_전문"])

    def test_a_script_tag_in_the_posting_does_not_break_the_page(self):
        """공고 본문은 남이 쓴 글이다. `</script>`가 들어 있으면 블록이 일찍 닫힌다."""
        nasty = {**ITEM, "자격요건": ["</script><script>alert(1)</script> 경험"]}
        html = build_page([nasty], PERSONAS, "s")
        body = re.search(r'<script id="items" type="application/json">(.*?)</script>', html, re.S)
        self.assertNotIn("</script>", body.group(1))
        self.assertIn("alert(1)", _payload(html)[0]["자격요건"][0], "내용 자체는 살아 있어야 한다")

    def test_downloaded_csv_matches_the_scoring_format(self):
        """페이지가 만드는 열 이름이 `--score`가 읽는 것과 같아야 한다."""
        html = build_page([ITEM], PERSONAS, "s")
        header = re.search(r"const head = \[([^\]]+)\]", html).group(1)
        columns = tuple(re.findall(r"'([^']+)'", header))
        self.assertEqual(SHEET_COLUMNS, columns)

    def test_progress_is_kept_per_run(self):
        """실행마다 따로 저장한다. 새 실행이 옛 채점을 덮어쓰면 안 된다."""
        a = build_page([ITEM], PERSONAS, "20260910-000000")
        b = build_page([ITEM], PERSONAS, "20260911-000000")
        self.assertIn('data-stamp="20260910-000000"', a)
        self.assertIn('data-stamp="20260911-000000"', b)

    def test_every_item_is_included(self):
        items = [{**ITEM, "번호": n} for n in range(1, 31)]
        self.assertEqual(30, len(_payload(build_page(items, PERSONAS, "s"))))


if __name__ == "__main__":
    unittest.main()
