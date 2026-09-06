"""자격요건 구간에서 전공·자격증·병역 조건을 뽑는다.

자격요건 줄의 73%가 학력·전공, 10%가 자격증·어학, 16%가 병역·결격 사유를 말한다.
이력서에는 전공(학력사항)과 자격사항이 있으니 비교할 수 있는데, 지금까지는 경력·학력만
봤다. 여기서 뽑은 값은 Job에 실려 하드 필터 세 곳(hard_filter.py / local_job_matcher.dart /
jobCoach.ts)이 같은 규칙으로 통과·확인 필요를 판정한다.

원칙: 공고에 적혀 있고 이력서와 맞으면 통과, 맞는지 확인할 수 없으면 확인 필요.
"관련 전공"처럼 경계가 흐린 요건은 불일치로 탈락시키지 않는다.

전공은 사람이 읽는 표시명(`majors`)과, 이력서 전공 문자열에 부분 일치시킬 정규화
용어(`major_terms`)를 따로 둔다. 매처는 용어 목록만 부분 일치시키면 되므로 세 언어에
전공 사전을 복제하지 않아도 된다.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# 표시명 → (공고 줄에서 이 그룹을 알아보는 단서, 이력서 전공에 부분 일치시킬 용어)
MAJOR_GROUPS: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    "컴퓨터·소프트웨어": (
        ("컴퓨터", "전산", "소프트웨어", "정보통신", "정보보호", "정보시스템", "정보공학", "컴공", "인공지능", "데이터"),
        ("컴퓨터", "전산", "소프트웨어", "정보통신", "정보보호", "정보시스템", "정보공학", "컴공", "인공지능", "데이터", "ai"),
    ),
    "전자·전기": (
        ("전자", "전기", "반도체", "제어", "통신공학"),
        ("전자", "전기", "반도체", "제어", "통신"),
    ),
    "통계·수학": (
        ("통계", "수학", "수리"),
        ("통계", "수학", "수리"),
    ),
    "산업·경영공학": (
        ("산업공학", "산업경영", "경영정보", "mis"),
        ("산업공학", "산업경영", "경영정보", "mis"),
    ),
    "기계·자동차": (
        ("기계", "자동차", "메카트로닉스"),
        ("기계", "자동차", "메카트로닉스"),
    ),
    "이공계": (
        ("이공계", "공학계열", "이과", "자연과학", "공대"),
        ("공학", "과학", "이학", "컴퓨터", "전산", "소프트웨어", "전자", "전기", "수학", "통계", "물리", "화학", "기계"),
    ),
}

_MAJOR_CONTEXT = re.compile(r"전공|학과|계열|학사|졸업")
_MAJOR_ANY = re.compile(r"(전공|학과|학력)\s*(무관|불문)|무관")

CERTIFICATIONS: tuple[str, ...] = (
    "정보처리기사", "정보처리산업기사", "정보보안기사", "정보보안산업기사", "네트워크관리사",
    "리눅스마스터", "빅데이터분석기사", "데이터분석준전문가", "데이터분석전문가",
    "SQLD", "SQLP", "ADsP", "ADP", "DAsP", "DAP",
    "AWS Certified", "AWS SAA", "CCNA", "CCNP", "PMP", "CISA", "CISSP",
    "컴퓨터활용능력", "워드프로세서", "전기기사", "산업안전기사", "일반기계기사",
    "OPIc", "OPIC", "TOEIC", "토익", "토스", "TOEIC Speaking", "TEPS", "JLPT", "HSK",
)
_CERT_CONTEXT = re.compile(r"자격|기사|certified|opic|toeic|토익|토스|teps|jlpt|hsk|sqld|adsp", re.IGNORECASE)
_GENERIC_GISA = re.compile(r"([가-힣A-Za-z]{2,12}(?:산업)?기사)")
_MILITARY = re.compile(r"병역|군필|군\s*복무")
_MILITARY_DONE = re.compile(r"필|면제|마친|완료")


@dataclass
class Qualifications:
    majors: list[str] = field(default_factory=list)
    major_terms: list[str] = field(default_factory=list)
    certifications: list[str] = field(default_factory=list)
    military_required: bool = False
    evidence: dict[str, list[str]] = field(default_factory=lambda: {"majors": [], "certifications": [], "military": []})


def normalize_term(text: str) -> str:
    """공백·기호를 지우고 소문자로. 매처 세 곳이 같은 정규화를 쓴다."""
    return re.sub(r"[\s\-_/·.()\[\]]", "", text).lower()


def extract_qualifications(required_lines: list[str]) -> Qualifications:
    """자격요건 구간의 줄 목록에서 전공·자격증·병역 조건을 뽑는다. '우대' 줄은 건너뛴다."""
    result = Qualifications()
    seen_groups: list[str] = []
    for raw in required_lines:
        line = raw.strip()
        if not line or "우대" in line:
            continue
        lowered = line.lower()

        if _MAJOR_CONTEXT.search(line) and not _MAJOR_ANY.search(line):
            for name, (cues, terms) in MAJOR_GROUPS.items():
                if name in seen_groups:
                    continue
                if any(cue.lower() in lowered for cue in cues):
                    seen_groups.append(name)
                    result.majors.append(name)
                    for term in terms:
                        normalized = normalize_term(term)
                        if normalized not in result.major_terms:
                            result.major_terms.append(normalized)
                    result.evidence["majors"].append(line)

        if _CERT_CONTEXT.search(line):
            found: list[str] = []
            for cert in CERTIFICATIONS:
                if normalize_term(cert) in normalize_term(line):
                    found.append(cert)
            for match in _GENERIC_GISA.findall(line):
                if not any(normalize_term(match) in normalize_term(c) or normalize_term(c) in normalize_term(match) for c in found):
                    found.append(match)
            for cert in found:
                if not any(normalize_term(cert) == normalize_term(c) for c in result.certifications):
                    result.certifications.append(cert)
            if found:
                result.evidence["certifications"].append(line)

        if _MILITARY.search(line) and _MILITARY_DONE.search(line) and "무관" not in line:
            result.military_required = True
            result.evidence["military"].append(line)
    return result
