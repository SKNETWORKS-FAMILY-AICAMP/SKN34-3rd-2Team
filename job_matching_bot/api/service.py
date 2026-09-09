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
from collections import OrderedDict, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

from job_matching_bot.api import prompts, schemas
from job_matching_bot.matching.hard_filter import hard_filter
from job_matching_bot.retrieval import search as retrieval
from job_matching_bot.retrieval import market_stats, store_search
from job_matching_bot.schemas.job_posting import Job
from job_matching_bot.schemas.resume import ResumeProfile

# 검색으로 가져올 후보 수. 하드 필터에서 일부가 떨어지므로 최종 표시분보다 넉넉히.
SEARCH_TOP_K = 25
# LLM에 넘길 상위 후보 수. 공고마다 따로, 동시에 판정하므로 늘려도 가장 느린 한 건만큼만
# 기다린다. 6건에서 12건으로 올렸을 때 실측(이력서 4종): 시간은 6.6초에서 7.0초로 0.4초
# 늘고, "높음" 판정은 9건에서 18건으로 늘었다. 벡터 검색이 위로 올린 순서가 사람이 보기에
# 늘 맞지는 않아, 적게 보면 좋은 공고를 판정도 못 해 보고 버리게 된다.
# 하드 필터를 통과하는 것이 보통 13~18건이라 12건은 그 안에 든다.
RERANK_TOP_K = 12
# 같은 회사가 목록을 채우지 않게 하는 상한.
MAX_PER_COMPANY = 2
# 재정렬에 넘길 공고 본문 길이. 메타데이터 excerpt와 같게 두어 자르지 않는다.
JOB_EXCERPT_CHARS = 1200
# LLM 추론 강도. 대조 작업이라 낮춰도 근거 품질이 유지되고 응답이 크게 빨라진다.
REASONING_EFFORT = "medium"
# 구조화 결과를 몇 벌까지 들고 있을지. 이력서 한 건이 몇 KB라 넉넉해도 가볍다.
PROFILE_CACHE_SIZE = 64


class StoreUnavailable(RuntimeError):
    """공고 저장소 파일이 없다. 팀원은 공유 파일을 받아야 한다."""


class SearchUnavailable(RuntimeError):
    """벡터 검색이나 하드 필터가 실패했다. 추천을 내보내지 않는다."""



def _build_generator(prompt, schema, effort: str | None = None):
    """프롬프트 | 구조화 출력. 첨삭 모듈과 같은 방식으로 맞춘다.

    추론 강도는 medium이다. 한때 low로 두었는데, 대조하는 일이니 깊게 생각해도 나아지지
    않으리라 본 것이었다. 이력서 하나로만 재고 내린 판단이었고, 다른 이력서로 재보니
    틀렸다. **low는 맞는 공고를 놓친다.**

    후보 12건 재정렬 실측:

        이력서        low                medium             high
        AI/데이터     8.8초 높음5 탈락1    15.3초 높음5 탈락0   58.2초 높음6 탈락3
        백엔드        8.0초 높음3 탈락3    10.8초 높음2 탈락0   31.9초 높음2 탈락0
        앱 개발       8.3초 높음1 탈락1    10.6초 높음5 탈락1   19.8초 높음4 탈락0

    앱 개발 이력서에서 low는 Flutter 공고를 1건만 "높음"으로 봤고 medium은 5건을 찾았다.
    "탈락"은 원문에 없어 검증 단계에서 지운 인용 수다 — low가 가장 많이 지어냈다.
    high는 medium보다 나은 것이 없으면서 두세 배 느리다.

    `OPENAI_REASONING_EFFORT`로 바꿀 수 있다.
    """
    import os

    from langchain_openai import ChatOpenAI

    model = ChatOpenAI(
        model=os.environ.get("OPENAI_MODEL", "gpt-5.6-luna"),
        reasoning_effort=effort
        or os.environ.get("OPENAI_REASONING_EFFORT", REASONING_EFFORT),
        max_retries=2,
    )
    return (prompt | model.with_structured_output(schema, method="json_schema")).invoke


