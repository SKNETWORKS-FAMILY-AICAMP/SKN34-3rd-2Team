"""채용 사이트 UI 문구가 섞인 회사명을 표시용 이름으로 정제한다."""

from __future__ import annotations

import re


_TRAILING_UI_NOISE = re.compile(
    r"(?:\s*(?:관심기업\s*등록|관심기업|스크랩|즉시지원|지원하기))+\s*$"
)


def clean_company_name(value: object) -> str:
    """회사명 뒤에 붙은 채용 사이트 버튼/상태 문구만 제거한다."""
    company = re.sub(r"\s+", " ", str(value or "")).strip()
    previous = None
    while company and company != previous:
        previous = company
        company = _TRAILING_UI_NOISE.sub("", company).strip()
    return company
