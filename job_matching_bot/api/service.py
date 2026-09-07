"""추천 서비스. 다섯 단계를 순서대로 실행한다.

    ① LLM 구조화   이력서 → 검색 질의문
    ② 벡터 검색     Pinecone Top-N (조건 필터 동시 적용)
    ③ 하드 필터     경력·학력·희망 조건으로 후보 좁히기
    ④ LLM 재정렬    상위 N건의 적합도와 근거 문장
    ⑤ 근거 검증     원문에 없는 인용 제거, 회사당 상한 적용

실패했을 때의 방침이 단계마다 다르다.

- ①·④ 실패 → 이어서 진행한다. ①은 이력서 원문으로 검색하고, ④는 검색 순서를 쓴다.
  결과 품질이 떨어질 뿐 엉뚱한 공고가 나오지는 않는다.
- ②·③ 실패 → **추천하지 않는다.** 검색이 안 되면 근거가 없고, 하드 필터가 안 돌면
  조건 위반 공고가 나간다. 아무거나 보여 주는 것보다 실패를 알리는 편이 낫다.
"""

from __future__ import annotations

import json
import re
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

from job_matching_bot.api import prompts, schemas
from job_matching_bot.matching.hard_filter import hard_filter
from job_matching_bot.retrieval import search as retrieval
from job_matching_bot.retrieval import store_search
from job_matching_bot.schemas.job_posting import Job
from job_matching_bot.schemas.resume import ResumeProfile

# 검색으로 가져올 후보 수. 하드 필터에서 일부가 떨어지므로 최종 표시분보다 넉넉히.
SEARCH_TOP_K = 25
# LLM에 넘길 상위 후보 수. 재정렬이 전체 응답 시간의 3분의 2를 차지하므로,
# 최종 표시할 건수보다 조금만 크게 둔다.
RERANK_TOP_K = 6
# 같은 회사가 목록을 채우지 않게 하는 상한.
MAX_PER_COMPANY = 2
# 재정렬에 넘길 공고 본문 길이. 메타데이터 excerpt와 같게 두어 자르지 않는다.
JOB_EXCERPT_CHARS = 1200
# LLM 추론 강도. 대조 작업이라 낮춰도 근거 품질이 유지되고 응답이 크게 빨라진다.
REASONING_EFFORT = "low"


class StoreUnavailable(RuntimeError):
    """공고 저장소 파일이 없다. 팀원은 공유 파일을 받아야 한다."""


class SearchUnavailable(RuntimeError):
    """벡터 검색이나 하드 필터가 실패했다. 추천을 내보내지 않는다."""



def _build_generator(prompt, schema):
    """프롬프트 | 구조화 출력. 첨삭 모듈과 같은 방식으로 맞춘다.

    추론 강도를 낮게 둔다. 이 단계들은 새로운 것을 궁리하는 일이 아니라 두 글을 대조해
    인용을 찾아내는 일이라, 깊게 생각하게 해도 결과가 나아지지 않고 시간만 는다.
    실측(공고 6건 재정렬): 기본 33.8초 / low 17.9초 / none 9.4초, 근거 개수는 11개로 같았다.
    `OPENAI_REASONING_EFFORT`로 바꿀 수 있다.
    """
    import os

    from langchain_openai import ChatOpenAI

    model = ChatOpenAI(
        model=os.environ.get("OPENAI_MODEL", "gpt-5.6-luna"),
        reasoning_effort=os.environ.get("OPENAI_REASONING_EFFORT", REASONING_EFFORT),
        max_retries=2,
    )
    return (prompt | model.with_structured_output(schema, method="json_schema")).invoke


