"""추천 Ranking.

점수는 합격 확률이 아니라 공고 간 정렬을 위한 POC 값이다. 가중치는
제품 품질 수치가 아니며 별도 평가 세트로 조정해야 한다.

기술 점수는 **공고가 언급한 기술 전체**와 이력서 기술의 겹침이다. 필수/우대를
따로 채점하지 않는다. 실제 수집본에서 LLM이 필수/우대를 가른 공고는 15건 중
1건이었고, 기업이 등록 때 고른 기술스택 태그는 13건에 있었다. 없는 구분에
가중치를 걸어 두면 그 몫이 통째로 0이 된다. 필수/우대 구분은 코치(무엇을 먼저
보강할지)에서 쓰고, 랭킹에서는 어느 출처에서 왔든 한 목록으로 본다.
어떤 출처가 기여했는지는 `score_detail.skills_source`에 남긴다.

기술명 비교는 `skill_normalize.canonical_skill`로 한다. `Spring Boot`와
`SpringBoot`가 불일치로 잡히면 기술스택을 신호로 쓰는 의미가 없다.

functions/src/jobCoach.ts 의 rankJobs 와 같은 규칙이다.
"""

from __future__ import annotations

from typing import Any

from job_matching_bot.matching.hard_filter import hard_filter
from job_matching_bot.matching.skill_normalize import canonical_set, canonical_skill
from job_matching_bot.schemas.job_posting import Job
from job_matching_bot.schemas.resume import ResumeProfile
from job_matching_bot.text_match import compile_terms, matched_terms

# 점수 가중치 합은 1.0이다. 변경하면 산출물과 보고서 수치가 함께 움직인다.
# functions/src/jobCoachScoring.ts 의 WEIGHTS 와 같아야 한다.
WEIGHT_ROLE = 0.35
WEIGHT_SKILLS = 0.45
WEIGHT_PROJECT = 0.10
WEIGHT_CONDITIONS = 0.10

# 직무 유사도 점수는 이 개수만큼 키워드가 맞으면 만점으로 본다.
ROLE_HITS_FOR_FULL_SCORE = 3

# 기술 점수 분모의 하한. 공고가 기술을 1개만 적었을 때 1/1 = 1.0이 되어
# 7개 중 5개 맞은 공고(0.71)를 이기는 것을 막는다. 적게 적은 공고가
# 유리해지면 안 된다. 실제 공고는 대개 4개 이상 적는다.
SKILL_POOL_FLOOR = 4

GRADE_HIGH_THRESHOLD = 70
GRADE_MEDIUM_THRESHOLD = 40

# 희망 직무 → 공고 텍스트에서 찾을 키워드. 목록에 없는 직무는 직무명 자체로 찾는다.
# functions/src/jobCoach.ts 의 ROLE_TERMS 와 같아야 한다.
ROLE_TERMS = {
    "백엔드 개발자": ["백엔드", "backend", "fastapi", "django", "api", "전산", "시스템운영"],
    "AI 엔지니어": ["ai engineering", "ai", "인공지능", "머신러닝", "추천 시스템", "데이터"],
    "프론트엔드 개발자": ["프론트엔드", "frontend", "front-end", "react", "vue", "웹개발", "ui개발"],
    "데이터 엔지니어": ["데이터엔지니어", "데이터 엔지니어", "data engineer", "데이터", "etl", "spark", "빅데이터"],
    "임베디드 개발자": ["임베디드", "embedded", "펌웨어", "firmware", "rtos", "h/w"],
}

# 기술 목록을 만드는 출처. 순서는 같은 기술이 여러 출처에 있을 때 표시용
# 원문을 어디서 가져올지 정한다.
SKILL_SOURCES = ("required_skills", "preferred_skills", "tech_stack")


def declared_skills(job: Job) -> tuple[dict[str, str], list[str]]:
    """공고가 언급한 기술. (표준 키 → 표시용 원문, 기여한 출처 목록)을 돌려준다."""
    pool: dict[str, str] = {}
    sources: list[str] = []
    for source in SKILL_SOURCES:
        values = getattr(job, source)
        if values:
            sources.append(source)
        for value in values:
            pool.setdefault(canonical_skill(value), value)
    return pool, sources


def _role_score(resume: ResumeProfile, job: Job) -> tuple[float, list[str]]:
    terms: list[str] = []
    for role in resume.target_roles:
        terms.extend(ROLE_TERMS.get(role, [role.lower()]))
    hits = matched_terms(job.matching_text(), compile_terms(terms))
    return min(1.0, len(hits) / ROLE_HITS_FOR_FULL_SCORE), hits


def _skill_score(resume_keys: set[str], pool: dict[str, str]) -> tuple[float, list[str]]:
    """겹치는 비율과, 겹친 기술의 공고 쪽 원문 표기."""
    if not pool:
        return 0.0, []
    matched = sorted(pool[key] for key in pool if key in resume_keys)
    return len(matched) / max(len(pool), SKILL_POOL_FLOOR), matched


def _grade(score: float) -> str:
    if score >= GRADE_HIGH_THRESHOLD:
        return "높음"
    return "보통" if score >= GRADE_MEDIUM_THRESHOLD else "낮음"


def rank_jobs(jobs: list[Job], resume: ResumeProfile) -> list[dict[str, Any]]:
    """Hard Filter를 통과했거나 확인이 필요한 공고를 점수 순으로 정렬한다."""
    resume_keys = canonical_set(resume.skills)
    project_keys = canonical_set(resume.project_skills)
    ranked = []
    for job in jobs:
        filter_result = hard_filter(job, resume)
        if filter_result["status"] == "FAIL":
            continue
        role_score, role_hits = _role_score(resume, job)
        pool, sources = declared_skills(job)
        skill_score, skill_hits = _skill_score(resume_keys, pool)
        # 프로젝트 경험은 공고가 언급한 기술 어디에 닿아도 근거가 된다.
        project_score, project_hits = _skill_score(project_keys, pool)
        condition_score = 1.0 if filter_result["status"] == "PASS" else 0.5
        final_score = round(
            100
            * (
                role_score * WEIGHT_ROLE
                + skill_score * WEIGHT_SKILLS
                + project_score * WEIGHT_PROJECT
                + condition_score * WEIGHT_CONDITIONS
            ),
            1,
        )
        ranked.append(
            {
                "job_id": job.job_id,
                "company": job.company,
                "title": job.title,
                "source": job.source,
                "source_url": job.source_url,
                "recommendation_score": final_score,
                "grade": _grade(final_score),
                "hard_filter": filter_result,
                "score_detail": {
                    "role": round(role_score, 3),
                    "skills": round(skill_score, 3),
                    "skills_source": sources,
                    "skills_total": len(pool),
                    "project": round(project_score, 3),
                    "conditions": condition_score,
                },
                "evidence": {
                    "role_terms": role_hits,
                    "matched_skills": skill_hits,
                    "matched_project_skills": project_hits,
                },
            }
        )
    return sorted(ranked, key=lambda item: item["recommendation_score"], reverse=True)
