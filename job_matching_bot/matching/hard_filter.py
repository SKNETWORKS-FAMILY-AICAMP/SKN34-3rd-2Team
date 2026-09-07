"""명시 조건 기반 Hard Filter.

확인할 수 없는 조건은 탈락으로 단정하지 않고 `CHECK_REQUIRED`로 남긴다.
공고에 적혀 있지 않은 것과 지원자가 충족하지 못한 것은 다르다.
"""

from __future__ import annotations

import re
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


NATIONWIDE = "전국"


def is_nationwide(job_region: str) -> bool:
    """공고 지역이 '전국'을 포함하면 어느 희망 지역이든 통과시킨다.

    local_job_matcher.dart / jobCoach.ts 의 같은 규칙과 맞춰야 한다.
    """
    return NATIONWIDE in job_region


def normalize_term(text: str) -> str:
    """공백·기호를 지우고 소문자로. qualifications.py 및 다른 매처와 같은 정규화."""
    return re.sub(r"[\s\-_/·.()\[\]]", "", text).lower()


def _qualification_checks(job: Job, resume: ResumeProfile, passed: list[str], unknown: list[str]) -> None:
    """전공·자격증·병역. 맞으면 통과, 확인할 수 없으면 확인 필요. 탈락시키지 않는다."""
    if job.required_majors:
        resume_majors = [m.strip() for m in resume.majors if m.strip()]
        if not resume_majors:
            unknown.append(f"전공 확인 필요: {', '.join(job.required_majors)}")
        else:
            matched = [
                m for m in resume_majors
                if any(term and term in normalize_term(m) for term in job.required_major_terms)
            ]
            if matched:
                passed.append(f"전공 요건 충족: {matched[0]}")
            else:
                unknown.append(
                    f"전공 요건 미확인: 공고 {', '.join(job.required_majors)} / 이력서 {', '.join(resume_majors)}"
                )
    resume_certs = [normalize_term(c) for c in resume.certifications if c.strip()]
    for cert in job.required_certifications:
        key = normalize_term(cert)
        if any(key and (key in c or c in key) for c in resume_certs):
            passed.append(f"자격증 요건 충족: {cert}")
        else:
            unknown.append(f"자격증 확인 필요: {cert}")
    if job.military_required:
        unknown.append("병역 조건 확인 필요 (병역필 또는 면제)")


def hard_filter(job: Job, resume: ResumeProfile) -> dict[str, Any]:
    failed: list[str] = []
    unknown: list[str] = []
    passed: list[str] = []

    if job.status != "OPEN":
        failed.append(f"공고 상태 {job.status}")
    else:
        passed.append("공고 진행 중")

    # 본문이 이미지뿐이면 텍스트로 확인한 요구사항이 없다. 탈락이 아니라 확인 필요다.
    if job.body_is_image:
        unknown.append("공고 상세가 이미지라 요구사항 미확인")

    if job.career_type == "EXPERIENCED":
        if job.min_career_years is None:
            # "경력자"라고만 쓰고 연차가 없는 공고. 경력이 있으면 충족이다. "얼마나"를 모를
            # 뿐 "경력을 원한다"는 적혀 있으니 신입에게는 확인 필요로 남긴다.
            if resume.career_years >= 1:
                passed.append("경력 조건 충족 (연차 미기재, 경력 보유)")
            else:
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

    _qualification_checks(job, resume, passed, unknown)

    if job.region == "미기재":
        unknown.append("근무지역 미기재")
    elif is_nationwide(job.region) or NATIONWIDE in resume.preferred_regions:
        # 공고가 전국 근무이거나 사용자가 전국을 골랐으면 지역은 따지지 않는다.
        passed.append("전국 근무 가능 — 지역 조건 충족")
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
