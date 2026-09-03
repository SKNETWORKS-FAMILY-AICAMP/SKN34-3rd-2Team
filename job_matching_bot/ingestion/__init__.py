"""채용공고 수집·정규화 레이어.

이 레이어는 원본(잡코리아 수집본, Mock)을 공통 `Job` 스키마로 바꾸는 일만
담당한다. Hard Filter·Ranking·Skill Gap은 이 레이어를 import하지만
반대 방향으로는 의존하지 않는다.
"""

from job_matching_bot.ingestion.collection import deduplicate, to_collection_record
from job_matching_bot.ingestion.it_filter import classify_it_job, filter_it_jobs
from job_matching_bot.ingestion.jobkorea import normalize_jobkorea
from job_matching_bot.ingestion.mock_source import mock_jobs
from job_matching_bot.ingestion.skill_extractor import extract_skills

__all__ = [
    "classify_it_job",
    "deduplicate",
    "extract_skills",
    "filter_it_jobs",
    "mock_jobs",
    "normalize_jobkorea",
    "to_collection_record",
]
