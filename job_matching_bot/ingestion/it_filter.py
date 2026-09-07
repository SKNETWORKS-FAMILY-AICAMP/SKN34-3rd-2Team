"""IT 직무 사전 필터.

이 서비스의 추천 대상은 IT 직무 채용공고로 한정한다. IT 기업이 올린
비IT 직무(헤드헌팅, 영업 등)는 제외한다.
"""

from typing import Any

from job_matching_bot.schemas.job_posting import Job
from job_matching_bot.text_match import compile_terms, matched_terms

IT_JOB_TERMS = (
    "백엔드",
    "프론트엔드",
    "개발자",
    "엔지니어",
    "engineering",
    "전산",
    "시스템운영",
    "정보보안",
    "소프트웨어",
    "데이터 엔지니어",
    "ai",
    "인공지능",
    "머신러닝",
    "devops",
    "클라우드",
    "서버",
    "react",
    "fastapi",
    "python",
)

NON_IT_ROLE_TERMS = (
    "헤드헌터",
    "스카우터",
    "인재 추천",
    "사회복지사",
    "구매",
    "영업",
)

_IT_PATTERNS = compile_terms(IT_JOB_TERMS)
_NON_IT_PATTERNS = compile_terms(NON_IT_ROLE_TERMS)


def classify_it_job(job: Job) -> dict[str, Any]:
    """직무 자체가 IT인지 판정한다. IT 산업의 비IT 직무는 제외한다."""
    text = f"{job.title} {job.description}".lower()
    matched = matched_terms(text, _IT_PATTERNS)
    # 키워드/본문에는 같은 회사의 타 직무가 섞일 수 있어 제외 직무는 제목을 우선한다.
    exclusions = matched_terms(job.title.lower(), _NON_IT_PATTERNS)
    included = bool(matched) and not exclusions
    return {
        "status": "INCLUDE" if included else "EXCLUDE",
        "matched_terms": matched,
        "exclusion_terms": exclusions,
        "reason": (
            f"IT 직무 근거: {', '.join(matched)}"
            if included
            else f"비IT 직무 근거: {', '.join(exclusions)}"
            if exclusions
            else "IT 직무 근거 없음"
        ),
    }


def filter_it_jobs(jobs: list[Job]) -> list[Job]:
    return [job for job in jobs if classify_it_job(job)["status"] == "INCLUDE"]
