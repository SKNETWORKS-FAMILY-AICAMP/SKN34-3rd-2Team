import re
from collections.abc import Callable

from langchain_openai import ChatOpenAI

from app.config import Settings
from app.models import (
    JobSearchResponse,
    RequirementStatus,
    ReviewGeneration,
    ReviewRequest,
    ReviewResponse,
    SourceReference,
)
from app.prompts import REVIEW_PROMPT
from app.vector_store import JobRepository, RetrievedJob, to_search_results


NUMBER_PATTERN = re.compile(r"(?<![A-Za-z가-힣])\d+(?:[.,]\d+)*(?:%|명|건|개|개월|년|일|시간|분|초|ms)?")


class CoverLetterService:
    def __init__(
        self,
        settings: Settings,
        repository: JobRepository,
        generator: Callable[[dict[str, str]], ReviewGeneration] | None = None,
    ) -> None:
        self._settings = settings
        self._repository = repository
        self._generator = generator or self._build_generator(settings)

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

    def search_jobs(self, resume_text: str, top_k: int) -> JobSearchResponse:
        jobs = self._repository.search(_retrieval_query(resume_text), top_k)
        return JobSearchResponse(results=to_search_results(jobs))

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

