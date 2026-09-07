import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator

from langchain_core.documents import Document


IT_TERMS = (
    "백엔드", "프론트엔드", "풀스택", "개발자", "소프트웨어", "데이터", "인공지능",
    "머신러닝", "딥러닝", "devops", "클라우드", "서버", "정보보안", "시스템운영",
    "python", "java", "javascript", "typescript", "react", "flutter", "fastapi",
    "spring", "sql", "firebase", "aws", "azure", "gcp", "llm", "rag",
)
EXCLUDED_TITLE_TERMS = ("헤드헌터", "스카우터", "인재 추천", "사회복지사")


@dataclass(frozen=True)
class CrawledJobStats:
    lines: int
    valid_records: int
    invalid_records: int
    unique_records: int
    duplicate_records: int
    it_records: int
    indexed_records: int
    detailed_records: int
    limited_records: int
    needs_confirmation_records: int


def load_crawled_job_documents(
    path: Path,
    *,
    it_only: bool = True,
    include_limited: bool = True,
    max_jobs: int | None = None,
) -> tuple[list[Document], CrawledJobStats]:
    latest: dict[str, dict[str, Any]] = {}
    lines = valid = invalid = 0

    with path.open("r", encoding="utf-8-sig") as stream:
        for line in stream:
            lines += 1
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                invalid += 1
                continue
            job_id = _job_id(record)
            if not job_id:
                invalid += 1
                continue
            latest[job_id] = record
            valid += 1

    documents: list[Document] = []
    it_records = detailed = limited = needs_confirmation = 0
    for job_id, record in latest.items():
        normalized = normalize_crawled_job(job_id, record)
        if it_only and not is_it_job(normalized):
            continue
        it_records += 1
        quality = normalized["detail_quality"]
        if quality == "DETAILED":
            detailed += 1
        elif quality == "LIMITED":
            limited += 1
        else:
            needs_confirmation += 1
        if not include_limited and quality != "DETAILED":
            continue
        documents.append(to_document(normalized))
        if max_jobs is not None and len(documents) >= max_jobs:
            break

    return documents, CrawledJobStats(
        lines=lines,
        valid_records=valid,
        invalid_records=invalid,
        unique_records=len(latest),
        duplicate_records=max(valid - len(latest), 0),
        it_records=it_records,
        indexed_records=len(documents),
        detailed_records=detailed,
        limited_records=limited,
        needs_confirmation_records=needs_confirmation,
    )


def normalize_crawled_job(job_id: str, record: dict[str, Any]) -> dict[str, Any]:
    item = record.get("list_item") or {}
    conditions = record.get("conditions") or {}
    sectors = _text_list(item.get("job_sectors") or record.get("job_sectors"))
    tags = _text_list(record.get("tags"))
    description = _text(record.get("description"))
    needs_review = bool(record.get("needs_human_review"))
    if needs_review:
        quality = "NEEDS_CONFIRMATION"
    elif len(description) < 800:
        quality = "LIMITED"
    else:
        quality = "DETAILED"

    return {
        "job_id": f"SARAMIN-{job_id}",
        "company": _text(item.get("company")),
        "title": _text(item.get("title")),
        "job_sectors": sectors,
        "tags": tags,
        "career": _condition(conditions, "경력"),
        "education": _condition(conditions, "학력"),
        "employment_type": _condition(conditions, "근무형태"),
        "location": _condition(conditions, "근무지역"),
        "description": description,
        "source": _text(record.get("source_url") or item.get("url")),
        "support_text": _text(record.get("support_text")),
        "detail_quality": quality,
        "parser_version": _text(record.get("parser_version")),
        "fetched_at": _text(record.get("fetched_at")),
    }


def is_it_job(job: dict[str, Any]) -> bool:
    title = job["title"].casefold()
    if any(term in title for term in EXCLUDED_TITLE_TERMS):
        return False
    searchable = " ".join(
        [job["title"], *job["job_sectors"], *job["tags"], job["description"][:2500]]
    ).casefold()
    return any(term in searchable for term in IT_TERMS)


def to_document(job: dict[str, Any]) -> Document:
    sectors = ", ".join(job["job_sectors"])
    tags = ", ".join(job["tags"])
    content = "\n".join(
        part for part in (
            f"회사: {job['company']}",
            f"공고명: {job['title']}",
            f"직무 분야: {sectors}" if sectors else "",
            f"기술 및 키워드: {tags}" if tags else "",
            f"경력: {job['career']}" if job["career"] else "",
            f"학력: {job['education']}" if job["education"] else "",
            f"근무형태: {job['employment_type']}" if job["employment_type"] else "",
            f"근무지역: {job['location']}" if job["location"] else "",
            job["description"],
            job["support_text"],
        ) if part
    )
    return Document(
        page_content=content,
        metadata={
            "job_id": job["job_id"],
            "company": job["company"],
            "title": job["title"],
            "location": job["location"],
            "employment_type": job["employment_type"],
            "career": job["career"],
            "education": job["education"],
            "job_sectors": sectors,
            "tech_tags": tags,
            "detail_quality": job["detail_quality"],
            "source": job["source"] or "saramin_crawl",
            "parser_version": job["parser_version"],
            "fetched_at": job["fetched_at"],
        },
    )


def _job_id(record: dict[str, Any]) -> str:
    item = record.get("list_item") or {}
    return _text(record.get("source_job_id") or item.get("source_job_id") or item.get("id"))


def _condition(conditions: dict[str, Any], key: str) -> str:
    value = conditions.get(key)
    if isinstance(value, list):
        return ", ".join(_text_list(value))
    return _text(value)


def _text_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return list(dict.fromkeys(text for item in value if (text := _text(item))))


def _text(value: Any) -> str:
    if value is None:
        return ""
    return " ".join(str(value).split())
