import re
from collections.abc import Callable

from langchain_openai import ChatOpenAI

from app.config import Settings
from app.models import (
    JobComparisonRequest,
    JobComparisonResponse,
    JobRecommendationRequest,
    JobRecommendationResponse,
    JobRecommendationResult,
    JobSearchResponse,
    RequirementStatus,
    ResumeProfileGeneration,
    ResumeProfileRequest,
    ResumeProfileResponse,
    ReviewGeneration,
    ReviewRequest,
    ReviewResponse,
    SourceReference,
)
from app.prompts import RESUME_PROFILE_PROMPT, REVIEW_PROMPT
from app.vector_store import JobRepository, RetrievedJob, to_search_results


NUMBER_PATTERN = re.compile(r"(?<![A-Za-z가-힣])\d+(?:[.,]\d+)*(?:%|명|건|개|개월|년|일|시간|분|초|ms)?")


class CoverLetterService:
    def __init__(
        self,
        settings: Settings,
        repository: JobRepository,
        generator: Callable[[dict[str, str]], ReviewGeneration] | None = None,
        profile_generator: Callable[[dict[str, str]], ResumeProfileGeneration] | None = None,
    ) -> None:
        self._settings = settings
        self._repository = repository
        self._generator = generator or self._build_generator(settings)
        self._profile_generator = profile_generator or self._build_profile_generator(settings)

    @staticmethod
    def _build_generator(settings: Settings) -> Callable[[dict[str, str]], ReviewGeneration]:
        model = ChatOpenAI(
            model=settings.openai_model,
            api_key=settings.openai_api_key,
            use_responses_api=True,
            reasoning_effort=settings.openai_reasoning_effort,
            max_retries=2,
        )
        chain = REVIEW_PROMPT | model.with_structured_output(
            ReviewGeneration,
            method="json_schema",
        )
        return chain.invoke

    @staticmethod
    def _build_profile_generator(
        settings: Settings,
    ) -> Callable[[dict[str, str]], ResumeProfileGeneration]:
        model = ChatOpenAI(
            model=settings.openai_model,
            api_key=settings.openai_api_key,
            use_responses_api=True,
            reasoning_effort=settings.openai_reasoning_effort,
            max_retries=2,
        )
        chain = RESUME_PROFILE_PROMPT | model.with_structured_output(
            ResumeProfileGeneration,
            method="json_schema",
        )
        return chain.invoke

    def search_jobs(self, resume_text: str, top_k: int) -> JobSearchResponse:
        jobs = self._repository.search(_retrieval_query(resume_text), top_k)
        return JobSearchResponse(results=to_search_results(jobs))

    def analyze_profile(self, request: ResumeProfileRequest) -> ResumeProfileResponse:
        generation = self._profile_generator(
            {
                "resume_text": request.resume_text,
                "base_cover_letter_text": request.base_cover_letter_text or "제공되지 않음",
                "preferred_roles": ", ".join(request.preferred_roles) or "제공되지 않음",
            }
        )
        return enforce_profile_grounding(request, generation)

    def recommend_jobs(self, request: JobRecommendationRequest) -> JobRecommendationResponse:
        profile_request = ResumeProfileRequest(
            resume_text=request.resume_text,
            base_cover_letter_text=request.base_cover_letter_text,
            preferred_roles=request.preferred_roles,
        )
        profile = self.analyze_profile(profile_request)
        query = _profile_query(profile, request)
        candidates = self._repository.search(query, min(request.top_k * 3, 30))
        filtered = [job for job in candidates if _matches_preferences(job, request)]
        selected = (filtered or candidates)[: request.top_k]
        return JobRecommendationResponse(
            analyzed_profile=profile,
            results=[
                _to_recommendation_result(rank, job, profile, request)
                for rank, job in enumerate(selected, start=1)
            ],
        )

    def compare_job(self, request: JobComparisonRequest) -> JobComparisonResponse:
        job = self._repository.get(request.job_id)
        if job is None:
            raise LookupError(f"job not found: {request.job_id}")
        job_posting_text = "\n\n".join(job.chunks)
        review_request = ReviewRequest(
            resume_text=request.resume_text,
            job_posting_text=job_posting_text,
            cover_letter_question="선택한 공고 요구사항과 현재 이력서의 근거 및 부족 정보를 비교해 주세요.",
            draft_text="선택한 공고와 이력서의 차이를 확인합니다.",
            top_k=1,
        )
        generation = self._generator(
            {
                "resume_text": request.resume_text,
                "job_posting_text": job_posting_text,
                "retrieved_context": _format_retrieved_jobs([job]),
                "cover_letter_question": review_request.cover_letter_question,
                "draft_text": review_request.draft_text,
            }
        )
        grounded = enforce_grounding(review_request, generation, [job])
        return JobComparisonResponse(
            job=to_search_results([job])[0],
            requirements=grounded.requirements,
            confirmation_questions=grounded.confirmation_questions,
            sources=grounded.sources,
            grounding_warnings=grounded.grounding_warnings,
        )

    def review(self, request: ReviewRequest) -> ReviewResponse:
        jobs = self._repository.search(
            _retrieval_query(f"{request.resume_text}\n{request.job_posting_text}"),
            request.top_k,
        )
        generation = self._generator(
            {
                "resume_text": request.resume_text,
                "job_posting_text": request.job_posting_text,
                "retrieved_context": _format_retrieved_jobs(jobs),
                "cover_letter_question": request.cover_letter_question,
                "draft_text": request.draft_text,
            }
        )
        return enforce_grounding(request, generation, jobs)


