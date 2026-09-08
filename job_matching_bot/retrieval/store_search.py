"""저장소에서 조건으로 공고를 찾는다. 챗봇 "공고 찾아보기"가 쓴다.

추천(`api/service.py`)과 목적이 다르다. 추천은 이력서를 읽고 **뜻이 가까운** 공고를
벡터로 찾지만, 여기는 사용자가 말한 **조건에 맞는** 공고를 고른다. "서울 백엔드 신입"은
해석이 갈릴 여지가 없으니 벡터가 필요 없고, 조건 조회가 정확하고 빠르다.

그래서 Pinecone이 아니라 저장소(SQLite)를 본다. 인덱스에는 요건 문장이 있는 IT 인접
공고만 올라가지만, 저장소에는 **모든 카테고리**가 있다. "생산관리 신입 있어?"에도
답하려면 저장소여야 한다.
"""

from __future__ import annotations

import json
import re
import sqlite3
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

KST = timezone(timedelta(hours=9))

# 한 번에 훑을 최대 행. 조건이 헐거우면 수만 건이 걸리므로 상한을 둔다.
SCAN_LIMIT = 3000

# 사용자가 말하는 경력 표현 → 저장소의 career_type
CAREER_TYPES = {"신입": ("ENTRY", "ANY"), "경력": ("EXPERIENCED", "ANY"), "무관": None}

# 접두사인데 **뜻이 다른** 말. 이것만 막는다.
#
# `LIKE '%Java%'` 는 JavaScript 도 걸린다. 실측으로 "Java" 검색 2,004건 중 198건(15%)이
# Java 태그 없이 Javascript 만 있는 공고였다. 그렇다고 단어 경계로 일괄 차단하면 안 된다.
# 기술 태그 220종에서 접두사 쌍 11개 중 10개는 같은 계열이라(Spring⊂SpringBoot,
# React⊂ReactJS, HTML⊂HTML5, 임베디드⊂임베디드리눅스 …) 막으면 열 곳이 나빠지고 한 곳만
# 고쳐진다. 뜻이 갈리는 것만 여기 적는다.
#
# 값은 그 말을 찾을 정규식이다. 형태가 제각각이라 규칙 하나로 못 묶는다.
#
# 후보는 `python -m job_matching_bot.evaluation.scan_terms` 로 뽑는다. 태그가 늘면
# 다시 돌려 새로 생긴 겹침만 보면 된다. 판단은 사람이 한다 — "같은 계열인가"는
# 글자로 알 수 없다.
CONFUSABLE = {
    # 뒤를 본다. JavaScript 는 Java 가 아니다.
    "java": r"java(?!script)",
    "자바": r"자바(?!스크립트)",
    # 앞뒤를 다 본다. MongoDB·Django·Google 의 "go" 는 Go 가 아니다. GoLang 은 맞다.
    # 두 글자짜리라 어쩔 수 없이 "Go-to-market" 같은 말은 남는다.
    "go": r"(?<![a-z])go(?:lang)?(?![a-z])",
}


def _like_or_regex(column: str, term: str) -> tuple[str, list[object]]:
    """한 컬럼에서 한 말을 찾는 조건. 헷갈리는 말이면 뒤에 오는 글자를 본다.

    돌려주는 것은 (SQL 조각, 값 목록)이다. 값 개수가 조건마다 다르므로 함께 돌려준다.
    """
    pattern = CONFUSABLE.get(term.strip().lower())
    if not pattern:
        return f"{column} LIKE ?", [f"%{term}%"]
    # 한 공고에 Java 와 Javascript 가 둘 다 있으면 Java 쪽이 걸린다. 빼면 진짜 Java
    # 공고를 잃는다.
    return f"RE_HAS(?, {column})", [pattern]


def _re_has(pattern: str, text: str | None) -> int:
    """SQLite에 등록해 쓰는 함수. 대소문자를 가리지 않는다."""
    if not text:
        return 0
    return 1 if re.search(pattern, text, re.IGNORECASE) else 0


def connect(store_path: Path) -> sqlite3.Connection:
    """읽기 전용으로 열고 `RE_HAS` 를 등록한다. 검색과 집계가 같이 쓴다."""
    connection = sqlite3.connect(
        f"{Path(store_path).resolve().as_uri()}?mode=ro", uri=True
    )
    connection.row_factory = sqlite3.Row
    connection.create_function("RE_HAS", 2, _re_has, deterministic=True)
    return connection


