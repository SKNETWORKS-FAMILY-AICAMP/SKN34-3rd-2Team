"""잡코리아 상세 수집본을 공통 `Job` 스키마로 정규화한다.

수집 자체는 하지 않는다. 이미 저장된 원본 레코드를 읽어 필드를 해석하고,
각 필드가 어떤 근거로 채워졌는지 `field_provenance`에 남긴다.
"""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime
from typing import Any

from job_matching_bot.config import AS_OF
from job_matching_bot.ingestion.skill_extractor import extract_skills
from job_matching_bot.schemas.job_posting import Job

PARSER_VERSION = "jobkorea-poc-0.1.0"

EMPLOYMENT_MAP = {
    "FULL_TIME": "정규직",
    "CONTRACTOR": "계약직",
    "PART_TIME": "파트타임",
    "INTERN": "인턴",
}

EDUCATION_LEVELS = ("학력무관", "대졸", "고졸", "석사", "박사")

CITY_TOKENS = (
    "서울",
    "경기",
    "인천",
    "대전",
    "대구",
    "부산",
    "광주",
    "울산",
    "세종",
    "강원",
    "충북",
    "충남",
    "전북",
    "전남",
    "경북",
    "경남",
    "제주",
)


def _first_json_ld(record: dict[str, Any]) -> dict[str, Any]:
    values = record.get("json_ld") or []
    return values[0] if values and isinstance(values[0], dict) else {}


def _description_text(record: dict[str, Any]) -> str:
    blocks = record.get("description_blocks") or []
    return " ".join(str(block.get("text") or "") for block in blocks)


def _parse_career(conditions: list[str]) -> tuple[str, int | None, str]:
    """신입/경력 조건을 `career_type`과 최소 경력 연수로 나눈다."""
    evidence = next(
        (value for value in conditions if value == "신입" or value.startswith("경력")), "미기재"
    )
    if evidence == "신입":
        return "ENTRY", 0, evidence
    if "경력무관" in evidence:
        return "ANY", None, evidence
    match = re.search(r"경력\s*(\d+)년", evidence)
    if match:
        return "EXPERIENCED", int(match.group(1)), evidence
    if evidence.startswith("경력"):
        return "EXPERIENCED", None, evidence
    return "UNKNOWN", None, evidence


def _parse_education(conditions: list[str], json_ld: dict[str, Any]) -> tuple[str, str]:
    for value in conditions:
        for level in EDUCATION_LEVELS:
            if level in value:
                return level, value
    evidence = str(json_ld.get("educationRequirements") or "미기재")
    return (evidence if evidence in EDUCATION_LEVELS else "미기재"), evidence


def _parse_region(conditions: list[str], json_ld: dict[str, Any]) -> tuple[str, str]:
    for value in conditions:
        if any(token in value for token in CITY_TOKENS):
            return value, value
    address = (
        json_ld.get("jobLocation", {}).get("address", {}).get("streetAddress")
        if isinstance(json_ld.get("jobLocation"), dict)
        else None
    )
    return (str(address), str(address)) if address else ("미기재", "미기재")


def _parse_employment(conditions: list[str], json_ld: dict[str, Any]) -> tuple[str, str]:
    known = ("정규직", "계약직", "프리랜서", "인턴", "파트타임")
    for value in conditions:
        if value in known:
            return value, value
    raw = str(json_ld.get("employmentType") or "")
    return EMPLOYMENT_MAP.get(raw, "미기재"), raw or "미기재"


def resolve_status(deadline: str | None, as_of: datetime) -> str:
    """마감일 기준으로 공고 상태를 정한다. 해석에 실패하면 열린 공고로 둔다."""
    if not deadline:
        return "OPEN"
    try:
        parsed = datetime.fromisoformat(deadline)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=as_of.tzinfo)
        return "OPEN" if parsed >= as_of else "EXPIRED"
    except ValueError:
        return "OPEN"


def normalize_jobkorea(record: dict[str, Any], as_of: datetime = AS_OF) -> Job:
    item = record.get("list_item") or {}
    conditions = [str(value) for value in item.get("conditions") or []]
    json_ld = _first_json_ld(record)
    description = _description_text(record)
    title = str(item.get("title") or json_ld.get("title") or "")
    keywords = str(item.get("keywords") or "")
    skill_text = " ".join([title, keywords, description])
    required_skills = extract_skills(skill_text)
    career_type, min_years, career_evidence = _parse_career(conditions)
    education, education_evidence = _parse_education(conditions, json_ld)
    region, region_evidence = _parse_region(conditions, json_ld)
    employment, employment_evidence = _parse_employment(conditions, json_ld)
    deadline = str(json_ld.get("validThrough") or "") or None
    posted_at = str(json_ld.get("datePosted") or "") or None
    source_job_id = str(record.get("job_id") or json_ld.get("identifier", {}).get("value") or "")
    raw_for_hash = json.dumps(record, ensure_ascii=False, sort_keys=True)
    corp_info = record.get("query_data", {}).get("CORP_INFO", {}).get("info") or {}

    return Job(
        job_id=f"JOBKOREA-{source_job_id}",
        source="JOBKOREA_POC",
        source_job_id=source_job_id,
        source_url=str(record.get("source_url") or json_ld.get("url") or ""),
        company=str(item.get("company") or json_ld.get("hiringOrganization", {}).get("name") or ""),
        company_type=str(corp_info.get("companyTypeName") or "미기재"),
        title=title,
        description=" ".join(filter(None, [keywords, description])).strip(),
        required_skills=required_skills,
        preferred_skills=[],
        career_type=career_type,
        min_career_years=min_years,
        education=education,
        region=region,
        employment_type=employment,
        posted_at=posted_at,
        deadline=deadline,
        status=resolve_status(deadline, as_of),
        content_hash=f"sha256:{hashlib.sha256(raw_for_hash.encode('utf-8')).hexdigest()}",
        parser_version=PARSER_VERSION,
        field_provenance={
            "career": {"method": "condition_parser", "evidence": career_evidence},
            "education": {"method": "condition_parser", "evidence": education_evidence},
            "region": {"method": "condition_or_json_ld", "evidence": region_evidence},
            "employment_type": {
                "method": "condition_or_json_ld",
                "evidence": employment_evidence,
            },
            "required_skills": {
                "method": "keyword_extractor",
                "evidence": required_skills,
                "confidence": 1.0 if required_skills else 0.0,
            },
        },
    )
