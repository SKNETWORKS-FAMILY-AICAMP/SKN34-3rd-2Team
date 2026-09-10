"""본문에 낀 HTML 주석이 단어를 쪼개지 않는가.

사람인은 공고 본문에 들어온 `script` 라는 글자를 XSS 방지로 주석을 끼워 끊어 둔다.
실제 공고(SARAMIN-54892650)의 원본 HTML이 이렇다.

    <p>ㆍ주요 개발 언어 : ja<!--x-->vasc<!--x-->ript, Typesc<!--x-->ript, <br>jQuery</p>

주석이 글자 조각을 가르기 때문에 줄바꿈 구분자가 그 자리마다 줄을 나눠 본문이
`ja` / `vasc` / `ript,` 세 줄로 저장됐다. 화면이 깨지는 것보다 나쁜 것은 기술 이름이
사라지는 것이다. `JavaScript`를 못 뽑으면 사전 순위의 기술 겹침에서 통째로 빠지고,
LLM도 본문에서 그 단어를 못 본다.

저장소에서 이 모양으로 끊긴 모집 중 공고가 640건 있었다.
"""

from __future__ import annotations

import unittest

from job_matching_bot.crawling.crawl_detail import parse_detail
from job_matching_bot.ingestion.skill_extractor import extract_skills

URL = "https://www.saramin.co.kr/zf_user/jobs/view?rec_idx=54892650"

# 실제 공고의 그 부분을 그대로 줄인 것.
SPLIT_HTML = """
<html><body>
  <div class="jv_cont">
    <h1>프론트엔드 개발자</h1>
    <dl><dt>경력</dt><dd>신입</dd></dl>
  </div>
  <div class="jv_cont">
    <h2>상세요강</h2>
    <div>
      <p>ㆍ주요 개발 언어 : ja<!--x-->vasc<!--x-->ript, Typesc<!--x-->ript, <br>jQuery</p>
      <p>ㆍ주요 프레임워크 : React, AngularJS,<br>Node.js</p>
      <p>ㆍja<!--x-->vasc<!--x-->ript 기반 데이터 시각화</p>
    </div>
  </div>
</body></html>
"""


class CommentSplitTest(unittest.TestCase):
    def setUp(self):
        self.body = parse_detail(SPLIT_HTML, "54892650", URL)["description"]

    def test_the_word_is_whole_again(self):
        self.assertIn("javascript, Typescript,", self.body)
        self.assertNotIn("vasc", self.body.replace("javascript", ""))

    def test_the_skill_names_are_found(self):
        """이게 진짜 손해였다. 쪼개진 글자에서는 기술을 뽑을 수 없다."""
        found = extract_skills(self.body)
        for name in ("JavaScript", "TypeScript", "jQuery", "React"):
            self.assertIn(name, found, f"{name} 이(가) 안 잡혔다")

    def test_real_line_breaks_are_kept(self):
        """`<br>`과 `<p>`는 진짜 줄바꿈이다. 주석만 지우고 이건 그대로 둔다."""
        lines = self.body.splitlines()
        self.assertIn("jQuery", lines)
        self.assertIn("Node.js", lines)

    def test_a_body_without_comments_is_untouched(self):
        plain = SPLIT_HTML.replace("<!--x-->", "")
        self.assertEqual(self.body, parse_detail(plain, "1", URL)["description"])

    def test_the_comment_content_never_leaks_into_the_body(self):
        html = SPLIT_HTML.replace("<!--x-->", "<!-- 관리자 메모: 이 공고는 대행 -->")
        self.assertNotIn("관리자 메모", parse_detail(html, "1", URL)["description"])


if __name__ == "__main__":
    unittest.main()
