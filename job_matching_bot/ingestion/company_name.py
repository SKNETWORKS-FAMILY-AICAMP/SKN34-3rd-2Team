"""목록 화면의 회사명 칸에서 회사명만 남긴다.

목록 카드의 회사명은 보통 링크 글자로 깔끔하게 온다. 링크가 없는 카드는 칸 전체 글자를
읽는데, 그러면 버튼과 뱃지가 딸려 온다.

    현대카드(주) 현대자동차그룹 대기업
    (주)라이드플럭스 쏘카그룹
    NEZOT주식회사 관심기업 등록 외국계

2026-09-13 밤 목록 21만 6천 줄 중 2,203줄이 이랬고, 이 이름이 챗봇 카드와 추천 카드에
그대로 나갔다. 뒤에서부터 뱃지 말을 떼어 낸다.

**"~그룹"은 조심해서 뗀다.** 그룹 뱃지("쏘카그룹")와 진짜 회사명("주식회사 와이앤컨설팅그룹")이
같은 모양이다. 떼고 나서 법인 표기("주식회사", "(주)")만 남으면 회사명 자체였던 것이라 되돌린다.
"""

from __future__ import annotations

# 칸에 섞여 오는 버튼 글자. 어디에 있든 지운다.
UI_TEXT = ("관심기업 등록", "관심기업", "스크랩", "지원하기", "즉시지원")

# 기업형태·상장 뱃지. 이름 **끝**에 붙은 것만 뗀다.
BADGES = frozenset({
    "대기업", "중견기업", "중소기업", "외국계", "공사·공기업", "공기업",
    "코스피", "코스닥", "코넥스", "유가증권", "헤드헌팅", "파견·도급·대행",
    "벤처기업", "스타트업",
})

# 이것만 남으면 회사명이 아니다.
LEGAL_FORMS = frozenset({
    "주식회사", "(주)", "㈜", "(유)", "유한회사", "(자)", "합자회사", "(합)", "합명회사",
    "(재)", "재단법인", "(사)", "사단법인", "(의)", "의료법인",
})


def clean_company_name(text: str) -> str:
    """회사명 칸의 글자에서 버튼·뱃지를 뗀다. 이미 깨끗하면 그대로 돌려준다."""
    for noise in UI_TEXT:
        text = text.replace(noise, " ")
    tokens = text.split()
    while len(tokens) > 1:
        last = tokens[-1]
        if last in BADGES:
            tokens.pop()
            continue
        if last.endswith("그룹") and len(last) > len("그룹"):
            rest = tokens[:-1]
            if all(token in LEGAL_FORMS for token in rest):
                break
            tokens = rest
            continue
        break
    return " ".join(tokens)
