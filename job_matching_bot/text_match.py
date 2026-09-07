"""한글·영문이 섞인 채용공고 텍스트용 키워드 매칭 유틸.

`\\b` 경계는 한글과 영문이 붙어 있는 구간에서 잘못 동작한다. 한글도 `\\w`라
`"REST API와"`의 `api`는 `\\bapi\\b`로 잡히지 않고, 반대로 `"fastapi"`의
`api`처럼 잡히면 안 되는 것이 잡힌다. 그래서 영문 키워드는 앞뒤가 ASCII
영숫자가 아닐 때만 매칭하도록 직접 경계를 만든다.
"""

import re

# 영문 경계 판정에서 단어의 일부로 취급할 문자.
_ASCII_WORD = "a-z0-9"


def _is_ascii_term(term: str) -> bool:
    return term.isascii()


def term_pattern(term: str) -> str:
    """키워드 하나를 정규식 조각으로 변환한다.

    영문 키워드는 ASCII 영숫자 경계를 붙이고, 한글이 포함된 키워드는
    경계 없이 그대로 부분 문자열로 찾는다.
    """
    escaped = re.escape(term.lower())
    if not _is_ascii_term(term):
        return escaped
    return f"(?<![{_ASCII_WORD}]){escaped}(?![{_ASCII_WORD}])"


def compile_terms(terms: tuple[str, ...] | list[str]) -> list[tuple[str, re.Pattern]]:
    """키워드 목록을 (원래 키워드, 컴파일된 패턴) 목록으로 만든다."""
    return [(term, re.compile(term_pattern(term), re.IGNORECASE)) for term in terms]


def matched_terms(text: str, compiled: list[tuple[str, re.Pattern]]) -> list[str]:
    """텍스트에서 실제로 발견된 키워드를 정렬해 중복 없이 돌려준다."""
    if not text:
        return []
    return sorted({term for term, pattern in compiled if pattern.search(text)})
