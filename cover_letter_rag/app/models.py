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
    location: str | None = None
    employment_type: str | None = None
    summary: str
    source: str


class JobSearchResponse(StrictModel):
    results: list[JobSearchResult]
    notice: str = "검색 순위는 공고 관련도이며 지원자 점수나 합격 가능성이 아닙니다."


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


class HealthResponse(StrictModel):
    status: Literal["ok"] = "ok"
    model: str
    index_ready: bool
    firebase_auth: Literal["planned"] = "planned"