class _LivenessMixin:
    """내려간 공고를 내보내기 직전에 걸러 내는 손잡이.

    저장소 상태는 밤에 한 번 맞춘 것이라 낮에 조기 마감된 공고를 모른다. 마감일이
    미래고 어젯밤 목록에도 있었는데 오늘 사이트에서는 "접수마감"인 공고가 실제로 있다.
    그건 페이지를 열어 봐야만 안다. 그래서 **사용자에게 나갈 것만** 그 자리에서 본다.

    확인이 안 되면(네트워크 오류·차단) 그대로 내보낸다. 잘못 지우는 것보다 낫다.
    """

    _liveness = None

    @property
    def liveness(self):
        if self._liveness is None:
            from job_matching_bot.retrieval.liveness import Liveness

            self._liveness = Liveness(self.store_path)
        return self._liveness

    def drop_dead(self, job_ids: list[str]) -> set[str]:
        """살아 있는 job_id 집합. 확인이 실패하면 전부 살아 있는 것으로 본다."""
        try:
            return set(self.liveness.alive(job_ids))
        except Exception:  # noqa: BLE001 — 확인 실패가 추천을 막을 이유는 아니다
            return set(job_ids)


class RecommendService(_LivenessMixin):
    def __init__(self, profiler=None, reranker=None, store_path: Path | None = None) -> None:
        self._profiler = profiler
        self._reranker = reranker
        self._store_path = store_path
        # 같은 이력서로 다시 추천하면 구조화를 건너뛴다. 앱은 범위(프로젝트·기술스택 …)를
        # 바꿔 가며 여러 번 부르는데, 범위마다 글이 다르므로 글 자체를 열쇠로 쓴다.
        self._profiles: OrderedDict[str, schemas.ResumeProfileOut] = OrderedDict()

    @property
    def store_path(self) -> Path:
        if self._store_path is None:
            from job_matching_bot.ingest import DEFAULT_STORE

            self._store_path = DEFAULT_STORE
        return self._store_path

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
        # 앱이 저장할 때 미리 만들어 보냈으면 그대로 쓴다. 다시 만들면 검색어가 달라져
        # 같은 이력서인데도 추천이 흔들린다.
        if request.profile is not None:
            return request.profile
        cached = self._profiles.get(request.resume_text)
        if cached is not None:
            self._profiles.move_to_end(request.resume_text)
            return cached
        try:
            profile = self.profiler({"resume_text": request.resume_text})
            self._profiles[request.resume_text] = profile
            if len(self._profiles) > PROFILE_CACHE_SIZE:
                self._profiles.popitem(last=False)
            return profile
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
        # 판정 **전에** 거른다. 내려간 공고에 LLM을 쓸 이유가 없고, 걸러 낸 만큼
        # 뒤 후보가 올라와 자리를 채운다.
        alive = self.drop_dead([hit.job_id for hit, _, _ in candidates])
        if len(alive) < len(candidates):
            warnings.append(f"마감된 공고 {len(candidates) - len(alive)}건을 제외했습니다.")
            candidates = [c for c in candidates if c[0].job_id in alive]
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
class ChatService(_LivenessMixin):
    """말을 받아 세 갈래로 답한다.

        검색   "서울 백엔드 신입 찾아줘"   → 저장소 조회, 목록
        질문   "백엔드 신입은 뭘 준비해?"  → 조건에 맞는 공고를 세어 그 숫자로 답
        공고   (목록에서 하나 고른 뒤)      → 그 공고 원문만 근거로 답

    추천과 다른 점이 둘이다. 첫째, 이력서가 아니라 **사용자가 말한 조건**으로 찾으므로
    벡터가 필요 없다. 둘째, Pinecone이 아니라 저장소를 보므로 IT 밖 공고도 답할 수 있다.

    LLM 호출 수를 갈래마다 다르게 둔다. 검색은 한 번(말→조건)이고 답 문장은 실제 결과로
    조립한다. 건수를 모르는 채 LLM이 쓰면 없는 공고를 있다고 말한다. 질문·공고는 두
    번째 호출로 답을 쓰되 **근거를 함께 준다** — 질문에는 공고를 센 표를, 공고에는 그
    공고 원문을. 근거 없이 쓰게 하면 어디서나 들을 수 있는 말이 나온다.

    대화를 서버에 저장하지 않는다. 직전 조건을 응답에 실어 보내고 앱이 되돌려준다.
    """

    def __init__(self, generator=None, store_path: Path | None = None,
                 adviser=None, job_asker=None, finder=None):
        self._generator = generator
        self._store_path = store_path
        self._adviser = adviser
        self._job_asker = job_asker
        self._finder = finder

    @property
    def finder(self):
        """뜻으로 찾는 함수. 인덱스를 실제로 부르므로 테스트에서는 갈아끼운다."""
        if self._finder is None:
            from job_matching_bot.retrieval import search as retrieval

            self._finder = retrieval.search
        return self._finder

    @property
    def generator(self):
        if self._generator is None:
            self._generator = _build_generator(prompts.CHAT_PROMPT, schemas.ChatTurnOut)
        return self._generator

    @property
    def adviser(self):
        if self._adviser is None:
            self._adviser = _build_generator(prompts.ADVICE_PROMPT, schemas.ChatAnswerOut)
        return self._adviser

    @property
    def job_asker(self):
        if self._job_asker is None:
            self._job_asker = _build_generator(prompts.JOB_ASK_PROMPT, schemas.ChatAnswerOut)
        return self._job_asker

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

        # 공고를 골라 물은 경우. 무슨 말이든 그 공고에 대한 물음이므로 의도를 가르지 않는다.
        if request.job_id:
            return self._ask_job(request, previous)

        turn = self.generator(
            {
                "previous": previous.model_dump_json(),
                "message": request.message,
            }
        )

        if turn.unavailable:
            return self._unavailable(turn.unavailable, previous)

        if turn.intent == "잡담":
            return schemas.JobChatResponse(
                mode="안내",
                reply=(
                    "채용에 대한 것을 도와드릴 수 있어요.\n"
                    "공고를 찾으시려면 \u201c서울 백엔드 신입\u201d처럼, "
                    "궁금한 게 있으시면 \u201c백엔드 신입은 뭘 준비해야 해?\u201d처럼 물어보세요."
                ),
                filters=previous,
                total=0,
                suggestions=["서울 백엔드 신입", "요즘 많이 요구하는 기술이 뭐야?"],
            )

        if turn.intent == "추천":
            # 챗봇은 이력서를 받지 않는다. 앱이 이 mode를 보고 추천으로 넘긴다.
            # 여기서 검색을 하면 앞 대화에 남은 조건으로 엉뚱한 목록이 나간다.
            source = {
                "프로젝트": "이력서의 프로젝트 경험만",
                "기술스택": "이력서의 기술스택만",
                "자기소개서": "이력서의 자기소개서만",
                "경력": "이력서의 경력만",
            }.get(turn.resume_scope, "이력서를")
            return schemas.JobChatResponse(
                mode="추천",
                resume_scope=turn.resume_scope,
                reply=f"{source} 읽고 맞는 공고를 골라 드릴게요.",
                filters=previous,
                total=0,
            )

        filters = _to_job_filters(turn.filters)

        if turn.intent == "질문":
            return self._advise(request, turn, filters)

        # 조건이 하나도 안 잡혔다고 바로 되묻지 않는다. "돈 다루는 일"처럼 조건으로
        # 옮길 말이 없는 경우가 있고, 그때는 뜻으로 찾으면 된다. 되묻는 것은 뜻으로
        # 찾을 문장마저 없을 때다.
        if filters.is_empty and not turn.requirement_query:
            return schemas.JobChatResponse(
                mode="안내",
                reply=turn.understood or "어떤 일을 찾으시는지 알려 주세요. 예: 데이터 분석 신입",
                filters=turn.filters,
                total=0,
            )

        result = (
            store_search.SearchResult(jobs=[], total=0, scanned_cap=False, strong=0)
            if filters.is_empty
            else store_search.search(self.store_path, filters, limit=request.top_k)
        )

        # 조건으로 못 찾았으면 뜻으로 찾는다. 사용자가 말한 직무·기술이 공고에 그대로
        # 적히는 말이 아닐 때(예: "돈 다루는 일") 여기서만 답이 나온다.
        by_meaning = False
        if turn.requirement_query and self._needs_meaning(filters, result):
            found = self._by_meaning(turn.requirement_query, filters, request.top_k)
            if found:
                result = store_search.SearchResult(
                    jobs=found, total=len(found), scanned_cap=False, strong=0
                )
                by_meaning = True

        # 보여 주기 직전에 내려간 공고를 뺀다. 저장소가 OPEN이라고 해도 사이트에서
        # 이미 마감됐을 수 있다 — 그건 열어 봐야만 안다.
        shown = result.jobs
        if shown:
            alive = self.drop_dead([hit.job_id for hit in shown])
            if len(alive) < len(shown):
                shown = [hit for hit in shown if hit.job_id in alive]
                result = store_search.SearchResult(
                    jobs=shown,
                    total=max(result.total - (len(result.jobs) - len(shown)), len(shown)),
                    scanned_cap=result.scanned_cap,
                    strong=min(result.strong, len(shown)),
                )

        return schemas.JobChatResponse(
            reply=self._reply(turn.understood, filters, result, by_meaning),
            filters=turn.filters,
            jobs=[_to_chat_job(hit) for hit in shown],
            total=result.total,
            suggestions=_suggestions(filters, result),
        )

    @staticmethod
    def _unavailable(kind: str, previous) -> schemas.JobChatResponse:
        """모으지 않는 것으로 찾아 달라고 했다. 없다고 말하고 할 수 있는 것을 권한다.

        "조건을 빼 보라"고 하면 안 된다. 빼면 찾을 수 있다는 뜻인데 그렇지 않다.
        왜 없는지도 밝힌다. 그래야 사용자가 다른 데서 찾아본다.
        """
        return schemas.JobChatResponse(
            mode="안내",
            reply=_UNAVAILABLE[kind],
            filters=previous,
            total=0,
            suggestions=_UNAVAILABLE_NEXT[kind],
        )

    @staticmethod
    def _needs_meaning(filters, result) -> bool:
        """조건 검색이 실패했나. 실패에 두 가지가 있다.

        하나는 0건이고, 하나는 **제목·태그에 하나도 안 걸린 것**이다. 후자는 본문에
        말이 스친 범용 공고("전 직군 공개채용")만 걸린 경우라, 건수는 많아도 물어본
        일과 상관이 없다.

        조건이 아예 안 잡힌 경우도 실패다. "돈 다루는 일"은 조건으로 옮길 말이 없어
        LLM이 비워 둔다. 그때는 뜻으로 찾는 수밖에 없다.

        다만 지역·경력만 걸었으면(찾을 말이 없으면) 조건 조회가 정확하므로 뜻으로 찾지
        않는다. 이걸 빼먹으면 "서울만" 같은 말에도 매번 벡터를 부르게 된다.
        """
        if filters.is_empty:
            return True
        if not (filters.roles or filters.skills or filters.keywords):
            return False
        return result.total == 0 or result.strong == 0

    def _by_meaning(self, query: str, filters, top_k: int) -> list:
        """뜻이 가까운 공고. 인덱스에서 찾아 저장소에서 다시 읽는다.

        여기서 실패해도 대화를 끊지 않는다. 조건 검색 결과가 이미 있고, 없으면 없다고
        답하면 된다. 인덱스가 안 붙었다고 챗봇 전체가 멈출 이유가 없다.
        """
        from job_matching_bot.retrieval import search as retrieval

        try:
            condition = retrieval.build_filter(
                regions=filters.regions,
                employment_types=filters.employment_types,
                # 신입이라고 했을 때만 경력 하한을 건다. 나머지는 걸지 않는다.
                career_years=0 if filters.career == "신입" else 5,
            )
            # 마감된 것이 걸러져 줄어드므로 넉넉히 가져온다.
            hits = self.finder(query, top_k=top_k * 3, filter=condition)
        except Exception as error:
            print(f"[챗봇] 의미 검색 실패, 조건 결과로 답한다: {type(error).__name__}: {error}")
            return []
        found = store_search.by_ids(self.store_path, [hit.job_id for hit in hits])
        return found[:top_k]

    def _advise(self, request, turn, filters) -> schemas.JobChatResponse:
        """채용 질문에 답한다. 조건이 잡혔으면 그 조건의 공고를 세어 근거로 준다.

        "백엔드 신입은 뭘 준비해?"는 셀 수 있고 "자소서 어떻게 써?"는 셀 것이 없다.
        후자에 표를 주면 상관없는 숫자가 답의 첫 문단을 차지한다. 조건이 남아 있느냐가
        아니라 **이번 물음이 세어서 답할 것이냐**로 가른다. 그 판정은 조건을 뽑을 때
        같이 받아 두므로 LLM을 더 부르지 않는다.

        조건이 비어 있어도 센다. "요즘 많이 요구하는 기술이 뭐야?"에는 조건이 없지만
        **전체를 세면** 답이 나온다. 조건이 없다고 세지 않았더니 세어 달라는 질문에
        "저희가 모은 공고로는 알 수 없어요"라고 답했다.
        """
        stats = None
        if turn.counts_jobs:
            stats = market_stats.summarize(self.store_path, filters)
        grounded = bool(stats and stats.total)

        answer = self.adviser(
            {
                "condition": filters.summary(),
                "stats": stats.to_prompt() if grounded else "(이 물음은 공고를 세어 답할 것이 아니다)",
                "question": request.message,
            }
        )
        return schemas.JobChatResponse(
            mode="질문",
            reply=answer.answer,
            filters=turn.filters,
            total=stats.total if grounded else 0,
            # 답의 근거가 된 공고를 몇 건 붙인다. 숫자만 있으면 확인할 길이 없다.
            jobs=self._peek(filters, request.top_k) if grounded else [],
            suggestions=answer.followups[:3],
        )

    def _ask_job(self, request, previous) -> schemas.JobChatResponse:
        """공고 하나를 놓고 묻는다. 그 공고 원문만 근거로 쓴다."""
        from job_matching_bot.ingestion.sqlite_store import SqliteJobStore

        with SqliteJobStore(self.store_path) as store:
            record = store.get(request.job_id)
        if record is None:
            return schemas.JobChatResponse(
                mode="안내",
                reply="그 공고를 저장소에서 찾지 못했어요. 마감되어 내려갔을 수 있어요.",
                filters=previous,
                total=0,
            )

        answer = self.job_asker(
            {"job": _job_text(record.job), "question": request.message}
        )
        return schemas.JobChatResponse(
            mode="공고",
            reply=answer.answer,
            filters=previous,
            total=0,
            suggestions=answer.followups[:3],
        )

    def _peek(self, filters, top_k: int) -> list[schemas.JobChatJob]:
        """센 조건에 맞는 공고 몇 건. 답에 붙여 숫자를 눈으로 확인하게 한다."""
        result = store_search.search(self.store_path, filters, limit=min(top_k, 3))
        return [_to_chat_job(hit) for hit in result.jobs]

    @staticmethod
    def _reply(understood: str, filters, result, by_meaning: bool = False) -> str:
        """실제 결과로 답을 만든다. 건수를 모르는 채로 LLM이 쓰면 틀린 말을 하게 된다."""
        condition = filters.summary()
        if result.total == 0:
            return (
                f"{condition} 조건으로는 열려 있는 공고를 찾지 못했어요. "
                "조건을 하나 빼거나 지역을 넓혀 보시겠어요?"
            )
        if by_meaning:
            # 어떻게 찾았는지 밝힌다. 조건에 맞는 공고를 센 것처럼 보이면 안 된다.
            head = understood.strip() or "찾아볼게요."
            found = f"뜻이 가까운 공고를 {len(result.jobs)}건 찾았어요."
            if filters.is_empty:
                return f"{head}\n말씀하신 말이 공고에 그대로 적히는 말은 아니라서, {found}"
            return f"{head}\n{condition} 조건 그대로는 걸리는 공고가 없어서, {found}"
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