def enforce_grounding(
    request: ReviewRequest,
    generation: ReviewGeneration,
    jobs: list[RetrievedJob],
) -> ReviewResponse:
    warnings: list[str] = []
    questions = list(generation.confirmation_questions)
    allowed_source_ids = {"provided_job_posting", *(f"indexed_job:{job.job_id}" for job in jobs)}

    for comparison in generation.requirements:
        if comparison.source_id not in allowed_source_ids:
            warnings.append(f"허용되지 않은 출처 ID를 provided_job_posting으로 교체했습니다: {comparison.source_id}")
            comparison.source_id = "provided_job_posting"

        valid_evidence = []
        for evidence in comparison.resume_evidence:
            quote = evidence.resume_quote.strip()
            if quote and quote in request.resume_text:
                valid_evidence.append(evidence)
            else:
                warnings.append(f"이력서 원문에서 확인되지 않은 근거를 제거했습니다: {quote[:80]}")
        comparison.resume_evidence = valid_evidence

        if not valid_evidence and comparison.status in {RequirementStatus.MET, RequirementStatus.PARTIAL}:
            comparison.status = RequirementStatus.NEEDS_CONFIRMATION
            if not comparison.confirmation_question:
                comparison.confirmation_question = f"'{comparison.requirement}'을 입증할 실제 경험이나 결과가 있나요?"
            questions.append(comparison.confirmation_question)

    for improvement in generation.improvements:
        quote = (improvement.grounded_resume_quote or "").strip()
        if quote and quote not in request.resume_text:
            warnings.append(f"첨삭 근거에서 확인되지 않은 이력서 인용을 제거했습니다: {quote[:80]}")
            improvement.grounded_resume_quote = None

    revised_draft = generation.revised_draft
    allowed_numbers = set(NUMBER_PATTERN.findall("\n".join(
        [request.resume_text, request.job_posting_text, request.draft_text]
    )))
    generated_numbers = set(NUMBER_PATTERN.findall(revised_draft))
    invented_numbers = sorted(generated_numbers - allowed_numbers)
    if invented_numbers:
        warnings.append(
            "입력 원문에 없는 수치가 감지되어 첨삭안 대신 원본 초안을 유지했습니다: "
            + ", ".join(invented_numbers)
        )
        revised_draft = request.draft_text
        questions.append("첨삭에 필요한 수치가 있다면 실제 측정값과 산출 근거를 알려주세요.")

    sources = [
        SourceReference(
            source_id="resume",
            source_type="resume",
            title="사용자 제공 이력서",
            excerpt=request.resume_text[:500],
        ),
        SourceReference(
            source_id="provided_job_posting",
            source_type="job_posting",
            title="사용자 제공 채용공고",
            excerpt=request.job_posting_text[:500],
        ),
        *[
            SourceReference(
                source_id=f"indexed_job:{job.job_id}",
                source_type="retrieved_job",
                title=f"{job.company} - {job.title}",
                excerpt=job.summary,
            )
            for job in jobs
        ],
    ]

    return ReviewResponse(
        question_intent=generation.question_intent,
        requirements=generation.requirements,
        improvements=generation.improvements,
        confirmation_questions=_deduplicate(questions),
        revised_draft=revised_draft,
        sources=sources,
        grounding_warnings=_deduplicate(warnings),
    )


