"""중복 제거와 수집 레코드 직렬화.

`to_collection_record`가 만드는 형태는 추천·검색 쪽(Functions, Flutter)이
그대로 읽는 공용 계약이므로 필드 이름을 임의로 바꾸지 않는다.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from job_matching_bot.config import AS_OF
from job_matching_bot.schemas.job_posting import Job


def deduplicate(jobs: list[Job]) -> list[Job]:
    """같은 공고는 `source + source_job_id` 기준으로 마지막 값만 남긴다."""
    by_key: dict[tuple[str, str], Job] = {}
    for job in jobs:
        by_key[(job.source, job.source_job_id)] = job
    return list(by_key.values())


def _date_only(value: str | None) -> str | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date().isoformat()
    except ValueError:
        return value


def to_collection_record(job: Job, collected_at: datetime = AS_OF) -> dict[str, Any]:
    """추천·검색 API가 바로 사용할 수 있는 채용공고 수집 레코드.

    `career_type`은 신입·경력 조건, `employment_type`은 정규직·계약직 같은
    고용형태다. 두 값은 의미가 다르므로 서로 대체해 쓰지 않는다.
    """
    return {
        "id": job.job_id,
        "company": job.company,
        "position": job.title,
        "career_type": job.career_type,
        "min_career_years": job.min_career_years,
        # 소비자(Functions)가 Hard Filter에 그대로 쓰므로 학력·상태도 함께 넘긴다.
        "education": job.education,
        "status": job.status,
        "employment_type": job.employment_type,
        "location": job.region,
        "deadline": _date_only(job.deadline),
        "required_skills": job.required_skills,
        "preferred_skills": job.preferred_skills,
        "tech_stack": job.tech_stack,
        "description": job.description,
        "source": job.source,
        "source_url": job.source_url,
        "collected_at": collected_at.date().isoformat(),
    }