class RecommendService:
    def __init__(self, profiler=None, reranker=None) -> None:
        self._profiler = profiler
        self._reranker = reranker

    @property
    def profiler(self):
        if self._profiler is None:
            self._profiler = _build_generator(prompts.PROFILE_PROMPT, schemas.ResumeProfileOut)
        return self._profiler

    @property
    def reranker(self):
        if self._reranker is None:
            self._reranker = _build_generator(prompts.RERANK_PROMPT, schemas.RerankOut)
        return self._reranker

    # ── ① 이력서 구조화 ──────────────────────────────
    def build_profile(
        self, request: schemas.RecommendRequest, warnings: list[str]
    ) -> schemas.ResumeProfileOut:
        try:
            return self.profiler({"resume_text": request.resume_text})
        except Exception as error:
            warnings.append(f"이력서 구조화에 실패해 원문으로 검색합니다: {type(error).__name__}")
            return schemas.ResumeProfileOut(
                search_query=request.resume_text[:2000],
                target_roles=[],
                skills=[],
                career_years=request.career_years,
                summary="",
            )

    # ── ③ 하드 필터용 프로필 ─────────────────────────
    @staticmethod
    def to_resume_profile(
        request: schemas.RecommendRequest, profile: schemas.ResumeProfileOut
    ) -> ResumeProfile:
        return ResumeProfile(
            resume_id="api",
            target_roles=profile.target_roles,
            skills=profile.skills,
            project_skills=profile.skills,
            preferred_regions=request.preferred_regions,
            preferred_employment_types=request.preferred_employment_types,
            education_level=request.education_level,
            career_years=int(max(request.career_years, profile.career_years)),
            majors=request.majors,
            certifications=request.certifications,
        )

    @staticmethod
    def hit_to_job(hit: retrieval.Hit) -> Job:
        """검색 결과 메타데이터를 하드 필터가 읽는 Job으로. 원문은 excerpt만 있다."""
        meta = hit.metadata
        years = meta.get("min_career_years")
        return Job(
            job_id=hit.job_id,
            source=str(meta.get("source", "")),
            source_job_id=hit.job_id.split("-")[-1],
            source_url=str(meta.get("source_url", "")),
            company=str(meta.get("company", "")),
            company_type="",
            title=str(meta.get("title", "")),
            description=str(meta.get("excerpt", "")),
            required_skills=list(meta.get("required_skills") or []),
            preferred_skills=list(meta.get("preferred_skills") or []),
            tech_stack=list(meta.get("tech_stack") or []),
            career_type=str(meta.get("career_type", "ANY")),
            min_career_years=None if years in (None, -1) else int(years),
            education=str(meta.get("education", "미기재")),
            region=str(meta.get("region_text", "미기재")),
            employment_type=str(meta.get("employment_type", "미기재")),
            posted_at=None,
            deadline=(meta.get("deadline") or None),
            status=str(meta.get("status", "OPEN")),
            content_hash=str(meta.get("content_hash", "")),
            parser_version="api",
            field_provenance={},
            body_is_image=bool(meta.get("body_is_image", False)),
        )

    # ── ④ 재정렬 ─────────────────────────────────────
    @staticmethod
    def _job_payload(job: Job) -> dict[str, str]:
        return {
            "job_id": job.job_id,
            "company": job.company,
            "title": job.title,
            "conditions": f"{job.region} · {job.career_type} · {job.employment_type} · {job.education}",
            "body": job.description[:JOB_EXCERPT_CHARS],
        }

    def rerank(
        self, resume_text: str, candidates: list[tuple[retrieval.Hit, Job, dict]], warnings: list[str]
    ) -> tuple[dict[str, schemas.JobFit], bool]:
        """공고를 한 건씩 **동시에** 판정한다.

        예전에는 6건을 한 프롬프트에 넣어 한 번 불렀다. 모델이 순서대로 처리하므로
        시간이 건수에 비례해 늘었다(실측 28.8초, 1건만이면 9.3초). 나눠서 동시에 부르면
        가장 느린 한 건만큼만 기다린다. 판정은 공고마다 독립이라 나눠도 결과가 달라지지 않는다.

        한 건이 실패해도 나머지는 살린다. 전부 실패했을 때만 검색 순서로 물러난다.
        """
        if not candidates:
            return {}, False

        def judge(job: Job) -> schemas.RerankOut:
            return self.reranker(
                {
                    "resume_text": resume_text,
                    "jobs": json.dumps([self._job_payload(job)], ensure_ascii=False, indent=2),
                }
            )

        fits: dict[str, schemas.JobFit] = {}
        failures: list[str] = []
        with ThreadPoolExecutor(max_workers=len(candidates)) as pool:
            futures = {pool.submit(judge, job): job for _, job, _ in candidates}
            for future in as_completed(futures):
                job = futures[future]
                try:
                    for fit in future.result().results:
                        fits[fit.job_id] = fit
                except Exception as error:
                    failures.append(f"{job.job_id}({type(error).__name__})")

        if failures:
            warnings.append(f"일부 공고를 분석하지 못해 검색 순서로 표시합니다: {', '.join(failures)}")
        return fits, bool(fits)

    # ── ⑤ 근거 검증 ──────────────────────────────────
    @staticmethod
    def verify(fit: schemas.JobFit, resume_text: str, job: Job, warnings: list[str]) -> schemas.JobFit:
        """모델이 낸 인용이 양쪽 원문에 실제로 있는지 대조한다.

        공백만 다른 경우까지 지어낸 것으로 보면 안 된다. 사람인 공고 본문에는
        ` `(줄바꿈 없는 공백)과 줄바꿈이 섞여 있어, 모델이 같은 문장을 옮겨 적어도
        정확 일치가 깨진다. 실측에서 실패한 인용 6건 중 5건이 이 경우였다.
        그래서 공백을 하나로 접어 비교하되, **글자는 그대로여야 한다.**
        """
        kept: list[schemas.Reason] = []
        for reason in fit.reasons:
            if not _quote_in(reason.resume_quote, resume_text):
                warnings.append(f"이력서에 없는 인용을 제거했습니다: {reason.resume_quote[:40]}")
                continue
            if not _quote_in(reason.job_quote, job.description):
                warnings.append(f"공고에 없는 인용을 제거했습니다: {reason.job_quote[:40]}")
                continue
            kept.append(reason)

        fit = fit.model_copy(update={"reasons": kept})
        if not kept and fit.fit != "낮음":
            # 근거를 하나도 못 대면 "낮음"이다. 이유 없이 추천 목록에 올리지 않는다.
            fit = fit.model_copy(update={"fit": "낮음"})
        return fit

    # ── 전체 ─────────────────────────────────────────
    def recommend(self, request: schemas.RecommendRequest) -> schemas.RecommendResponse:
        warnings: list[str] = []
        profile = self.build_profile(request, warnings)

        try:
            hits = retrieval.search(
                profile.search_query,
                SEARCH_TOP_K,
                retrieval.build_filter(
                    request.preferred_regions,
                    request.preferred_employment_types,
                    max(request.career_years, profile.career_years),
                ),
            )
        except Exception as error:
            raise SearchUnavailable(f"공고 검색에 실패했습니다: {type(error).__name__}") from error
        if not hits:
            return schemas.RecommendResponse(
                recommendations=[],
                search_query=profile.search_query,
                profile_summary=profile.summary,
                reranked=False,
                warnings=[*warnings, "조건에 맞는 공고를 찾지 못했습니다."],
            )

        resume_profile = self.to_resume_profile(request, profile)
        candidates: list[tuple[retrieval.Hit, Job, dict]] = []
        try:
            for hit in hits:
                job = self.hit_to_job(hit)
                result = hard_filter(job, resume_profile)
                if result["status"] == "FAIL":
                    continue
                candidates.append((hit, job, result))
        except Exception as error:
            raise SearchUnavailable(f"조건 판정에 실패했습니다: {type(error).__name__}") from error

        candidates = candidates[:RERANK_TOP_K]
        fits, reranked = self.rerank(request.resume_text, candidates, warnings)

        order = {"높음": 0, "보통": 1, "낮음": 2}
        rows: list[tuple[int, int, schemas.Recommendation]] = []
        for hit, job, filter_result in candidates:
            fit = fits.get(job.job_id)
            if fit is not None:
                fit = self.verify(fit, request.resume_text, job, warnings)
            rows.append(
                (
                    order.get(fit.fit, 1) if fit else 1,
                    hit.rank,
                    schemas.Recommendation(
                        job_id=job.job_id,
                        company=job.company,
                        title=job.title,
                        source_url=job.source_url,
                        fit=fit.fit if fit else "보통",
                        reasons=fit.reasons if fit else [],
                        concerns=fit.concerns if fit else [],
                        conditions=schemas.Conditions(
                            region=job.region,
                            employment_type=job.employment_type,
                            career=_career_label(job),
                            education=job.education,
                            deadline=job.deadline,
                        ),
                        filter_status=filter_result["status"],
                        unknown_conditions=filter_result["unknown"],
                        passed_conditions=filter_result["passed"],
                        search_rank=hit.rank,
                        body_is_image=job.body_is_image,
                    ),
                )
            )

        rows.sort(key=lambda r: (r[0], r[1]))
        limited = _limit_per_company(row[2] for row in rows)
        return schemas.RecommendResponse(
            recommendations=limited[: request.top_k],
            search_query=profile.search_query,
            profile_summary=profile.summary,
            reranked=reranked,
            warnings=_deduplicate(warnings),
        )


