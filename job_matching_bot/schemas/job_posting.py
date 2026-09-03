"""수집원과 무관하게 사용하는 공통 채용공고 스키마."""

from dataclasses import dataclass, field
from typing import Any


@dataclass
class Job:
    job_id: str
    source: str
    source_job_id: str
    source_url: str
    company: str
    company_type: str
    title: str
    description: str
    required_skills: list[str]
    preferred_skills: list[str]
    career_type: str
    min_career_years: int | None
    education: str
    region: str
    employment_type: str
    posted_at: str | None
    deadline: str | None
    status: str
    content_hash: str
    parser_version: str
    field_provenance: dict[str, Any]
    # 기업이 공고 등록 때 고른 기술 태그. 필수·우대가 구분돼 있지 않아
    # required/preferred와 별도로 둔다. 소스에 그런 태그가 없으면 빈 목록이다.
    tech_stack: list[str] = field(default_factory=list)
    # 기업이 고른 분류 태그 중 기술이 아닌 것(직무·전문분야). 직무 점수의 근거가 된다.
    keywords: list[str] = field(default_factory=list)

    def matching_text(self) -> str:
        return " ".join(
            [
                self.title,
                self.description,
                " ".join(self.required_skills),
                " ".join(self.preferred_skills),
                " ".join(self.tech_stack),
                " ".join(self.keywords),
            ]
        ).lower()
