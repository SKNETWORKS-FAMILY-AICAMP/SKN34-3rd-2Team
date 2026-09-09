from functools import lru_cache

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from langchain_core.exceptions import LangChainException
from openai import OpenAIError

from app.config import Settings, get_settings
from app.models import (
    FirestoreResumeReviewRequest,
    FirestoreResumeReviewResponse,
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
    TailoredResumeCreateRequest,
    TailoredResumeResponse,
    TailoredResumeSummary,
)
from app.firebase_gateway import (
    FirebaseAuthenticationError,
    FirebaseGateway,
    ResumeNotFoundError,
    extract_bearer_token,
)
from app.resume_review import ResumeReviewService
from app.review_workflow import ReviewConflict, ReviewInputError
from app.firebase_gateway import ResumeAccessError
from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import GoogleAuthError
from app.service import CoverLetterService
from app.vector_store import JobRepository
from app.tailored_resumes import TailoredResumeService


app = FastAPI(
    title="Cover Letter RAG API",
    version="0.1.0",
    description="이력서 근거 기반 채용공고 검색 및 자기소개서 첨삭 API",
)
from app.resume_apply import router as resume_apply_router
app.include_router(resume_apply_router)


def get_context_gateway() -> FirebaseGateway:
    settings = get_settings()
    if not settings.firebase_project_id:
        raise HTTPException(status_code=503, detail='Firebase configuration unavailable')
    try:
        return FirebaseGateway(settings)
    except (GoogleAuthError, GoogleAPIError, ValueError) as exc:
        raise HTTPException(status_code=503, detail='Firebase configuration unavailable') from exc


@app.get('/api/v1/resumes/review-context')
def review_context(
    cohort_id: str = Query(min_length=1, max_length=200, pattern=r'^[^/]+$'),
    resume_id: str = Query(min_length=1, max_length=200, pattern=r'^[^/]+$'),
    job_id: str | None = Query(default=None, min_length=1, max_length=200),
    authorization: str | None = Header(default=None),
    gateway: FirebaseGateway = Depends(get_context_gateway),
    settings: Settings = Depends(get_settings),
):
    from app.matching_handoff import load_selected_job
    from app.review_workflow import digest
    from fastapi.responses import JSONResponse
    try:
        uid = gateway.verify_id_token(extract_bearer_token(authorization))
        resume = gateway.get_owned_resume(cohort_id, resume_id, uid)
        job = load_selected_job(settings.matching_job_store_path, job_id) if job_id else None
        content = resume.get('content') or {}
        return JSONResponse({'content': content, 'input_hash': digest(content), 'job_source': job['source'] if job else {}},
                            headers={'Cache-Control': 'no-store'})
    except FirebaseAuthenticationError as exc:
        raise HTTPException(status_code=401, detail='Firebase authentication failed') from exc
    except ResumeAccessError as exc:
        raise HTTPException(status_code=403, detail='Resume access denied') from exc
    except ResumeNotFoundError as exc:
        raise HTTPException(status_code=404, detail='Resume was not found') from exc
    except ReviewConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except ReviewInputError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except (RuntimeError, GoogleAPIError, GoogleAuthError) as exc:
        raise HTTPException(status_code=503, detail=_safe_error(exc)) from exc


@app.post('/api/v1/resumes/tailored', response_model=TailoredResumeResponse)
def create_tailored_resume(
    request: TailoredResumeCreateRequest,
    authorization: str | None = Header(default=None),
    gateway: FirebaseGateway = Depends(get_context_gateway),
    settings: Settings = Depends(get_settings),
):
    from app.matching_handoff import load_selected_job
    try:
        uid = gateway.verify_id_token(extract_bearer_token(authorization))
        service = TailoredResumeService(gateway, lambda job_id: load_selected_job(settings.matching_job_store_path, job_id))
        return service.create(uid, request)
    except FirebaseAuthenticationError as exc:
        raise HTTPException(status_code=401, detail='Firebase authentication failed') from exc
    except ResumeAccessError as exc:
        raise HTTPException(status_code=403, detail='Resume access denied') from exc
    except ResumeNotFoundError as exc:
        raise HTTPException(status_code=404, detail='Resume or job was not found') from exc
    except (ReviewConflict, ReviewInputError, ValueError) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except (RuntimeError, GoogleAPIError, GoogleAuthError) as exc:
        raise HTTPException(status_code=503, detail=_safe_error(exc)) from exc


