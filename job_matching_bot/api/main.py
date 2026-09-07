"""추천 API 서버.

    uvicorn job_matching_bot.api.main:app --reload --port 8010

앱은 이력서 평문과 희망 조건을 보내고, 서버는 추천 목록과 근거 문장을 돌려준다.
이력서는 저장하지 않는다. 임베딩해 검색에 쓰고 응답 후 버린다.

CORS는 개발용이다. `functions/.env`의 두 값으로 켠다. 둘 다 비어 있으면 아무 출처도
허용하지 않으므로 배포본은 그대로 두면 된다.

    CORS_ALLOW_ORIGINS       정확히 일치하는 출처 목록(쉼표 구분)
    CORS_ALLOW_ORIGIN_REGEX  정규식. 개발 중에는 로컬호스트의 아무 포트나 허용한다

`flutter run -d chrome`은 실행할 때마다 포트가 달라진다. 포트를 고정하지 않아도 되게
`CORS_ALLOW_ORIGIN_REGEX = 'http://(localhost|127\.0\.0\.1)(:\d+)?'` 를 쓴다.
로컬호스트만 매칭하므로 외부 사이트는 여전히 막힌다.
"""

from __future__ import annotations

import os

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from job_matching_bot.api import schemas
from job_matching_bot.api.service import (
    FeedbackService,
    JobNotFound,
    JobTextUnavailable,
    RecommendService,
    SearchUnavailable,
)
from job_matching_bot.env import ensure_loaded
from job_matching_bot.retrieval.pinecone_index import client, index_name

app = FastAPI(
    title="AI 취업 코치 — 채용공고 추천 API",
    version="0.1.0",
    description="이력서를 읽고 채용공고를 추천한다. 벡터 검색 + LLM 재정렬 + 근거 검증.",
)

ensure_loaded()

_origins = [
    origin.strip()
    for origin in os.environ.get("CORS_ALLOW_ORIGINS", "").split(",")
    if origin.strip()
]
_origin_regex = os.environ.get("CORS_ALLOW_ORIGIN_REGEX", "").strip() or None
if _origins or _origin_regex:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_origins,
        allow_origin_regex=_origin_regex,
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type", "Authorization"],
    )

_service = RecommendService()
_feedback = FeedbackService()


@app.get("/health", response_model=schemas.HealthResponse)
def health() -> schemas.HealthResponse:
    try:
        stats = client().Index(index_name()).describe_index_stats()
        count = int(stats.get("total_vector_count", 0))
    except Exception:
        count = -1
    return schemas.HealthResponse(
        index_name=index_name(),
        vector_count=count,
        llm_configured=bool(os.environ.get("OPENAI_API_KEY")),
    )


@app.post("/api/v1/jobs/recommend", response_model=schemas.RecommendResponse)
def recommend(request: schemas.RecommendRequest) -> schemas.RecommendResponse:
    try:
        return _service.recommend(request)
    except SearchUnavailable as error:
        # 검색이나 조건 판정이 실패하면 추천하지 않는다. 근거 없는 목록을 보여 주지 않는다.
        raise HTTPException(status_code=503, detail=str(error)) from error


@app.post("/api/v1/jobs/feedback", response_model=schemas.JobFeedbackResponse)
def job_feedback(request: schemas.JobFeedbackRequest) -> schemas.JobFeedbackResponse:
    """고른 공고 하나를 기준으로 이력서에 피드백을 준다.

    읽기만 하므로 저장 전 초안으로도 받을 수 있다. 이력서를 저장하거나 고치지 않는다.
    """
    try:
        return _feedback.feedback(request)
    except JobNotFound as error:
        raise HTTPException(status_code=404, detail="저장소에 없는 공고입니다.") from error
    except JobTextUnavailable as error:
        raise HTTPException(
            status_code=422,
            detail="이 공고는 상세가 이미지뿐이라 대조할 글이 없습니다.",
        ) from error
