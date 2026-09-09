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
    # 앱이 이력서를 저장할 때 미리 만들어 둔 구조화 결과. 있으면 서버는 다시 만들지 않는다.
    # 대기 시간이 2.7초 줄고, 무엇보다 **검색어가 고정되어 추천이 매번 흔들리지 않는다.**
    # 이력서를 고쳤으면 앱이 보내지 않으면 된다 — 그때는 서버가 새로 만든다.
    profile: "ResumeProfileOut | None" = None

    @field_validator("resume_text")
    @classmethod
    def reject_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("resume_text must not be blank")
        return value.strip()


class ProfileRequest(StrictModel):
    """구조화만 요청한다. 이력서를 저장할 때 미리 불러 두는 용도다."""

    resume_text: str = Field(min_length=20, max_length=50_000)

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


# RecommendRequest 가 위에서 이 형을 이름으로만 가리켰다. 여기서 이어 준다.
RecommendRequest.model_rebuild()


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
    """재정렬 결과 하나.

    필드 순서가 곧 판단 순서다. 구조화 출력은 위에서부터 채워지므로, `fit`을 정하기 전에
    **무엇과 무엇을 견줬는지 먼저 쓰게** 한다. 이 세 칸이 없을 때는 모델이 대조를 건너뛰고
    감으로 등급을 매겨 30건 중 20건이 "높음"으로 몰렸다.
    """

    job_id: str
    job_core: str = Field(
        description="이 공고에서 매일 쓸 주된 기술·업무. 제목과 주요업무에서 잡는다. 셋 이내, 공고의 말로"
    )
    resume_core: str = Field(
        description="이력서의 주력. 실제로 만들어 본 것 기준. 셋 이내, 이력서에 적힌 말로"
    )
    overlap: str = Field(
        description="위 둘이 실제로 겹치는 것. 겹치는 게 없으면 '없음'이라고 쓴다"
    )
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


# ── 공고 찾아보기 챗봇 ──────────────────────────────────

class ChatFilters(StrictModel):
    """대화에서 뽑아낸 검색 조건.

    앱이 응답으로 받은 그대로 다음 요청에 실어 보낸다. 그래야 "서울만"처럼 앞말을
    이어받는 말이 통한다. 서버는 대화를 저장하지 않는다.
    """

    roles: list[str] = Field(default_factory=list, description="직무. 백엔드, 데이터분석")
    skills: list[str] = Field(default_factory=list, description="기술. Python, React")
    regions: list[str] = Field(default_factory=list, description="지역. 서울, 경기")
    career: Literal["신입", "경력", "무관"] = "무관"
    employment_types: list[str] = Field(default_factory=list, description="정규직, 인턴")
    deadline_within_days: int | None = Field(
        default=None, description="마감 임박만 볼 때의 날짜 수. 아니면 null"
    )
    keywords: list[str] = Field(default_factory=list, description="위에 안 들어가는 말")


class ChatTurnOut(StrictModel):
    """LLM ①: 무엇을 원하는 말인지 가르고, 조건을 뽑는다.

    조건은 의도와 상관없이 뽑는다. "백엔드 신입은 뭘 준비해야 해?"는 질문이지만
    그 안에 직무·경력이 들어 있고, 그 조건으로 공고를 세어야 숫자로 답할 수 있다.
    """

    intent: Literal["검색", "질문", "추천", "잡담"] = Field(
        description=(
            "공고 목록을 원하면 검색, 채용에 대해 묻는 말이면 질문, "
            "이력서를 근거로 골라 달라는 말이면 추천, 그 밖은 잡담"
        )
    )
    filters: ChatFilters
    counts_jobs: bool = Field(
        default=False,
        description="공고를 세어서 답할 질문이면 true. 조언을 구하는 말이면 false",
    )
    resume_scope: Literal["전체", "프로젝트", "기술스택", "자기소개서", "경력"] = Field(
        default="전체",
        description=(
            "추천일 때 이력서의 어디를 근거로 삼을지. 사용자가 콕 집어 말했을 때만 "
            "좁힌다. '프로젝트 경험 보고' → 프로젝트, '기술스택으로' → 기술스택"
        ),
    )
    unavailable: Literal["", "급여", "복지", "합격 가능성", "회사 평판"] = Field(
        default="",
        description=(
            "우리가 가지고 있지 않은 정보로 찾거나 줄 세워 달라는 요청이면 그것. "
            "아니면 빈 문자열"
        ),
    )
    requirement_query: str = Field(
        default="",
        description=(
            "원하는 일을 채용공고의 자격요건·주요업무 말투로 고쳐 쓴 한두 문장. "
            "조건으로 못 찾았을 때 뜻으로 찾는 데 쓴다"
        ),
    )
    understood: str = Field(description="무엇으로 찾을지 사용자에게 확인시키는 한 문장")


class ChatAnswerOut(StrictModel):
    """LLM ②: 채용 질문에 대한 답. 공고 통계나 공고 원문을 근거로 쓴다."""

    answer: str = Field(description="사용자에게 보여 줄 답. 여러 문단이어도 된다")
    followups: list[str] = Field(
        default_factory=list,
        description="이어서 물어볼 만한 말 세 개 이내. 그대로 눌러 보낼 수 있는 문장으로",
    )


class JobChatRequest(StrictModel):
    message: str = Field(min_length=1, max_length=500)
    filters: ChatFilters | None = Field(
        default=None, description="직전 응답의 filters. 첫 질문이면 비운다"
    )
    top_k: int = Field(default=5, ge=1, le=20)
    job_id: str | None = Field(
        default=None,
        description="이 공고를 놓고 묻는 경우의 job_id. 있으면 그 공고 원문만 근거로 답한다",
    )


class JobChatJob(StrictModel):
    job_id: str
    company: str
    title: str
    source_url: str
    region: str
    career: str
    employment_type: str
    deadline: str | None = None
    tech_stack: list[str] = Field(default_factory=list)


class JobChatResponse(StrictModel):
    mode: Literal["검색", "질문", "공고", "추천", "안내"] = Field(
        default="검색", description="앱이 답을 어떻게 보여 줄지 정하는 데 쓴다"
    )
    resume_scope: Literal["전체", "프로젝트", "기술스택", "자기소개서", "경력"] = Field(
        default="전체",
        description="mode가 추천일 때 이력서의 어디를 근거로 삼을지. 앱이 그만큼만 보낸다",
    )
    reply: str
    filters: ChatFilters
    jobs: list[JobChatJob] = Field(default_factory=list)
    total: int = Field(description="조건에 맞는 전체 건수. jobs는 그중 일부")
    suggestions: list[str] = Field(
        default_factory=list, description="다음에 더 좁힐 거리. 그대로 눌러 보낼 수 있는 말"
    )


class HealthResponse(StrictModel):
    status: Literal["ok"] = "ok"
    index_name: str
    vector_count: int
    llm_configured: bool
