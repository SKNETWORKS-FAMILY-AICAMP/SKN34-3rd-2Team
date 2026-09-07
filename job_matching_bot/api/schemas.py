"""추천 API의 요청·응답과 LLM 구조화 출력 스키마.

`StrictModel`은 정의되지 않은 필드를 거부한다. 앱이 오타 난 필드를 보내면
조용히 무시되는 대신 422로 돌아오게 하려는 것이다.

LLM 출력 스키마(`ResumeProfileOut`, `JobFit`)는 `with_structured_output`에
그대로 넘긴다. 모델이 형식을 지키도록 강제하되, 받은 값은 서비스에서 한 번 더
검증한다 — 형식이 맞다고 내용이 사실인 것은 아니다.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


# ── 요청 ────────────────────────────────────────────────

class RecommendRequest(StrictModel):
    """앱이 보내는 것. 이력서 원본은 Firestore에 있고, 서버는 평문만 받는다."""

    resume_text: str = Field(min_length=20, max_length=50_000)
    preferred_regions: list[str] = Field(default_factory=list, max_length=20)
    preferred_employment_types: list[str] = Field(default_factory=list, max_length=10)
    education_level: str = "미기재"
    career_years: float = Field(default=0, ge=0, le=60)
    majors: list[str] = Field(default_factory=list, max_length=10)
    certifications: list[str] = Field(default_factory=list, max_length=30)
    top_k: int = Field(default=10, ge=1, le=20)

    @field_validator("resume_text")
    @classmethod
    def reject_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("resume_text must not be blank")
        return value.strip()


# ── LLM ① 이력서 구조화 ─────────────────────────────────

class ResumeProfileOut(StrictModel):
    """이력서에서 뽑은 검색용 프로필.

    `search_query`가 핵심이다. 이력서는 "FastAPI로 API를 개발했습니다"(경험)로
    쓰이고 공고는 "Python 개발 경험 2년 이상"(요구)으로 쓰여 표현이 다르다.
    공고 쪽 표현으로 바꿔야 벡터 검색이 잘 걸린다.
    """

    search_query: str = Field(
        description="이 사람에게 맞는 공고를 찾기 위한 질의문. 공고 자격요건처럼 쓴다."
    )
    target_roles: list[str] = Field(description="지원할 만한 직무 이름", max_length=5)
    skills: list[str] = Field(description="이력서에 근거가 있는 기술만", max_length=30)
    career_years: float = Field(description="이력서 경력사항으로 계산한 연차. 없으면 0", ge=0)
    summary: str = Field(description="이 지원자를 한 문장으로")


# ── LLM ② 재정렬 ────────────────────────────────────────

class Reason(StrictModel):
    claim: str = Field(description="적합하다고 본 이유 한 줄")
    resume_quote: str = Field(
        description="이력서 원문에 연속해서 존재하는 직접 인용. 할 줄 아는 일을 보여 주는 대목"
    )
    job_quote: str = Field(
        description="공고 원문에 연속해서 존재하는 직접 인용. 요구하는 업무·기술 대목"
    )


class JobFit(StrictModel):
    job_id: str
    fit: Literal["높음", "보통", "낮음"]
    reasons: list[Reason] = Field(
        default_factory=list,
        # 상한이 4면 "필수 요건 대부분을 충족했다"를 셀 수가 없어 적합도가 전부 '보통'으로
        # 몰렸다. 자격요건과 우대사항 충족을 함께 담을 만큼 넉넉하게 둔다.
        max_length=6,
        description="충족한 업무·기술. 자격요건·우대사항 모두. 조건(연차·학력·지역)은 넣지 않는다",
    )
    concerns: list[str] = Field(
        default_factory=list,
        max_length=3,
        description="자격요건(필수) 중 이력서에서 확인되지 않는 것만. 우대사항은 넣지 않는다",
    )


class RerankOut(StrictModel):
    results: list[JobFit]


# ── 응답 ────────────────────────────────────────────────

class Conditions(StrictModel):
    region: str = ""
    employment_type: str | None = None
    career: str = ""
    education: str = ""
    deadline: str | None = None


class Recommendation(StrictModel):
    job_id: str
    company: str
    title: str
    source_url: str
    fit: Literal["높음", "보통", "낮음"]
    reasons: list[Reason] = Field(default_factory=list)
    concerns: list[str] = Field(default_factory=list)
    conditions: Conditions
    filter_status: Literal["PASS", "CHECK_REQUIRED"] = "PASS"
    unknown_conditions: list[str] = Field(default_factory=list)
    passed_conditions: list[str] = Field(default_factory=list)
    search_rank: int = Field(description="벡터 검색에서의 순위")
    body_is_image: bool = False


class RecommendResponse(StrictModel):
    recommendations: list[Recommendation]
    search_query: str = Field(description="LLM이 만든 검색 질의문. 왜 이렇게 찾았는지 보여 준다")
    profile_summary: str = ""
    reranked: bool = Field(description="LLM 재정렬이 적용됐는지. false면 검색 순서 그대로")
    warnings: list[str] = Field(default_factory=list, description="근거 검증에서 제거한 내용")
    notice: str = (
        "추천 순서는 이력서와 공고의 관련도이며 합격 가능성이나 지원자 점수가 아닙니다."
    )


class HealthResponse(StrictModel):
    status: Literal["ok"] = "ok"
    index_name: str
    vector_count: int
    llm_configured: bool