# 모으지 않는 것들. 왜 못 하는지까지 말한다. 실측에 근거한 숫자를 그대로 쓴다.
_UNAVAILABLE = {
    "급여": (
        "급여로는 줄을 세울 수 없어요. 공고 10건 중 9건이 급여를 \u201c면접 후 결정\u201d으로 "
        "적어 두거든요. 남은 1건도 대부분 최저임금 안내라, 급여로 정렬하면 정작 많이 주는 "
        "곳이 빠지고 순서가 거꾸로 나옵니다.\n"
        "대신 직무·지역·경력으로 좁혀 드릴 수 있어요. 급여는 공고를 열어 확인하시는 게 정확합니다."
    ),
    "복지": (
        "복지로 줄을 세우지는 못해요. 공고마다 적는 방식이 달라 비교할 수 있는 값이 아니거든요.\n"
        "찾으시는 조건(재택, 유연근무 같은)을 말씀해 주시면 그 말이 적힌 공고를 찾아 드릴게요."
    ),
    "합격 가능성": (
        "합격 가능성이나 경쟁률은 알 수 없어요. 지원자 수는 공개되지 않습니다.\n"
        "대신 이력서를 읽고 어느 공고가 요건에 가까운지는 골라 드릴 수 있어요."
    ),
    "회사 평판": (
        "회사 분위기나 평판은 저희가 가지고 있지 않아요. 채용공고에 적힌 것만 봅니다.\n"
        "직무·지역·경력으로 찾아 드리고, 고른 공고에 무엇이 적혀 있는지는 자세히 알려 드릴게요."
    ),
}