@dataclass
class JobFilters:
    """대화에서 뽑아낸 검색 조건. 다음 turn에 그대로 돌려주어 이어서 좁힌다."""

    roles: list[str] = field(default_factory=list)          # 직무 (백엔드, 데이터분석)
    skills: list[str] = field(default_factory=list)         # 기술 (Python, React)
    regions: list[str] = field(default_factory=list)        # 시·도 (서울, 경기)
    career: str = "무관"                                     # 신입 / 경력 / 무관
    employment_types: list[str] = field(default_factory=list)
    deadline_within_days: int | None = None                 # 마감 임박만 보기
    keywords: list[str] = field(default_factory=list)       # 그 밖의 말

    @property
    def is_empty(self) -> bool:
        return not any(
            [self.roles, self.skills, self.regions, self.employment_types,
             self.keywords, self.deadline_within_days, self.career != "무관"]
        )

    def summary(self) -> str:
        """무엇으로 걸렀는지 사람 말로. 해석이 틀렸을 때 사용자가 알아채야 한다."""
        parts = [
            *self.roles, *self.skills,
            *(f"{region}" for region in self.regions),
            *self.employment_types,
        ]
        if self.career != "무관":
            parts.append(self.career)
        if self.deadline_within_days:
            parts.append(f"{self.deadline_within_days}일 내 마감")
        parts.extend(self.keywords)
        return " · ".join(parts) if parts else "조건 없음"


@dataclass
class JobHit:
    """찾은 공고 한 건. `relevance`는 사용자가 말한 말이 **어디에** 있었는지다."""

    job_id: str
    company: str
    title: str
    source_url: str
    region: str
    career_label: str
    employment_type: str
    deadline: str | None
    tech_stack: list[str]
    relevance: int = 0   # 3 제목 · 2 직무·기술 태그 · 1 본문에만


@dataclass
class SearchResult:
    jobs: list[JobHit]
    total: int          # 조건에 맞는 전체 건수 (보여 준 것보다 많을 수 있다)
    scanned_cap: bool   # 상한에 걸려 세다 만 경우
    strong: int         # 그중 제목·태그에 직접 맞은 건수


# 공고 한 건을 만드는 데 필요한 컬럼. 조건 검색과 의미 검색이 같은 것을 읽는다.
_HIT_COLUMNS = (
    "job_id, company, title, source_url, region, career_type, min_career_years, "
    "employment_type, deadline, tech_stack"
)


def _to_hit(row, relevance: int) -> JobHit:
    return JobHit(
        job_id=row["job_id"],
        company=row["company"] or "",
        title=row["title"] or "",
        source_url=row["source_url"] or "",
        region=row["region"] or "미기재",
        career_label=_career_label(row["career_type"] or "", row["min_career_years"]),
        employment_type=row["employment_type"] or "미기재",
        deadline=(row["deadline"] or None),
        tech_stack=json.loads(row["tech_stack"] or "[]"),
        relevance=relevance,
    )


def _career_label(career_type: str, min_years: int | None) -> str:
    if career_type == "ENTRY":
        return "신입"
    if career_type == "EXPERIENCED":
        return "경력" if min_years is None else f"경력 {min_years}년 이상"
    if career_type == "ANY":
        return "경력무관"
    return "미기재"


def _terms(filters: JobFilters) -> list[str]:
    """공고 글에서 찾을 말. 직무·기술·자유 키워드를 합친다."""
    seen: list[str] = []
    for term in [*filters.roles, *filters.skills, *filters.keywords]:
        term = term.strip()
        if term and term not in seen:
            seen.append(term)
    return seen


def conditions(filters: JobFilters, as_of: datetime) -> tuple[list[str], list[object]]:
    """조건을 WHERE 절과 값으로. 검색(`search`)과 집계(`market_stats`)가 같이 쓴다.

    조건이 여럿이면 **모두 만족**해야 한다. 직무·기술 말은 그중 하나만 맞아도 된다 —
    "백엔드 파이썬"이라고 하면 둘 다 적힌 공고만 남기는 것보다 하나라도 걸리는 편이 낫다.

    두 곳이 같은 함수를 쓰는 것이 중요하다. "412건 중 Spring 61%"라고 말해 놓고 목록에는
    다른 모수의 공고가 나오면 답이 거짓말이 된다.
    """
    today = as_of.date().isoformat()
    where = ["status = 'OPEN'", "(deadline IS NULL OR substr(deadline, 1, 10) >= ?)"]
    params: list[object] = [today]

    if filters.regions:
        where.append("(" + " OR ".join("region LIKE ?" for _ in filters.regions) + ")")
        params.extend(f"%{region}%" for region in filters.regions)

    types = CAREER_TYPES.get(filters.career)
    if types:
        where.append("career_type IN (" + ", ".join("?" for _ in types) + ")")
        params.extend(types)

    if filters.employment_types:
        where.append("(" + " OR ".join("employment_type LIKE ?" for _ in filters.employment_types) + ")")
        params.extend(f"%{value}%" for value in filters.employment_types)

    if filters.deadline_within_days:
        until = (as_of + timedelta(days=filters.deadline_within_days)).date().isoformat()
        where.append("deadline IS NOT NULL AND substr(deadline, 1, 10) <= ?")
        params.append(until)

    # 직무·기술은 제목·분류 태그·기술 태그·본문 어디에 있어도 맞은 것으로 본다.
    terms = _terms(filters)
    if terms:
        clauses = []
        for term in terms:
            parts = []
            for column in ("title", "keywords", "tech_stack", "description"):
                sql, values = _like_or_regex(column, term)
                parts.append(sql)
                params.extend(values)
            clauses.append("(" + " OR ".join(parts) + ")")
        where.append("(" + " OR ".join(clauses) + ")")

    return where, params


