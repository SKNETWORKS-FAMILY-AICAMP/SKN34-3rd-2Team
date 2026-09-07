"""파이프라인 자체 검증.

공고 건수 같은 fixture 개수를 그대로 박아두면 공고 하나만 추가해도 깨진다.
그래서 개수 대신 관계를 확인한다. 예를 들어 "IT 5건"이 아니라
"통과한 공고는 모두 INCLUDE이고 통과 + 제외 = 전체"를 본다.
"""

from __future__ import annotations

from typing import Any

from job_matching_bot.ingestion.it_filter import classify_it_job
from job_matching_bot.schemas.job_posting import Job

# Hard Filter가 의미 있게 동작하는지 보려면 세 상태가 모두 재현돼야 한다.
EXPECTED_FILTER_STATUSES = {"PASS", "CHECK_REQUIRED", "FAIL"}

# 명시적인 기술요건과 신입 조건을 모두 갖춘 공고. 1순위로 올라와야 정상이다.
EXPECTED_TOP_JOB_ID = "MOCK-BE-001"


def build_checks(
    *,
    records: list[dict[str, Any]],
    normalized_jobs: list[Job],
    all_jobs: list[Job],
    it_jobs: list[Job],
    hard_filter_results: list[dict[str, Any]],
    selected_job: Job,
    skill_analysis: dict[str, Any],
) -> list[dict[str, Any]]:
    judgement_by_skill = {
        item["criterion"]: item["judgement"] for item in skill_analysis["judgements"]
    }
    statuses = {item["result"]["status"] for item in hard_filter_results}
    excluded = [job for job in all_jobs if job not in it_jobs]
    confirmed_missing = {
        criterion
        for criterion, judgement in judgement_by_skill.items()
        if judgement == "CONFIRMED_MISSING"
    }
    recommended_skills = {
        item["skill"] for item in skill_analysis["learning_recommendations"]
    }

    return [
        {
            "name": "잡코리아 수집본이 모두 공통 스키마로 정규화됨",
            "passed": len(normalized_jobs) == len(records) and len(records) > 0,
        },
        {
            "name": "source + source_job_id 중복 없이 병합됨",
            "passed": len({(job.source, job.source_job_id) for job in all_jobs})
            == len(all_jobs),
        },
        {
            "name": "IT 필터 통과 공고는 모두 IT 직무 근거를 가짐",
            "passed": bool(it_jobs)
            and all(classify_it_job(job)["status"] == "INCLUDE" for job in it_jobs),
        },
        {
            "name": "IT 통과 + 비IT 제외 = 전체 공고",
            "passed": len(it_jobs) + len(excluded) == len(all_jobs),
        },
        {
            "name": "Hard Filter가 PASS/CHECK_REQUIRED/FAIL을 구분",
            "passed": statuses == EXPECTED_FILTER_STATUSES,
        },
        {
            "name": "명시 기술요건이 있는 백엔드 공고가 1순위",
            "passed": selected_job.job_id == EXPECTED_TOP_JOB_ID,
        },
        {
            "name": "근거 없는 역량은 NOT_EVIDENCED로 유지",
            "passed": judgement_by_skill.get("Redis") == "NOT_EVIDENCED",
        },
        {
            "name": "사용자 확인이 있는 역량만 CONFIRMED_MISSING",
            "passed": judgement_by_skill.get("Kubernetes") == "CONFIRMED_MISSING",
        },
        {
            "name": "학습 추천은 CONFIRMED_MISSING 항목에서만 생성",
            "passed": recommended_skills <= confirmed_missing and bool(recommended_skills),
        },
    ]
