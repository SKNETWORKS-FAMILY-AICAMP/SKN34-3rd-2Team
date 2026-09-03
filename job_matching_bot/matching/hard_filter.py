"""명시 조건 기반 Hard Filter.

확인할 수 없는 조건은 탈락으로 단정하지 않고 `CHECK_REQUIRED`로 남긴다.
공고에 적혀 있지 않은 것과 지원자가 충족하지 못한 것은 다르다.
"""

from __future__ import annotations

from typing import Any

from job_matching_bot.schemas.job_posting import Job
from job_matching_bot.schemas.resume import ResumeProfile

# 초대졸(전문대 2,3년제)은 고졸과 대졸 사이다. 이 표는
# functions/src/jobCoachScoring.ts 의 EDUCATION_RANK 와 같아야 한다.
EDUCATION_RANK = {"학력무관": 0, "고졸": 1, "초대졸": 2, "대졸": 3, "석사": 4, "박사": 5}


def _education_passes(resume_level: str, required_level: str) -> bool | None:
    """학력 충족 여부. 판단할 수 없으면 `None`을 돌려준다."""
    if required_level in ("학력무관", "미기재"):
        return True if required_level == "학력무관" else None
    if resume_level not in EDUCATION_RANK or required_level not in EDUCATION_RANK:
        return None
    return EDUCATION_RANK[resume_level] >= EDUCATION_RANK[required_level]


def hard_filter(job: Job, resume: ResumeProfile) -> dict[str, Any]:
    failed: list[str] = []
    unknown: list[str] = []
    passed: list[str] = []

    if job.status != "OPEN":
        failed.append(f"공고 상태 {job.status}")
    else:
        passed.append("공고 진행 중")

    if job.career_type == "EXPERIENCED":
        if job.min_career_years is None:
            unknown.append("경력 연수 미기재")
        elif resume.career_years < job.min_career_years:
            failed.append(f"최소 경력 {job.min_career_years}년")
        else:
            passed.append("경력 조건 충족")
    elif job.career_type in ("ENTRY", "ANY"):
        passed.append("경력 조건 충족")
    else:
        unknown.append("경력 조건 미기재")

    education_result = _education_passes(resume.education_level, job.education)
    if education_result is True:
        passed.append("학력 조건 충족")
    elif education_result is False:
        failed.append(f"필수 학력 {job.education}")
    else:
        unknown.append("학력 조건 미기재")

    if job.region == "미기재":
        unknown.append("근무지역 미기재")
    elif any(region in job.region for region in resume.preferred_regions):
        passed.append("희망 근무지역 일치")
    else:
        failed.append(f"희망지역 불일치: {job.region}")

    if job.employment_type == "미기재":
        unknown.append("고용형태 미기재")
    elif job.employment_type in resume.preferred_employment_types:
        passed.append("희망 고용형태 일치")
    else:
        failed.append(f"희망 고용형태 불일치: {job.employment_type}")

    status = "FAIL" if failed else "CHECK_REQUIRED" if unknown else "PASS"
    return {"status": status, "passed": passed, "failed": failed, "unknown": unknown}