_WHITESPACE = re.compile(r"\s+")


def _normalize_quote(text: str) -> str:
    """공백을 하나로 접는다. ` ` 같은 특수 공백도 일반 공백으로 본다."""
    return _WHITESPACE.sub(" ", (text or "").replace(" ", " ")).strip()


def _quote_in(quote: str, source: str) -> bool:
    """인용이 원문에 있는가. 공백 차이는 무시하고 글자만 본다."""
    normalized = _normalize_quote(quote)
    if not normalized:
        return False
    return normalized in _normalize_quote(source)


def _career_label(job: Job) -> str:
    if job.career_type == "ENTRY":
        return "신입"
    if job.career_type == "ANY":
        return "경력무관"
    if job.career_type == "EXPERIENCED":
        return "경력" if job.min_career_years is None else f"경력 {job.min_career_years}년 이상"
    return "미기재"


def _limit_per_company(rows) -> list[schemas.Recommendation]:
    """한 회사가 목록을 채우지 않게 상한을 둔다.

    지점별·연차별로 나눠 올린 공고가 본문이 같아 나란히 올라오는 일이 있다.
    """
    seen: dict[str, int] = defaultdict(int)
    kept: list[schemas.Recommendation] = []
    for row in rows:
        if seen[row.company] >= MAX_PER_COMPANY:
            continue
        seen[row.company] += 1
        kept.append(row)
    return kept


