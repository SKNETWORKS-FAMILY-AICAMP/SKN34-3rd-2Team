"""수집한 IT 공고를 cover_letter_rag 인덱서가 읽는 정적 공고 JSON으로 내보낸다.

cover_letter_rag 서버는 `data/jobs/*.json` 같은 디렉터리를 읽어 청킹·임베딩하고
Chroma에 저장한 뒤, 이력서 텍스트로 공고 Top-k를 검색해 준다. 그 서버 코드를
고치지 않고 수집 공고를 임베딩 검색에 올리려면, 인덱서가 기대하는 형식으로
파일을 만들어 `--data-dir`로 넘기면 된다.

    python -m job_matching_bot                       # artifacts/cover_letter_rag_jobs/ 생성
    cd cover_letter_rag
    python -m scripts.index_jobs --data-dir ../job_matching_bot/artifacts/cover_letter_rag_jobs

인덱서가 요구하는 필드(scripts/index_jobs.py `_validate_job`):
`job_id, company, title, summary, responsibilities, requirements(비어 있지 않은 목록)`.
선택 필드는 `location, employment_type, preferred`.

검색 결과의 `job_id`는 수집 레코드의 `id`(예: SARAMIN-54645823)를 그대로 쓰므로,
앱은 이 값으로 키워드 추천 결과와 조인할 수 있다.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

UNKNOWN_MARKERS = frozenset({"", "미기재", "학력무관", "무관"})
SUMMARY_MAX_CHARS = 300
_FILENAME_SAFE = re.compile(r"[^A-Za-z0-9_.-]+")


def to_rag_job(record: dict[str, Any]) -> dict[str, Any]:
    """수집 레코드(`collected_it_jobs.json` 한 건) → 인덱서 입력 JSON."""
    company = _text(record.get("company"))
    title = _text(record.get("position"))
    description_lines = _lines(record.get("description"))

    requirements = [
        {"type": "필수", "text": skill} for skill in _unique(record.get("required_skills"))
    ]
    requirements.extend(_condition_requirements(record))
    if not requirements:
        # 인덱서는 빈 requirements를 거부한다. 기업이 등록한 기술스택 태그를 대신 쓰되,
        # 필수·우대 어느 쪽도 아니므로 '기타'로 표시한다.
        requirements = [
            {"type": "기타", "text": f"기술스택 태그: {tag}"}
            for tag in _unique(record.get("tech_stack"))
        ]
    if not requirements:
        requirements = [{"type": "기타", "text": "공고 원문에 명시된 자격요건이 없습니다."}]

    summary = _summary(description_lines) or f"{company} {title}".strip()

    return {
        "job_id": _text(record.get("id")),
        "company": company,
        "title": title,
        "location": _text(record.get("location")),
        "employment_type": _text(record.get("employment_type")),
        "summary": summary,
        "responsibilities": description_lines or [summary],
        "requirements": requirements,
        "preferred": _unique(record.get("preferred_skills")),
        # 인덱서는 아래 키를 읽지 않지만, 파일만 보고도 출처를 추적할 수 있게 남긴다.
        "source": _text(record.get("source")),
        "source_url": _text(record.get("source_url")),
    }


def write_rag_jobs(collected_jobs: list[dict[str, Any]], output_dir: Path) -> list[Path]:
    """공고마다 `<job_id>.json`을 쓴다. 디렉터리에 남아 있던 이전 생성 파일은 지운다.

    이 디렉터리는 파이프라인 전용 산출물이라 사람이 만든 파일이 섞이지 않는다.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    for stale in output_dir.glob("*.json"):
        stale.unlink()

    written: list[Path] = []
    for record in collected_jobs:
        job = to_rag_job(record)
        if not job["job_id"]:
            continue
        path = output_dir / f"{_FILENAME_SAFE.sub('_', job['job_id'])}.json"
        path.write_text(json.dumps(job, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        written.append(path)
    return written


def _condition_requirements(record: dict[str, Any]) -> list[dict[str, str]]:
    """경력·학력 같은 하드 조건도 자격요건 문장으로 넣어 임베딩에 반영한다."""
    conditions: list[dict[str, str]] = []
    years = record.get("min_career_years")
    if isinstance(years, int) and years > 0:
        conditions.append({"type": "필수", "text": f"경력 {years}년 이상"})
    education = _text(record.get("education"))
    if education not in UNKNOWN_MARKERS:
        conditions.append({"type": "필수", "text": f"학력 {education}"})
    return conditions


def _summary(lines: list[str]) -> str:
    text = " ".join(lines)
    if len(text) <= SUMMARY_MAX_CHARS:
        return text
    return text[:SUMMARY_MAX_CHARS].rstrip() + "…"


def _lines(value: Any) -> list[str]:
    if not isinstance(value, str):
        return []
    return _unique(line.strip() for line in value.splitlines())


def _unique(values: Any) -> list[str]:
    if values is None:
        return []
    seen: dict[str, None] = {}
    for value in values:
        text = _text(value)
        if text:
            seen.setdefault(text, None)
    return list(seen)


def _text(value: Any) -> str:
    if value is None:
        return ""
    return " ".join(str(value).split())