def enforce_profile_grounding(
    request: ResumeProfileRequest,
    generation: ResumeProfileGeneration,
) -> ResumeProfileResponse:
    warnings: list[str] = []
    valid_skills = []
    for skill in generation.skills:
        quote = skill.resume_quote.strip()
        if quote and quote in request.resume_text:
            valid_skills.append(skill)
        else:
            warnings.append(f"이력서에서 확인되지 않은 기술 근거를 제거했습니다: {skill.name}")

    valid_experiences = []
    for experience in generation.experiences:
        quote = experience.resume_quote.strip()
        if quote and quote in request.resume_text:
            valid_experiences.append(experience)
        else:
            warnings.append(
                f"이력서에서 확인되지 않은 경험 근거를 제거했습니다: {experience.summary[:60]}"
            )

    intent_source = "\n".join(
        [request.resume_text, request.base_cover_letter_text or "", *request.preferred_roles]
    ).casefold()
    target_roles = [item for item in generation.target_roles if item.casefold() in intent_source]
    cover_letter_intents = [
        item for item in generation.cover_letter_intents if item.casefold() in intent_source
    ]
    allowed_search_terms = [skill.name for skill in valid_skills] + target_roles + request.preferred_roles
    search_terms = _deduplicate(
        [*allowed_search_terms, *(term for term in generation.search_terms if term.casefold() in intent_source)]
    )

    return ResumeProfileResponse(
        target_roles=_deduplicate([*request.preferred_roles, *target_roles]),
        skills=valid_skills,
        experiences=valid_experiences,
        career_summary=generation.career_summary if valid_experiences else None,
        search_terms=search_terms,
        cover_letter_intents=_deduplicate(cover_letter_intents),
        grounding_warnings=_deduplicate(warnings),
    )


def _profile_query(profile: ResumeProfileResponse, request: JobRecommendationRequest) -> str:
    evidence = [skill.resume_quote for skill in profile.skills]
    evidence.extend(experience.resume_quote for experience in profile.experiences)
    parts = [
        *profile.target_roles,
        *profile.search_terms,
        *profile.cover_letter_intents,
        *evidence,
        request.base_cover_letter_text or "",
    ]
    return _retrieval_query("\n".join(part for part in parts if part) or request.resume_text)


def _matches_preferences(job: RetrievedJob, request: JobRecommendationRequest) -> bool:
    if request.preferred_locations:
        location = (job.location or "").casefold()
        if location and not any(item.casefold() in location for item in request.preferred_locations):
            return False
    if request.employment_types:
        employment = (job.employment_type or "").casefold()
        if employment and not any(item.casefold() in employment for item in request.employment_types):
            return False
    return True


def _to_recommendation_result(
    rank: int,
    job: RetrievedJob,
    profile: ResumeProfileResponse,
    request: JobRecommendationRequest,
) -> JobRecommendationResult:
    job_text = " ".join([job.title, *job.job_sectors, *job.tech_tags, *job.chunks]).casefold()
    matched = [skill for skill in profile.skills if skill.name.casefold() in job_text]
    reasons = []
    if matched:
        reasons.append("이력서에 직접 근거가 있는 기술과 공고 키워드가 일치합니다: " + ", ".join(skill.name for skill in matched))
    role_matches = [role for role in profile.target_roles if role.casefold() in job_text]
    if role_matches:
        reasons.append("희망 직무와 공고 직무가 관련됩니다: " + ", ".join(role_matches))
    if request.preferred_locations and job.location:
        reasons.append(f"희망 근무지역 조건과 비교된 공고입니다: {job.location}")
    if job.detail_quality != "DETAILED":
        reasons.append("공고 상세 본문의 품질이 제한적이므로 선택 후 원문 확인이 필요합니다.")
    if not reasons:
        reasons.append("이력서와 공고 문서의 의미 유사도를 기준으로 검색된 결과입니다.")

    base = to_search_results([job])[0]
    return JobRecommendationResult(
        **base.model_dump(exclude={"rank"}),
        rank=rank,
        matched_resume_skills=[skill.name for skill in matched],
        resume_evidence=[skill.resume_quote for skill in matched],
        recommendation_reasons=reasons,
    )


def _retrieval_query(text: str) -> str:
    normalized = " ".join(text.split())
    return normalized[:12_000]


def _format_retrieved_jobs(jobs: list[RetrievedJob]) -> str:
    if not jobs:
        return "검색된 공고 없음"
    return "\n\n".join(
        f"[출처 ID: indexed_job:{job.job_id}]\n회사: {job.company}\n직무: {job.title}\n{job.summary}"
        for job in jobs
    )


def _deduplicate(items: list[str]) -> list[str]:
    return list(dict.fromkeys(item.strip() for item in items if item and item.strip()))
