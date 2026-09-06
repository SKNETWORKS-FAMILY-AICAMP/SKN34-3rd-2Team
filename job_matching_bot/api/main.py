"""추천 API 서버.

    uvicorn job_matching_bot.api.main:app --reload --port 8010

앱은 이력서 평문과 희망 조건을 보내고, 서버는 추천 목록과 근거 문장을 돌려준다.
이력서는 저장하지 않는다. 임베딩해 검색에 쓰고 응답 후 버린다.

CORS는 개발용이다. `functions/.env`의 `CORS_ALLOW_ORIGINS`에 출처를 적어야 켜진다.
비어 있으면 아무 출처도 허용하지 않으므로 배포본은 그대로 두면 된다.
Chrome에서 `flutter run -d chrome --web-port 5000`으로 띄운다면
`CORS_ALLOW_ORIGINS = 'http://localhost:5000'` 을 넣는다.
"""

from __future__ import annotations

import os

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from job_matching_bot.api import schemas
from job_matching_bot.api.service import RecommendService, SearchUnavailable
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
if _origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_origins,
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type", "Authorization"],
    )

_service = RecommendService()


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