def _deduplicate(items: list[str]) -> list[str]:
    return list(dict.fromkeys(item for item in items if item))


# ── 공고 찾아보기 챗봇 ───────────────────────────────────
class ChatService:
    """말로 조건을 받아 저장소에서 공고를 찾는다.

    추천과 다른 점이 둘이다. 첫째, 이력서가 아니라 **사용자가 말한 조건**으로 찾으므로
    벡터가 필요 없다. 둘째, Pinecone이 아니라 저장소를 보므로 IT 밖 공고도 답할 수 있다.

    LLM은 한 번만 부른다. 말을 조건으로 바꾸는 데만 쓰고, 답 문장은 실제 결과로 조립한다.
    두 번 부르면 말맛은 좋아지겠지만 몇 초가 더 걸린다.

    대화를 서버에 저장하지 않는다. 직전 조건을 응답에 실어 보내고 앱이 되돌려준다.
    """

    def __init__(self, generator=None, store_path: Path | None = None):
        self._generator = generator
        self._store_path = store_path

    @property
    def generator(self):
        if self._generator is None:
            self._generator = _build_generator(prompts.CHAT_PROMPT, schemas.ChatTurnOut)
        return self._generator

    @property
    def store_path(self) -> Path:
        if self._store_path is None:
            from job_matching_bot.ingest import DEFAULT_STORE

            self._store_path = DEFAULT_STORE
        return self._store_path

    def chat(self, request: schemas.JobChatRequest) -> schemas.JobChatResponse:
        if not self.store_path.exists():
            raise StoreUnavailable("공고 저장소가 없습니다. 공유 파일을 먼저 받아 주세요.")

        previous = request.filters or schemas.ChatFilters()
        turn = self.generator(
            {
                "previous": previous.model_dump_json(),
                "message": request.message,
            }
        )

        if turn.off_topic:
            return schemas.JobChatResponse(
                reply="공고 찾기를 도와드릴게요. 직무나 지역을 말씀해 주세요. 예: 서울 백엔드 신입",
                filters=previous,
                total=0,
            )

        filters = _to_job_filters(turn.filters)
        if filters.is_empty:
            return schemas.JobChatResponse(
                reply=turn.understood or "어떤 일을 찾으시는지 알려 주세요. 예: 데이터 분석 신입",
                filters=turn.filters,
                total=0,
            )

        result = store_search.search(self.store_path, filters, limit=request.top_k)
        return schemas.JobChatResponse(
            reply=self._reply(turn.understood, filters, result),
            filters=turn.filters,
            jobs=[
                schemas.JobChatJob(
                    job_id=hit.job_id,
                    company=hit.company,
                    title=hit.title,
                    source_url=hit.source_url,
                    region=hit.region,
                    career=hit.career_label,
                    employment_type=hit.employment_type,
                    deadline=hit.deadline,
                    tech_stack=hit.tech_stack,
                )
                for hit in result.jobs
            ],
            total=result.total,
            suggestions=_suggestions(filters, result),
        )

    @staticmethod
    def _reply(understood: str, filters, result) -> str:
        """실제 결과로 답을 만든다. 건수를 모르는 채로 LLM이 쓰면 틀린 말을 하게 된다."""
        condition = filters.summary()
        if result.total == 0:
            return (
                f"{condition} 조건으로는 열려 있는 공고를 찾지 못했어요. "
                "조건을 하나 빼거나 지역을 넓혀 보시겠어요?"
            )
        head = understood.strip() or f"{condition} 조건으로 찾았어요."
        # 제목·태그에 직접 맞은 건수를 따로 말한다. 본문에 말이 스친 범용 공고까지
        # 뭉뚱그려 세면 실제보다 훨씬 많아 보인다.
        if result.strong and result.strong < result.total:
            counted = f"{result.total}건 중 직무가 맞는 건 {result.strong}건이에요"
        else:
            counted = f"{result.total}건" + ("이 넘어요" if result.scanned_cap else "이에요")
        shown = len(result.jobs)
        tail = f" 관련도 순으로 {shown}건 보여드릴게요." if result.total > shown else ""
        return f"{head}" + "\n" + f"{condition} · {counted}.{tail}"


def _to_job_filters(filters: schemas.ChatFilters):
    return store_search.JobFilters(
        roles=filters.roles,
        skills=filters.skills,
        regions=filters.regions,
        career=filters.career,
        employment_types=filters.employment_types,
        deadline_within_days=filters.deadline_within_days,
        keywords=filters.keywords,
    )


def _suggestions(filters, result) -> list[str]:
    """다음에 좁힐 거리. 사용자가 그대로 눌러 보낼 수 있는 말로 준다.

    이미 건 조건은 다시 권하지 않는다. 결과가 없으면 넓히는 쪽을 권한다.
    """
    if result.total == 0:
        wider = []
        if filters.regions:
            wider.append("지역 상관없이")
        if filters.career != "무관":
            wider.append("경력 상관없이")
        if filters.deadline_within_days:
            wider.append("마감 상관없이")
        return wider[:3]

    narrower = []
    if not filters.regions:
        narrower.append("서울만")
    if filters.career == "무관":
        narrower.append("신입만")
    if not filters.deadline_within_days:
        narrower.append("마감 임박한 것만")
    if not filters.employment_types:
        narrower.append("정규직만")
    return narrower[:3]
