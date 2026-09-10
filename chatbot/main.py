"""LMS 학생 챗봇 전용 FastAPI 서버.

실행: uvicorn chatbot.main:app --reload --port 8001
"""

import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from chatbot.api import router

app = FastAPI(title="LMS 학생 챗봇 API", version="0.1.0")

origins = [
    origin.strip()
    for origin in os.environ.get("CORS_ALLOW_ORIGINS", "").split(",")
    if origin.strip()
]
origin_regex = os.environ.get("CORS_ALLOW_ORIGIN_REGEX", "").strip() or (
    r"http://(localhost|127\.0\.0\.1)(:\d+)?"
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_origin_regex=origin_regex,
    allow_methods=["POST"],
    allow_headers=["Content-Type", "Authorization"],
)

app.include_router(router)
