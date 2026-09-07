"""AI 취업 코치 Phase 1 Vertical Slice 오케스트레이션.

각 단계의 로직은 레이어별 모듈에 있고, 이 파일은 순서만 정한다.

    수집·정규화(ingestion) → IT 직무 필터 → Hard Filter → Ranking
    → 근거 기반 Skill Gap(coach) → 보고서(reporting)

외부 API, 로그인, LLM 호출 없이 재현 가능한 규칙 기반 테스트다.
"""

from __future__ import annotations

import json
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Any

from job_matching_bot.coach.skill_gap import analyze_skill_evidence
from job_matching_bot.config import AS_OF, DEFAULT_RESUME_MOCKS_INPUT
from job_matching_bot.exporters.dart import build_dart_module
from job_matching_bot.exporters.resume_mocks_dart import build_resume_mocks_module
from job_matching_bot.ingestion.collection import deduplicate, to_collection_record
from job_matching_bot.ingestion.it_filter import classify_it_job, filter_it_jobs
from job_matching_bot.ingestion.job_store import open_store
from job_matching_bot.ingestion.jobkorea import normalize_jobkorea
from job_matching_bot.ingestion.mock_source import mock_jobs
from job_matching_bot.matching.hard_filter import hard_filter
from job_matching_bot.matching.ranking import rank_jobs
from job_matching_bot.reporting.markdown_report import build_report
from job_matching_bot.schemas.job_posting import Job
from job_matching_bot.schemas.resume import ResumeProfile, sample_resume
from job_matching_bot.validation import build_checks


def _find_job(jobs: list[Job], job_id: str) -> Job:
    return next(job for job in jobs if job.job_id == job_id)


def load_store_jobs(store_path: Path | None) -> list[Job]:
    """수집 저장소(`ingest.py`가 쌓는 것)에서 진행 중인 공고를 읽는다.

    저장소가 없으면 빈 목록이다. 테스트는 저장소 없이 fixture만으로 돌아야
    하므로 기본값은 읽지 않는 것이고, CLI만 기본 경로를 넘긴다.
    """
    if store_path is None or not Path(store_path).exists():
        return []
    return open_store(Path(store_path)).load().active_jobs()


def collect_jobs(
    records: list[dict[str, Any]],
    as_of: datetime = AS_OF,
    store_path: Path | None = None,
) -> tuple[list[Job], list[Job], list[Job]]:
    """원본 레코드를 정규화하고 Mock·저장소 공고를 합친 뒤 IT 직무만 남긴다.

    (잡코리아 정규화본, 중복 제거된 전체, IT 직무만)을 돌려준다.
    저장소 공고를 마지막에 두어 같은 공고가 fixture에도 있으면 저장소 쪽
    (상태 전이가 반영된 것)이 남는다.
    """
    normalized = [normalize_jobkorea(record, as_of=as_of) for record in records]
    store_jobs = load_store_jobs(store_path)
    all_jobs = deduplicate(normalized + mock_jobs(as_of=as_of) + store_jobs)
    return normalized, all_jobs, filter_it_jobs(all_jobs)


def analyze(
    records: list[dict[str, Any]],
    resume: ResumeProfile | None = None,
    as_of: datetime = AS_OF,
    store_path: Path | None = None,
) -> dict[str, Any]:
    """파일 입출력 없이 파이프라인을 실행하고 결과 딕셔너리를 만든다."""
    resume = resume or sample_resume()
    normalized, all_jobs, it_jobs = collect_jobs(records, as_of=as_of, store_path=store_path)
    store_count = len(load_store_jobs(store_path))

    it_filter_results = [
        {
            "job_id": job.job_id,
            "company": job.company,
            "title": job.title,
            "result": classify_it_job(job),
        }
        for job in all_jobs
    ]
    hard_filter_results = [
        {
            "job_id": job.job_id,
            "company": job.company,
            "title": job.title,
            "result": hard_filter(job, resume),
        }
        for job in it_jobs
    ]
    recommendations = rank_jobs(it_jobs, resume)
    if not recommendations:
        raise ValueError("Hard Filter를 통과한 공고가 없어 분석을 진행할 수 없습니다.")

    selected_job = _find_job(it_jobs, recommendations[0]["job_id"])
    skill_analysis = analyze_skill_evidence(selected_job, resume)
    checks = build_checks(
        records=records,
        normalized_jobs=normalized,
        all_jobs=all_jobs,
        it_jobs=it_jobs,
        hard_filter_results=hard_filter_results,
        selected_job=selected_job,
        skill_analysis=skill_analysis,
    )

    return {
        "test_status": "PASS" if all(check["passed"] for check in checks) else "FAIL",
        "as_of": as_of.isoformat(),
        "input_summary": {
            "jobkorea": len(records),
            "store": store_count,
            "mock": len(all_jobs) - len(normalized) - store_count,
            "deduplicated": len(all_jobs),
            "it_jobs": len(it_jobs),
            "non_it_excluded": len(all_jobs) - len(it_jobs),
        },
        "resume": asdict(resume),
        "normalized_jobs": [asdict(job) for job in all_jobs],
        "collected_jobs": [to_collection_record(job, as_of) for job in it_jobs],
        "it_filter_results": it_filter_results,
        "hard_filter_results": hard_filter_results,
        "recommendations": recommendations,
        "selected_job": asdict(selected_job),
        "skill_analysis": skill_analysis,
        "checks": checks,
    }


def _write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def run_pipeline(
    input_path: Path,
    json_output: Path,
    report_output: Path,
    as_of: datetime = AS_OF,
    collection_output: Path | None = None,
    dart_output: Path | None = None,
    resume_mocks_output: Path | None = None,
    store_path: Path | None = None,
) -> dict[str, Any]:
    """입력 파일을 읽어 분석하고 산출물을 저장한다.

    `dart_output`을 주면 Flutter의 공고 검색·기술 카탈로그가 읽는 공고 데이터
    모듈도 함께 생성한다. 공고 데이터의 단일 출처를 이 파이프라인으로 유지하기
    위한 것이다.
    """
    records = json.loads(Path(input_path).read_text(encoding="utf-8"))
    result = analyze(records, as_of=as_of, store_path=store_path)

    _write_json(Path(json_output), result)
    report_path = Path(report_output)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(build_report(result), encoding="utf-8")
    if collection_output is not None:
        _write_json(Path(collection_output), result["collected_jobs"])
    if dart_output is not None:
        dart_path = Path(dart_output)
        dart_path.parent.mkdir(parents=True, exist_ok=True)
        dart_path.write_text(build_dart_module(result["collected_jobs"]), encoding="utf-8")
    if resume_mocks_output is not None and DEFAULT_RESUME_MOCKS_INPUT.exists():
        # 공고 데이터와 같은 이유로 생성한다: 시드 스크립트가 쓰는 JSON이 단일 출처다.
        mocks = json.loads(DEFAULT_RESUME_MOCKS_INPUT.read_text(encoding="utf-8"))
        mocks_path = Path(resume_mocks_output)
        mocks_path.parent.mkdir(parents=True, exist_ok=True)
        mocks_path.write_text(build_resume_mocks_module(mocks), encoding="utf-8")
    return result
