"""근거 기반 Skill Gap 분석.

이력서에 어떤 기술이 적혀 있지 않다는 이유만으로 경험이 없다고 단정하지
않는다. 판정은 세 갈래로 나뉘고, 각 갈래마다 다음 행동이 다르다.

- `EVIDENCED`        근거 확인 → 표현이 부족하면 이력서 피드백
- `NOT_EVIDENCED`    근거 불충분 → 사용자에게 확인 질문
- `CONFIRMED_MISSING` 사용자가 경험 없음을 확인 → 학습 추천

판정 대상은 세 층이다. `REQUIRED`/`PREFERRED`는 LLM이 본문에서 가른 것이고,
`DECLARED`는 기업이 공고 등록 때 고른 기술스택 태그다. 태그에는 필수·우대
구분이 없지만 "이 공고가 언급한 기술"인 건 분명하므로 판정은 같이 한다.
같은 기술이 여러 층에 있으면 더 구체적인 층(REQUIRED > PREFERRED > DECLARED)
하나로만 판정한다.
"""

from __future__ import annotations

from typing import Any

from job_matching_bot.coach.learning_catalog import find_learning_item
from job_matching_bot.matching.skill_normalize import canonical_set, canonical_skill
from job_matching_bot.schemas.job_posting import Job
from job_matching_bot.schemas.resume import ResumeProfile

METHOD = "deterministic_fixture_rule"

# 층 이름 → 공고 근거에 적을 표현
_TIER_LABEL = {"REQUIRED": "REQUIRED", "PREFERRED": "PREFERRED", "DECLARED": "기술스택 태그"}


def analyze_skill_evidence(job: Job, resume: ResumeProfile) -> dict[str, Any]:
    resume_keys = canonical_set(resume.skills)
    project_keys = canonical_set(resume.project_skills)
    confirmed_missing = canonical_set(resume.confirmed_missing_skills)
    judgements: list[dict[str, Any]] = []
    feedback: list[str] = []
    learning: list[dict[str, Any]] = []
    seen: set[str] = set()

    for requirement_type, values in (
        ("REQUIRED", job.required_skills),
        ("PREFERRED", job.preferred_skills),
        ("DECLARED", job.tech_stack),
    ):
        for skill in values:
            key = canonical_skill(skill)
            if not key or key in seen:
                continue
            seen.add(key)

            if key in resume_keys:
                evidence = [f"기술스택: {skill}"]
                if key in project_keys:
                    evidence.append(f"프로젝트 기술: {skill}")
                else:
                    # 경험은 있으나 표현이 부족한 경우 → 이력서를 대신 고치지 않고 피드백만 준다.
                    feedback.append(
                        f"{skill}: 기술스택에는 있으나 프로젝트에서 사용한 기능·역할·결과 근거를 보강하세요."
                    )
                judgement = "EVIDENCED"
                question = None
            elif key in confirmed_missing:
                evidence = [f"사용자 확인: {skill} 실사용 경험 없음"]
                judgement = "CONFIRMED_MISSING"
                question = None
                catalog_item = find_learning_item(skill)
                if catalog_item:
                    learning.append({"skill": skill, **catalog_item})
            else:
                evidence = []
                judgement = "NOT_EVIDENCED"
                question = f"이력서에서는 {skill} 경험을 확인하지 못했습니다. 실제 사용 경험이 있나요?"

            judgements.append(
                {
                    "criterion": skill,
                    "requirement_type": requirement_type,
                    "judgement": judgement,
                    "resume_evidence": evidence,
                    "job_evidence": [f"{_TIER_LABEL[requirement_type]}: {skill}"],
                    "confirmation_question": question,
                    "confidence": 1.0,
                    "method": METHOD,
                }
            )

    return {
        "judgements": judgements,
        "resume_feedback": feedback,
        "learning_recommendations": learning,
    }