@app.get('/api/v1/resumes/{resume_id}/tailored', response_model=list[TailoredResumeSummary])
def list_tailored_resumes(
    resume_id: str,
    cohort_id: str = Query(min_length=1, max_length=200, pattern=r'^[^/]+$'),
    authorization: str | None = Header(default=None),
    gateway: FirebaseGateway = Depends(get_context_gateway),
):
    try:
        uid = gateway.verify_id_token(extract_bearer_token(authorization))
        return TailoredResumeService(gateway, lambda _: {}).list(uid, cohort_id, resume_id)
    except FirebaseAuthenticationError as exc:
        raise HTTPException(status_code=401, detail='Firebase authentication failed') from exc
    except ResumeAccessError as exc:
        raise HTTPException(status_code=403, detail='Resume access denied') from exc
    except ResumeNotFoundError as exc:
        raise HTTPException(status_code=404, detail='Resume was not found') from exc


@lru_cache
def get_service() -> CoverLetterService:
    settings = get_settings()
    if not settings.openai_api_key:
        raise HTTPException(status_code=503, detail="OPENAI_API_KEY is not configured on the server")
    if not JobRepository.is_index_ready(settings):
        raise HTTPException(
            status_code=503,
            detail=f"{settings.vector_store_provider} index is not ready; run the indexing command first",
        )
    return CoverLetterService(settings, JobRepository(settings))


def get_resume_review_service(authorization: str | None = Header(default=None)) -> ResumeReviewService:
    try:
        extract_bearer_token(authorization)
    except FirebaseAuthenticationError as exc:
        raise HTTPException(status_code=401, detail='Firebase authentication failed') from exc
    settings = get_settings()
    if not settings.openai_api_key:
        raise HTTPException(status_code=503, detail="OPENAI_API_KEY is not configured on the server")
    if not settings.firebase_project_id:
        raise HTTPException(status_code=503, detail="FIREBASE_PROJECT_ID is not configured on the server")
    try:
        return ResumeReviewService(settings, FirebaseGateway(settings))
    except (GoogleAuthError, GoogleAPIError, ValueError) as exc:
        raise HTTPException(status_code=503, detail='Firebase configuration unavailable') from exc


@app.get("/health", response_model=HealthResponse)
def health(settings: Settings = Depends(get_settings)) -> HealthResponse:
    return HealthResponse(
        model=settings.openai_model,
        index_ready=JobRepository.is_index_ready(settings),
        firebase_auth="configured" if settings.firebase_project_id else "not_configured",
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


@app.post("/api/v1/resumes/reviews", response_model=FirestoreResumeReviewResponse)
def review_stored_resume(
    request: FirestoreResumeReviewRequest,
    authorization: str | None = Header(default=None),
    service: ResumeReviewService = Depends(get_resume_review_service),
) -> FirestoreResumeReviewResponse:
    try:
        id_token = extract_bearer_token(authorization)
        return service.review(id_token, request)
    except FirebaseAuthenticationError as exc:
        raise HTTPException(status_code=401, detail="Firebase authentication failed") from exc
    except ResumeAccessError as exc:
        raise HTTPException(status_code=403, detail='Resume access denied') from exc
    except ReviewConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except ReviewInputError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except ResumeNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Resume was not found") from exc
    except (GoogleAPIError, GoogleAuthError, RuntimeError) as exc:
        raise HTTPException(status_code=503, detail=_safe_error(exc)) from exc
    except (OpenAIError, LangChainException, ValueError) as exc:
        raise HTTPException(status_code=503, detail=_safe_error(exc)) from exc


def _safe_error(exc: Exception) -> str:
    return f"RAG service is unavailable: {type(exc).__name__}"
