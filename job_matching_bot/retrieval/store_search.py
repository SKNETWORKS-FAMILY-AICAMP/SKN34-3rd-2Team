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
import sqlite3
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

KST = timezone(timedelta(hours=9))

# 한 번에 훑을 최대 행. 조건이 헐거우면 수만 건이 걸리므로 상한을 둔다.
SCAN_LIMIT = 3000

# 사용자가 말하는 경력 표현 → 저장소의 career_type
CAREER_TYPES = {"신입": ("ENTRY", "ANY"), "경력": ("EXPERIENCED", "ANY"), "무관": None}


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


def search(
    store_path: Path, filters: JobFilters, limit: int = 5, as_of: datetime | None = None
) -> SearchResult:
    """조건에 맞는 공고를 최근 등록순으로. (보여 줄 것, 전체 건수).

    조건이 여럿이면 **모두 만족**해야 한다. 직무·기술 말은 그중 하나만 맞아도 된다 —
    "백엔드 파이썬"이라고 하면 둘 다 적힌 공고만 남기는 것보다 하나라도 걸리는 편이 낫다.
    """
    as_of = as_of or datetime.now(KST)
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
    #
    # 다만 **어디에 있었는지로 순서를 가른다.** 본문만 훑으면 "신입/경력 공개채용" 같은
    # 범용 공고가 온갖 직무 말을 다 담고 있어서 무엇을 물어도 같은 공고가 올라온다.
    # 제목에 있으면 그 일을 뽑는 공고이고, 태그에 있으면 기업이 그렇게 분류한 것이다.
    terms = _terms(filters)
    relevance = "0"
    if terms:
        clauses = []
        for term in terms:
            clauses.append("(title LIKE ? OR keywords LIKE ? OR tech_stack LIKE ? OR description LIKE ?)")
            params.extend([f"%{term}%"] * 4)
        where.append("(" + " OR ".join(clauses) + ")")

        title_like = " OR ".join("title LIKE ?" for _ in terms)
        tag_like = " OR ".join("(keywords LIKE ? OR tech_stack LIKE ?)" for _ in terms)
        relevance = f"CASE WHEN {title_like} THEN 3 WHEN {tag_like} THEN 2 ELSE 1 END"

    # CASE 식이 SELECT에 들어가므로 그 물음표 값을 따로 모은다. 제목 먼저, 그다음 태그 둘씩.
    case_params: list[object] = []
    if terms:
        case_params.extend(f"%{term}%" for term in terms)
        for term in terms:
            case_params.extend([f"%{term}%"] * 2)

    sql = (
        f"SELECT job_id, company, title, source_url, region, career_type, min_career_years, "
        f"employment_type, deadline, tech_stack, {relevance} AS relevance FROM jobs WHERE "
        + " AND ".join(where)
        # 관련도가 같으면 태그를 적게 단 공고를 먼저. 직무 태그를 열 개씩 달아 둔
        # "전 직군 공개채용"은 무엇을 물어도 걸리므로, 그 일에 특화된 공고에 자리를 내준다.
        + " ORDER BY relevance DESC, LENGTH(keywords) ASC, first_seen_at DESC LIMIT ?"
    )

    # ORDER BY는 별칭을 쓰므로 값이 없다. 순서는 SELECT → WHERE → LIMIT.
    connection = sqlite3.connect(f"{Path(store_path).resolve().as_uri()}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        rows = connection.execute(sql, [*case_params, *params, SCAN_LIMIT]).fetchall()
    finally:
        connection.close()

    jobs = [
        JobHit(
            job_id=row["job_id"],
            company=row["company"] or "",
            title=row["title"] or "",
            source_url=row["source_url"] or "",
            region=row["region"] or "미기재",
            career_label=_career_label(row["career_type"] or "", row["min_career_years"]),
            employment_type=row["employment_type"] or "미기재",
            deadline=(row["deadline"] or None),
            tech_stack=json.loads(row["tech_stack"] or "[]"),
            relevance=int(row["relevance"] or 0),
        )
        for row in rows[:limit]
    ]
    return SearchResult(
        jobs=jobs,
        total=len(rows),
        scanned_cap=len(rows) >= SCAN_LIMIT,
        strong=sum(1 for row in rows if int(row["relevance"] or 0) >= 2),
    )
