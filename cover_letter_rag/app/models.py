from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class RequirementStatus(StrEnum):
    MET = "충족"
    PARTIAL = "부분 충족"
    NOT_MET = "미충족"
    NEEDS_CONFIRMATION = "확인 필요"


class JobSearchRequest(StrictModel):
    resume_text: str = Field(min_length=20, max_length=50_000)
    top_k: int = Field(default=4, ge=1, le=10)

    @field_validator("resume_text")
    @classmethod
    def reject_blank_resume(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("resume_text must not be blank")
        return value.strip()


class JobSearchResult(StrictModel):
    rank: int = Field(ge=1)
    job_id: str
    company: str
    title: str
    industry_code: str | None = None
    industry_name: str | None = None
    job_mid_code: str | None = None
    job_mid_name: str | None = None
    job_code: str | None = None
    job_name: str | None = None
    location_code: str | None = None
    location: str | None = None
    employment_type_code: str | None = None
    employment_type: str | None = None
    career: str | None = None
    education: str | None = None
    job_sectors: list[str] = Field(default_factory=list)
    tech_tags: list[str] = Field(default_factory=list)
    detail_quality: Literal["DETAILED", "LIMITED", "NEEDS_CONFIRMATION"] | None = None
    summary: str
    source: str


class JobSearchResponse(StrictModel):
    results: list[JobSearchResult]
    notice: str = "검색 순위는 공고 관련도이며 지원자 점수나 합격 가능성이 아닙니다."


class JobRecommendationRequest(StrictModel):
    resume_text: str = Field(min_length=20, max_length=50_000)
    base_cover_letter_text: str | None = Field(default=None, max_length=50_000)
    preferred_roles: list[str] = Field(default_factory=list, max_length=10)
    preferred_locations: list[str] = Field(default_factory=list, max_length=10)
    employment_types: list[str] = Field(default_factory=list, max_length=10)
    top_k: int = Field(default=5, ge=1, le=10)

    @field_validator(
        "preferred_roles",
        "preferred_locations",
        "employment_types",
    )
    @classmethod
    def normalize_tags(cls, values: list[str]) -> list[str]:
        normalized = [value.strip() for value in values if value.strip()]
        if not normalized:
            return []
        return list(dict.fromkeys(normalized))

    @field_validator("resume_text")
    @classmethod
    def normalize_resume(cls, value: str) -> str:
        return value.strip()

    @field_validator("base_cover_letter_text")
    @classmethod
    def normalize_cover_letter(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None


class SaraminSearchCriteria(StrictModel):
    keywords: str
    job_mid_cd: str | None = None
    job_cd: str | None = None
    loc_cd: str | None = None
    job_type: str | None = None
    start: int = 0
    count: int = Field(default=30, ge=1, le=110)
    unmapped_skills: list[str] = Field(default_factory=list)
    unmapped_preferences: list[str] = Field(default_factory=list)


class ResumeSkill(StrictModel):
    name: str
    resume_quote: str = Field(description="이력서에 연속해서 존재하는 직접 인용문")


class ResumeExperience(StrictModel):
    summary: str
    resume_quote: str = Field(description="이력서에 연속해서 존재하는 직접 인용문")


class ResumeProfileGeneration(StrictModel):
    target_roles: list[str] = Field(default_factory=list)
    skills: list[ResumeSkill] = Field(default_factory=list)
    experiences: list[ResumeExperience] = Field(default_factory=list)
    career_summary: str | None = None
    search_terms: list[str] = Field(default_factory=list)
    cover_letter_intents: list[str] = Field(default_factory=list)


class ResumeProfileResponse(ResumeProfileGeneration):
    grounding_warnings: list[str] = Field(default_factory=list)


class ResumeProfileRequest(StrictModel):
    resume_text: str = Field(min_length=20, max_length=50_000)
    base_cover_letter_text: str | None = Field(default=None, max_length=50_000)
    preferred_roles: list[str] = Field(default_factory=list, max_length=10)

    @field_validator("resume_text")
    @classmethod
    def normalize_resume(cls, value: str) -> str:
        return value.strip()

    @field_validator("base_cover_letter_text")
    @classmethod
    def normalize_cover_letter(cls, value: str | None) -> str | None:
        normalized = value.strip() if value else ""
        return normalized or None


class JobRecommendationResult(JobSearchResult):
    matched_resume_skills: list[str] = Field(default_factory=list)
    resume_evidence: list[str] = Field(default_factory=list)
    recommendation_reasons: list[str] = Field(default_factory=list)


class JobRecommendationResponse(StrictModel):
    analyzed_profile: ResumeProfileResponse
    results: list[JobRecommendationResult]
    notice: str = (
        "추천 순위는 이력서 원문·기본 자소서의 지원 의도·희망 조건과 공고의 관련도이며 "
        "지원자 점수나 합격 가능성이 아닙니다."
    )


class JobComparisonRequest(StrictModel):
    job_id: str = Field(min_length=1, max_length=200)
    resume_text: str = Field(min_length=20, max_length=50_000)

    @field_validator("job_id", "resume_text")
    @classmethod
    def reject_blank_text(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("input text must not be blank")
        return value.strip()


class ReviewRequest(StrictModel):
    resume_text: str = Field(min_length=20, max_length=50_000)
    job_posting_text: str = Field(min_length=20, max_length=50_000)
    cover_letter_question: str = Field(min_length=3, max_length=5_000)
    draft_text: str = Field(min_length=1, max_length=50_000)
    top_k: int = Field(default=4, ge=1, le=10)

    @field_validator("resume_text", "job_posting_text", "cover_letter_question", "draft_text")
    @classmethod
    def reject_blank_text(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("input text must not be blank")
        return value.strip()


class ResumeEvidence(StrictModel):
    resume_quote: str = Field(description="이력서에 연속해서 존재하는 직접 인용문")
    explanation: str


class RequirementComparison(StrictModel):
    requirement: str
    requirement_type: Literal["필수", "우대", "업무", "기타"]
    source_id: str
    status: RequirementStatus
    resume_evidence: list[ResumeEvidence] = Field(default_factory=list)
    gap: str | None = None
    confirmation_question: str | None = None


class DraftImprovement(StrictModel):
    issue: str
    suggestion: str
    grounded_resume_quote: str | None = None


class SourceReference(StrictModel):
    source_id: str
    source_type: Literal["resume", "job_posting", "retrieved_job"]
    title: str
    excerpt: str


class ReviewGeneration(StrictModel):
    question_intent: str
    requirements: list[RequirementComparison]
    improvements: list[DraftImprovement]
    confirmation_questions: list[str]
    revised_draft: str


class ReviewResponse(ReviewGeneration):
    sources: list[SourceReference]
    grounding_warnings: list[str] = Field(default_factory=list)
    notice: str = "이 결과는 근거 기반 첨삭이며 합격 가능성 판단이나 지원자 점수가 아닙니다."


class JobComparisonResponse(StrictModel):
    job: JobSearchResult
    requirements: list[RequirementComparison]
    confirmation_questions: list[str]
    sources: list[SourceReference]
    grounding_warnings: list[str] = Field(default_factory=list)
    notice: str = "이 비교는 이력서 직접 근거 확인 결과이며 합격 가능성이나 지원자 점수가 아닙니다."


class HealthResponse(StrictModel):
    status: Literal["ok"] = "ok"
    model: str
    index_ready: bool
    firebase_auth: Literal["planned"] = "planned"