_UNAVAILABLE_NEXT = {
    "급여": ["서울 신입 공고 보여줘", "대기업 공고만"],
    "복지": ["재택 되는 공고", "정규직만"],
    "합격 가능성": ["내 이력서로 추천해줘", "신입도 되는 공고"],
    "회사 평판": ["대기업 공고만", "서울 공고 보여줘"],
}


def _to_chat_job(hit) -> schemas.JobChatJob:
    return schemas.JobChatJob(
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


def _job_text(job) -> str:
    """공고 한 건을 LLM이 읽을 글로. 본문은 자르지 않는다 — 요건은 대개 뒤쪽에 있다."""
    lines = [
        f"회사: {job.company}",
        f"제목: {job.title}",
        f"지역: {job.region or '미기재'}",
        f"경력: {store_search._career_label(job.career_type or '', job.min_career_years)}",
        f"학력: {job.education or '미기재'}",
        f"고용형태: {job.employment_type or '미기재'}",
        f"마감: {job.deadline or '미기재'}",
    ]
    if job.tech_stack:
        lines.append("기술 태그: " + ", ".join(job.tech_stack))
    if job.required_certifications:
        lines.append("자격증: " + ", ".join(job.required_certifications))
    lines.append("")
    lines.append(job.description or "(본문 없음)")
    return "\n".join(lines)


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
