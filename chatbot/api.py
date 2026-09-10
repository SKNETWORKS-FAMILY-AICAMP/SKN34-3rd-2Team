"""Firebase 학생 정보로 LMS 챗봇을 초기화하고 NDJSON으로 스트리밍한다."""

from __future__ import annotations

import json
import os
import re
from datetime import date, datetime, timedelta, timezone
from functools import lru_cache
from typing import Any, Iterator

import firebase_admin
from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.responses import StreamingResponse
from firebase_admin import auth, credentials, firestore
from pydantic import BaseModel, Field

from chatbot.student_chatbot import LmsStudentChatbot, create_student_chatbot
from chatbot.unit_period import calculate_unit_period_context

router = APIRouter(prefix="/api/v1/student-chatbot", tags=["student-chatbot"])
KST = timezone(timedelta(hours=9), name="Asia/Seoul")
THREAD_RE = re.compile(r"^[A-Za-z0-9._-]{1,80}$")
DATE_RE = re.compile(
    r"(?:(\d{4})\s*(?:년|[./-])\s*)?"
    r"(\d{1,2})\s*(?:월|[./-])\s*(\d{1,2})\s*일?"
)


class InitRequest(BaseModel):
    thread_id: str = Field(min_length=1, max_length=80, pattern=THREAD_RE.pattern)


class ChatRequest(InitRequest):
    question: str = Field(min_length=1, max_length=2000)


def _to_kst_date(value: Any) -> date | None:
    if isinstance(value, datetime):
        return (value.replace(tzinfo=KST) if value.tzinfo is None else value.astimezone(KST)).date()
    if isinstance(value, date):
        return value
    return None


def _parse_schedule_date(label: str, course_start: date) -> date | None:
    match = DATE_RE.search(label.strip())
    if not match:
        return None
    year = int(match.group(1)) if match.group(1) else course_start.year
    month, day = int(match.group(2)), int(match.group(3))
    if not match.group(1) and month < course_start.month:
        year += 1
    try:
        return date(year, month, day)
    except ValueError:
        return None


@lru_cache
def _firebase_app():
    try:
        return firebase_admin.get_app()
    except ValueError:
        project_id = os.getenv("FIREBASE_PROJECT_ID") or os.getenv("GOOGLE_CLOUD_PROJECT")
        options = {"projectId": project_id} if project_id else None
        return firebase_admin.initialize_app(credentials.ApplicationDefault(), options)


def _student_session(authorization: str | None = Header(default=None)) -> dict[str, Any]:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Firebase 로그인이 필요합니다")
    try:
        app = _firebase_app()
        uid = auth.verify_id_token(authorization[7:].strip(), app=app).get("uid")
        if not isinstance(uid, str) or not uid:
            raise ValueError("missing uid")
        db = firestore.client(app=app)
        profile = db.collection("users").document(uid).get().to_dict() or {}
        if profile.get("role") != "student" or profile.get("isActive") is not True:
            raise HTTPException(status_code=403, detail="학생 계정만 챗봇을 사용할 수 있습니다")
        cohort = str(profile.get("cohortId") or "").strip()
        if not cohort:
            raise HTTPException(status_code=422, detail="학생 기수 정보가 없습니다")
        return {"uid": uid, "cohort": cohort, "db": db}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Firebase 로그인이 만료됐습니다") from exc


def _load_unit_context(session: dict[str, Any], today: date | None = None) -> dict[str, Any]:
    db, cohort, uid = session["db"], session["cohort"], session["uid"]
    cohort_data = db.collection("cohorts").document(cohort).get().to_dict() or {}
    start, end = _to_kst_date(cohort_data.get("startDate")), _to_kst_date(cohort_data.get("endDate"))
    if not start or not end:
        return {"unavailable_reason": "기수의 개강일 또는 종강일이 등록되지 않았습니다"}

    scheduled_dates: set[date] = set()
    sheets = list(
        db.collection("cohorts").document(cohort).collection("curriculumSheets")
        .order_by("uploadedAt", direction=firestore.Query.DESCENDING).limit(1).stream()
    )
    if sheets:
        for row in (sheets[0].to_dict() or {}).get("rows", []):
            parsed = _parse_schedule_date(str(row.get("dateLabel") or ""), start)
            if parsed and start <= parsed <= end:
                scheduled_dates.add(parsed)

    attendance: dict[date, str] = {}
    records = (
        db.collection("cohorts").document(cohort).collection("attendances")
        .where("userId", "==", uid).stream()
    )
    for document in records:
        data = document.to_dict() or {}
        try:
            day = date.fromisoformat(str(data.get("dateKey") or ""))
        except ValueError:
            continue
        status = str(data.get("status") or ("present" if data.get("type") == "checkIn" else ""))
        if status:
            attendance[day] = status

    return calculate_unit_period_context(
        start,
        end,
        today=today or datetime.now(KST).date(),
        scheduled_dates=scheduled_dates,
        attendance_records=attendance,
    )


@lru_cache
def get_student_chatbot() -> LmsStudentChatbot:
    return create_student_chatbot()


def _chat_inputs(request: InitRequest, session: dict[str, Any]) -> dict[str, Any]:
    safe_uid = re.sub(r"[^A-Za-z0-9._-]", "_", session["uid"])[:40]
    return {
        "thread_id": f"{safe_uid}.{request.thread_id}",
        "cohort": session["cohort"],
        "unit_period_context": _load_unit_context(session),
    }


@router.post("/init")
def initialize_chatbot(
    request: InitRequest,
    session: dict[str, Any] = Depends(_student_session),
) -> dict[str, Any]:
    get_student_chatbot()
    inputs = _chat_inputs(request, session)
    return {
        "thread_id": request.thread_id,
        "cohort": inputs["cohort"],
        "unit_period_context": inputs["unit_period_context"],
    }


def _ndjson(chunks: Iterator[str]) -> Iterator[str]:
    try:
        for chunk in chunks:
            yield json.dumps({"type": "token", "content": chunk}, ensure_ascii=False) + "\n"
        yield '{"type":"done"}\n'
    except Exception:
        yield json.dumps({"type": "error", "message": "답변 생성 중 오류가 발생했습니다"}, ensure_ascii=False) + "\n"


@router.post("/stream")
def stream_chat(
    request: ChatRequest,
    session: dict[str, Any] = Depends(_student_session),
) -> StreamingResponse:
    inputs = _chat_inputs(request, session)
    inputs["question"] = request.question.strip()
    return StreamingResponse(
        _ndjson(get_student_chatbot().stream(inputs)),
        media_type="application/x-ndjson",
        headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"},
    )
