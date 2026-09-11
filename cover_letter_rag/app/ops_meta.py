"""LLMOps 관측용 프롬프트 버전 (취업 코치 첨삭)."""

from __future__ import annotations

import os

RESUME_REVIEW_PROMPT_VERSION = os.environ.get(
    "RESUME_REVIEW_PROMPT_VERSION", "resume_review_v1"
)
