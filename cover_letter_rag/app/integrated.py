"""Run from repo root: python -m uvicorn app.integrated:app --app-dir cover_letter_rag."""
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from job_matching_bot.api.main import app as matching_app
from app.main import app as review_app

app = FastAPI(title='LMS 취업 코치 통합 API', docs_url=None, redoc_url=None, openapi_url=None)
origins = [s.strip() for s in os.environ.get('CORS_ALLOW_ORIGINS', '').split(',') if s.strip()]
regex = os.environ.get('CORS_ALLOW_ORIGIN_REGEX', '').strip() or None
if origins or regex:
    app.add_middleware(CORSMiddleware, allow_origins=origins, allow_origin_regex=regex,
                       allow_methods=['GET', 'POST'], allow_headers=['Content-Type', 'Authorization'])

# Both apps already own /api/v1/jobs/recommend with incompatible schemas.
# Preserve matching's root routes and isolate the legacy review app by prefix.
app.mount('/resume-review', review_app)
app.mount('/', matching_app)