def search(
    store_path: Path, filters: JobFilters, limit: int = 5, as_of: datetime | None = None
) -> SearchResult:
    """조건에 맞는 공고를 관련도 순으로. (보여 줄 것, 전체 건수)."""
    as_of = as_of or datetime.now(KST)
    where, params = conditions(filters, as_of)

    # 어디에서 맞았는지로 순서를 가른다. 본문만 훑으면 "신입/경력 공개채용" 같은 범용
    # 공고가 온갖 직무 말을 다 담고 있어서 무엇을 물어도 같은 공고가 올라온다.
    # 제목에 있으면 그 일을 뽑는 공고이고, 태그에 있으면 기업이 그렇게 분류한 것이다.
    terms = _terms(filters)
    relevance = "0"
    # CASE 식이 SELECT에 들어가므로 그 물음표 값을 따로 모은다. 제목 먼저, 그다음 태그 둘씩.
    case_params: list[object] = []
    if terms:
        title_parts, tag_parts = [], []
        for term in terms:
            sql, values = _like_or_regex("title", term)
            title_parts.append(sql)
            case_params.extend(values)
        for term in terms:
            pieces = []
            for column in ("keywords", "tech_stack"):
                sql, values = _like_or_regex(column, term)
                pieces.append(sql)
                case_params.extend(values)
            tag_parts.append("(" + " OR ".join(pieces) + ")")
        relevance = (
            f"CASE WHEN {' OR '.join(title_parts)} THEN 3 "
            f"WHEN {' OR '.join(tag_parts)} THEN 2 ELSE 1 END"
        )

    sql = (
        f"SELECT {_HIT_COLUMNS}, {relevance} AS relevance FROM jobs WHERE "
        + " AND ".join(where)
        # 관련도가 같으면 태그를 적게 단 공고를 먼저. 직무 태그를 열 개씩 달아 둔
        # "전 직군 공개채용"은 무엇을 물어도 걸리므로, 그 일에 특화된 공고에 자리를 내준다.
        + " ORDER BY relevance DESC, LENGTH(keywords) ASC, first_seen_at DESC LIMIT ?"
    )

    # ORDER BY는 별칭을 쓰므로 값이 없다. 순서는 SELECT → WHERE → LIMIT.
    connection = connect(store_path)
    try:
        rows = connection.execute(sql, [*case_params, *params, SCAN_LIMIT]).fetchall()
    finally:
        connection.close()

    jobs = [_to_hit(row, int(row["relevance"] or 0)) for row in rows[:limit]]
    return SearchResult(
        jobs=jobs,
        total=len(rows),
        scanned_cap=len(rows) >= SCAN_LIMIT,
        strong=sum(1 for row in rows if int(row["relevance"] or 0) >= 2),
    )


def by_ids(
    store_path: Path, job_ids: list[str], as_of: datetime | None = None
) -> list[JobHit]:
    """job_id 목록을 **준 순서 그대로** 꺼낸다. 벡터 검색이 매긴 순서가 곧 관련도다.

    마감했거나 내려간 공고는 뺀다. 인덱스는 밤에 한 번 갱신되므로 낮 동안 마감된 것이
    남아 있을 수 있다. 저장소가 먼저 안다.
    """
    if not job_ids:
        return []
    as_of = as_of or datetime.now(KST)
    today = as_of.date().isoformat()

    placeholders = ", ".join("?" for _ in job_ids)
    sql = (
        f"SELECT {_HIT_COLUMNS} FROM jobs WHERE job_id IN ({placeholders}) "
        "AND status = 'OPEN' AND (deadline IS NULL OR substr(deadline, 1, 10) >= ?)"
    )
    connection = connect(store_path)
    try:
        rows = connection.execute(sql, [*job_ids, today]).fetchall()
    finally:
        connection.close()

    found = {row["job_id"]: row for row in rows}
    # relevance는 0으로 둔다. 이 목록의 순서는 글자가 어디에 있었는지가 아니라 뜻이
    # 얼마나 가까운지로 매겨졌으므로, 조건 검색의 점수와 섞어 쓸 수 없다.
    return [_to_hit(found[job_id], 0) for job_id in job_ids if job_id in found]
