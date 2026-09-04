from functools import lru_cache

from fastapi import Depends, FastAPI, HTTPException
from langchain_core.exceptions import LangChainException
from openai import OpenAIError

from app.config import Settings, get_settings
from app.models import (
    HealthResponse,
    JobComparisonRequest,
    JobComparisonResponse,
    JobRecommendationRequest,
    JobRecommendationResponse,
    JobSearchRequest,
    JobSearchResponse,
    ReviewRequest,
    ReviewResponse,
    ResumeProfileRequest,
    ResumeProfileResponse,
)
from app.service import CoverLetterService
from app.vector_store import JobRepository


app = FastAPI(
    title="Cover Letter RAG API",
    version="0.1.0",
    description="이력서 근거 기반 채용공고 검색 및 자기소개서 첨삭 API",
)


@lru_cache
def get_service() -> CoverLetterService:
    settings = get_settings()
    if not settings.openai_api_key:
        raise HTTPException(status_code=503, detail="OPENAI_API_KEY is not configured on the server")
    if not JobRepository.is_index_ready(settings.chroma_persist_directory):
        raise HTTPException(status_code=503, detail="Chroma index is not ready; run the indexing command first")
    return CoverLetterService(settings, JobRepository(settings))


@app.get("/health", response_model=HealthResponse)
def health(settings: Settings = Depends(get_settings)) -> HealthResponse:
    return HealthResponse(
        model=settings.openai_model,
        index_ready=JobRepository.is_index_ready(settings.chroma_persist_directory),
    )


@app.post("/api/v1/jobs/search", response_model=JobSearchResponse)
def search_jobs(
    request: JobSearchRequest,
    service: CoverLetterService = Depends(get_service),
) -> JobSearchResponse:
    try:
        return service.search_jobs(request.resume_text, request.top_k)
    except (OpenAIError, LangChainException, ValueError) as exc:
        raise HTTPException(status_code=503, detail=_safe_error(exc)) from exc


@app.post("/api/v1/profiles/analyze", response_model=ResumeProfileResponse)
def analyze_resume_profile(
    request: ResumeProfileRequest,
    service: CoverLetterService = Depends(get_service),
) -> ResumeProfileResponse:
    try:
        return service.analyze_profile(request)
    except (OpenAIError, LangChainException, ValueError) as exc:
        raise HTTPException(status_code=503, detail=_safe_error(exc)) from exc


@app.post("/api/v1/jobs/recommend", response_model=JobRecommendationResponse)
def recommend_jobs(
    request: JobRecommendationRequest,
    service: CoverLetterService = Depends(get_service),
) -> JobRecommendationResponse:
    try:
        return service.recommend_jobs(request)
    except (OpenAIError, LangChainException, ValueError) as exc:
        raise HTTPException(status_code=503, detail=_safe_error(exc)) from exc


@app.post("/api/v1/jobs/compare", response_model=JobComparisonResponse)
def compare_selected_job(
    request: JobComparisonRequest,
    service: CoverLetterService = Depends(get_service),
) -> JobComparisonResponse:
    try:
        return service.compare_job(request)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="Selected job was not found") from exc
    except (OpenAIError, LangChainException, ValueError) as exc:
        raise HTTPException(status_code=503, detail=_safe_error(exc)) from exc


@app.post("/api/v1/reviews", response_model=ReviewResponse)
def review_cover_letter(
    request: ReviewRequest,
    service: CoverLetterService = Depends(get_service),
) -> ReviewResponse:
    try:
        return service.review(request)
    except (OpenAIError, LangChainException, ValueError) as exc:
        raise HTTPException(status_code=503, detail=_safe_error(exc)) from exc


def _safe_error(exc: Exception) -> str:
    return f"RAG service is unavailable: {type(exc).__name__}"
